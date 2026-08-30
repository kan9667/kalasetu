# ============================================================
# enhancer.py — Main image enhancement pipeline
# ============================================================
# This is the core module. The enhance_image() function runs
# the complete pipeline from raw photo to e-commerce image.
#
# Pipeline order:
#   1. Validate input
#   2. Remove background (rembg)
#   3. Detect product + auto-crop
#   4. Improve lighting (CLAHE + gamma)
#   5. Correct white balance (gray-world)
#   6. Optional sharpening
#   7. Place on clean background
#   8. Place on e-commerce canvas
#   9. Resize (if needed)
#  10. Save to disk
#
# Lighting and color corrections happen BEFORE placing on the
# white canvas. This is intentional — if we added the white
# background first, the large white area would dominate the
# histogram and make the corrections ineffective.
# ============================================================

import os
import sys
import time
from pathlib import Path

# Ensure ML/image_pipeline directory is in sys.path so 'processors' and 'config' can be imported anywhere
_PIPELINE_DIR = Path(__file__).resolve().parent
if str(_PIPELINE_DIR) not in sys.path:
    sys.path.insert(0, str(_PIPELINE_DIR))

try:
    from processors.input_validation import validate_input
    from processors.background_removal import remove_background
    from processors.cropping import auto_crop
    from processors.background_canvas import place_on_clean_background, place_on_ecommerce_canvas
    from processors.lighting import improve_lighting, correct_white_balance, sharpen_image
    from processors.image_output import resize_image, save_image
except ImportError:
    from .processors.input_validation import validate_input
    from .processors.background_removal import remove_background
    from .processors.cropping import auto_crop
    from .processors.background_canvas import place_on_clean_background, place_on_ecommerce_canvas
    from .processors.lighting import improve_lighting, correct_white_balance, sharpen_image
    from .processors.image_output import resize_image, save_image


def enhance_image(input_path, output_path=None, **options):
    """
    Run the complete image enhancement pipeline.
    
    Takes a raw product photograph and produces a clean,
    professional, e-commerce-ready product image.
    
    This function is designed to be called by:
    - The command-line interface (main.py)
    - A future FastAPI backend
    - Any other Python code
    
    Args:
        input_path (str): Path to the input image file.
        output_path (str, optional): Path for the output image.
            If not provided, saves to 'output/' directory with
            '_enhanced' suffix added to the original filename.
        **options: Optional overrides for pipeline settings:
            - crop_padding (float): Padding around product (default: config)
            - bg_color (tuple): Background RGB color (default: white)
            - canvas_width (int): Output canvas width (default: config)
            - canvas_height (int): Output canvas height (default: config)
            - sharpen (bool): Enable/disable sharpening (default: config)
            - wb_strength (float): White balance strength 0-1 (default: config)
            - output_format (str): "JPEG", "PNG", or "WEBP" (default: auto)
            - quality (int): JPEG/WEBP quality 1-95 (default: config)
            
    Returns:
        str: Path to the saved output image.
        
    Raises:
        ImageValidationError: If the input image is invalid.
        ValueError: If no product is detected after background removal.
        OSError: If the output cannot be saved.
    """
    start_time = time.time()
    
    # --- Generate default output path if not provided ---
    if output_path is None:
        output_path = _generate_output_path(input_path)
    
    # --- Stage 1: Validate input ---
    _log("Loading and validating image...")
    image = validate_input(input_path)
    _log(f"  Image loaded: {image.size[0]}x{image.size[1]} pixels, mode={image.mode}")
    
    # --- Stage 2: Remove background ---
    _log("Removing background (this may take a moment)...")
    image = remove_background(image)
    _log("  Background removed successfully.")
    
    # --- Stages 3-4: Detect product and auto-crop ---
    _log("Detecting product and cropping...")
    crop_padding = options.get("crop_padding", None)
    image = auto_crop(image, padding=crop_padding)
    _log(f"  Cropped to: {image.size[0]}x{image.size[1]} pixels")
    
    # --- Stage 6: Improve lighting ---
    # (Done before placing on white canvas — see module docstring)
    _log("Correcting lighting...")
    image = improve_lighting(image)
    
    # --- Stage 7: Correct white balance ---
    _log("Correcting white balance...")
    wb_strength = options.get("wb_strength", None)
    image = correct_white_balance(image, strength=wb_strength)
    
    # --- Stage 8: Optional sharpening ---
    sharpen_enabled = options.get("sharpen", None)
    if sharpen_enabled is not False:
        _log("Applying mild sharpening...")
    image = sharpen_image(image, enabled=sharpen_enabled)
    
    # --- Stage 5: Place on clean background ---
    _log("Creating clean background...")
    bg_color = options.get("bg_color", None)
    image = place_on_clean_background(image, bg_color=bg_color)
    
    # --- Stage 9: Place on e-commerce canvas ---
    _log("Placing on e-commerce canvas...")
    canvas_w = options.get("canvas_width", None)
    canvas_h = options.get("canvas_height", None)
    image = place_on_ecommerce_canvas(
        image, canvas_width=canvas_w, canvas_height=canvas_h, bg_color=bg_color
    )
    _log(f"  Canvas size: {image.size[0]}x{image.size[1]} pixels")
    
    # --- Stage 10: Resize (usually already done by canvas, but as a safety) ---
    # The canvas step already handles sizing, but resize_image acts as a
    # final check to ensure we don't exceed the target dimensions.
    image = resize_image(image)
    
    # --- Stage 11: Save ---
    _log("Saving result...")
    output_format = options.get("output_format", None)
    quality = options.get("quality", None)
    saved_path = save_image(
        image, output_path,
        output_format=output_format,
        quality=quality
    )
    
    elapsed = time.time() - start_time
    file_size_kb = os.path.getsize(saved_path) / 1024
    _log(f"Done! Saved to: {saved_path}")
    _log(f"  Output size: {file_size_kb:.0f} KB")
    _log(f"  Total time: {elapsed:.1f} seconds")
    
    return saved_path


def _generate_output_path(input_path):
    """
    Generate a default output path based on the input filename.
    
    Example: "input/photo.jpg" → "output/photo_enhanced.jpg"
    """
    # Get the filename without the directory
    filename = os.path.basename(input_path)
    name, ext = os.path.splitext(filename)
    
    # Default to JPEG if the extension is unusual
    if ext.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
        ext = ".jpg"
    
    output_filename = f"{name}_enhanced{ext}"
    
    # Save to the 'output' directory relative to the script's location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, "output")
    
    return os.path.join(output_dir, output_filename)


def _log(message):
    """
    Print a progress message to the console.
    
    This is a simple print wrapper. In the future, this could be
    replaced with proper logging if needed.
    """
    print(f"[Enhancer] {message}")
