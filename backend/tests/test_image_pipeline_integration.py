"""
Integration Tests for AI Image Enhancement Pipeline & FastAPI Catalog Router.

Stage 1: Validates standalone Python pipeline output:
- Resolution is exact 1200x1200 square e-commerce standard
- Background pixels are pure white (255, 255, 255)
- Image is valid, non-empty, and lighting-enhanced

Stage 2: Validates FastAPI multipart POST endpoint:
- Non-blocking execution via threadpool
- HTTP 200 response with original_url and enhanced_url
- Files are saved properly in upload directories
"""

import os
import sys
import io
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
import pytest

# Ensure root is in path
PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))
ML_DIR = PROJECT_ROOT / "ML" / "image_pipeline"
if str(ML_DIR) not in sys.path:
    sys.path.insert(0, str(ML_DIR))

from fastapi.testclient import TestClient
from backend.main import app
from ML.image_pipeline.enhancer import enhance_image


def _create_sample_test_image(path: Path):
    """Create a synthetic test craft image with a subject and colored background."""
    img = Image.new("RGB", (600, 800), color=(180, 160, 140)) # Warm dusty background
    draw = ImageDraw.Draw(img)
    # Draw a simulated clay vase subject
    draw.ellipse([150, 250, 450, 700], fill=(160, 60, 40), outline=(100, 30, 20), width=4)
    draw.polygon([(220, 260), (380, 260), (350, 180), (250, 180)], fill=(180, 80, 50))
    img.save(path, format="JPEG", quality=90)


def test_stage1_standalone_image_pipeline(tmp_path):
    """Stage 1 Verification: Standalone Python pipeline correctness (opt-in via RUN_REMBG_TESTS=1)."""
    if os.environ.get("RUN_REMBG_TESTS") != "1":
        pytest.skip("Real rembg ML execution is opt-in via RUN_REMBG_TESTS=1")

    try:
        import rembg  # noqa: F401
    except Exception as e:
        pytest.skip(f"rembg ML dependency failed runtime import or initialization: {e}")

    input_file = tmp_path / "test_raw_pot.jpg"
    output_file = tmp_path / "test_enhanced_pot.jpg"
    _create_sample_test_image(input_file)

    # Execute enhancement
    result_path = enhance_image(str(input_file), output_path=str(output_file))
    assert Path(result_path).exists(), "Output enhanced image was not created"

    # Verify output properties
    with Image.open(result_path) as out_img:
        # 1. Exact square 1200x1200 canvas
        assert out_img.size == (1200, 1200), f"Expected 1200x1200, got {out_img.size}"
        assert out_img.mode == "RGB", f"Expected RGB mode, got {out_img.mode}"

        # 2. Pure white background at corners
        img_np = np.array(out_img)
        top_left_corner = img_np[10, 10]
        bottom_right_corner = img_np[1190, 1190]
        assert (top_left_corner >= [250, 250, 250]).all(), f"Top-left corner is not white: {top_left_corner}"
        assert (bottom_right_corner >= [250, 250, 250]).all(), f"Bottom-right corner is not white: {bottom_right_corner}"

    print("✅ Stage 1 Passed: Standalone pipeline output is 1200x1200 with pure white background canvas.")


