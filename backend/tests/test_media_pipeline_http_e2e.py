"""
End-to-End Media Pipeline HTTP Integration Tests.

Validates the full lifecycle:
1. Raw image upload via /api/v1/media/upload -> server-owned MediaAsset with provenance 'artisan_direct_upload'.
2. Image enhancement via /api/v1/catalog/enhance-image -> derived MediaAsset with lineage (source_media_id), provenance 'enhanced_image', and degradation tracking.
3. Private vs Public access boundaries:
   - Private GET /api/v1/media/{id} accessible only by owning artisan (403 for other tenants).
   - Public GET /api/v1/media/{id}/public returns 404 before approval.
4. Product draft attachment -> explicit approval & publish -> Public GET /api/v1/media/{id}/public returns 200.
5. Product unpublish -> transitions back to draft, bumps revision, and revokes public media access (404).
6. Lineage-aware deduplication: degraded fallback asset preserves source_media_id and does not collapse into raw asset.
"""

import io
import uuid
from pathlib import Path
from unittest.mock import patch, AsyncMock
import pytest
from httpx import AsyncClient, ASGITransport
from PIL import Image

from backend.main import app
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB, MediaAssetDB, ProductDB, ProductStatus
from backend.utils.auth import create_access_token
from backend.utils.hashing import compute_content_hash

# Valid 1x1 PNG bytes
VALID_PNG_BYTES = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff"
    b"?\x00\x05\xfe\x02\xfe\xa748V\x00\x00\x00\x00IEND\xaeB`\x82"
)


@pytest.fixture(scope="module")
def setup_media_tenants():
    init_db()
    db = SessionLocal()

    artisan_a = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_media_pipe_a").first()
    if not artisan_a:
        artisan_a = ArtisanDB(
            id="artisan_media_pipe_a",
            name="Artisan Ananya",
            phone="+919800000001",
            craft_type="Terracotta",
        )
        db.add(artisan_a)

    artisan_b = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_media_pipe_b").first()
    if not artisan_b:
        artisan_b = ArtisanDB(
            id="artisan_media_pipe_b",
            name="Artisan Bharat",
            phone="+919800000002",
            craft_type="Woodcarving",
        )
        db.add(artisan_b)

    db.commit()
    token_a = create_access_token("artisan_media_pipe_a")
    token_b = create_access_token("artisan_media_pipe_b")
    db.close()

    return {
        "artisan_a": "artisan_media_pipe_a",
        "token_a": token_a,
        "artisan_b": "artisan_media_pipe_b",
        "token_b": token_b,
    }


