# ============================================================
# background_canvas.py — Stages 5 & 9: Clean background + canvas
# ============================================================
# Places the transparent-background product onto a clean solid
# background, and then onto a standard e-commerce-sized canvas.
# ============================================================

from PIL import Image

from config import BACKGROUND_COLOR, OUTPUT_WIDTH, OUTPUT_HEIGHT


def place_on_clean_background(rgba_image, bg_color=None):
    """
    Place the product (with transparent background) onto a clean
    solid-color background.
    
    This composites the RGBA product image over a solid background,
    producing an RGB image. The default background is white, which
    is the standard for e-commerce product photography.
    
    Args:
        rgba_image (PIL.Image): RGBA image (product with transparent bg).
        bg_color (tuple, optional): RGB color for the background.
            Defaults to BACKGROUND_COLOR from config.py (white).
            
    Returns:
        PIL.Image: RGB image with the product on a clean background.
    """
    if bg_color is None:
        bg_color = BACKGROUND_COLOR
    
    # Create a solid-color background image the same size as the input
    background = Image.new("RGB", rgba_image.size, bg_color)
    
    # Paste the product onto the background using its alpha channel as a mask.
    # This means transparent pixels show the background color,
    # and opaque pixels show the product.
    background.paste(rgba_image, (0, 0), rgba_image)
    
    return background


def place_on_ecommerce_canvas(rgb_image, canvas_width=None, canvas_height=None,
                               bg_color=None):
    """
    Place the product image onto a standard-sized e-commerce canvas.
    
    The product is centered on the canvas while maintaining its
    original aspect ratio. The remaining space is filled with the
    background color.
    
    This ensures all output images have a consistent size and
    aspect ratio, which looks professional in product listings.
    
    Args:
        rgb_image (PIL.Image): RGB image of the product on clean background.
        canvas_width (int, optional): Canvas width in pixels.
            Defaults to OUTPUT_WIDTH from config.py.
        canvas_height (int, optional): Canvas height in pixels.
            Defaults to OUTPUT_HEIGHT from config.py.
        bg_color (tuple, optional): RGB background color.
            Defaults to BACKGROUND_COLOR from config.py.
            
    Returns:
        PIL.Image: RGB image on the standard canvas, product centered.
    """
    if canvas_width is None:
        canvas_width = OUTPUT_WIDTH
    if canvas_height is None:
        canvas_height = OUTPUT_HEIGHT
    if bg_color is None:
        bg_color = BACKGROUND_COLOR
    
    # Create the canvas
    canvas = Image.new("RGB", (canvas_width, canvas_height), bg_color)
    
    # Calculate the size the product should be on the canvas.
    # We want the product to fill most of the canvas but leave some margin.
    # Use 90% of the canvas area (5% margin on each side).
    available_width = int(canvas_width * 0.90)
    available_height = int(canvas_height * 0.90)
    
    # Calculate scale factor to fit the product within the available area
    # while maintaining aspect ratio
    product_width, product_height = rgb_image.size
    
    scale_w = available_width / product_width
    scale_h = available_height / product_height
    
    # Use the smaller scale to ensure the product fits entirely
    scale = min(scale_w, scale_h)
    
    # Don't upscale if the product already fits
    if scale > 1.0:
        # Only upscale a little to avoid quality loss
        from config import MAX_UPSCALE_FACTOR
        scale = min(scale, MAX_UPSCALE_FACTOR)
    
    # Calculate the new product size
    new_width = int(product_width * scale)
    new_height = int(product_height * scale)
    
    # Resize the product image (LANCZOS gives the best quality)
    resized_product = rgb_image.resize(
        (new_width, new_height), Image.LANCZOS
    )
    
    # Calculate position to center the product on the canvas
    paste_x = (canvas_width - new_width) // 2
    paste_y = (canvas_height - new_height) // 2
    
    # Paste the product onto the canvas
    canvas.paste(resized_product, (paste_x, paste_y))
    
    return canvas
