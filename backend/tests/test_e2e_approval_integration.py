"""
End-to-End Real HTTP Integration Suite for Artisan Approval, Revisions, Idempotency, and Media Lifecycle.

Validates the 5 Mandatory Acceptance Criteria:
1. Rejection of client image URLs (HTTP 422 on create & PUT; published listing remains unchanged; legitimate replacement resets approval and unlists).
2. Server-returned attachment state chaining for approval and publishing.
3. Strict enforcement of Idempotency-Key headers on all mutating routes (create, update, delete, upload, approve/publish, sync).
4. Deliberate audit preservation via soft-delete tombstone policy retaining ProductRevisionDB rows.
5. Media upload failure artifact cleanup and idempotent deduplication.
"""

import io
import uuid
from datetime import datetime, timezone
from pathlib import Path
import pytest
from httpx import AsyncClient, ASGITransport

from backend.main import app
from backend.database import SessionLocal, init_db
from backend.config import get_settings
from backend.models.db_models import ArtisanDB, MediaAssetDB, ProductDB, ProductRevisionDB, ProductStatus, IdempotencyRecordDB
from backend.utils.auth import create_access_token


VALID_PNG_BYTES = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff"
    b"?\x00\x05\xfe\x02\xfe\xa748V\x00\x00\x00\x00IEND\xaeB`\x82"
)


@pytest.fixture(scope="module")
def e2e_env():
    init_db()
    db = SessionLocal()

    artisan_id = "artisan_e2e_test"
    artisan = db.query(ArtisanDB).filter(ArtisanDB.id == artisan_id).first()
    if not artisan:
        artisan = ArtisanDB(
            id=artisan_id,
            name="Devi Lal",
            phone="+919876599999",
            craft_type="Woodcarving",
            created_at=datetime.now(timezone.utc),
        )
        db.add(artisan)
        db.commit()

    token = create_access_token(artisan_id)
    db.close()
    return {"artisan_id": artisan_id, "token": token}


def auth_headers(token: str, idempotency_key: str = None) -> dict:
    headers = {"Authorization": f"Bearer {token}"}
    if idempotency_key is not None:
        headers["Idempotency-Key"] = idempotency_key
    return headers


