# ============================================================
# main.py — Command-line interface for the image enhancer
# ============================================================
# Usage:
#   python main.py input/photo.jpg
#   python main.py input/photo.jpg output/enhanced.jpg
#   python main.py input/photo.jpg --quality 85 --no-sharpen
# ============================================================

import sys
import os
import argparse

# Add the project root to the Python path so imports work
# when running as: python main.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from enhancer import enhance_image
from processors.input_validation import ImageValidationError


def main():
    """Parse command-line arguments and run the enhancement pipeline."""
    
    parser = argparse.ArgumentParser(
        description="AI Image Enhancer — Turn product photos into e-commerce-ready images",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python main.py input/photo.jpg
  python main.py input/photo.jpg output/enhanced.jpg
  python main.py input/photo.jpg --quality 85
  python main.py input/photo.jpg --no-sharpen
  python main.py input/photo.jpg --format PNG
  python main.py input/photo.jpg --width 800 --height 800
        """
    )
    
    # Required: input image path
    parser.add_argument(
        "input",
        help="Path to the input image file (JPG, JPEG, PNG, or WEBP)"
    )
    
    # Optional: output image path
    parser.add_argument(
        "output",
        nargs="?",
        default=None,
        help="Path for the output image (default: output/<name>_enhanced.<ext>)"
    )
    
    # Optional: quality
    parser.add_argument(
        "--quality", "-q",
        type=int,
        default=None,
        help="JPEG/WEBP quality (1-95, default: 92)"
    )
    
    # Optional: output format
    parser.add_argument(
        "--format", "-f",
        choices=["JPEG", "PNG", "WEBP", "jpeg", "png", "webp"],
        default=None,
        help="Output format (default: auto-detect from extension)"
    )
    
    # Optional: canvas size
    parser.add_argument(
        "--width",
        type=int,
        default=None,
        help="Output canvas width in pixels (default: 1200)"
    )
    parser.add_argument(
        "--height",
        type=int,
        default=None,
        help="Output canvas height in pixels (default: 1200)"
    )
    
    # Optional: padding
    parser.add_argument(
        "--padding",
        type=float,
        default=None,
        help="Crop padding as a fraction (e.g., 0.08 for 8%%, default: 0.08)"
    )
    
    # Optional: disable sharpening
    parser.add_argument(
        "--no-sharpen",
        action="store_true",
        help="Disable the sharpening step"
    )
    
    # Optional: white balance strength
    parser.add_argument(
        "--wb-strength",
        type=float,
        default=None,
        help="White balance correction strength (0.0-1.0, default: 0.5)"
    )
    
    args = parser.parse_args()
    
    # Build the options dict from command-line arguments
    options = {}
    
    if args.quality is not None:
        options["quality"] = args.quality
    
    if args.format is not None:
        options["output_format"] = args.format.upper()
    
    if args.width is not None:
        options["canvas_width"] = args.width
    
    if args.height is not None:
        options["canvas_height"] = args.height
    
    if args.padding is not None:
        options["crop_padding"] = args.padding
    
    if args.no_sharpen:
        options["sharpen"] = False
    
    if args.wb_strength is not None:
        options["wb_strength"] = args.wb_strength
    
    # Run the pipeline
    try:
        print("=" * 50)
        print("  AI Image Enhancer")
        print("=" * 50)
        print(f"  Input:  {args.input}")
        print(f"  Output: {args.output or '(auto)'}")
        print("=" * 50)
        print()
        
        result_path = enhance_image(
            args.input,
            args.output,
            **options
        )
        
        print()
        print("=" * 50)
        print(f"  Enhancement complete!")
        print(f"  Output saved to: {result_path}")
        print("=" * 50)
        
    except ImageValidationError as e:
        print(f"\n[ERROR] Input validation failed:\n{e}", file=sys.stderr)
        sys.exit(1)
        
    except ValueError as e:
        print(f"\n[ERROR] Processing failed:\n{e}", file=sys.stderr)
        sys.exit(1)
        
    except MemoryError:
        print(
            "\n[ERROR] Out of memory!\n"
            "The image may be too large. Try reducing the image size\n"
            "before processing, or reduce the output canvas dimensions.",
            file=sys.stderr
        )
        sys.exit(1)
        
    except OSError as e:
        print(f"\n[ERROR] File system error:\n{e}", file=sys.stderr)
        sys.exit(1)
        
    except Exception as e:
        print(f"\n[ERROR] Unexpected error: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
