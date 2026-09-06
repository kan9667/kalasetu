# ============================================================
# enhancer.py — Core AI Image Enhancement Pipeline
# ============================================================
# This module coordinates the 6 student-friendly stages:
#
#   Stage 1: Load & Validate Image (Format, Size, Dimensions)
#   Stage 2: AI Background Removal (Deep Learning segmentation)
#   Stage 3: Subject Detection & Auto-Crop (Tightly center product)
#   Stage 4: Lighting & White Balance (CLAHE + Gray-World)
#   Stage 5: Clean Canvas Placement (Square 1200x1200 white canvas)
#   Stage 6: Save & Compression (Optimized e-commerce JPEG/PNG)
# ============================================================

import os
import sys
import time
from pathlib import Path

# Ensure image_pipeline directory is in sys.path
_PIPELINE_DIR = Path(__file__).resolve().parent
if str(_PIPELINE_DIR) not in sys.path:
    sys.path.insert(0, str(_PIPELINE_DIR))

from processors.input_validation import validate_input, ImageValidationError
from processors.background_removal import remove_background
from processors.cropping import auto_crop
from processors.background_canvas import place_on_clean_background, place_on_ecommerce_canvas
from processors.lighting import improve_lighting, correct_white_balance, sharpen_image
from processors.image_output import resize_image, save_image


def enhance_image(input_path, output_path=None, **options):
    """
    Run the complete image enhancement pipeline on an image.
    
    Args:
        input_path (str): Path to input image (JPG, PNG, or WEBP).
        output_path (str, optional): Target save path. If omitted,
                                    saves in 'output/' folder.
        **options: Optional overrides from config.py
    
    Returns:
        str: Path to the enhanced output image file.
    """
    start_time = time.time()
    
    # 1. Output path calculation
    if output_path is None:
        output_path = _generate_output_path(input_path)
    
    # --- Stage 1: Load & Validate ---
    _log("[1/6] Loading and validating image...")
    image = validate_input(input_path)
    _log(f"      Size: {image.size[0]}x{image.size[1]} px, Mode: {image.mode}")
    
    # --- Stage 2: AI Background Removal ---
    _log("[2/6] Removing background with AI...")
    image = remove_background(image)
    
    # --- Stage 3: Detect Subject & Auto-Crop ---
    _log("[3/6] Detecting product and auto-cropping...")
    crop_padding = options.get("crop_padding", None)
    image = auto_crop(image, padding=crop_padding)
    _log(f"      Cropped subject to: {image.size[0]}x{image.size[1]} px")
    
    # --- Stage 4: Lighting, White Balance & Sharpening ---
    _log("[4/6] Enhancing lighting, color balance & details...")
    image = improve_lighting(image)
    
    wb_strength = options.get("wb_strength", None)
    image = correct_white_balance(image, strength=wb_strength)
    
    sharpen_enabled = options.get("sharpen", None)
    image = sharpen_image(image, enabled=sharpen_enabled)
    
    # --- Stage 5: Clean Canvas Placement ---
    _log("[5/6] Placing product on clean e-commerce canvas...")
    bg_color = options.get("bg_color", None)
    image = place_on_clean_background(image, bg_color=bg_color)
    
    canvas_w = options.get("canvas_width", None)
    canvas_h = options.get("canvas_height", None)
    image = place_on_ecommerce_canvas(
        image, canvas_width=canvas_w, canvas_height=canvas_h, bg_color=bg_color
    )
    image = resize_image(image)
    _log(f"      Final canvas: {image.size[0]}x{image.size[1]} px")
    
    # --- Stage 6: Save & Compress ---
    _log("[6/6] Saving enhanced image...")
    output_format = options.get("output_format", None)
    quality = options.get("quality", None)
    saved_path = save_image(
        image, output_path,
        output_format=output_format,
        quality=quality
    )
    
    elapsed = time.time() - start_time
    file_size_kb = os.path.getsize(saved_path) / 1024
    _log(f"Done in {elapsed:.1f}s! ({file_size_kb:.0f} KB) -> {os.path.basename(saved_path)}")
    
    return saved_path


def _generate_output_path(input_path):
    """Generate default output path in the output/ directory."""
    filename = os.path.basename(input_path)
    name, ext = os.path.splitext(filename)
    
    if ext.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
        ext = ".jpg"
    
    output_filename = f"{name}_enhanced{ext}"
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, "output")
    os.makedirs(output_dir, exist_ok=True)
    
    return os.path.join(output_dir, output_filename)


def _log(message):
    """Print student-friendly progress message."""
    print(f"  {message}")
