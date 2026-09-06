# AI Image Enhancer for Artisans (Student Edition)

A clean, easy-to-understand Python project that automatically turns ordinary handicraft photos into clean, studio-quality e-commerce product listings.

Built for students, learners, and hackathons (e.g. Smart India Hackathon / Kalasetu) to showcase how AI & Computer Vision can empower local artisans.

---

## What Problem Does This Solve?

Artisans often photograph their handmade products (pottery, sarees, jewelry, wooden crafts) in homes or workshops with:
- Cluttered backgrounds (walls, floors, workshop tools)
- Poor or uneven lighting
- Awkward angles and off-center placement

This pipeline automatically:
1. Removes the cluttered background using AI.
2. Centers and crops the product neatly with ideal margin padding.
3. Fixes lighting and color casts.
4. Places the product on a standard square (1200x1200px) white e-commerce canvas.

---

## Quick Start (in 2 Steps!)

### 1. Install Requirements
Open your terminal in this folder and run:
```bash
pip install -r requirements.txt
```

### 2. Run the Enhancer
Simply run:
```bash
python run_enhancer.py
```
This opens an interactive menu where you can:
- Pick any sample photo (`[1]` to `[8]`)
- Enhance all sample photos at once (`[A]`)
- Enter your own photo path (`[C]`)

You can also run directly on any photo:
```bash
python run_enhancer.py input/clean_bg.jpg
```
Or specify where to save the output:
```bash
python run_enhancer.py input/clean_bg.jpg output/my_product.jpg
```

---

## How It Works (6-Stage Pipeline)

For project presentations and vivas, here is how each stage works:

```
[Raw Photo] 
    │
    ▼
1. Validation        ── Checks file format (.jpg, .png, .webp) and size.
    │
    ▼
2. AI Background     ── Deep learning model (U2-Net / rembg) removes background
   Removal              leaving a transparent product image.
    │
    ▼
3. Auto-Crop         ── Detects product bounding box and crops with 8% padding.
    │
    ▼
4. Lighting & Color  ── CLAHE fixes contrast in LAB color space;
   Correction           Gray-World algorithm corrects yellow/blue light casts.
    │
    ▼
5. E-Commerce Canvas ── Centers product on a clean 1200x1200px white background.
    │
    ▼
6. Optimization      ── Saves as an optimized, compressed e-commerce image.
```

---

## Project Structure

```
image_pipeline/
├── run_enhancer.py      # Main runner script (interactive menu & CLI)
├── enhancer.py          # The 6-stage enhancement pipeline
├── config.py            # Easy settings (image dimensions, quality, colors)
├── requirements.txt     # Python libraries needed
│
├── input/               # Place your raw photos here
│   ├── clean_bg.jpg
│   ├── cluttered_bg.jpg
│   ├── jewelry.jpg
│   └── textile_saree.jpg
│
├── output/              # Enhanced photos are saved here!
│
├── processors/          # Modular computer vision functions
│   ├── background_removal.py  # AI background separation (rembg)
│   ├── cropping.py            # Contours and bounding box crop
│   ├── lighting.py            # Contrast, brightness & color balance
│   ├── background_canvas.py   # White canvas compositing
│   ├── input_validation.py    # File format & size checks
│   └── image_output.py        # Resizing and saving
│
└── create_test_images.py # Helper script to generate synthetic test photos
```

---

## Changing Settings (`config.py`)

You can easily tweak settings in `config.py`:
- `OUTPUT_WIDTH` & `OUTPUT_HEIGHT`: Canvas size (default: 1200x1200px).
- `BACKGROUND_COLOR`: Canvas color (default: white `(255, 255, 255)`).
- `JPEG_QUALITY`: Output quality (default: 92).
- `SHARPEN_ENABLED`: Toggle edge sharpening on/off (`True` or `False`).

---

## Technologies Used

- **Python 3.10+**
- **rembg & ONNX Runtime**: AI background segmentation
- **OpenCV (`opencv-python-headless`)**: Computer vision and color space transformations
- **Pillow (PIL)**: Image loading, canvas composition, and export
- **NumPy**: Matrix and image array operations
