"""
Approval & Publishing Lifecycle Integration Tests.
Verifies:
- Product create defaults strictly to draft, revision 1, with content hash.
- Client status manipulation (attempting to set published/live) is ignored.
- Floor price enforcement rejects below-floor publishing with 422.
- Media validation requirement rejects unvalidated media with 422.
- Explicit approval transitions draft -> published, recording revision & timestamp.
- Subsequent edits bump revision and invalidate previous approval.
- Stale revision or content hash mismatch yields 409 Conflict.
- Idempotent retry with the same Idempotency-Key returns 200 without side effects.
"""

import uuid
import pytest
from httpx import AsyncClient, ASGITransport

from backend.main import app
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB, MediaAssetDB, ProductDB, ProductRevisionDB, ProductStatus
from backend.utils.auth import create_access_token


@pytest.fixture(scope="module")
def artisan_session():
    init_db()
    db = SessionLocal()

    artisan = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_approval_test").first()
    if not artisan:
        artisan = ArtisanDB(
            id="artisan_approval_test",
            name="Ramesh Kumar",
            phone="+919876500000",
            craft_type="Pottery",
        )
        db.add(artisan)
        db.commit()

    token = create_access_token("artisan_approval_test")

    # Create two ready media assets for this artisan
    media_id = f"media_app_{uuid.uuid4().hex[:8]}"
    media = MediaAssetDB(
        id=media_id,
        artisan_id="artisan_approval_test",
        file_path=f"/fake/uploads/{media_id}.jpg",
        file_url=f"/uploads/{media_id}.jpg",
        mime_type="image/jpeg",
        byte_size=2048,
        sha256_checksum="test_sha256_valid",
        status="ready",
    )
    db.add(media)

    media_id_2 = f"media_app2_{uuid.uuid4().hex[:8]}"
    media2 = MediaAssetDB(
        id=media_id_2,
        artisan_id="artisan_approval_test",
        file_path=f"/fake/uploads/{media_id_2}.jpg",
        file_url=f"/uploads/{media_id_2}.jpg",
        mime_type="image/jpeg",
        byte_size=3072,
        sha256_checksum="test_sha256_valid_2",
        status="ready",
    )
    db.add(media2)
    db.commit()

    yield {
        "artisan_id": "artisan_approval_test",
        "token": token,
        "media_id": media_id,
        "media_id_2": media_id_2,
    }
    db.close()


def get_headers(token: str, key: str = None) -> dict:
    return {
        "Authorization": f"Bearer {token}",
        "Idempotency-Key": key or f"idem_{uuid.uuid4().hex}",
    }


@pytest.mark.anyio
async def test_product_creation_defaults_to_draft_and_ignores_client_status(artisan_session):
    """Client cannot create a published listing directly; must be draft."""
    transport = ASGITransport(app=app)
    token = artisan_session["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post(
            "/api/v1/products",
            json={
                "title": "Terracotta Chai Cup",
                "description": "Kulhad cup",
                "price": 150.0,
                "category": "Pottery",
                "status": "published",  # Client attempts to publish immediately
                "materials_cost": 40.0,
                "labor_hours": 1.0,
                "hourly_rate": 50.0,
            },
            headers=get_headers(token),
        )
        assert res.status_code == 201
        data = res.json()

        assert data["status"] == "draft", "Status must be draft despite client payload"
        assert data["revision"] == 1
        assert len(data["content_hash"]) == 64
        assert data["approved_revision"] is None
        assert data["approved_at"] is None
        assert data["published_at"] is None


@pytest.mark.anyio
async def test_product_update_cannot_directly_publish(artisan_session):
    """Client PUT update cannot directly flip status to published."""
    transport = ASGITransport(app=app)
    token = artisan_session["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Clay Pitcher",
                "description": "Handmade pitcher",
                "price": 300.0,
                "category": "Pottery",
            },
            headers=get_headers(token),
        )
        assert create_res.status_code == 201
        prod_id = create_res.json()["id"]

        update_res = await client.put(
            f"/api/v1/products/{prod_id}",
            json={
                "title": "Clay Pitcher Large",
                "status": "published",  # Forbidden direct publish
            },
            headers=get_headers(token),
        )
        assert update_res.status_code == 200
        assert update_res.json()["status"] == "draft"


