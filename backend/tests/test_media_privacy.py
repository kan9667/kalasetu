"""
Media Privacy & Access Control Tests.
Verifies:
- Authenticated tenant-only access for private drafts: GET /api/v1/media/{id}.
- Rejection of unauthenticated callers (401) and other artisans (404/403).
- Public access gatekept strictly against active published ProductRevisionDB: GET /api/v1/media/{id}/public.
- Static /uploads directory mount is eliminated (404).
- Failure artifact cleanup: orphaned files on disk are removed if transaction fails.
- Idempotent upload returns original media_id without duplicate files.
"""

import io
import os
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path
import pytest
from httpx import AsyncClient, ASGITransport

from backend.main import app
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB, IdempotencyRecordDB, MediaAssetDB, ProductDB, ProductRevisionDB, ProductStatus
from backend.utils.auth import create_access_token


@pytest.fixture(scope="module")
def setup_media_env():
    init_db()
    db = SessionLocal()

    # Create two artisans
    artisan_a = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_media_a").first()
    if not artisan_a:
        artisan_a = ArtisanDB(
            id="artisan_media_a",
            name="Artisan A",
            phone="9876543201",
            craft_type="Pottery",
            created_at=datetime.now(timezone.utc),
        )
        db.add(artisan_a)

    artisan_b = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_media_b").first()
    if not artisan_b:
        artisan_b = ArtisanDB(
            id="artisan_media_b",
            name="Artisan B",
            phone="9876543202",
            craft_type="Weaving",
            created_at=datetime.now(timezone.utc),
        )
        db.add(artisan_b)

    db.commit()
    token_a = create_access_token("artisan_media_a")
    token_b = create_access_token("artisan_media_b")
    db.close()

    return {"token_a": token_a, "token_b": token_b}


# Minimal valid 1x1 PNG bytes
VALID_PNG_BYTES = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff"
    b"?\x00\x05\xfe\x02\xfe\xa748V\x00\x00\x00\x00IEND\xaeB`\x82"
)


@pytest.mark.anyio
async def test_static_uploads_mount_removed():
    """Verify that the unauthenticated static /uploads mount is completely removed."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.get("/uploads/test.jpg")
        assert res.status_code == 404


@pytest.mark.anyio
async def test_unauthenticated_media_rejected():
    """Unauthenticated request to private media endpoint is rejected with 401."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.get("/api/v1/media/med_nonexistent")
        assert res.status_code == 401


