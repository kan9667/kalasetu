"""
Server Idempotency and Concurrency Control Tests.
Verifies:
- Required Idempotency-Key on all mutating routes (missing -> 422).
- Replay with identical key and payload returns cached response without duplicate operations.
- Reusing key with altered payload raises 409 Conflict (tampering detection).
- Concurrent in-progress lease returns 409 Conflict with Retry-After header.
- Expired lease reclamation allows retry after worker/connection crash.
- Optimistic locking: PUT with mismatched expected_revision returns 409 Conflict.
"""

import io
import uuid
from datetime import datetime, timedelta, timezone
import pytest
from httpx import AsyncClient, ASGITransport

from backend.main import app
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB, IdempotencyRecordDB, MediaAssetDB, ProductDB, ProductStatus
from backend.utils.auth import create_access_token


VALID_PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff"
    b"?\x00\x05\xfe\x02\xfe\xa748V\x00\x00\x00\x00IEND\xaeB`\x82"
)


@pytest.fixture(scope="module")
def setup_idempotency_artisan():
    init_db()
    db = SessionLocal()

    artisan = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_idem_test").first()
    if not artisan:
        artisan = ArtisanDB(
            id="artisan_idem_test",
            name="Idem Artisan",
            phone="9876543233",
            craft_type="Brass",
            created_at=datetime.now(timezone.utc),
        )
        db.add(artisan)

    # Add verified media asset
    media = db.query(MediaAssetDB).filter(MediaAssetDB.id == "med_idem_ready").first()
    if not media:
        media = MediaAssetDB(
            id="med_idem_ready",
            artisan_id="artisan_idem_test",
            file_path="/tmp/med_idem_ready.png",
            file_url="/api/v1/media/med_idem_ready",
            mime_type="image/png",
            byte_size=len(VALID_PNG),
            sha256_checksum="dummy_checksum_idem",
            status="ready",
        )
        db.add(media)

    db.commit()
    token = create_access_token("artisan_idem_test")
    db.close()
    return {"token": token, "media_id": "med_idem_ready"}


@pytest.mark.anyio
async def test_missing_idempotency_key_rejected_with_422(setup_idempotency_artisan):
    """Mutating endpoints strictly require Idempotency-Key header."""
    transport = ASGITransport(app=app)
    token = setup_idempotency_artisan["token"]
    headers_no_idem = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. POST /products
        res_create = await client.post(
            "/api/v1/products",
            json={"title": "Test", "description": "Test", "price": 100.0},
            headers=headers_no_idem,
        )
        assert res_create.status_code == 422
        assert "Idempotency-Key" in res_create.json()["detail"]

        # 2. PUT /products/some_id
        res_put = await client.put(
            "/api/v1/products/prod_dummy",
            json={"title": "Updated"},
            headers=headers_no_idem,
        )
        assert res_put.status_code == 422
        assert "Idempotency-Key" in res_put.json()["detail"]

        # 3. DELETE /products/some_id
        res_del = await client.delete(
            "/api/v1/products/prod_dummy",
            headers=headers_no_idem,
        )
        assert res_del.status_code == 422
        assert "Idempotency-Key" in res_del.json()["detail"]

        # 4. POST /media/upload
        res_upload = await client.post(
            "/api/v1/media/upload",
            files={"file": ("test.png", io.BytesIO(VALID_PNG), "image/png")},
            headers=headers_no_idem,
        )
        assert res_upload.status_code == 422
        assert "Idempotency-Key" in res_upload.json()["detail"]

        # 5. POST /approve-and-publish
        res_pub = await client.post(
            "/api/v1/products/prod_dummy/approve-and-publish",
            json={"revision": 1, "content_hash": "a" * 64},
            headers=headers_no_idem,
        )
        assert res_pub.status_code == 422
        assert "Idempotency-Key" in res_pub.json()["detail"]

        # 6. POST /sync
        res_sync = await client.post(
            "/api/v1/products/sync",
            json={"products": []},
            headers=headers_no_idem,
        )
        assert res_sync.status_code == 422
        assert "Idempotency-Key" in res_sync.json()["detail"]