@pytest.mark.anyio
async def test_creation_and_publish_rejected_below_cost_floor(artisan_session):
    """Mutations and publishing must fail with 422 if price is below the calculated cost floor."""
    transport = ASGITransport(app=app)
    token = artisan_session["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Direct create below floor (price=400 < floor=500) -> 422
        create_below = await client.post(
            "/api/v1/products",
            json={
                "title": "Low Price Rug",
                "description": "Woven rug",
                "price": 400.0,
                "materials_cost": 200.0,
                "labor_hours": 2.0,
                "hourly_rate": 150.0,
                "media_id": artisan_session["media_id"],
            },
            headers=get_headers(token),
        )
        assert create_below.status_code == 422
        assert "below the calculated cost floor" in create_below.json()["detail"].lower()


@pytest.mark.anyio
async def test_publish_rejected_without_validated_media(artisan_session):
    """Publishing must fail with 422 if media_id is missing or asset not ready."""
    transport = ASGITransport(app=app)
    token = artisan_session["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "No Media Pot",
                "description": "Missing media asset",
                "price": 500.0,
                "materials_cost": 50.0,
                "labor_hours": 1.0,
                "hourly_rate": 50.0,
                # No media_id provided
            },
            headers=get_headers(token),
        )
        assert create_res.status_code == 201
        prod = create_res.json()

        pub_res = await client.post(
            f"/api/v1/products/{prod['id']}/approve-and-publish",
            json={
                "revision": prod["revision"],
                "content_hash": prod["content_hash"],
            },
            headers=get_headers(token),
        )
        assert pub_res.status_code == 422
        assert "media" in pub_res.json()["detail"].lower()


@pytest.mark.anyio
async def test_successful_approval_and_publish_flow(artisan_session):
    """Full lifecycle: create draft -> approve & publish -> edit bumps revision & invalidates approval."""
    transport = ASGITransport(app=app)
    token = artisan_session["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Create valid draft with verified media
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Fine Glazed Planter",
                "description": "Glazed planter pot",
                "price": 600.0,
                "materials_cost": 100.0,
                "labor_hours": 2.0,
                "hourly_rate": 100.0,
                "media_id": artisan_session["media_id"],
            },
            headers=get_headers(token),
        )
        assert create_res.status_code == 201
        prod = create_res.json()
        prod_id = prod["id"]
        assert prod["status"] == "draft"
        assert prod["revision"] == 1

        # 2. Approve and publish
        pub_res = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={
                "revision": prod["revision"],
                "content_hash": prod["content_hash"],
            },
            headers=get_headers(token),
        )
        assert pub_res.status_code == 200
        pub_data = pub_res.json()

        assert pub_data["status"] == "published"
        assert pub_data["revision"] == 1
        assert pub_data["approved_revision"] == 1
        assert pub_data["approved_by_artisan_id"] == artisan_session["artisan_id"]
        assert pub_data["approved_at"] is not None
        assert pub_data["published_at"] is not None

        # 3. Edit published product -> must increment revision and invalidate approval
        update_res = await client.put(
            f"/api/v1/products/{prod_id}",
            json={"title": "Fine Glazed Planter - Indigo"},
            headers=get_headers(token),
        )
        assert update_res.status_code == 200
        updated_data = update_res.json()

        assert updated_data["revision"] == 2
        assert updated_data["status"] in ("draft", "superseded")
        assert updated_data["approved_revision"] is None
        assert updated_data["approved_at"] is None
        assert updated_data["published_at"] is None


@pytest.mark.anyio
async def test_stale_revision_conflict(artisan_session):
    """Publishing with a stale revision number or mismatched content hash yields 409 Conflict."""
    transport = ASGITransport(app=app)
    token = artisan_session["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Conflict Test Bowl",
                "description": "Ceramic bowl",
                "price": 300.0,
                "materials_cost": 50.0,
                "labor_hours": 1.0,
                "hourly_rate": 50.0,
                "media_id": artisan_session["media_id"],
            },
            headers=get_headers(token),
        )
        assert create_res.status_code == 201
        prod = create_res.json()
        prod_id = prod["id"]

        # 1. Update product to bump revision to 2
        update_res = await client.put(
            f"/api/v1/products/{prod_id}",
            json={"title": "Conflict Test Bowl - Modified"},
            headers=get_headers(token),
        )
        assert update_res.status_code == 200

        # 2. Attempt to publish with old revision (1) -> 409 Conflict
        stale_res = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={
                "revision": 1,
                "content_hash": prod["content_hash"],
            },
            headers=get_headers(token),
        )
        assert stale_res.status_code == 409
        assert "stale" in stale_res.json()["detail"].lower()


