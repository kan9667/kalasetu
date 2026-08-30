# ============================================================
# background_removal.py — Stage 2: AI-based background removal
# ============================================================
# Uses rembg to remove the background from a product photo.
# The output is an RGBA image where the background is transparent
# and only the product remains visible.
# ============================================================

from PIL import Image
from rembg import remove


def remove_background(image):
    """
    Remove the background from a product photograph using rembg.
    
    This removes walls, furniture, clutter, and other distracting
    elements while preserving the main product/subject.
    
    The rembg library uses the U2-Net deep learning model to detect
    the foreground subject and create a transparency mask.
    
    Args:
        image (PIL.Image): Input image in RGB mode.
        
    Returns:
        PIL.Image: RGBA image with transparent background.
                   The product pixels keep their original colors.
                   Background pixels have alpha = 0 (fully transparent).
    """
    # Ensure the image is in RGB mode for rembg
    if image.mode != "RGB":
        image = image.convert("RGB")
    
    # rembg.remove() accepts a PIL Image and returns a PIL Image in RGBA mode.
    # It uses the default u2net model which works well for general objects.
    result = remove(image)
    
    # Make sure the result is in RGBA mode (it should be, but let's be safe)
    if result.mode != "RGBA":
        result = result.convert("RGBA")
    
    return result
