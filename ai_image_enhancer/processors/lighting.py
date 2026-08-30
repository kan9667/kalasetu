# ============================================================
# lighting.py — Stages 6, 7, 8: Lighting, white balance, sharpen
# ============================================================
# Corrects common lighting problems, color casts, and optionally
# applies mild sharpening. All corrections are conservative to
# preserve the real appearance of the product.
# ============================================================

import cv2
import numpy as np
from PIL import Image, ImageFilter

from config import (
    CLAHE_CLIP_LIMIT, CLAHE_TILE_SIZE,
    TARGET_BRIGHTNESS, GAMMA_MIN, GAMMA_MAX,
    WHITE_BALANCE_STRENGTH,
    SHARPEN_ENABLED, SHARPEN_RADIUS, SHARPEN_PERCENT, SHARPEN_THRESHOLD,
)


# ---- Helper: Convert between PIL and OpenCV ----

def _pil_to_cv2(pil_image):
    """Convert a PIL Image (RGB) to an OpenCV image (BGR numpy array)."""
    rgb_array = np.array(pil_image)
    # OpenCV uses BGR channel order, PIL uses RGB
    bgr_array = cv2.cvtColor(rgb_array, cv2.COLOR_RGB2BGR)
    return bgr_array


def _cv2_to_pil(cv2_image):
    """Convert an OpenCV image (BGR numpy array) to a PIL Image (RGB)."""
    rgb_array = cv2.cvtColor(cv2_image, cv2.COLOR_BGR2RGB)
    return Image.fromarray(rgb_array)


def _pil_rgba_to_cv2_with_alpha(pil_image):
    """Convert a PIL RGBA Image to an OpenCV BGRA numpy array."""
    rgba_array = np.array(pil_image)
    bgra_array = cv2.cvtColor(rgba_array, cv2.COLOR_RGBA2BGRA)
    return bgra_array


def _cv2_bgra_to_pil(cv2_image):
    """Convert an OpenCV BGRA numpy array to a PIL RGBA Image."""
    rgba_array = cv2.cvtColor(cv2_image, cv2.COLOR_BGRA2RGBA)
    return Image.fromarray(rgba_array)


# ---- Stage 6: Lighting Correction ----

def improve_lighting(image):
    """
    Improve the lighting of a product image.
    
    This function corrects two common problems:
    1. Poor contrast — using CLAHE (Contrast Limited Adaptive Histogram
       Equalization) on the L channel in LAB color space
    2. Wrong brightness — using gamma correction to bring the average
       brightness closer to a target value
    
    The corrections are applied conservatively to avoid making the
    image look artificial or destroying product details.
    
    Why LAB color space?
    - LAB separates lightness (L) from color (A, B)
    - We can fix brightness/contrast without changing colors
    - This is much better than adjusting RGB channels directly
    
    Works with both RGB and RGBA images. If the image has an alpha
    channel, corrections are applied only to the visible (product) pixels.
    
    Args:
        image (PIL.Image): Input image (RGB or RGBA).
        
    Returns:
        PIL.Image: Image with improved lighting (same mode as input).
    """
    has_alpha = (image.mode == "RGBA")
    
    if has_alpha:
        # Split out the alpha channel, work on RGB part only
        r, g, b, a = image.split()
        rgb_image = Image.merge("RGB", (r, g, b))
        cv2_image = _pil_to_cv2(rgb_image)
        alpha_channel = np.array(a)
    else:
        cv2_image = _pil_to_cv2(image)
        alpha_channel = None
    
    # Convert BGR to LAB color space
    lab = cv2.cvtColor(cv2_image, cv2.COLOR_BGR2LAB)
    
    # Split into L (lightness), A (green-red), B (blue-yellow) channels
    l_channel, a_channel, b_channel = cv2.split(lab)
    
    # --- Step 1: Apply CLAHE to the L (lightness) channel ---
    # CLAHE enhances local contrast without over-amplifying noise
    clahe = cv2.createCLAHE(
        clipLimit=CLAHE_CLIP_LIMIT,
        tileGridSize=(CLAHE_TILE_SIZE, CLAHE_TILE_SIZE)
    )
    l_enhanced = clahe.apply(l_channel)
    
    # --- Step 2: Gamma correction for overall brightness ---
    # Calculate the average brightness of the L channel
    if alpha_channel is not None:
        # Only consider foreground pixels (where alpha > 0)
        foreground_mask = alpha_channel > 30
        if np.any(foreground_mask):
            avg_brightness = np.mean(l_enhanced[foreground_mask])
        else:
            avg_brightness = np.mean(l_enhanced)
    else:
        avg_brightness = np.mean(l_enhanced)
    
    # Calculate gamma to move average brightness toward the target
    # gamma < 1 makes the image brighter, gamma > 1 makes it darker
    if avg_brightness > 0:
        gamma = np.log(TARGET_BRIGHTNESS / 255.0) / np.log(avg_brightness / 255.0)
    else:
        gamma = 1.0
    
    # Clamp gamma to safe range (don't over-correct)
    gamma = np.clip(gamma, GAMMA_MIN, GAMMA_MAX)
    
    # Apply gamma correction using a lookup table (fast)
    if abs(gamma - 1.0) > 0.05:  # Only apply if gamma is noticeably different from 1
        gamma_table = np.array([
            ((i / 255.0) ** gamma) * 255
            for i in range(256)
        ], dtype=np.uint8)
        l_enhanced = gamma_table[l_enhanced]
    
    # Merge the enhanced L channel back with original A, B channels
    lab_enhanced = cv2.merge([l_enhanced, a_channel, b_channel])
    
    # Convert back to BGR
    result = cv2.cvtColor(lab_enhanced, cv2.COLOR_LAB2BGR)
    
    # Convert back to PIL
    result_pil = _cv2_to_pil(result)
    
    if has_alpha:
        # Reattach the alpha channel
        r, g, b = result_pil.split()
        result_pil = Image.merge("RGBA", (r, g, b, Image.fromarray(alpha_channel)))
    
    return result_pil