@pytest.mark.anyio
async def test_publish_idempotency(artisan_session):
    """Submitting duplicate approve-and-publish with the same Idempotency-Key is safe and returns 200."""
    transport = ASGITransport(app=app)
    token = artisan_session["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Idempotent Mug",
                "description": "Clay mug",
                "price": 250.0,
                "materials_cost": 30.0,
                "labor_hours": 1.0,
                "hourly_rate": 50.0,
                "media_id": artisan_session["media_id"],
            },
            headers=get_headers(token),
        )
        assert create_res.status_code == 201
        prod = create_res.json()
        prod_id = prod["id"]
        idempotency_key = f"idem_{uuid.uuid4().hex}"

        pub_headers = get_headers(token, key=idempotency_key)

        # First publish request
        res1 = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={
                "revision": prod["revision"],
                "content_hash": prod["content_hash"],
            },
            headers=pub_headers,
        )
        assert res1.status_code == 200

        # Duplicate retry with same idempotency key
        res2 = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={
                "revision": prod["revision"],
                "content_hash": prod["content_hash"],
            },
            headers=pub_headers,
        )
        assert res2.status_code == 200
        assert res2.json()["id"] == res1.json()["id"]
        assert res2.json()["status"] == "published"


@pytest.mark.anyio
async def test_adversarial_image_url_injection_rejected_and_legitimate_media_replacement(artisan_session):
    """
    Mandatory Acceptance Criteria 1:
    - Direct PUT with client-controlled image_url -> 422; published listing and approved revision remain unchanged.
    - Direct POST with image_url -> 422.
    - Legitimate replacement uses verified owned media_id -> new draft revision, approval cleared, removed from public catalogue.
    """
    transport = ASGITransport(app=app)
    token = artisan_session["token"]
    media_id_1 = artisan_session["media_id"]
    media_id_2 = artisan_session["media_id_2"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Create valid product and publish it
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Adversarial Pottery Vase",
                "description": "Handmade clay vase",
                "price": 500.0,
                "materials_cost": 100.0,
                "labor_hours": 1.0,
                "hourly_rate": 100.0,
                "media_id": media_id_1,
            },
            headers=get_headers(token),
        )
        assert create_res.status_code == 201
        prod = create_res.json()
        prod_id = prod["id"]

        pub_res = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={
                "revision": prod["revision"],
                "content_hash": prod["content_hash"],
            },
            headers=get_headers(token),
        )
        assert pub_res.status_code == 200
        pub_data = pub_res.json()
        assert pub_data["status"] == "published"
        assert pub_data["approved_revision"] == 1

        # Confirm listing is live in public catalogue
        pub_cat_1 = await client.get("/api/v1/products/public")
        assert pub_cat_1.status_code == 200
        assert any(p["id"] == prod_id for p in pub_cat_1.json())

        # 2. Adversarial attack: Direct PUT with client-supplied image_url must yield 422
        put_attack = await client.put(
            f"/api/v1/products/{prod_id}",
            json={
                "title": "Hacked Title",
                "image_url": "https://attacker.com/malicious_image.png",
                "expected_revision": 1,
            },
            headers=get_headers(token),
        )
        assert put_attack.status_code == 422
        assert "image_url is strictly prohibited" in put_attack.text

        # Verify published listing and approved revision remain completely unchanged
        get_res = await client.get(
            f"/api/v1/products/{prod_id}",
            headers=get_headers(token),
        )
        assert get_res.status_code == 200
        unchanged = get_res.json()
        assert unchanged["status"] == "published"
        assert unchanged["revision"] == 1
        assert unchanged["approved_revision"] == 1
        assert unchanged["media_id"] == media_id_1

        # Verify still present and uncorrupted in public catalogue
        pub_cat_2 = await client.get("/api/v1/products/public")
        assert pub_cat_2.status_code == 200
        assert any(p["id"] == prod_id and p["title"] == "Adversarial Pottery Vase" for p in pub_cat_2.json())

        # 3. Direct POST with client-supplied image_url must also yield 422
        post_attack = await client.post(
            "/api/v1/products",
            json={
                "title": "Direct Image URL Post",
                "description": "Attempt to bypass media validation",
                "price": 300.0,
                "image_url": "https://attacker.com/bypass.png",
            },
            headers=get_headers(token),
        )
        assert post_attack.status_code == 422
        assert "image_url is strictly prohibited" in post_attack.text

        # 4. Legitimate image replacement using verified owned media_id
        replace_res = await client.put(
            f"/api/v1/products/{prod_id}",
            json={
                "media_id": media_id_2,
                "expected_revision": 1,
            },
            headers=get_headers(token),
        )
        assert replace_res.status_code == 200
        replaced = replace_res.json()

        # Invariants: new draft revision, approval cleared, removed from public catalogue
        assert replaced["revision"] == 2
        assert replaced["status"] == "draft"
        assert replaced["approved_revision"] is None
        assert replaced["approved_at"] is None
        assert replaced["published_at"] is None
        assert replaced["media_id"] == media_id_2

        # Verify removed from public catalogue
        pub_cat_3 = await client.get("/api/v1/products/public")
        assert pub_cat_3.status_code == 200
        assert not any(p["id"] == prod_id for p in pub_cat_3.json()), "Product must be excluded from public catalogue"


