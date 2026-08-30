# ============================================================
# config.py — All configurable settings for the image enhancer
# ============================================================
# Change values here instead of editing the processing code.
# These defaults are tuned for typical e-commerce product photos.
# ============================================================

# --- Output Dimensions ---
# Final canvas size in pixels (square canvas is standard for e-commerce)
OUTPUT_WIDTH = 1200
OUTPUT_HEIGHT = 1200

# --- JPEG Compression ---
# Quality from 1 (worst) to 95 (best). 92 is a good balance.
JPEG_QUALITY = 92

# --- Cropping ---
# Fractional padding around the detected product (0.08 = 8% of product size)
CROP_PADDING = 0.08

# --- Background ---
# RGB color for the clean background (white is standard for e-commerce)
BACKGROUND_COLOR = (255, 255, 255)

# --- Sharpening ---
# Set to False to skip sharpening entirely
SHARPEN_ENABLED = True

# Sharpening strength (radius, percent, threshold for UnsharpMask)
SHARPEN_RADIUS = 2          # Pixel radius of the blur
SHARPEN_PERCENT = 80        # Strength of sharpening (0-200 is safe range)
SHARPEN_THRESHOLD = 3       # Minimum brightness difference to sharpen

# --- Lighting Correction ---
# CLAHE clip limit — higher = more contrast enhancement. 2.0 is conservative.
CLAHE_CLIP_LIMIT = 2.0

# CLAHE tile grid size — smaller tiles = more local contrast
CLAHE_TILE_SIZE = 8

# Target average brightness (0-255). If image average is far from this, gamma is applied.
TARGET_BRIGHTNESS = 130

# How much gamma correction is allowed (1.0 = none, <1 = brighter, >1 = darker)
GAMMA_MIN = 0.6
GAMMA_MAX = 1.6

# --- White Balance ---
# Strength of white-balance correction (0.0 = no change, 1.0 = full gray-world correction)
# 0.5 is conservative — enough to reduce obvious casts without destroying product colors
WHITE_BALANCE_STRENGTH = 0.5

# --- Input Validation ---
# Maximum input file size in megabytes
MAX_INPUT_SIZE_MB = 25

# Minimum image dimension in pixels (width or height)
MIN_DIMENSION = 100

# Maximum image dimension in pixels (to prevent memory issues)
MAX_DIMENSION = 10000

# Supported input file extensions
SUPPORTED_FORMATS = {".jpg", ".jpeg", ".png", ".webp"}

# --- Resize Limits ---
# Maximum upscale factor (2.0 means we won't upscale beyond 2x the original)
MAX_UPSCALE_FACTOR = 2.0

# --- Alpha Detection ---
# Minimum alpha value to consider a pixel as "foreground" (0-255)
ALPHA_THRESHOLD = 30

# Minimum contour area (in pixels) to consider as part of the product
# Small blobs below this are treated as noise
MIN_CONTOUR_AREA = 500
