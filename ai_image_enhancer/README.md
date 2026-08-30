# AI Image Enhancer

A standalone Python module that transforms ordinary product photographs into clean, professional, e-commerce-ready product images.

Built for artisans who create handmade products (textiles, sarees, handicrafts, pottery, jewelry, woodwork, bamboo crafts) and need professional-looking product photos without knowing photo editing.

---

## What It Does

Takes an ordinary product photo with cluttered backgrounds, poor lighting, or color casts, and automatically produces a clean, centered, well-lit product image on a white background — ready for e-commerce listings.

## Pipeline

```
Input Photo
    ↓
Input Validation (format, size, corruption check)
    ↓
Background Removal (AI-based, using rembg / U2-Net)
    ↓
Product Detection (bounding box via alpha channel)
    ↓
Auto Crop (tight crop with configurable padding)
    ↓
Lighting Correction (CLAHE + gamma in LAB color space)
    ↓
White Balance (gray-world correction in LAB space)
    ↓
Optional Sharpening (mild unsharp mask)
    ↓
Clean Background (solid white)
    ↓
E-commerce Canvas (centered, consistent size)
    ↓
Resize + Compression
    ↓
Final E-commerce Image
```

---

## Installation

### 1. Create a virtual environment

```bash
python -m venv venv
```

### 2. Activate it

**Windows:**
```bash
venv\Scripts\activate
```

**Linux/macOS:**
```bash
source venv/bin/activate
```

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

> **Note:** The first run will download the rembg U2-Net model (~170 MB). This happens only once and is cached automatically.

---

## Usage

### Command Line

**Basic usage** (output goes to `output/` directory):
```bash
python main.py input/photo.jpg
```

**Specify output path:**
```bash
python main.py input/photo.jpg output/enhanced.jpg
```

**With options:**
```bash
# Lower JPEG quality for smaller file
python main.py input/photo.jpg --quality 85

# Disable sharpening
python main.py input/photo.jpg --no-sharpen

# Custom canvas size
python main.py input/photo.jpg --width 800 --height 800

# Output as PNG
python main.py input/photo.jpg output/enhanced.png --format PNG

# Custom white balance strength
python main.py input/photo.jpg --wb-strength 0.3

# Custom crop padding
python main.py input/photo.jpg --padding 0.15
```

### Python API

```python
from enhancer import enhance_image

# Basic usage
result = enhance_image("input/photo.jpg", "output/enhanced.jpg")

# With options
result = enhance_image(
    "input/photo.jpg",
    "output/enhanced.jpg",
    quality=85,
    canvas_width=800,
    canvas_height=800,
    sharpen=False,
    wb_strength=0.3,
    crop_padding=0.10,
    bg_color=(245, 245, 245),  # Light gray background
    output_format="PNG"
)
```

---

## Configuration

All settings are in **`config.py`**. Key settings:

| Setting | Default | Description |
|---|---|---|
| `OUTPUT_WIDTH` | 1200 | Canvas width in pixels |
| `OUTPUT_HEIGHT` | 1200 | Canvas height in pixels |
| `JPEG_QUALITY` | 92 | JPEG compression quality (1-95) |
| `CROP_PADDING` | 0.08 | Padding around product (8%) |
| `BACKGROUND_COLOR` | (255,255,255) | Background RGB color (white) |
| `SHARPEN_ENABLED` | True | Enable/disable sharpening |
| `SHARPEN_PERCENT` | 80 | Sharpening strength |
| `CLAHE_CLIP_LIMIT` | 2.0 | Contrast enhancement limit |
| `TARGET_BRIGHTNESS` | 130 | Target brightness level |
| `WHITE_BALANCE_STRENGTH` | 0.5 | WB correction intensity (0-1) |
| `MAX_INPUT_SIZE_MB` | 25 | Max input file size |

---

## Project Structure

