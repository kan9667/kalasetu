"""
Tenant Isolation & Authorization Tests.
Ensures:
- Bearer token authentication is required on all private product routes.
- Cross-tenant access is rejected with 404 Not Found (no info leakage).
- Query parameters (?artisan_id=...) cannot select another tenant's data.
- Public route (/public) serves only published items without private cost data.
- legacy_unverified products are excluded from the public catalogue.
"""

import uuid
from datetime import datetime, timezone
import pytest
from httpx import AsyncClient, ASGITransport

from backend.main import app
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB, MediaAssetDB, ProductDB, ProductRevisionDB, ProductStatus
from backend.utils.auth import create_access_token


@pytest.fixture(scope="module")
def setup_tenants():
    init_db()
    db = SessionLocal()

    # Create Tenant A
    artisan_a = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_tenant_a").first()
    if not artisan_a:
        artisan_a = ArtisanDB(
            id="artisan_tenant_a",
            name="Artisan Alice",
            phone="+919811111111",
            craft_type="Textiles",
        )
        db.add(artisan_a)

    # Create Tenant B
    artisan_b = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_tenant_b").first()
    if not artisan_b:
        artisan_b = ArtisanDB(
            id="artisan_tenant_b",
            name="Artisan Bob",
            phone="+919822222222",
            craft_type="Pottery",
        )
        db.add(artisan_b)

    db.commit()

    token_a = create_access_token("artisan_tenant_a")
    token_b = create_access_token("artisan_tenant_b")

    yield {
        "artisan_a": artisan_a,
        "artisan_b": artisan_b,
        "token_a": token_a,
        "token_b": token_b,
    }
    db.close()


@pytest.mark.anyio
async def test_private_routes_require_authentication():
    """Unauthenticated requests to private product routes must return 401."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.get("/api/v1/products")
        assert res.status_code == 401

        res_post = await client.post("/api/v1/products", json={"title": "Test", "price": 100})
        assert res_post.status_code == 401


@pytest.mark.anyio
async def test_cross_tenant_access_rejected(setup_tenants):
    """Tenant B cannot access or mutate Tenant A's products."""
    transport = ASGITransport(app=app)
    token_a = setup_tenants["token_a"]
    token_b = setup_tenants["token_b"]

    headers_a = {"Authorization": f"Bearer {token_a}", "Idempotency-Key": "idem_tenant_a_create"}
    headers_b = {"Authorization": f"Bearer {token_b}", "Idempotency-Key": "idem_tenant_b_mut"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Tenant A creates a draft
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Alice's Silk Scarf",
                "description": "Pure silk scarf",
                "price": 800.0,
                "category": "Textiles",
                "materials_cost": 300.0,
                "labor_hours": 2.0,
                "hourly_rate": 200.0,
            },
            headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": f"idem_create_{uuid.uuid4().hex}"},
        )
        assert create_res.status_code == 201
        prod_id = create_res.json()["id"]

        # 2. Tenant B attempts GET by id -> 404 Not Found
        get_res = await client.get(f"/api/v1/products/{prod_id}", headers={"Authorization": f"Bearer {token_b}"})
        assert get_res.status_code == 404

        # 3. Tenant B attempts PUT update -> 404 Not Found
        put_res = await client.put(
            f"/api/v1/products/{prod_id}",
            json={"title": "Hacked Title"},
            headers={"Authorization": f"Bearer {token_b}", "Idempotency-Key": f"idem_put_{uuid.uuid4().hex}"},
        )
        assert put_res.status_code == 404

        # 4. Tenant B attempts approve-and-publish -> 404 Not Found
        pub_res = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={"revision": 1, "content_hash": "a" * 64},
            headers={"Authorization": f"Bearer {token_b}", "Idempotency-Key": f"idem_pub_{uuid.uuid4().hex}"},
        )
        assert pub_res.status_code == 404

        # 5. Tenant B attempts DELETE -> 404 Not Found
        del_res = await client.delete(
            f"/api/v1/products/{prod_id}",
            headers={"Authorization": f"Bearer {token_b}", "Idempotency-Key": f"idem_del_{uuid.uuid4().hex}"},
        )
        assert del_res.status_code == 404