@pytest.mark.anyio
async def test_criterion_1_reject_client_image_urls_explicitly(e2e_env):
    """
    Criterion 1:
    - Direct PUT with image_url -> 422; published listing and approved revision remain unchanged.
    - Direct POST with image_url -> 422.
    - Legitimate image replacement uses verified owned media_id -> new draft revision, approval cleared, removed from public catalogue.
    """
    transport = ASGITransport(app=app)
    token = e2e_env["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Step 1: Upload initial media asset 1
        up1 = await client.post(
            "/api/v1/media/upload",
            files={"file": ("wood1.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers=auth_headers(token, f"idem_up1_{uuid.uuid4().hex}"),
        )
        assert up1.status_code == 201
        media_id_1 = up1.json()["media_id"]

        # Step 2: Create product draft and approve/publish it
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Carved Teak Elephant",
                "description": "Solid teak wood elephant",
                "price": 1200.0,
                "materials_cost": 300.0,
                "labor_hours": 3.0,
                "hourly_rate": 150.0,
                "media_id": media_id_1,
            },
            headers=auth_headers(token, f"idem_cr_{uuid.uuid4().hex}"),
        )
        assert create_res.status_code == 201
        prod = create_res.json()
        prod_id = prod["id"]
        assert prod["revision"] == 1
        assert prod["status"] == "draft"

        pub_res = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={"revision": prod["revision"], "content_hash": prod["content_hash"]},
            headers=auth_headers(token, f"idem_pub_{uuid.uuid4().hex}"),
        )
        assert pub_res.status_code == 200
        pub_data = pub_res.json()
        assert pub_data["status"] == "published"
        assert pub_data["approved_revision"] == 1

        # Check visible in public catalogue
        pub_cat_res = await client.get("/api/v1/products/public")
        assert pub_cat_res.status_code == 200
        assert any(p["id"] == prod_id for p in pub_cat_res.json())

        # Step 3: Adversarial direct PUT with client image_url -> strictly 422
        put_attack = await client.put(
            f"/api/v1/products/{prod_id}",
            json={
                "title": "Hacked Teak Elephant",
                "image_url": "https://malicious-bucket.com/exploit.jpg",
                "expected_revision": 1,
            },
            headers=auth_headers(token, f"idem_atk_{uuid.uuid4().hex}"),
        )
        assert put_attack.status_code == 422
        assert "image_url is strictly prohibited" in put_attack.text

        # Verify published listing and approved revision remain completely untouched
        get_res = await client.get(f"/api/v1/products/{prod_id}", headers=auth_headers(token))
        assert get_res.status_code == 200
        unchanged = get_res.json()
        assert unchanged["status"] == "published"
        assert unchanged["revision"] == 1
        assert unchanged["approved_revision"] == 1
        assert unchanged["media_id"] == media_id_1

        # Step 4: Adversarial direct POST with client image_url -> strictly 422
        post_attack = await client.post(
            "/api/v1/products",
            json={
                "title": "Direct image_url Attempt",
                "description": "Bypass upload",
                "price": 500.0,
                "image_url": "https://malicious-bucket.com/exploit.jpg",
            },
            headers=auth_headers(token, f"idem_atk_post_{uuid.uuid4().hex}"),
        )
        assert post_attack.status_code == 422
        assert "image_url is strictly prohibited" in post_attack.text

        # Step 5: Legitimate image replacement using verified owned media_id
        up2 = await client.post(
            "/api/v1/media/upload",
            files={"file": ("wood2.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers=auth_headers(token, f"idem_up2_{uuid.uuid4().hex}"),
        )
        assert up2.status_code == 201
        media_id_2 = up2.json()["media_id"]

        replace_res = await client.put(
            f"/api/v1/products/{prod_id}",
            json={"media_id": media_id_2, "expected_revision": 1},
            headers=auth_headers(token, f"idem_rep_{uuid.uuid4().hex}"),
        )
        assert replace_res.status_code == 200
        replaced = replace_res.json()

        assert replaced["revision"] == 2
        assert replaced["status"] == "draft"
        assert replaced["approved_revision"] is None
        assert replaced["approved_at"] is None
        assert replaced["published_at"] is None
        assert replaced["media_id"] == media_id_2

        # Invariant: Must be removed from public catalogue
        pub_cat_after = await client.get("/api/v1/products/public")
        assert not any(p["id"] == prod_id for p in pub_cat_after.json())


@pytest.mark.anyio
async def test_criterion_2_approval_uses_server_returned_attachment_state(e2e_env):
    """
    Criterion 2:
    Offline replay chaining: ATTACH_MEDIA saves exact revision and content_hash
    returned by server, and APPROVE_PUBLISH submits those exact returned values.
    """
    transport = ASGITransport(app=app)
    token = e2e_env["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Create a draft product without media initially
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Sandalwood Box",
                "description": "Fragrant carved sandalwood box",
                "price": 2000.0,
                "materials_cost": 800.0,
                "labor_hours": 4.0,
                "hourly_rate": 200.0,
            },
            headers=auth_headers(token, f"idem_box_{uuid.uuid4().hex}"),
        )
        assert create_res.status_code == 201
        initial_prod = create_res.json()
        prod_id = initial_prod["id"]
        assert initial_prod["revision"] == 1
        assert initial_prod["media_id"] is None

        # 2. Upload media file
        up_res = await client.post(
            "/api/v1/media/upload",
            files={"file": ("box.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers=auth_headers(token, f"idem_box_media_{uuid.uuid4().hex}"),
        )
        assert up_res.status_code == 201
        uploaded_media_id = up_res.json()["media_id"]

        # 3. Simulate ATTACH_MEDIA operation: PUT product with media_id
        attach_res = await client.put(
            f"/api/v1/products/{prod_id}",
            json={"media_id": uploaded_media_id, "expected_revision": initial_prod["revision"]},
            headers=auth_headers(token, f"idem_attach_{uuid.uuid4().hex}"),
        )
        assert attach_res.status_code == 200
        attached_prod = attach_res.json()

        # Capture server-returned revision and content_hash
        server_revision = attached_prod["revision"]
        server_content_hash = attached_prod["content_hash"]
        assert server_revision == 2
        assert len(server_content_hash) == 64

        # 4. Simulate APPROVE_PUBLISH operation using server-returned revision & hash
        pub_res = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={"revision": server_revision, "content_hash": server_content_hash},
            headers=auth_headers(token, f"idem_box_pub_{uuid.uuid4().hex}"),
        )
        assert pub_res.status_code == 200
        published = pub_res.json()
        assert published["status"] == "published"
        assert published["revision"] == 2
        assert published["approved_revision"] == 2
        assert published["content_hash"] == server_content_hash


@pytest.mark.anyio
async def test_criterion_3_require_idempotency_keys_on_all_mutating_calls(e2e_env):
    """
    Criterion 3:
    Backend returns HTTP 422 when required Idempotency-Key header is absent
    on create, update, delete, upload, approve/publish, and sync.
    """
    transport = ASGITransport(app=app)
    token = e2e_env["token"]
    no_key_headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Create product
        res1 = await client.post("/api/v1/products", json={"title": "Test", "price": 100.0, "description": "T"}, headers=no_key_headers)
        assert res1.status_code == 422
        assert "Idempotency-Key" in res1.json()["detail"]

        # 2. Update product
        res2 = await client.put("/api/v1/products/prod_dummy", json={"title": "Test"}, headers=no_key_headers)
        assert res2.status_code == 422
        assert "Idempotency-Key" in res2.json()["detail"]

        # 3. Delete product
        res3 = await client.delete("/api/v1/products/prod_dummy", headers=no_key_headers)
        assert res3.status_code == 422
        assert "Idempotency-Key" in res3.json()["detail"]

        # 4. Media upload
        res4 = await client.post(
            "/api/v1/media/upload",
            files={"file": ("test.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers=no_key_headers,
        )
        assert res4.status_code == 422
        assert "Idempotency-Key" in res4.json()["detail"]

        # 5. Approve and publish
        res5 = await client.post(
            "/api/v1/products/prod_dummy/approve-and-publish",
            json={"revision": 1, "content_hash": "a" * 64},
            headers=no_key_headers,
        )
        assert res5.status_code == 422
        assert "Idempotency-Key" in res5.json()["detail"]

        # 6. Batch sync
        res6 = await client.post("/api/v1/products/sync", json={"products": []}, headers=no_key_headers)
        assert res6.status_code == 422
        assert "Idempotency-Key" in res6.json()["detail"]


@pytest.mark.anyio
async def test_criterion_4_preserve_audit_history_deliberately(e2e_env):
    """
    Criterion 4:
    Soft-delete / tombstone policy preserves ProductRevisionDB records for auditability.
    Product is excluded from listings and public catalogue; FK relationships remain intact.
    """
    transport = ASGITransport(app=app)
    token = e2e_env["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Upload media and create product
        up_res = await client.post(
            "/api/v1/media/upload",
            files={"file": ("audit.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers=auth_headers(token, f"idem_audit_med_{uuid.uuid4().hex}"),
        )
        assert up_res.status_code == 201
        media_id = up_res.json()["media_id"]

        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Rosewood Panel",
                "description": "Hand carved rosewood wall panel",
                "price": 3000.0,
                "materials_cost": 1000.0,
                "labor_hours": 5.0,
                "hourly_rate": 200.0,
                "media_id": media_id,
            },
            headers=auth_headers(token, f"idem_audit_cr_{uuid.uuid4().hex}"),
        )
        assert create_res.status_code == 201
        prod = create_res.json()
        prod_id = prod["id"]

        # 2. Approve and publish -> generates ProductRevisionDB row
        pub_res = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={"revision": prod["revision"], "content_hash": prod["content_hash"]},
            headers=auth_headers(token, f"idem_audit_pub_{uuid.uuid4().hex}"),
        )
        assert pub_res.status_code == 200

        # 3. Soft-delete the product
        del_res = await client.delete(
            f"/api/v1/products/{prod_id}",
            headers=auth_headers(token, f"idem_audit_del_{uuid.uuid4().hex}"),
        )
        assert del_res.status_code == 200
        assert del_res.json()["deleted"] is True

        # 4. Verified excluded from private GET, artisan list, and public catalogue
        get_res = await client.get(f"/api/v1/products/{prod_id}", headers=auth_headers(token))
        assert get_res.status_code == 404

        artisan_list = await client.get("/api/v1/products", headers=auth_headers(token))
        assert not any(p["id"] == prod_id for p in artisan_list.json())

        pub_cat = await client.get("/api/v1/products/public")
        assert not any(p["id"] == prod_id for p in pub_cat.json())

    # 5. Authoritative database assertion: ProductRevisionDB audit record remains intact!
    db = SessionLocal()
    prod_row = db.query(ProductDB).filter(ProductDB.id == prod_id).first()
    assert prod_row is not None
    assert prod_row.is_deleted is True
    assert prod_row.status == ProductStatus.DELETED.value

    revisions = db.query(ProductRevisionDB).filter(ProductRevisionDB.product_id == prod_id).all()
    assert len(revisions) == 1
    rev = revisions[0]
    assert rev.revision == 1
    assert rev.title == "Rosewood Panel"
    assert rev.media_id == media_id
    assert rev.approved_by_artisan_id == e2e_env["artisan_id"]
    db.close()


@pytest.mark.anyio
async def test_criterion_5_clean_up_media_failure_artifacts_and_deduplicate(e2e_env, monkeypatch):
    """
    Criterion 5:
    - If database transaction fails during media upload, orphaned local file is cleaned up.
    - Idempotent upload replay returns original media_id without duplicate records or files.
    """
    transport = ASGITransport(app=app)
    token = e2e_env["token"]
    fail_key = f"idem_fail_media_{uuid.uuid4().hex}"

    upload_dir = Path(get_settings().upload_dir) / "private"
    files_before = set(upload_dir.glob("*")) if upload_dir.exists() else set()

    # Part A: Test transaction failure cleans up orphaned file
    def mock_flush(self, *args, **kwargs):
        raise RuntimeError("Simulated Database Error During File Registration")

    with monkeypatch.context() as m:
        m.setattr("sqlalchemy.orm.Session.flush", mock_flush)
        with pytest.raises(RuntimeError, match="Simulated Database Error"):
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                await client.post(
                    "/api/v1/media/upload",
                    files={"file": ("crash.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
                    headers=auth_headers(token, fail_key),
                )

    files_after_crash = set(upload_dir.glob("*")) if upload_dir.exists() else set()
    new_orphans = files_after_crash - files_before
    assert len(new_orphans) == 0, f"Orphaned files remained on disk: {new_orphans}"

    # Part B: Test idempotent deduplication returns original media_id without extra files
    dedup_key = f"idem_dedup_media_{uuid.uuid4().hex}"
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # First upload
        res1 = await client.post(
            "/api/v1/media/upload",
            files={"file": ("wood_item.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers=auth_headers(token, dedup_key),
        )
        assert res1.status_code == 201
        media_id_1 = res1.json()["media_id"]

        files_after_first = len(list(upload_dir.glob("*")))

        # Duplicate replay with same idempotency key
        res2 = await client.post(
            "/api/v1/media/upload",
            files={"file": ("wood_item.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers=auth_headers(token, dedup_key),
        )
        assert res2.status_code == 201
        media_id_2 = res2.json()["media_id"]

        assert media_id_1 == media_id_2, "Idempotent replay must return original media_id"
        files_after_second = len(list(upload_dir.glob("*")))
        assert files_after_second == files_after_first, "Duplicate file must not be created on replay"
