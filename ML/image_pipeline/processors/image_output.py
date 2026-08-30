# ============================================================
# image_output.py — Stages 10 & 11: Resize, compress, and save
# ============================================================
# Resizes the final image to the target dimensions and saves it
# in the requested format with configurable quality.
# ============================================================

import os
from PIL import Image

from config import OUTPUT_WIDTH, OUTPUT_HEIGHT, JPEG_QUALITY, MAX_UPSCALE_FACTOR


def resize_image(image, max_width=None, max_height=None):
    """
    Resize the image to fit within the target dimensions.
    
    Maintains aspect ratio — the image is scaled down (or up, within
    limits) to fit inside the specified max width and height.
    
    To avoid quality degradation, extremely small images are not
    upscaled beyond MAX_UPSCALE_FACTOR (default 2x).
    
    Uses LANCZOS resampling for the best quality.
    
    Args:
        image (PIL.Image): Input image.
        max_width (int, optional): Maximum width. Defaults to OUTPUT_WIDTH.
        max_height (int, optional): Maximum height. Defaults to OUTPUT_HEIGHT.
        
    Returns:
        PIL.Image: Resized image.
    """
    if max_width is None:
        max_width = OUTPUT_WIDTH
    if max_height is None:
        max_height = OUTPUT_HEIGHT
    
    current_width, current_height = image.size
    
    # Calculate the scale factor needed to fit within the target
    scale_w = max_width / current_width
    scale_h = max_height / current_height
    scale = min(scale_w, scale_h)
    
    # Limit upscaling to prevent quality loss
    if scale > MAX_UPSCALE_FACTOR:
        scale = MAX_UPSCALE_FACTOR
    
    # If no resizing is needed (image already fits), return as-is
    if abs(scale - 1.0) < 0.01:
        return image
    
    new_width = int(current_width * scale)
    new_height = int(current_height * scale)
    
    # Ensure dimensions are at least 1 pixel
    new_width = max(1, new_width)
    new_height = max(1, new_height)
    
    resized = image.resize((new_width, new_height), Image.LANCZOS)
    
    return resized


def save_image(image, output_path, output_format=None, quality=None):
    """
    Save the final image to disk in the specified format.
    
    Supports JPEG, PNG, and WEBP formats. The format is auto-detected
    from the file extension if not explicitly provided.
    
    JPEG quality is configurable to balance file size vs image quality.
    
    Args:
        image (PIL.Image): The image to save.
        output_path (str): Path where the image will be saved.
        output_format (str, optional): "JPEG", "PNG", or "WEBP".
            Auto-detected from the file extension if not provided.
        quality (int, optional): JPEG/WEBP quality (1-95).
            Defaults to JPEG_QUALITY from config.py.
            
    Returns:
        str: The path where the image was saved.
        
    Raises:
        ValueError: If the output format is not supported.
        OSError: If the output directory cannot be created.
    """
    if quality is None:
        quality = JPEG_QUALITY
    
    # Auto-detect format from file extension if not specified
    if output_format is None:
        ext = os.path.splitext(output_path)[1].lower()
        format_map = {
            ".jpg": "JPEG",
            ".jpeg": "JPEG",
            ".png": "PNG",
            ".webp": "WEBP",
        }
        output_format = format_map.get(ext, "JPEG")
    
    # Normalize format name
    output_format = output_format.upper()
    
    if output_format not in ("JPEG", "PNG", "WEBP"):
        raise ValueError(
            f"Unsupported output format: '{output_format}'\n"
            f"Supported formats: JPEG, PNG, WEBP"
        )
    
    # Create output directory if it doesn't exist
    output_dir = os.path.dirname(output_path)
    if output_dir and not os.path.exists(output_dir):
        try:
            os.makedirs(output_dir, exist_ok=True)
        except OSError as e:
            raise OSError(
                f"Cannot create output directory: '{output_dir}'\n"
                f"Error: {e}"
            )
    
    # JPEG doesn't support transparency — convert RGBA to RGB
    if output_format == "JPEG" and image.mode == "RGBA":
        # Composite over white background before saving as JPEG
        from config import BACKGROUND_COLOR
        background = Image.new("RGB", image.size, BACKGROUND_COLOR)
        background.paste(image, (0, 0), image)
        image = background
    elif output_format == "JPEG" and image.mode != "RGB":
        image = image.convert("RGB")
    
    # Save with appropriate settings
    save_kwargs = {}
    
    if output_format == "JPEG":
        save_kwargs["quality"] = quality
        save_kwargs["optimize"] = True
        # Progressive JPEG loads faster on web
        save_kwargs["progressive"] = True
    elif output_format == "PNG":
        save_kwargs["optimize"] = True
    elif output_format == "WEBP":
        save_kwargs["quality"] = quality
        save_kwargs["method"] = 4  # Balance between speed and compression
    
    image.save(output_path, format=output_format, **save_kwargs)
    
    return output_path