```
ai_image_enhancer/
├── main.py                         # CLI entry point
├── enhancer.py                     # Main pipeline (enhance_image)
├── config.py                       # All settings
├── processors/
│   ├── __init__.py                 # Package exports
│   ├── input_validation.py         # File/format/size validation
│   ├── background_removal.py       # rembg background removal
│   ├── cropping.py                 # Product detection + auto-crop
│   ├── background_canvas.py        # Clean background + canvas
│   ├── lighting.py                 # Lighting, WB, sharpening
│   └── image_output.py            # Resize + save
├── requirements.txt
├── input/                          # Put your photos here
├── output/                         # Enhanced images appear here
└── tests/
    └── test_enhancer.py            # Unit tests
```

---

## Running Tests

```bash
pip install pytest
python -m pytest tests/ -v
```

---

## Dependencies

| Package | Purpose |
|---|---|
| `rembg` | AI-based background removal (U2-Net model) |
| `opencv-python-headless` | Image processing (lighting, color correction) |
| `Pillow` | Image manipulation, resize, compression |
| `numpy` | Array operations for image data |

---

## Processing Stages Explained

### 1. Input Validation
Checks that the file exists, has a supported format (.jpg/.jpeg/.png/.webp), isn't corrupted, and has reasonable dimensions (100-10000 pixels).

### 2. Background Removal
Uses the rembg library with the U2-Net deep learning model to separate the product from its background. Creates a transparent (RGBA) image where only the product is visible.

### 3. Product Detection
Analyzes the alpha channel to find the bounding box of the product. Uses OpenCV contour detection to ignore small noise pixels that might be left from imperfect background removal.

### 4. Auto-Crop
Crops the image tightly around the product with configurable padding (default 8%). Ensures no part of the product is cut off.

### 5. Lighting Correction
Converts to LAB color space and applies CLAHE (Contrast Limited Adaptive Histogram Equalization) to the L channel for better contrast. Then applies gamma correction if the image is too dark or too bright.

### 6. White Balance
Uses the gray-world assumption in LAB color space to reduce color casts (yellowish indoor lighting, bluish outdoor shadows). Applied at 50% strength by default to avoid over-correcting product colors.

### 7. Sharpening
Applies a mild unsharp mask to improve detail clarity. Optional and conservative — won't create artificial-looking edges.

### 8. Canvas Placement
Places the product on a clean white background and centers it on a standard 1200×1200 canvas. Maintains aspect ratio — never stretches the product.

### 9. Resize & Save
Final resize to target dimensions using LANCZOS resampling. Saves as progressive JPEG (optimized for web) by default.

---

## Troubleshooting

### "rembg" or model download issues
- Make sure you have internet access for the first run (model download)
- Try: `pip install rembg[gpu]` if you have a GPU
- The model is cached in `~/.u2net/`

### Out of memory errors
- Reduce `MAX_DIMENSION` in `config.py`
- Reduce input image size before processing
- Close other applications

### Colors look wrong after processing
- Reduce `WHITE_BALANCE_STRENGTH` to `0.2` or `0.0`
- Check if the original image has extreme color casts

### Product is cropped incorrectly
- Increase `CROP_PADDING` in `config.py` (try `0.15`)
- The product might not have been fully detected by rembg

### Output file is too large / too small
- Adjust `JPEG_QUALITY` (lower = smaller file, less quality)
- Adjust `OUTPUT_WIDTH` and `OUTPUT_HEIGHT`

### "No product detected" error
- The background removal model couldn't find a foreground object
- Try with a photo that has better contrast between product and background

### Import errors
- Make sure you're running from inside the `ai_image_enhancer/` directory
- Make sure the virtual environment is activated
- Run `pip install -r requirements.txt` again

---

## Future Integration

This module is designed to be called from a FastAPI backend:

```python
# Example future integration (NOT implemented here)
from enhancer import enhance_image

@app.post("/enhance")
async def enhance_endpoint(file: UploadFile):
    input_path = save_upload(file)
    output_path = enhance_image(input_path, output_path)
    return FileResponse(output_path)
```

The `enhance_image()` function is the single entry point — no changes needed to the processing logic.

---

## Limitations

- Background removal quality depends on the rembg U2-Net model. Very complex or camouflaged products may not separate cleanly.
- White balance correction uses a statistical method (gray-world). It may not be perfect for all lighting conditions.
- The module processes one image at a time. Batch processing would need to be implemented separately.
- Very small input images (under 100px) are rejected. The pipeline works best with reasonably high-resolution photos.