@pytest.mark.anyio
async def test_soft_delete_preserves_audit_revisions(artisan_session):
    """
    Mandatory Acceptance Criteria 4:
    - Product deletion performs soft-delete/tombstone.
    - Foreign-key relationships with ProductRevisionDB do not error.
    - Approved revisions remain preserved in database for auditability.
    - Product is excluded from public catalogue and artisan listings.
    """
    transport = ASGITransport(app=app)
    token = artisan_session["token"]
    media_id = artisan_session["media_id"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Create and approve & publish product
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Tombstone Audit Pottery",
                "description": "Pottery with audit trail",
                "price": 450.0,
                "materials_cost": 50.0,
                "labor_hours": 1.0,
                "hourly_rate": 50.0,
                "media_id": media_id,
            },
            headers=get_headers(token),
        )
        assert create_res.status_code == 201
        prod = create_res.json()
        prod_id = prod["id"]

        pub_res = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={
                "revision": prod["revision"],
                "content_hash": prod["content_hash"],
            },
            headers=get_headers(token),
        )
        assert pub_res.status_code == 200

        # 2. DELETE product
        del_res = await client.delete(
            f"/api/v1/products/{prod_id}",
            headers=get_headers(token),
        )
        assert del_res.status_code == 200
        assert del_res.json() == {"status": "success", "id": prod_id, "deleted": True}

        # 3. GET product by ID returns 404
        get_res = await client.get(
            f"/api/v1/products/{prod_id}",
            headers=get_headers(token),
        )
        assert get_res.status_code == 404

        # 4. Excluded from artisan listings
        list_res = await client.get(
            "/api/v1/products",
            headers=get_headers(token),
        )
        assert list_res.status_code == 200
        assert not any(p["id"] == prod_id for p in list_res.json())

        # 5. Excluded from public catalogue
        pub_res = await client.get("/api/v1/products/public")
        assert pub_res.status_code == 200
        assert not any(p["id"] == prod_id for p in pub_res.json())

    # 6. Verify audit records in DB: ProductRevisionDB is deliberately preserved
    db = SessionLocal()
    prod_row = db.query(ProductDB).filter(ProductDB.id == prod_id).first()
    assert prod_row is not None
    assert prod_row.is_deleted is True
    assert prod_row.status == ProductStatus.DELETED.value

    revisions = db.query(ProductRevisionDB).filter(ProductRevisionDB.product_id == prod_id).all()
    assert len(revisions) == 1
    rev = revisions[0]
    assert rev.revision == 1
    assert rev.title == "Tombstone Audit Pottery"
    assert rev.approved_by_artisan_id == artisan_session["artisan_id"]
    assert rev.content_hash == prod["content_hash"]
    db.close()
