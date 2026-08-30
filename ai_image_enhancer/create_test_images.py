# ============================================================
# create_test_images.py — Generate synthetic test images
# ============================================================
# Creates various test images to verify the enhancement pipeline
# works correctly with different scenarios.
# Run: python create_test_images.py
# ============================================================

import os
import sys
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image, ImageDraw, ImageFilter


def create_product_on_cluttered_bg(path):
    """Test case: Product on a cluttered, busy background."""
    img = Image.new("RGB", (800, 600), (120, 100, 80))
    draw = ImageDraw.Draw(img)
    
    # Draw background clutter (random rectangles)
    random.seed(42)
    for _ in range(30):
        x1, y1 = random.randint(0, 700), random.randint(0, 500)
        x2, y2 = x1 + random.randint(20, 100), y1 + random.randint(20, 100)
        color = (random.randint(50, 200), random.randint(50, 200), random.randint(50, 200))
        draw.rectangle([x1, y1, x2, y2], fill=color)
    
    # Draw the "product" — a vase-like shape in the center
    # Body
    draw.ellipse([300, 150, 500, 450], fill=(200, 80, 40))
    # Neck
    draw.rectangle([370, 100, 430, 180], fill=(200, 80, 40))
    # Rim
    draw.ellipse([355, 85, 445, 120], fill=(220, 100, 60))
    # Decorative pattern
    draw.ellipse([340, 250, 460, 350], fill=(180, 60, 30), outline=(240, 180, 100), width=3)
    
    img.save(path, "JPEG", quality=90)
    print(f"  Created: {path}")


def create_dark_product(path):
    """Test case: Product in very dark/underexposed conditions."""
    img = Image.new("RGB", (600, 600), (15, 15, 20))
    draw = ImageDraw.Draw(img)
    
    # Very dark product (barely visible)
    draw.ellipse([150, 100, 450, 500], fill=(40, 35, 30))
    draw.ellipse([200, 200, 400, 400], fill=(50, 45, 35))
    # Small highlight
    draw.ellipse([280, 220, 320, 260], fill=(70, 65, 55))
    
    img.save(path, "JPEG", quality=90)
    print(f"  Created: {path}")


def create_bright_product(path):
    """Test case: Overexposed/very bright product."""
    img = Image.new("RGB", (600, 600), (250, 248, 245))
    draw = ImageDraw.Draw(img)
    
    # Bright product on bright background
    draw.rounded_rectangle([150, 100, 450, 500], radius=30, fill=(245, 230, 210))
    draw.rounded_rectangle([180, 150, 420, 450], radius=20, fill=(240, 220, 195))
    # Pattern
    for y in range(180, 430, 40):
        draw.line([(200, y), (400, y)], fill=(230, 200, 170), width=2)
    
    img.save(path, "JPEG", quality=90)
    print(f"  Created: {path}")


def create_uneven_lighting(path):
    """Test case: Product with uneven lighting (bright left, dark right)."""
    img = Image.new("RGB", (700, 500), (100, 110, 105))
    draw = ImageDraw.Draw(img)
    
    # Gradient background to simulate uneven lighting
    for x in range(700):
        brightness = int(180 - (x / 700) * 120)
        for y in range(500):
            # Only set background pixels
            pass
    
    # Simpler approach: draw two halves
    draw.rectangle([0, 0, 350, 500], fill=(180, 185, 175))
    draw.rectangle([350, 0, 700, 500], fill=(60, 65, 55))
    
    # Product spanning both zones
    draw.ellipse([200, 100, 500, 400], fill=(180, 50, 50))
    draw.ellipse([250, 150, 450, 350], fill=(200, 70, 70))
    draw.ellipse([300, 200, 400, 300], fill=(220, 90, 90))
    
    img.save(path, "JPEG", quality=90)
    print(f"  Created: {path}")


