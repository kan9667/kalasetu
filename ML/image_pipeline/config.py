# ============================================================
# config.py — Easy Settings for AI Image Enhancer
# ============================================================
# Students: You can easily tweak these settings to experiment
# with different results without changing any complex code!
# ============================================================

# ------------------------------------------------------------
# 1. BASIC SETTINGS (Most common things to change)
# ------------------------------------------------------------

# Final image dimensions (square 1200x1200 is standard for e-commerce)
OUTPUT_WIDTH = 1200
OUTPUT_HEIGHT = 1200

# Background color for the product canvas (RGB tuple)
# (255, 255, 255) = Clean White
BACKGROUND_COLOR = (255, 255, 255)

# Output image quality (1 to 95). 92 gives crisp photos with small file sizes.
JPEG_QUALITY = 92

# Padding around the product (0.08 means 8% space around edges)
CROP_PADDING = 0.08


# ------------------------------------------------------------
# 2. ENHANCEMENT TOGGLES (Turn features ON/OFF)
# ------------------------------------------------------------

# Sharpening: makes soft edges clearer without white edge halos
SHARPEN_ENABLED = True
SHARPEN_PERCENT = 40        # Mild sharpening strength (avoids white halo artifacts)
SHARPEN_RADIUS = 1          # Radius in pixels (1px keeps edges crisp without halos)
SHARPEN_THRESHOLD = 3

# Lighting correction: fixes dark/underexposed photos gently without bleaching
LIGHTING_ENABLED = True
TARGET_BRIGHTNESS = 110     # Natural brightness level (avoids washed-out whitish look)
CLAHE_CLIP_LIMIT = 1.0      # Gentle contrast adjustment (prevents chalky midtones)
CLAHE_TILE_SIZE = 8
GAMMA_MIN = 0.85            # Prevents aggressive over-brightening
GAMMA_MAX = 1.2             # Maximum brightness adjustment

# White balance: fixes yellow indoor lighting or blue tint
# 0.0 = preserve 100% natural original colors (prevents unnatural color shifts or greenish tints)
# Higher values (e.g. 0.3 - 0.5) shift colors toward neutral gray
WHITE_BALANCE_STRENGTH = 0.0


# ------------------------------------------------------------
# 3. SAFETY CHECKS (File validation)
# ------------------------------------------------------------

# Allowed file formats
SUPPORTED_FORMATS = {".jpg", ".jpeg", ".png", ".webp"}

# Max file size allowed (in Megabytes)
MAX_INPUT_SIZE_MB = 25

# Min & max pixel dimensions
MIN_DIMENSION = 100
MAX_DIMENSION = 10000

# Internal detection thresholds
ALPHA_THRESHOLD = 30
MIN_CONTOUR_AREA = 500
MAX_UPSCALE_FACTOR = 2.0
