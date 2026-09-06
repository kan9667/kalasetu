# ============================================================
# run_enhancer.py — Student-Friendly AI Image Enhancer Runner
# ============================================================
# Easy ways to run this:
#   1. Double-click or run: python run_enhancer.py
#      (Interactive menu: pick sample images, enhance all, or enter custom path)
#   2. Run directly on a photo:
#      python run_enhancer.py input/clean_bg.jpg
#   3. Run with custom output path:
#      python run_enhancer.py input/clean_bg.jpg output/my_product.jpg
# ============================================================

import os
import sys
import glob
from pathlib import Path

# Add project root to sys.path
PROJECT_DIR = Path(__file__).resolve().parent
if str(PROJECT_DIR) not in sys.path:
    sys.path.insert(0, str(PROJECT_DIR))

from enhancer import enhance_image
from processors.input_validation import ImageValidationError


def print_banner():
    """Display a friendly project banner."""
    print("=" * 60)
    print("           Kalasetu - AI Image Enhancer")
    print("   Transforming artisan photos into e-commerce listings")
    print("=" * 60)


def get_sample_images():
    """Find available sample images in the input directory."""
    input_dir = PROJECT_DIR / "input"
    extensions = ("*.jpg", "*.jpeg", "*.png", "*.webp")
    images = []
    for ext in extensions:
        images.extend(input_dir.glob(ext))
    return sorted(images)


def process_single_image(input_path, output_path=None):
    """Process a single image with clear, friendly feedback."""
    try:
        input_name = os.path.basename(input_path)
        print(f"\nProcessing: {input_name}")
        print("-" * 50)
        
        result_path = enhance_image(str(input_path), output_path)
        
        print("-" * 50)
        print(f"Enhancement complete!")
        print(f"Result saved to: {result_path}")
        return True
    except ImageValidationError as e:
        print(f"\n[Image Error] Could not process '{input_path}':\n  {e}")
        print("Tip: Make sure the file exists and is a valid JPG/PNG/WEBP photo.")
        return False
    except ValueError as e:
        print(f"\n[Detection Error] {e}")
        print("Tip: The background removal could not clearly isolate the subject.")
        return False
    except Exception as e:
        print(f"\n[Unexpected Error] {e}")
        return False


def run_interactive_menu():
    """Interactive menu for students when running without CLI arguments."""
    print_banner()
    samples = get_sample_images()
    
    print("\nSelect an image to enhance:")
    if samples:
        for idx, sample in enumerate(samples, start=1):
            print(f"  [{idx}] {sample.name}")
        print(f"  [A] Process ALL sample images ({len(samples)} found)")
    else:
        print("  (No images currently found in the 'input/' folder)")
        
    print("  [C] Enter custom file path")
    print("  [Q] Exit")
    print("=" * 60)

    # Check if running in a non-interactive environment (e.g. piped or automated)
    if not sys.stdin.isatty():
        if samples:
            print(f"Non-interactive session detected. Processing first sample: {samples[0].name}")
            process_single_image(samples[0])
        return

    try:
        choice = input("\nEnter your choice [1-8 / A / C / Q]: ").strip()
    except (EOFError, KeyboardInterrupt):
        print("\nExiting.")
        return

    if not choice:
        if samples:
            print(f"Defaulting to first sample: {samples[0].name}")
            process_single_image(samples[0])
        return

    choice_upper = choice.upper()

    if choice_upper == "Q":
        print("Exiting. Happy learning!")
        return

    if choice_upper == "A":
        if not samples:
            print("No samples found in input/.")
            return
        print(f"\nBatch processing all {len(samples)} images...")
        success_count = 0
        for sample in samples:
            if process_single_image(sample):
                success_count += 1
        print("\n" + "=" * 60)
        print(f"Batch completed: {success_count}/{len(samples)} images enhanced.")
        print(f"Check your results in: {PROJECT_DIR / 'output'}")
        print("=" * 60)
        return

    if choice_upper == "C":
        try:
            custom_path = input("Enter path to your image: ").strip().strip('"').strip("'")
            if custom_path:
                process_single_image(custom_path)
        except (EOFError, KeyboardInterrupt):
            pass
        return

    # Check if user selected a number from the list
    if choice.isdigit():
        index = int(choice) - 1
        if 0 <= index < len(samples):
            process_single_image(samples[index])
            return
        else:
            print(f"Invalid option '{choice}'. Please pick between 1 and {len(samples)}.")
            return

    # If user typed an image path directly in the prompt
    if os.path.exists(choice.strip('"').strip("'")):
        process_single_image(choice.strip('"').strip("'"))
    else:
        print(f"Unrecognized option or file not found: {choice}")


def main():
    """Main program entry point."""
    # Case 1: Image path provided as CLI argument
    # Example: python run_enhancer.py "input/clean_bg.jpg"
    if len(sys.argv) > 1:
        print_banner()
        input_file = sys.argv[1].strip('"').strip("'")
        output_file = sys.argv[2].strip('"').strip("'") if len(sys.argv) > 2 else None
        process_single_image(input_file, output_file)
    else:
        # Case 2: No argument passed — open friendly interactive menu
        run_interactive_menu()


if __name__ == "__main__":
    main()