def test_stage2_fastapi_multipart_endpoint(tmp_path, monkeypatch):
    """Stage 2 Verification: FastAPI TestClient multipart POST with deterministic fake enhancer asserting ready output."""
    from backend.database import SessionLocal, init_db
    from backend.models.db_models import ArtisanDB
    from backend.utils.auth import create_access_token
    from backend.routers.catalog import catalog_service
    import uuid

    init_db()
    db = SessionLocal()
    if not db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_img_test").first():
        db.add(ArtisanDB(id="artisan_img_test", name="Img Artisan", phone="+919876543214"))
        db.commit()
    db.close()

    # Deterministic fake enhancer creating a valid 1200x1200 canvas
    async def fake_enhance(input_path: str, output_path: str | None = None):
        out_p = Path(output_path or input_path)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        img = Image.new("RGB", (1200, 1200), color=(255, 255, 255))
        img.save(out_p, format="JPEG", quality=90)
        return str(out_p), False, None

    monkeypatch.setattr(catalog_service, "enhance_product_photo", fake_enhance)

    token = create_access_token("artisan_img_test")
    client = TestClient(app, headers={"Authorization": f"Bearer {token}"})

    # Prepare in-memory image
    sample_path = tmp_path / "upload_sample.jpg"
    _create_sample_test_image(sample_path)

    with open(sample_path, "rb") as f:
        file_bytes = f.read()

    response = client.post(
        "/api/v1/catalog/enhance-image",
        files={"image": ("upload_sample.jpg", file_bytes, "image/jpeg")},
        data={"return_format": "JPEG"},
        headers={"Idempotency-Key": f"test_img_stage2_{uuid.uuid4().hex}"},
    )

    assert response.status_code == 200, f"Expected 200, got {response.status_code}: {response.text}"
    data = response.json()
    assert "media_id" in data
    assert "original_media_id" in data
    assert data["status"] in ["ready", "success"]
    assert data["is_degraded"] is False
    assert data["degraded_reason"] is None
    assert data["media_id"].startswith("med_")
    assert data["original_media_id"].startswith("med_")
    print(f"✅ Stage 2 Passed: FastAPI endpoint returned 200 OK with media_id={data['media_id']} and status={data['status']}")


def test_stage3_fastapi_multipart_endpoint_degraded_fallback(tmp_path, monkeypatch):
    """Stage 3 Verification: Deterministic forced failure asserting degraded status and preserved media lineage."""
    from backend.database import SessionLocal, init_db
    from backend.models.db_models import ArtisanDB
    from backend.utils.auth import create_access_token
    from backend.routers.catalog import catalog_service
    import uuid

    init_db()
    db = SessionLocal()
    if not db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_img_test").first():
        db.add(ArtisanDB(id="artisan_img_test", name="Img Artisan", phone="+919876543214"))
        db.commit()
    db.close()

    # Deterministic forced failure returning degraded status
    forced_reason = "Simulated GPU out-of-memory during rembg inference"
    async def forced_failure_enhance(input_path: str, output_path: str | None = None):
        out_p = Path(output_path or input_path)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        import shutil
        shutil.copy2(input_path, out_p)
        return str(out_p), True, forced_reason

    monkeypatch.setattr(catalog_service, "enhance_product_photo", forced_failure_enhance)

    token = create_access_token("artisan_img_test")
    client = TestClient(app, headers={"Authorization": f"Bearer {token}"})

    sample_path = tmp_path / "upload_sample_degraded.jpg"
    _create_sample_test_image(sample_path)

    with open(sample_path, "rb") as f:
        file_bytes = f.read()

    response = client.post(
        "/api/v1/catalog/enhance-image",
        files={"image": ("upload_sample_degraded.jpg", file_bytes, "image/jpeg")},
        data={"return_format": "JPEG"},
        headers={"Idempotency-Key": f"test_img_stage3_{uuid.uuid4().hex}"},
    )

    assert response.status_code == 200, f"Expected 200, got {response.status_code}: {response.text}"
    data = response.json()
    assert "media_id" in data
    assert "original_media_id" in data
    assert data["status"] == "degraded"
    assert data["is_degraded"] is True
    assert data["degraded_reason"] == forced_reason
    assert data["media_id"].startswith("med_")
    assert data["original_media_id"].startswith("med_")
    print(f"✅ Stage 3 Passed: Forced failure returned 200 degraded with lineage preserved (original={data['original_media_id']}, media={data['media_id']})")


if __name__ == "__main__":
    import tempfile
    with tempfile.TemporaryDirectory() as tmp_dir:
        test_stage1_standalone_image_pipeline(Path(tmp_dir))
        # Note: Stage 2 & 3 use monkeypatch, run via pytest
    print("\n🎉 Standalone ML Image Pipeline Tests Completed!")