@pytest.mark.anyio
async def test_tenant_query_parameter_tampering_prevented(setup_tenants):
    """Providing another artisan's ID in query params is ignored; scoped to caller."""
    transport = ASGITransport(app=app)
    token_b = setup_tenants["token_b"]
    headers_b = {"Authorization": f"Bearer {token_b}"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Tenant B asks for products with ?artisan_id=artisan_tenant_a
        res = await client.get(
            "/api/v1/products?artisan_id=artisan_tenant_a",
            headers=headers_b,
        )
        assert res.status_code == 200
        items = res.json()
        # Tenant B must never see Alice's items
        for item in items:
            assert item["artisan_id"] == "artisan_tenant_b"


@pytest.mark.anyio
async def test_public_catalogue_filters_and_sanitizes(setup_tenants):
    """Public catalogue serves only published items, excluding drafts and legacy_unverified."""
    db = SessionLocal()
    transport = ASGITransport(app=app)

    # Insert media asset for foreign key integrity
    media_asset = MediaAssetDB(
        id="med_test_pub",
        artisan_id="artisan_tenant_a",
        file_path="/tmp/med_test_pub.jpg",
        file_url="/api/v1/media/med_test_pub",
        mime_type="image/jpeg",
        byte_size=1024,
        sha256_checksum="dummy_checksum",
        status="ready",
    )
    db.merge(media_asset)
    db.commit()

    # Insert a published product with approved revision snapshot
    now = datetime.now(timezone.utc)
    pub_id = f"pub_{uuid.uuid4().hex[:8]}"
    pub_prod = ProductDB(
        id=pub_id,
        artisan_id="artisan_tenant_a",
        title="Public Brass Lamp",
        description="Handcrafted lamp",
        legacy_price=1500.0,
        price_paise=150000,
        media_id="med_test_pub",
        status=ProductStatus.PUBLISHED.value,
        revision=1,
        approved_revision=1,
        approved_at=now,
        published_at=now,
        content_hash="pub_hash_1",
        is_deleted=False,
    )
    rev_prod = ProductRevisionDB(
        id=f"rev_{uuid.uuid4().hex[:8]}",
        product_id=pub_id,
        artisan_id="artisan_tenant_a",
        revision=1,
        title="Public Brass Lamp",
        price_paise=150000,
        floor_price_paise=100000,
        category="General",
        tags="[]",
        media_id="med_test_pub",
        media_checksum="dummy_checksum",
        media_mime_type="image/jpeg",
        media_byte_size=1024,
        public_media_url="/api/v1/media/med_test_pub/public",
        content_hash="pub_hash_1",
        approved_by_artisan_id="artisan_tenant_a",
        approved_at=now,
        published_at=now,
        created_at=now,
    )
    # Insert a legacy_unverified product
    leg_prod = ProductDB(
        id=f"leg_{uuid.uuid4().hex[:8]}",
        artisan_id="artisan_tenant_a",
        title="Legacy Unverified Lamp",
        description="Should not appear in public",
        legacy_price=900.0,
        price_paise=90000,
        status=ProductStatus.LEGACY_UNVERIFIED.value,
        revision=1,
        content_hash="leg_hash_1",
        is_deleted=False,
    )
    # Insert a draft product
    draft_prod = ProductDB(
        id=f"drf_{uuid.uuid4().hex[:8]}",
        artisan_id="artisan_tenant_a",
        title="Draft Secret Lamp",
        description="Draft should not appear",
        legacy_price=500.0,
        price_paise=50000,
        status=ProductStatus.DRAFT.value,
        revision=1,
        content_hash="drf_hash_1",
        is_deleted=False,
    )
    db.add_all([pub_prod, rev_prod, leg_prod, draft_prod])
    db.commit()
    leg_id = leg_prod.id
    draft_id = draft_prod.id
    db.close()

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.get("/api/v1/products/public")
        assert res.status_code == 200
        items = res.json()
        ids = [item["id"] for item in items]

        assert pub_id in ids
        assert leg_id not in ids, "legacy_unverified must be excluded from public catalogue"
        assert draft_id not in ids, "drafts must be excluded from public catalogue"

        # Verify sanitized schema: no internal cost breakdown exposed
        for item in items:
            assert "materials_cost" not in item
            assert "materials_paise" not in item
            assert "hourly_rate" not in item
            assert "floor_price" not in item
            assert "floor_price_paise" not in item