@pytest.mark.anyio
async def test_idempotent_replay_and_tampering_detection(setup_idempotency_artisan):
    """Replaying exact request returns cached response; modified payload with same key returns 409."""
    transport = ASGITransport(app=app)
    token = setup_idempotency_artisan["token"]
    key = f"idem_replay_{uuid.uuid4().hex}"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        payload1 = {
            "title": "Idempotent Vase",
            "description": "Ceramic vase",
            "price": 500.0,
            "materials_cost": 100.0,
            "labor_hours": 1.0,
            "hourly_rate": 100.0,
        }

        # 1. First execution -> 201 Created
        res1 = await client.post(
            "/api/v1/products",
            json=payload1,
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
        )
        assert res1.status_code == 201
        created_id = res1.json()["id"]

        # 2. Replay with identical payload -> 201 with identical content
        res2 = await client.post(
            "/api/v1/products",
            json=payload1,
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
        )
        assert res2.status_code == 201
        assert res2.json()["id"] == created_id

        # 3. Tampering: reusing the same idempotency key with a DIFFERENT payload -> 409 Conflict
        payload_tampered = {
            "title": "Tampered Vase Title",
            "description": "Different content",
            "price": 800.0,
            "materials_cost": 100.0,
            "labor_hours": 1.0,
            "hourly_rate": 100.0,
        }
        res3 = await client.post(
            "/api/v1/products",
            json=payload_tampered,
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
        )
        assert res3.status_code == 409
        assert "mismatched request payload" in res3.json()["detail"].lower()


@pytest.mark.anyio
async def test_concurrent_claim_protection_and_expired_lease_reclamation(setup_idempotency_artisan):
    """An active in-progress lease returns 409 with Retry-After; an expired lease is reclaimed."""
    db = SessionLocal()
    token = setup_idempotency_artisan["token"]
    key = f"idem_lease_{uuid.uuid4().hex}"
    now = datetime.now(timezone.utc)

    # 1. Manually insert an active in_progress record
    active_rec = IdempotencyRecordDB(
        id=f"idem_rec_{uuid.uuid4().hex[:8]}",
        artisan_id="artisan_idem_test",
        idempotency_key=key,
        endpoint="/api/v1/products",
        request_hash="some_hash",
        status="in_progress",
        lease_expires_at=now + timedelta(seconds=60),  # Active lease
        created_at=now,
        updated_at=now,
    )
    db.add(active_rec)
    db.commit()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Request while lease is active returns 409 with Retry-After
        res_conflict = await client.post(
            "/api/v1/products",
            json={"title": "Bowl", "description": "Bowl", "price": 200.0},
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
        )
        assert res_conflict.status_code == 409
        assert "in progress" in res_conflict.json()["detail"].lower()
        assert res_conflict.headers.get("retry-after") == "5"

        # 2. Simulate worker crash: expire the lease
        active_rec.lease_expires_at = now - timedelta(seconds=10)
        db.commit()
        db.close()

        # Subsequent request reclaims the lease successfully
        res_reclaimed = await client.post(
            "/api/v1/products",
            json={"title": "Bowl", "description": "Bowl", "price": 200.0},
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
        )
        assert res_reclaimed.status_code == 201
        assert res_reclaimed.json()["title"] == "Bowl"


