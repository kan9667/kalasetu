# ============================================================
# test_enhancer.py — Tests for the image enhancement pipeline
# ============================================================
# Uses synthetic test images created with Pillow so no external
# images are needed. Run with: python -m pytest tests/ -v
# ============================================================

import os
import sys
import pytest
import numpy as np
from PIL import Image, ImageDraw

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from config import SUPPORTED_FORMATS, MIN_DIMENSION, OUTPUT_WIDTH, OUTPUT_HEIGHT
from processors.input_validation import validate_input, ImageValidationError
from processors.cropping import detect_product_bounds, auto_crop
from processors.background_canvas import place_on_clean_background, place_on_ecommerce_canvas
from processors.lighting import improve_lighting, correct_white_balance, sharpen_image
from processors.image_output import resize_image, save_image


# ---- Helper: Create synthetic test images ----

def create_test_image(width=400, height=400, color=(180, 100, 50), mode="RGB"):
    """Create a simple solid-color test image."""
    return Image.new(mode, (width, height), color)


def create_product_on_background(
    canvas_size=(600, 600),
    product_size=(200, 200),
    product_color=(200, 100, 50),
    bg_color=(120, 150, 100)
):
    """Create a test image with a 'product' shape on a background."""
    image = Image.new("RGB", canvas_size, bg_color)
    draw = ImageDraw.Draw(image)
    
    # Center the product
    cx, cy = canvas_size[0] // 2, canvas_size[1] // 2
    pw, ph = product_size
    left = cx - pw // 2
    top = cy - ph // 2
    
    # Draw the product as a filled ellipse
    draw.ellipse([left, top, left + pw, top + ph], fill=product_color)
    
    return image


def create_rgba_with_product(
    canvas_size=(600, 600),
    product_size=(200, 200),
    product_color=(200, 100, 50, 255)
):
    """Create an RGBA image with a product on transparent background."""
    image = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    
    cx, cy = canvas_size[0] // 2, canvas_size[1] // 2
    pw, ph = product_size
    left = cx - pw // 2
    top = cy - ph // 2
    
    draw.ellipse([left, top, left + pw, top + ph], fill=product_color)
    
    return image


def save_temp_image(image, tmp_path, filename="test.jpg", format="JPEG"):
    """Save a test image to a temporary directory."""
    path = os.path.join(str(tmp_path), filename)
    if format == "JPEG" and image.mode == "RGBA":
        image = image.convert("RGB")
    image.save(path, format=format)
    return path


# ============================================================
# Tests for Stage 1: Input Validation
# ============================================================

class TestInputValidation:
    
    def test_valid_jpg(self, tmp_path):
        """Test that a valid JPG image passes validation."""
        img = create_test_image()
        path = save_temp_image(img, tmp_path, "test.jpg", "JPEG")
        result = validate_input(path)
        assert result is not None
        assert result.mode == "RGB"
    
    def test_valid_png(self, tmp_path):
        """Test that a valid PNG image passes validation."""
        img = create_test_image()
        path = save_temp_image(img, tmp_path, "test.png", "PNG")
        result = validate_input(path)
        assert result is not None
    
    def test_missing_file(self):
        """Test that a missing file raises ImageValidationError."""
        with pytest.raises(ImageValidationError, match="File not found"):
            validate_input("nonexistent_file.jpg")
    
    def test_unsupported_format(self, tmp_path):
        """Test that an unsupported format raises ImageValidationError."""
        path = os.path.join(str(tmp_path), "test.bmp")
        img = create_test_image()
        img.save(path, format="BMP")
        with pytest.raises(ImageValidationError, match="Unsupported file format"):
            validate_input(path)
    
    def test_too_small_image(self, tmp_path):
        """Test that a very small image raises ImageValidationError."""
        img = create_test_image(width=10, height=10)
        path = save_temp_image(img, tmp_path, "tiny.jpg", "JPEG")
        with pytest.raises(ImageValidationError, match="too small"):
            validate_input(path)
    
    def test_corrupted_file(self, tmp_path):
        """Test that a corrupted file raises ImageValidationError."""
        path = os.path.join(str(tmp_path), "corrupt.jpg")
        with open(path, "wb") as f:
            f.write(b"this is not an image at all")
        with pytest.raises(ImageValidationError, match="Cannot open"):
            validate_input(path)