# ---- Stage 7: White Balance Correction ----

def correct_white_balance(image, strength=None):
    """
    Apply automatic white-balance correction using the gray-world assumption.
    
    The gray-world assumption says that, on average, the colors in a
    well-lit scene should average out to neutral gray. If there's a
    color cast (e.g., yellow from indoor lighting), the average will
    be shifted, and we can correct it.
    
    How it works:
    1. Convert to LAB color space
    2. Calculate the average A (green-red) and B (blue-yellow) values
    3. Shift A and B toward neutral (128) based on the strength parameter
    4. Convert back to RGB
    
    The strength parameter controls how aggressive the correction is:
    - 0.0 = no correction at all
    - 0.5 = half correction (conservative, default)
    - 1.0 = full gray-world correction (may be too aggressive)
    
    Why not full correction? Because product colors matter for e-commerce.
    A red saree should stay red, not become pinkish-gray.
    
    Works with both RGB and RGBA images.
    
    Args:
        image (PIL.Image): Input image (RGB or RGBA).
        strength (float, optional): Correction strength from 0.0 to 1.0.
            Defaults to WHITE_BALANCE_STRENGTH from config.py.
            
    Returns:
        PIL.Image: Image with corrected white balance (same mode as input).
    """
    if strength is None:
        strength = WHITE_BALANCE_STRENGTH
    
    # If strength is zero, skip processing entirely
    if strength <= 0.0:
        return image
    
    has_alpha = (image.mode == "RGBA")
    
    if has_alpha:
        r, g, b, alpha = image.split()
        rgb_image = Image.merge("RGB", (r, g, b))
        cv2_image = _pil_to_cv2(rgb_image)
        alpha_array = np.array(alpha)
    else:
        cv2_image = _pil_to_cv2(image)
        alpha_array = None
    
    # Convert to LAB color space
    lab = cv2.cvtColor(cv2_image, cv2.COLOR_BGR2LAB)
    lab = lab.astype(np.float32)
    
    l_channel, a_channel, b_channel = cv2.split(lab)
    
    # Calculate the average A and B values
    # In LAB: A=128 is neutral (no green/red), B=128 is neutral (no blue/yellow)
    if alpha_array is not None:
        foreground_mask = alpha_array > 30
        if np.any(foreground_mask):
            avg_a = np.mean(a_channel[foreground_mask])
            avg_b = np.mean(b_channel[foreground_mask])
        else:
            avg_a = np.mean(a_channel)
            avg_b = np.mean(b_channel)
    else:
        avg_a = np.mean(a_channel)
        avg_b = np.mean(b_channel)
    
    # Calculate how far the averages are from neutral (128)
    shift_a = (128.0 - avg_a) * strength
    shift_b = (128.0 - avg_b) * strength
    
    # Apply the correction (shift A and B toward neutral)
    a_corrected = np.clip(a_channel + shift_a, 0, 255)
    b_corrected = np.clip(b_channel + shift_b, 0, 255)
    
    # Merge back
    lab_corrected = cv2.merge([l_channel, a_corrected, b_corrected])
    lab_corrected = lab_corrected.astype(np.uint8)
    
    # Convert back to BGR
    result = cv2.cvtColor(lab_corrected, cv2.COLOR_LAB2BGR)
    
    # Convert to PIL
    result_pil = _cv2_to_pil(result)
    
    if has_alpha:
        r, g, b = result_pil.split()
        result_pil = Image.merge("RGBA", (r, g, b, Image.fromarray(alpha_array)))
    
    return result_pil


# ---- Stage 8: Optional Mild Sharpening ----

def sharpen_image(image, enabled=None):
    """
    Apply mild sharpening to improve product detail clarity.
    
    Uses Pillow's UnsharpMask filter, which is a standard and safe
    sharpening method. Despite the name, "unsharp mask" actually
    sharpens the image by enhancing edges.
    
    The sharpening is very conservative to avoid creating artificial
    edges or halos around the product.
    
    Can be disabled via config or the 'enabled' parameter.
    
    Args:
        image (PIL.Image): Input image (RGB or RGBA).
        enabled (bool, optional): Whether to apply sharpening.
            Defaults to SHARPEN_ENABLED from config.py.
            
    Returns:
        PIL.Image: Sharpened image (or original if disabled).
    """
    if enabled is None:
        enabled = SHARPEN_ENABLED
    
    if not enabled:
        return image
    
    has_alpha = (image.mode == "RGBA")
    
    if has_alpha:
        # Sharpen only the RGB channels, not the alpha
        r, g, b, a = image.split()
        rgb_image = Image.merge("RGB", (r, g, b))
        
        sharpened_rgb = rgb_image.filter(ImageFilter.UnsharpMask(
            radius=SHARPEN_RADIUS,
            percent=SHARPEN_PERCENT,
            threshold=SHARPEN_THRESHOLD
        ))
        
        r, g, b = sharpened_rgb.split()
        result = Image.merge("RGBA", (r, g, b, a))
    else:
        result = image.filter(ImageFilter.UnsharpMask(
            radius=SHARPEN_RADIUS,
            percent=SHARPEN_PERCENT,
            threshold=SHARPEN_THRESHOLD
        ))
    
    return result