@pytest.mark.anyio
async def test_optimistic_locking_expected_revision(setup_idempotency_artisan):
    """PUT update with mismatched expected_revision returns 409 Conflict."""
    transport = ASGITransport(app=app)
    token = setup_idempotency_artisan["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Create draft (revision=1)
        cr = await client.post(
            "/api/v1/products",
            json={"title": "Concurrency Lamp", "description": "Brass lamp", "price": 900.0},
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": f"idem_cr_{uuid.uuid4().hex}"},
        )
        assert cr.status_code == 201
        prod_id = cr.json()["id"]

        # Update with wrong expected_revision (expected 99, current is 1) -> 409
        bad_update = await client.put(
            f"/api/v1/products/{prod_id}",
            json={"title": "Updated Lamp", "expected_revision": 99},
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": f"idem_bad_{uuid.uuid4().hex}"},
        )
        assert bad_update.status_code == 409
        assert "revision conflict" in bad_update.json()["detail"].lower()

        # Update with correct expected_revision (1) -> 200 OK (bumps to 2)
        good_update = await client.put(
            f"/api/v1/products/{prod_id}",
            json={"title": "Updated Lamp", "expected_revision": 1},
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": f"idem_good_{uuid.uuid4().hex}"},
        )
        assert good_update.status_code == 200
        assert good_update.json()["revision"] == 2


@pytest.mark.anyio
async def test_batch_sync_optimistic_locking_and_rollback(setup_idempotency_artisan):
    """
    Requirement 5: Add optimistic locking to batch sync.
    Verify:
    1. Syncing existing product with mismatched expected_revision returns 409 Conflict.
    2. Syncing existing product with omitted expected_revision returns 409 Conflict.
    3. In an all-or-nothing batch with 2 products (one valid new product and one stale update),
       the 409 Conflict rolls back the entire batch, so the valid new product is NOT created.
    4. Syncing with valid matching expected_revision succeeds and increments revision.
    """
    transport = ASGITransport(app=app)
    token = setup_idempotency_artisan["token"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Create an existing product (revision=1)
        cr = await client.post(
            "/api/v1/products",
            json={"title": "Sync Target Vase", "description": "Terracotta vase", "price": 800.0},
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": f"idem_sync_init_{uuid.uuid4().hex}"},
        )
        assert cr.status_code == 201
        existing_id = cr.json()["id"]
        assert cr.json()["revision"] == 1

        # Test 1: Sync with mismatched expected_revision (expected 99, remote is 1) -> 409
        bad_sync_batch = {
            "products": [
                {
                    "id": existing_id,
                    "title": "Sync Target Vase Modified",
                    "description": "Terracotta vase modified",
                    "price": 800.0,
                    "expected_revision": 99,
                }
            ]
        }
        res_bad_sync = await client.post(
            "/api/v1/products/sync",
            json=bad_sync_batch,
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": f"idem_sync_bad_{uuid.uuid4().hex}"},
        )
        assert res_bad_sync.status_code == 409
        assert "conflict" in res_bad_sync.json()["detail"].lower()

        # Test 2: Sync with omitted expected_revision on existing product -> 409
        omitted_sync_batch = {
            "products": [
                {
                    "id": existing_id,
                    "title": "Sync Target Vase Without Rev",
                    "description": "Terracotta vase",
                    "price": 800.0,
                }
            ]
        }
        res_omitted_sync = await client.post(
            "/api/v1/products/sync",
            json=omitted_sync_batch,
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": f"idem_sync_omit_{uuid.uuid4().hex}"},
        )
        assert res_omitted_sync.status_code == 409

        # Test 3: All-or-nothing batch rollback:
        # Product A is brand new. Product B has stale expected_revision.
        new_prod_id = f"prod_new_batch_{uuid.uuid4().hex[:8]}"
        mixed_batch = {
            "products": [
                {
                    "id": new_prod_id,
                    "title": "New Batch Product",
                    "description": "Should be rolled back",
                    "price": 500.0,
                    "expected_revision": None,
                },
                {
                    "id": existing_id,
                    "title": "Stale Update in Batch",
                    "description": "Will cause conflict",
                    "price": 800.0,
                    "expected_revision": 5,  # Mismatch (remote is 1)
                },
            ]
        }
        res_mixed = await client.post(
            "/api/v1/products/sync",
            json=mixed_batch,
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": f"idem_sync_mix_{uuid.uuid4().hex}"},
        )
        assert res_mixed.status_code == 409

        # Verify all-or-nothing transaction rollback: new_prod_id must NOT exist in DB
        res_check_new = await client.get(
            f"/api/v1/products/{new_prod_id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert res_check_new.status_code == 404

        # Verify existing_id was NOT modified by the rolled back batch
        res_check_existing = await client.get(
            f"/api/v1/products/{existing_id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert res_check_existing.status_code == 200
        assert res_check_existing.json()["revision"] == 1
        assert res_check_existing.json()["title"] == "Sync Target Vase"

        # Test 4: Sync with matching expected_revision (1) -> 200 OK, bumps revision to 2
        good_sync_batch = {
            "products": [
                {
                    "id": existing_id,
                    "title": "Sync Target Vase Successfully Updated",
                    "description": "Terracotta vase updated",
                    "price": 850.0,
                    "expected_revision": 1,
                }
            ]
        }
        res_good_sync = await client.post(
            "/api/v1/products/sync",
            json=good_sync_batch,
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": f"idem_sync_good_{uuid.uuid4().hex}"},
        )
        assert res_good_sync.status_code == 200
        assert res_good_sync.json()["synced_count"] == 1
        synced_item = res_good_sync.json()["products"][0]
        assert synced_item["revision"] == 2
        assert synced_item["title"] == "Sync Target Vase Successfully Updated"