@pytest.mark.anyio
async def test_media_upload_and_tenant_privacy(setup_media_env):
    """Artisan A uploads media; only Artisan A can view private media; Artisan B is rejected."""
    transport = ASGITransport(app=app)
    token_a = setup_media_env["token_a"]
    token_b = setup_media_env["token_b"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Upload media as Artisan A
        upload_res = await client.post(
            "/api/v1/media/upload",
            files={"file": ("pot.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": f"idem_up_{uuid.uuid4().hex}"},
        )
        assert upload_res.status_code == 201
        media_data = upload_res.json()
        media_id = media_data["media_id"]
        assert media_data["status"] == "ready"
        assert len(media_data["sha256_checksum"]) == 64

        # 2. Owner Artisan A can retrieve private media
        get_res_a = await client.get(
            f"/api/v1/media/{media_id}",
            headers={"Authorization": f"Bearer {token_a}"},
        )
        assert get_res_a.status_code == 200
        assert get_res_a.headers["content-type"] == "image/png"
        assert get_res_a.content == VALID_PNG_BYTES

        # 3. Other Artisan B is rejected (tenant isolation)
        get_res_b = await client.get(
            f"/api/v1/media/{media_id}",
            headers={"Authorization": f"Bearer {token_b}"},
        )
        assert get_res_b.status_code in (403, 404)

        # 4. Public access is rejected because media is not yet in an approved published revision
        pub_get_res = await client.get(f"/api/v1/media/{media_id}/public")
        assert pub_get_res.status_code == 404


@pytest.mark.anyio
async def test_public_media_access_gatekept_by_published_revision(setup_media_env):
    """Media is publicly accessible only once referenced in an active approved published revision."""
    transport = ASGITransport(app=app)
    token_a = setup_media_env["token_a"]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Upload media
        upload_res = await client.post(
            "/api/v1/media/upload",
            files={"file": ("bowl.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": f"idem_up_{uuid.uuid4().hex}"},
        )
        assert upload_res.status_code == 201
        media_id = upload_res.json()["media_id"]

        # 2. Create product with media
        create_res = await client.post(
            "/api/v1/products",
            json={
                "title": "Clay Bowl",
                "description": "Handmade bowl",
                "price": 400.0,
                "materials_cost": 100.0,
                "labor_hours": 1.0,
                "hourly_rate": 100.0,
                "media_id": media_id,
            },
            headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": f"idem_cr_{uuid.uuid4().hex}"},
        )
        assert create_res.status_code == 201
        prod = create_res.json()
        prod_id = prod["id"]

        # Before publish, public media access fails
        pub_before = await client.get(f"/api/v1/media/{media_id}/public")
        assert pub_before.status_code == 404

        # 3. Explicitly approve and publish
        pub_res = await client.post(
            f"/api/v1/products/{prod_id}/approve-and-publish",
            json={"revision": prod["revision"], "content_hash": prod["content_hash"]},
            headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": f"idem_pub_{uuid.uuid4().hex}"},
        )
        assert pub_res.status_code == 200

        # After publish, public media access succeeds without authentication
        pub_after = await client.get(f"/api/v1/media/{media_id}/public")
        assert pub_after.status_code == 200
        assert pub_after.headers["content-type"] == "image/png"
        assert pub_after.content == VALID_PNG_BYTES

        # 4. If product is un-published / edited, public media access is immediately revoked
        edit_res = await client.put(
            f"/api/v1/products/{prod_id}",
            json={"title": "Clay Bowl Modified"},
            headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": f"idem_ed_{uuid.uuid4().hex}"},
        )
        assert edit_res.status_code == 200

        pub_revoked = await client.get(f"/api/v1/media/{media_id}/public")
        assert pub_revoked.status_code == 404


@pytest.mark.anyio
async def test_media_upload_idempotency(setup_media_env):
    """Replaying media upload with the same Idempotency-Key returns the original media_id without duplicate files."""
    transport = ASGITransport(app=app)
    token_a = setup_media_env["token_a"]
    key = f"idem_upload_dedup_{uuid.uuid4().hex}"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # First attempt
        res1 = await client.post(
            "/api/v1/media/upload",
            files={"file": ("pottery.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": key},
        )
        assert res1.status_code == 201
        media_id_1 = res1.json()["media_id"]

        # Duplicate attempt with same key
        res2 = await client.post(
            "/api/v1/media/upload",
            files={"file": ("pottery.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
            headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": key},
        )
        assert res2.status_code == 201
        media_id_2 = res2.json()["media_id"]

        # Must return exact same media_id
        assert media_id_1 == media_id_2


@pytest.mark.anyio
async def test_media_upload_failure_cleans_up_orphaned_file(setup_media_env, monkeypatch):
    """
    Mandatory Acceptance Criteria 5:
    If a database transaction fails after writing a local media file,
    the orphaned file must be cleaned up and removed from disk.
    """
    transport = ASGITransport(app=app)
    token_a = setup_media_env["token_a"]
    key = f"idem_fail_{uuid.uuid4().hex}"

    from backend.config import get_settings
    upload_dir = Path(get_settings().upload_dir) / "private"

    files_before = set(upload_dir.glob("*")) if upload_dir.exists() else set()

    # Monkeypatch Session.flush to raise a database crash
    def mock_flush(self, *args, **kwargs):
        raise RuntimeError("Simulated DB Crash during Media Persistence")

    with monkeypatch.context() as m:
        m.setattr("sqlalchemy.orm.Session.flush", mock_flush)
        with pytest.raises(RuntimeError, match="Simulated DB Crash"):
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                await client.post(
                    "/api/v1/media/upload",
                    files={"file": ("crash.png", io.BytesIO(VALID_PNG_BYTES), "image/png")},
                    headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": key},
                )

    # Verify no orphaned files were left behind in the uploads directory
    files_after = set(upload_dir.glob("*")) if upload_dir.exists() else set()
    new_orphans = files_after - files_before
    assert len(new_orphans) == 0, f"Found orphaned files left on disk after failure: {new_orphans}"


@pytest.mark.anyio
async def test_media_upload_lease_expiry_reclamation_and_replay_dedup(setup_media_env):
    """
    Mandatory Acceptance Criteria 5:
    If an idempotency lease expires, a subsequent upload attempt safely reclaims the lease.
    A completed idempotent replay returns the original media_id without duplicate files.
    """
    transport = ASGITransport(app=app)
    token_a = setup_media_env["token_a"]
    key = f"idem_media_lease_{uuid.uuid4().hex}"
    now = datetime.now(timezone.utc)

    # 1. Simulate a crashed worker: insert an in_progress record with expired lease
    import hashlib
    from backend.utils.idempotency import compute_request_fingerprint
    unique_bytes = VALID_PNG_BYTES + f"unique_lease_{uuid.uuid4().hex}".encode()
    file_sha = hashlib.sha256(unique_bytes).hexdigest()
    req_hash = compute_request_fingerprint("POST", "/api/v1/media/upload", file_sha)

    db = SessionLocal()
    crashed_rec = IdempotencyRecordDB(
        id=f"idem_rec_{uuid.uuid4().hex[:8]}",
        artisan_id="artisan_media_a",
        idempotency_key=key,
        endpoint="/api/v1/media/upload",
        request_hash=req_hash,
        status="in_progress",
        lease_expires_at=now - timedelta(seconds=10),
        created_at=now - timedelta(seconds=70),
        updated_at=now - timedelta(seconds=70),
    )
    db.add(crashed_rec)
    db.commit()
    db.close()

    from backend.config import get_settings
    upload_dir = Path(get_settings().upload_dir) / "private"
    files_before = len(list(upload_dir.glob("*"))) if upload_dir.exists() else 0

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Reclaimed attempt succeeds and returns 201
        res1 = await client.post(
            "/api/v1/media/upload",
            files={"file": ("clay.png", io.BytesIO(unique_bytes), "image/png")},
            headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": key},
        )
        assert res1.status_code == 201
        media_id_1 = res1.json()["media_id"]

        files_after_res1 = len(list(upload_dir.glob("*")))
        assert files_after_res1 == files_before + 1

        # Replaying identical completed request returns cached media_id and DOES NOT create a new file
        res2 = await client.post(
            "/api/v1/media/upload",
            files={"file": ("clay.png", io.BytesIO(unique_bytes), "image/png")},
            headers={"Authorization": f"Bearer {token_a}", "Idempotency-Key": key},
        )
        assert res2.status_code == 201
        assert res2.json()["media_id"] == media_id_1

        files_after_res2 = len(list(upload_dir.glob("*")))
        assert files_after_res2 == files_after_res1, "Duplicate file must NOT be created on idempotent replay"
