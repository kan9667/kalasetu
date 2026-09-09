# ============================================================
# background_removal.py — Stage 2: AI-based background removal
# ============================================================
# Uses rembg to remove the background from a product photo.
# The output is an RGBA image where the background is transparent
# and only the product remains visible.
# ============================================================

from PIL import Image
from rembg import remove, new_session

_session = None


def get_rembg_session():
    """Lazily initialize and reuse the ONNX session to avoid model reload penalty.
    Uses u2netp (4MB lightweight model) for blazing-fast 0.5s inference and low RAM usage.
    """
    global _session
    if _session is None:
        try:
            _session = new_session("u2netp")
        except Exception:
            _session = new_session("u2net")
    return _session


def remove_background(image):
    """
    Remove the background from a product photograph using rembg.
    
    This removes walls, furniture, clutter, and other distracting
    elements while preserving the main product/subject.
    
    Args:
        image (PIL.Image): Input image in RGB mode.
        
    Returns:
        PIL.Image: RGBA image with transparent background.
    """
    # Ensure the image is in RGB mode for rembg
    if image.mode != "RGB":
        image = image.convert("RGB")
    
    # Downscale for fast rembg processing if image is huge (e.g. 50MP phone camera)
    # 1024px provides crisp edge detection while running 4x faster with minimal RAM.
    max_dim = max(image.size)
    if max_dim > 1024:
        ratio = 1024.0 / max_dim
        new_size = (int(image.size[0] * ratio), int(image.size[1] * ratio))
        process_img = image.resize(new_size, Image.Resampling.BILINEAR)
    else:
        process_img = image

    session = get_rembg_session()
    result = remove(process_img, session=session)
    
    # Make sure the result is in RGBA mode
    if result.mode != "RGBA":
        result = result.convert("RGBA")
    
    return result