def create_textile_saree(path):
    """Test case: Textile/saree-like image with intricate patterns."""
    img = Image.new("RGB", (800, 600), (180, 160, 140))
    draw = ImageDraw.Draw(img)
    
    # Folded fabric shape
    draw.polygon(
        [(100, 100), (700, 80), (680, 520), (120, 500)],
        fill=(180, 30, 60)
    )
    
    # Fabric pattern (horizontal lines for weave)
    for y in range(100, 500, 8):
        color = (200, 50, 80) if (y // 8) % 2 == 0 else (160, 20, 50)
        draw.line([(120, y), (680, y)], fill=color, width=2)
    
    # Border pattern
    draw.rectangle([100, 100, 140, 500], fill=(220, 180, 50))
    draw.rectangle([660, 80, 700, 520], fill=(220, 180, 50))
    
    # Zari-like pattern on borders
    for y in range(100, 500, 20):
        draw.ellipse([108, y, 132, y + 15], fill=(240, 200, 80))
        draw.ellipse([668, y, 692, y + 15], fill=(240, 200, 80))
    
    img.save(path, "JPEG", quality=90)
    print(f"  Created: {path}")


def create_jewelry(path):
    """Test case: Jewelry/small handicraft item."""
    img = Image.new("RGB", (500, 500), (200, 195, 190))
    draw = ImageDraw.Draw(img)
    
    # Table surface
    draw.rectangle([0, 300, 500, 500], fill=(140, 120, 100))
    
    # Necklace-like circular shape
    draw.ellipse([150, 120, 350, 320], outline=(200, 170, 50), width=8)
    draw.ellipse([155, 125, 345, 315], outline=(220, 190, 70), width=4)
    
    # Pendant
    draw.polygon([(235, 310), (265, 310), (250, 360)], fill=(200, 170, 50))
    draw.ellipse([240, 290, 260, 310], fill=(220, 190, 70))
    
    # Gemstones
    for angle_offset in range(0, 360, 45):
        import math
        cx = 250 + int(95 * math.cos(math.radians(angle_offset)))
        cy = 220 + int(95 * math.sin(math.radians(angle_offset)))
        draw.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=(180, 30, 30))
    
    img.save(path, "JPEG", quality=90)
    print(f"  Created: {path}")


def create_small_product(path):
    """Test case: Very small product in a large frame."""
    img = Image.new("RGB", (800, 800), (160, 165, 155))
    draw = ImageDraw.Draw(img)
    
    # Background texture
    for i in range(0, 800, 4):
        shade = 155 + (i % 20)
        draw.line([(0, i), (800, i)], fill=(shade, shade + 5, shade - 5))
    
    # Small product in center
    draw.ellipse([350, 350, 450, 450], fill=(50, 100, 180))
    draw.ellipse([365, 365, 435, 435], fill=(70, 120, 200))
    
    img.save(path, "JPEG", quality=90)
    print(f"  Created: {path}")


def create_clean_bg_product(path):
    """Test case: Product already on a relatively clean background."""
    img = Image.new("RGB", (600, 600), (240, 240, 240))
    draw = ImageDraw.Draw(img)
    
    # Product — a pot/vase shape
    draw.ellipse([180, 200, 420, 480], fill=(160, 80, 40))
    draw.rectangle([230, 120, 370, 230], fill=(160, 80, 40))
    draw.ellipse([220, 105, 380, 145], fill=(175, 95, 55))
    
    # Pattern on pot
    draw.arc([220, 280, 380, 400], 0, 360, fill=(200, 140, 80), width=3)
    draw.arc([200, 320, 400, 440], 0, 360, fill=(200, 140, 80), width=3)
    
    img.save(path, "JPEG", quality=90)
    print(f"  Created: {path}")


def main():
    """Generate all test images in the input/ directory."""
    input_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "input")
    os.makedirs(input_dir, exist_ok=True)
    
    print("Generating synthetic test images...")
    print()
    
    create_product_on_cluttered_bg(os.path.join(input_dir, "cluttered_bg.jpg"))
    create_dark_product(os.path.join(input_dir, "dark_product.jpg"))
    create_bright_product(os.path.join(input_dir, "bright_product.jpg"))
    create_uneven_lighting(os.path.join(input_dir, "uneven_lighting.jpg"))
    create_textile_saree(os.path.join(input_dir, "textile_saree.jpg"))
    create_jewelry(os.path.join(input_dir, "jewelry.jpg"))
    create_small_product(os.path.join(input_dir, "small_product.jpg"))
    create_clean_bg_product(os.path.join(input_dir, "clean_bg.jpg"))
    
    print()
    print(f"Done! {8} test images created in: {input_dir}")
    print("Run the enhancer on them:")
    print("  python main.py input/cluttered_bg.jpg")


if __name__ == "__main__":
    main()
