# ============================================================
# input_validation.py — Stage 1: Validate the input image
# ============================================================
# Checks that the file exists, has a supported format, can be
# opened as an image, and has reasonable dimensions/file size.
# ============================================================

import os
from PIL import Image

from config import SUPPORTED_FORMATS, MAX_INPUT_SIZE_MB, MIN_DIMENSION, MAX_DIMENSION


class ImageValidationError(Exception):
    """Raised when the input image fails validation."""
    pass


def validate_input(input_path):
    """
    Validate and load an input image file.
    
    Checks performed:
    1. File exists
    2. File extension is supported (JPG, JPEG, PNG, WEBP)
    3. File size is within limits
    4. File can be opened as a valid image
    5. Image dimensions are reasonable
    
    Args:
        input_path (str): Path to the input image file.
        
    Returns:
        PIL.Image: The loaded image in RGB or RGBA mode.
        
    Raises:
        ImageValidationError: If any validation check fails.
    """
    # --- Check 1: File exists ---
    if not os.path.exists(input_path):
        raise ImageValidationError(
            f"File not found: '{input_path}'\n"
            f"Please check the file path and try again."
        )
    
    if not os.path.isfile(input_path):
        raise ImageValidationError(
            f"'{input_path}' is not a file (it may be a directory)."
        )
    
    # --- Check 2: Supported format ---
    file_extension = os.path.splitext(input_path)[1].lower()
    if file_extension not in SUPPORTED_FORMATS:
        raise ImageValidationError(
            f"Unsupported file format: '{file_extension}'\n"
            f"Supported formats: {', '.join(sorted(SUPPORTED_FORMATS))}"
        )
    
    # --- Check 3: File size ---
    file_size_mb = os.path.getsize(input_path) / (1024 * 1024)
    if file_size_mb > MAX_INPUT_SIZE_MB:
        raise ImageValidationError(
            f"File too large: {file_size_mb:.1f} MB\n"
            f"Maximum allowed size: {MAX_INPUT_SIZE_MB} MB"
        )
    
    if file_size_mb == 0:
        raise ImageValidationError(
            f"File is empty (0 bytes): '{input_path}'"
        )
    
    # --- Check 4: Can be opened as an image ---
    try:
        image = Image.open(input_path)
        # Force Pillow to actually read the image data (not just the header)
        image.load()
    except (IOError, OSError, SyntaxError) as e:
        raise ImageValidationError(
            f"Cannot open file as an image: '{input_path}'\n"
            f"The file may be corrupted or not a valid image.\n"
            f"Error details: {e}"
        )
    
    # --- Check 5: Dimensions are reasonable ---
    width, height = image.size
    
    if width < MIN_DIMENSION or height < MIN_DIMENSION:
        raise ImageValidationError(
            f"Image too small: {width}x{height} pixels\n"
            f"Minimum dimension: {MIN_DIMENSION} pixels"
        )
    
    if width > MAX_DIMENSION or height > MAX_DIMENSION:
        raise ImageValidationError(
            f"Image too large: {width}x{height} pixels\n"
            f"Maximum dimension: {MAX_DIMENSION} pixels\n"
            f"Please resize the image before processing."
        )
    
    # Convert to RGB if needed (some images are in palette mode, CMYK, etc.)
    # Keep RGBA if it already has transparency
    if image.mode == "RGBA":
        pass  # Already good
    elif image.mode in ("RGB", "L", "P", "CMYK", "YCbCr"):
        image = image.convert("RGB")
    else:
        # Try to convert anyway
        try:
            image = image.convert("RGB")
        except Exception as e:
            raise ImageValidationError(
                f"Cannot convert image mode '{image.mode}' to RGB.\n"
                f"Error: {e}"
            )
    
    return image