# ============================================================
# Tests for Stages 3-4: Detection and Cropping
# ============================================================

class TestCropping:
    
    def test_detect_product_bounds(self):
        """Test that product bounds are detected correctly."""
        rgba = create_rgba_with_product(
            canvas_size=(600, 600),
            product_size=(200, 200)
        )
        left, top, right, bottom = detect_product_bounds(rgba)
        
        # Product should be roughly centered
        assert left > 100
        assert top > 100
        assert right < 500
        assert bottom < 500
        # Bounding box should roughly match product size
        assert 150 < (right - left) < 250
        assert 150 < (bottom - top) < 250
    
    def test_detect_empty_image_raises(self):
        """Test that a fully transparent image raises ValueError."""
        empty = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
        with pytest.raises(ValueError, match="No product detected"):
            detect_product_bounds(empty)
    
    def test_auto_crop_contains_product(self):
        """Test that auto-crop doesn't cut off the product."""
        rgba = create_rgba_with_product(
            canvas_size=(600, 600),
            product_size=(200, 200),
            product_color=(200, 100, 50, 255)
        )
        cropped = auto_crop(rgba, padding=0.1)
        
        # The cropped image should be smaller than the original
        assert cropped.size[0] < 600
        assert cropped.size[1] < 600
        
        # But should still contain the product (check non-transparent area)
        alpha = np.array(cropped.split()[-1])
        assert np.any(alpha > 0), "Cropped image should contain product pixels"
    
    def test_auto_crop_with_zero_padding(self):
        """Test auto-crop with no padding."""
        rgba = create_rgba_with_product(
            canvas_size=(600, 600),
            product_size=(200, 200)
        )
        cropped = auto_crop(rgba, padding=0.0)
        
        # Should be tightly cropped
        assert cropped.size[0] < 300
        assert cropped.size[1] < 300


# ============================================================
# Tests for Stages 5 & 9: Background and Canvas
# ============================================================

class TestBackgroundCanvas:
    
    def test_clean_background_is_rgb(self):
        """Test that placing on clean background produces RGB."""
        rgba = create_rgba_with_product()
        result = place_on_clean_background(rgba)
        assert result.mode == "RGB"
    
    def test_clean_background_is_white(self):
        """Test that the background is white by default."""
        rgba = create_rgba_with_product(
            canvas_size=(100, 100),
            product_size=(20, 20)
        )
        result = place_on_clean_background(rgba)
        # Check a corner pixel (should be white)
        corner = result.getpixel((0, 0))
        assert corner == (255, 255, 255)
    
    def test_ecommerce_canvas_size(self):
        """Test that the canvas has the expected dimensions."""
        img = create_test_image(300, 200)
        result = place_on_ecommerce_canvas(img, canvas_width=800, canvas_height=800)
        assert result.size == (800, 800)
    
    def test_ecommerce_canvas_product_not_distorted(self):
        """Test that the product is not stretched on the canvas."""
        # Create a rectangular product
        img = create_test_image(400, 200, color=(200, 50, 50))
        result = place_on_ecommerce_canvas(img, canvas_width=800, canvas_height=800)
        # Result should be square canvas
        assert result.size == (800, 800)
        # Product should be centered (check that corners are white)
        assert result.getpixel((0, 0)) == (255, 255, 255)


# ============================================================
# Tests for Stages 6-8: Lighting, WB, Sharpening
# ============================================================