@pytest.mark.anyio
async def test_full_media_pipeline_lifecycle(setup_media_tenants, tmp_path):
    """
    Test complete lifecycle from upload -> enhancement -> draft -> approval -> public media access -> unpublish.
    """
    transport = ASGITransport(app=app)
    token_a = setup_media_tenants["token_a"]
    token_b = setup_media_tenants["token_b"]
    headers_a = {"Authorization": f"Bearer {token_a}"}
    headers_b = {"Authorization": f"Bearer {token_b}"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Step 1: Upload raw image
        raw_test_bytes = VALID_PNG_BYTES + f"e2e_{uuid.uuid4().hex}".encode()
        upload_key = f"idem_upload_{uuid.uuid4().hex[:8]}"
        res_upload = await client.post(
            "/api/v1/media/upload",
            files={"file": ("raw.png", io.BytesIO(raw_test_bytes), "image/png")},
            headers={**headers_a, "Idempotency-Key": upload_key},
        )
        assert res_upload.status_code == 201
        upload_data = res_upload.json()
        raw_media_id = upload_data["media_id"]
        assert raw_media_id.startswith("med_")
        assert upload_data["status"] == "ready"

        # Step 2: Enhance image
        # Create a mock enhanced image on disk
        enhanced_file = tmp_path / f"mock_enhanced_{uuid.uuid4().hex}.png"
        img = Image.new("RGBA", (200, 200), (255, 255, 255, 255))
        img.putpixel((0, 0), (uuid.uuid4().int % 256, 0, 0, 255))
        img.save(str(enhanced_file), "PNG")

        enhance_key = f"idem_enhance_{uuid.uuid4().hex[:8]}"
        with patch(
            "backend.routers.catalog.catalog_service.enhance_product_photo",
            new=AsyncMock(return_value=(str(enhanced_file), False, None)),
        ):
            res_enhance = await client.post(
                "/api/v1/catalog/enhance-image",
                files={"image": ("raw.png", io.BytesIO(raw_test_bytes), "image/png")},
                data={"return_format": "PNG"},
                headers={**headers_a, "Idempotency-Key": enhance_key},
            )
            assert res_enhance.status_code == 200
            enhance_data = res_enhance.json()
            enhanced_media_id = enhance_data["media_id"]
            assert enhanced_media_id.startswith("med_")
            assert enhance_data["is_degraded"] is False
            assert enhance_data["degraded_reason"] is None
            assert enhance_data["original_media_id"] is not None

        # Verify database lineage
        db = SessionLocal()
        derived_asset = db.query(MediaAssetDB).filter(MediaAssetDB.id == enhanced_media_id).first()
        assert derived_asset is not None
        assert derived_asset.source_media_id == enhance_data["original_media_id"]
        assert derived_asset.is_degraded is False
        assert derived_asset.processing_provenance == "ai_enhanced_image"
        db.close()

        # Step 3: Access Control Verification
        # 3a. Owner can access private media
        res_priv_owner = await client.get(f"/api/v1/media/{enhanced_media_id}", headers=headers_a)
        assert res_priv_owner.status_code == 200

        # 3b. Another artisan CANNOT access owner's private media (403)
        res_priv_other = await client.get(f"/api/v1/media/{enhanced_media_id}", headers=headers_b)
        assert res_priv_other.status_code == 403

        # 3c. Public endpoint returns 404 because media is not in an approved published revision
        res_pub_pre = await client.get(f"/api/v1/media/{enhanced_media_id}/public")
        assert res_pub_pre.status_code == 404

        # Step 4: Create Product Draft with the enhanced media
        create_key = f"idem_create_{uuid.uuid4().hex[:8]}"
        prod_payload = {
            "title": "Terracotta Pot",
            "title_hi": "मिट्टी का घड़ा",
            "description": "Handcrafted earthen pot",
            "price": 600.0,
            "materials": 100.0,
            "labor_hours": 2.0,
            "hourly_rate": 100.0,
            "transport": 50.0,
            "overhead": 50.0,
            "category": "Pottery",
            "tags": ["terracotta", "pot"],
            "media_id": enhanced_media_id,
        }
        res_create = await client.post(
            "/api/v1/products",
            json=prod_payload,
            headers={**headers_a, "Idempotency-Key": create_key},
        )
        assert res_create.status_code == 201
        prod_data = res_create.json()
        prod_id = prod_data["id"]
        assert prod_data["status"] == "draft"
        assert prod_data["revision"] == 1

        # Step 5: Approve and Publish Product
        content_hash = compute_content_hash(
            title=prod_payload["title"],
            title_hi=prod_payload["title_hi"],
            description=prod_payload["description"],
            description_hi="",
            price_paise=60000,
            category=prod_payload["category"],
            tags=prod_payload["tags"],
            floor_price_paise=40000,
            media_id=enhanced_media_id,
            media_checksum=derived_asset.sha256_checksum,
        )
        pub_key = f"idem_pub_{uuid.uuid4().hex[:8]}"
        res_pub = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={
                "revision": 1,
                "content_hash": content_hash,
                "agreed_to_fair_price": True,
            },
            headers={**headers_a, "Idempotency-Key": pub_key},
        )
        assert res_pub.status_code == 200
        assert res_pub.json()["status"] == "published"

        # Step 6: Public access NOW succeeds because media is in an approved published revision
        res_pub_post = await client.get(f"/api/v1/media/{enhanced_media_id}/public")
        assert res_pub_post.status_code == 200

        # Step 7: Unpublish product
        unpub_key = f"idem_unpub_{uuid.uuid4().hex[:8]}"
        res_unpub = await client.post(
            f"/api/v1/products/{prod_id}/unpublish",
            json={"expected_revision": 1, "content_hash": content_hash},
            headers={**headers_a, "Idempotency-Key": unpub_key},
        )
        assert res_unpub.status_code == 200
        unpub_data = res_unpub.json()
        assert unpub_data["status"] == "draft"
        assert unpub_data["revision"] == 2
        assert unpub_data["approved_revision"] is None
        assert unpub_data["published_at"] is None

        # Step 8: Public access returns 404 again after unpublish
        res_pub_revoked = await client.get(f"/api/v1/media/{enhanced_media_id}/public")
        assert res_pub_revoked.status_code == 404


@pytest.mark.anyio
async def test_degraded_enhancement_lineage_and_non_collapsing(setup_media_tenants, tmp_path):
    """
    Test that when enhancement falls back, is_degraded is True with degraded_reason,
    source_media_id points to the raw asset, and the asset is NOT collapsed into the raw asset.
    """
    transport = ASGITransport(app=app)
    token_a = setup_media_tenants["token_a"]
    headers_a = {"Authorization": f"Bearer {token_a}"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Upload a unique image
        unique_bytes = VALID_PNG_BYTES + f"unique_{uuid.uuid4().hex}".encode()

        # Mock fallback where enhancer returns original image path with degraded flag
        fallback_file = tmp_path / "fallback_raw.png"
        fallback_file.write_bytes(unique_bytes)

        enhance_key = f"idem_fallback_{uuid.uuid4().hex[:8]}"
        with patch(
            "backend.routers.catalog.catalog_service.enhance_product_photo",
            new=AsyncMock(return_value=(str(fallback_file), True, "rembg execution timed out; fallback to original image")),
        ):
            res = await client.post(
                "/api/v1/catalog/enhance-image",
                files={"image": ("fallback.png", io.BytesIO(unique_bytes), "image/png")},
                data={"return_format": "PNG"},
                headers={**headers_a, "Idempotency-Key": enhance_key},
            )
            assert res.status_code == 200
            data = res.json()
            assert data["is_degraded"] is True
            assert "timed out" in data["degraded_reason"]
            assert data["media_id"] != data["original_media_id"]

            # Verify in DB that two distinct rows exist with proper lineage
            db = SessionLocal()
            raw_asset = db.query(MediaAssetDB).filter(MediaAssetDB.id == data["original_media_id"]).first()
            derived_asset = db.query(MediaAssetDB).filter(MediaAssetDB.id == data["media_id"]).first()

            assert raw_asset is not None
            assert derived_asset is not None
            assert derived_asset.source_media_id == raw_asset.id
            assert derived_asset.is_degraded is True
            assert derived_asset.degraded_reason == "rembg execution timed out; fallback to original image"
            assert derived_asset.processing_provenance == "degraded_enhanced_image"
            db.close()
