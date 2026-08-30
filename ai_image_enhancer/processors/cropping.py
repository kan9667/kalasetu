# ============================================================
# cropping.py — Stages 3 & 4: Detect product and auto-crop
# ============================================================
# After background removal, this module finds the bounding box
# of the remaining product and crops the image with padding.
# ============================================================

import numpy as np
from PIL import Image

from config import CROP_PADDING, ALPHA_THRESHOLD, MIN_CONTOUR_AREA


def detect_product_bounds(rgba_image):
    """
    Find the bounding box of the product in an RGBA image.
    
    Uses the alpha (transparency) channel to find which pixels
    belong to the product (non-transparent) vs background (transparent).
    
    Small noise regions (tiny clusters of non-transparent pixels) are
    ignored to avoid the bounding box being thrown off by stray pixels.
    
    Args:
        rgba_image (PIL.Image): RGBA image from background removal.
        
    Returns:
        tuple: (left, top, right, bottom) bounding box of the product.
               Coordinates are in pixels, relative to the image.
               
    Raises:
        ValueError: If no product is detected in the image.
    """
    # Get the alpha channel as a numpy array
    alpha = np.array(rgba_image.split()[-1])  # Last channel is alpha
    
    # Create a binary mask: True where pixel is foreground (product)
    # Pixels with alpha above the threshold are considered part of the product
    foreground_mask = alpha > ALPHA_THRESHOLD
    
    # --- Remove small noise blobs ---
    # We use a simple approach: find connected regions and remove tiny ones.
    # This prevents isolated noise pixels from expanding the bounding box.
    
    # Import cv2 here to avoid importing it at module level if not needed
    import cv2
    
    # Convert boolean mask to uint8 for OpenCV
    mask_uint8 = foreground_mask.astype(np.uint8) * 255
    
    # Find contours (connected regions) in the mask
    contours, _ = cv2.findContours(
        mask_uint8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    
    # Create a cleaned mask keeping only large-enough contours
    cleaned_mask = np.zeros_like(mask_uint8)
    for contour in contours:
        area = cv2.contourArea(contour)
        if area >= MIN_CONTOUR_AREA:
            cv2.drawContours(cleaned_mask, [contour], -1, 255, cv2.FILLED)
    
    # Check if any product was detected
    if np.sum(cleaned_mask) == 0:
        raise ValueError(
            "No product detected in the image after background removal.\n"
            "The image might not contain a clear foreground object, or\n"
            "the background removal model could not separate it."
        )
    
    # Find the bounding box of all remaining foreground pixels
    # np.where returns (row_indices, col_indices) where mask is non-zero
    rows = np.any(cleaned_mask > 0, axis=1)
    cols = np.any(cleaned_mask > 0, axis=0)
    
    top = int(np.argmax(rows))            # First row with foreground
    bottom = int(len(rows) - 1 - np.argmax(rows[::-1]))  # Last row
    left = int(np.argmax(cols))           # First column with foreground
    right = int(len(cols) - 1 - np.argmax(cols[::-1]))    # Last column
    
    return (left, top, right, bottom)


def auto_crop(rgba_image, padding=None):
    """
    Crop the image around the detected product with padding.
    
    Steps:
    1. Detect the product bounding box
    2. Add padding around the product (so it doesn't look cramped)
    3. Make sure the crop doesn't go outside the image boundaries
    4. Crop the image
    
    Args:
        rgba_image (PIL.Image): RGBA image from background removal.
        padding (float, optional): Fractional padding around the product.
            For example, 0.08 means 8% of the product dimensions.
            Uses CROP_PADDING from config.py if not specified.
            
    Returns:
        PIL.Image: Cropped RGBA image containing just the product
                   with some breathing room around it.
    """
    if padding is None:
        padding = CROP_PADDING
    
    # Get the product bounding box
    left, top, right, bottom = detect_product_bounds(rgba_image)
    
    # Calculate product dimensions
    product_width = right - left
    product_height = bottom - top
    
    # Calculate padding in pixels based on the product size
    # Using the larger dimension ensures consistent-looking padding
    pad_reference = max(product_width, product_height)
    pad_pixels = int(pad_reference * padding)
    
    # Apply padding (expand the crop area)
    img_width, img_height = rgba_image.size
    
    crop_left = max(0, left - pad_pixels)
    crop_top = max(0, top - pad_pixels)
    crop_right = min(img_width, right + pad_pixels)
    crop_bottom = min(img_height, bottom + pad_pixels)
    
    # Crop the image
    cropped = rgba_image.crop((crop_left, crop_top, crop_right, crop_bottom))
    
    return cropped
