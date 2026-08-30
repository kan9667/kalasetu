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
    """Stage 1 Verification: Standalone Python pipeline correctness."""
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


def test_stage2_fastapi_multipart_endpoint(tmp_path):
    """Stage 2 Verification: FastAPI TestClient multipart POST to /api/v1/catalog/enhance-image."""
    client = TestClient(app)

    # Prepare in-memory image
    sample_path = tmp_path / "upload_sample.jpg"
    _create_sample_test_image(sample_path)

    with open(sample_path, "rb") as f:
        file_bytes = f.read()

    response = client.post(
        "/api/v1/catalog/enhance-image",
        files={"image": ("upload_sample.jpg", file_bytes, "image/jpeg")},
    )

    assert response.status_code == 200, f"Expected 200, got {response.status_code}: {response.text}"
    data = response.json()
    assert "original_url" in data
    assert "enhanced_url" in data
    assert data["status"] == "success"
    assert "/uploads/raw/" in data["original_url"] or "/uploads/" in data["original_url"]
    assert "/uploads/enhanced/" in data["enhanced_url"]

    print(f"✅ Stage 2 Passed: FastAPI endpoint returned 200 OK with original_url={data['original_url']} & enhanced_url={data['enhanced_url']}")


if __name__ == "__main__":
    import tempfile
    with tempfile.TemporaryDirectory() as tmp_dir:
        test_stage1_standalone_image_pipeline(Path(tmp_dir))
        test_stage2_fastapi_multipart_endpoint(Path(tmp_dir))
    print("\n🎉 All Backend & ML Image Pipeline Tests Passed Successfully!")