class TestLighting:
    
    def test_improve_lighting_rgb(self):
        """Test that lighting correction works on RGB images."""
        # Create a dark image
        dark = create_test_image(300, 300, color=(30, 30, 30))
        result = improve_lighting(dark)
        
        # Result should be brighter
        result_array = np.array(result)
        dark_array = np.array(dark)
        assert np.mean(result_array) > np.mean(dark_array)
    
    def test_improve_lighting_rgba(self):
        """Test that lighting correction preserves alpha channel."""
        rgba = create_rgba_with_product(
            canvas_size=(300, 300),
            product_size=(100, 100),
            product_color=(30, 30, 30, 255)
        )
        result = improve_lighting(rgba)
        assert result.mode == "RGBA"
        
        # Alpha should be preserved
        orig_alpha = np.array(rgba.split()[-1])
        result_alpha = np.array(result.split()[-1])
        np.testing.assert_array_equal(orig_alpha, result_alpha)
    
    def test_white_balance_no_change_at_zero_strength(self):
        """Test that WB with strength=0 returns unchanged image."""
        img = create_test_image(200, 200, color=(100, 150, 200))
        result = correct_white_balance(img, strength=0.0)
        
        orig_array = np.array(img)
        result_array = np.array(result)
        np.testing.assert_array_equal(orig_array, result_array)
    
    def test_white_balance_rgba(self):
        """Test that WB preserves alpha channel."""
        rgba = create_rgba_with_product()
        result = correct_white_balance(rgba)
        assert result.mode == "RGBA"
    
    def test_sharpen_disabled(self):
        """Test that sharpening can be disabled."""
        img = create_test_image(200, 200)
        result = sharpen_image(img, enabled=False)
        
        orig_array = np.array(img)
        result_array = np.array(result)
        np.testing.assert_array_equal(orig_array, result_array)
    
    def test_sharpen_enabled(self):
        """Test that sharpening modifies the image when enabled."""
        # Create an image with sharp edges (checkerboard pattern)
        # The unsharp mask needs actual edge contrast to have an effect
        img = Image.new("RGB", (200, 200))
        draw = ImageDraw.Draw(img)
        for y in range(0, 200, 20):
            for x in range(0, 200, 20):
                color = (200, 50, 50) if (x + y) % 40 == 0 else (50, 50, 200)
                draw.rectangle([x, y, x + 19, y + 19], fill=color)
        
        result = sharpen_image(img, enabled=True)
        
        # Sharpened image should be different from the original
        orig_array = np.array(img)
        result_array = np.array(result)
        assert not np.array_equal(orig_array, result_array)


# ============================================================
# Tests for Stages 10-11: Resize and Save
# ============================================================

class TestOutput:
    
    def test_resize_maintains_aspect_ratio(self):
        """Test that resizing preserves aspect ratio."""
        img = create_test_image(800, 400)
        result = resize_image(img, max_width=400, max_height=400)
        
        w, h = result.size
        # Should fit within 400x400 but maintain 2:1 ratio
        assert w <= 400
        assert h <= 400
        assert abs(w / h - 2.0) < 0.1  # Roughly 2:1
    
    def test_resize_no_extreme_upscale(self):
        """Test that tiny images aren't upscaled too much."""
        img = create_test_image(50, 50)
        # Even if max is 1200, should only upscale by MAX_UPSCALE_FACTOR
        result = resize_image(img, max_width=1200, max_height=1200)
        
        w, h = result.size
        # With MAX_UPSCALE_FACTOR=2.0, max size should be ~100x100
        assert w <= 150  # Some tolerance
        assert h <= 150
    
    def test_save_jpeg(self, tmp_path):
        """Test saving as JPEG."""
        img = create_test_image(200, 200)
        path = os.path.join(str(tmp_path), "test_out.jpg")
        result = save_image(img, path, output_format="JPEG")
        
        assert os.path.exists(result)
        assert os.path.getsize(result) > 0
        
        # Verify it can be opened
        saved = Image.open(result)
        assert saved.mode == "RGB"
    
    def test_save_png(self, tmp_path):
        """Test saving as PNG."""
        img = create_test_image(200, 200)
        path = os.path.join(str(tmp_path), "test_out.png")
        result = save_image(img, path, output_format="PNG")
        
        assert os.path.exists(result)
        assert os.path.getsize(result) > 0
    
    def test_save_webp(self, tmp_path):
        """Test saving as WEBP."""
        img = create_test_image(200, 200)
        path = os.path.join(str(tmp_path), "test_out.webp")
        result = save_image(img, path, output_format="WEBP")
        
        assert os.path.exists(result)
        assert os.path.getsize(result) > 0
    
    def test_save_creates_directory(self, tmp_path):
        """Test that save_image creates missing directories."""
        img = create_test_image(200, 200)
        path = os.path.join(str(tmp_path), "new_dir", "sub_dir", "out.jpg")
        result = save_image(img, path)
        
        assert os.path.exists(result)
    
    def test_save_unsupported_format(self, tmp_path):
        """Test that unsupported format raises ValueError."""
        img = create_test_image(200, 200)
        path = os.path.join(str(tmp_path), "test.tiff")
        with pytest.raises(ValueError, match="Unsupported output format"):
            save_image(img, path, output_format="TIFF")
