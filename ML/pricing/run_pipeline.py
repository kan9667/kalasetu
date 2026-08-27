"""
Karigar Setu Pricing Pipeline — Manual CLI Runner.

Run this script to execute the pricing pipeline stages on demand.

Usage:
    # Build the benchmark index using seed data (no network needed):
    python run_pipeline.py build --seed

    # Build the index with live scraping:
    python run_pipeline.py build

    # Build with force reindex (clears existing ChromaDB data):
    python run_pipeline.py build --seed --force

    # Get a price suggestion for an artisan product:
    python run_pipeline.py price --image path/to/image.jpg --description "Hand-woven silk saree from Varanasi"

    # Price with cost inputs:
    python run_pipeline.py price --image photo.jpg --description "Brass vase" --materials 500 --labor-hours 10 --hourly-rate 60

    # Check the current benchmark index status:
    python run_pipeline.py status
"""

import argparse
import json
import logging
import sys
from pathlib import Path

# Fix Windows console encoding for emoji output
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# Add the project root to sys.path so imports work when running directly
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


def setup_logging(verbose: bool = False) -> None:
    """Configure logging for the CLI."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s │ %(levelname)-8s │ %(name)s │ %(message)s",
        datefmt="%H:%M:%S",
    )
    # Quiet noisy libraries
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("chromadb").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)


def cmd_build(args) -> None:
    """Build the benchmark product index."""
    from ML.pricing.embeddings.build_index import build_benchmark_index

    print("\n🔨 Building benchmark index...")
    print(f"   Seed only: {args.seed}")
    print(f"   Force reindex: {args.force}")
    print()

    result = build_benchmark_index(
        use_seed=args.seed,
        skip_scraping=False,
        force_reindex=args.force,
    )

    print("\n✅ Build complete!")
    print(f"   Products scraped:  {result.get('products_scraped', 0)}")
    print(f"   Vectors generated: {result.get('vectors_generated', 0)}")
    print(f"   Vectors indexed:   {result.get('vectors_indexed', 0)}")
    print(f"   Total in store:    {result.get('total_in_store', 0)}")
    print(f"   Elapsed:           {result.get('elapsed_seconds', 0)}s")


def cmd_price(args) -> None:
    """Get a price suggestion for an artisan product."""
    from ML.pricing import get_price_suggestion

    # Build cost inputs if provided
    cost_inputs = None
    if any([args.materials, args.labor_hours, args.hourly_rate, args.transport, args.overhead]):
        cost_inputs = {
            "materials": args.materials or 0,
            "labor_hours": args.labor_hours or 0,
            "hourly_rate": args.hourly_rate or 0,
            "transport": args.transport or 0,
            "overhead": args.overhead or 0,
        }

    print("\n💰 Getting price suggestion...")
    print(f"   Image: {args.image}")
    print(f"   Description: {args.description[:80]}...")
    if cost_inputs:
        print(f"   Cost inputs: {cost_inputs}")
    if args.category:
        print(f"   Category: {args.category}")
    print()

    result = get_price_suggestion(
        image_path=args.image,
        description=args.description,
        cost_inputs=cost_inputs,
        category=args.category,
    )

    print("\n" + "=" * 60)
    print("  📊 PRICING RECOMMENDATION")
    print("=" * 60)
    print(f"  💵 Suggested Price:  ₹{result['suggested_price']:,.0f}")
    print(f"  📉 Price Range:      ₹{result['price_range_low']:,.0f} – ₹{result['price_range_high']:,.0f}")
    if result['cost_floor'] > 0:
        print(f"  🔒 Cost Floor:       ₹{result['cost_floor']:,.0f}")
    print(f"  🎯 Confidence:       {result['confidence_score']:.0%}")
    print(f"  📍 Market Position:  {result['market_position']}")
    print(f"\n  💬 Reasoning:")
    # Word-wrap the reasoning
    reasoning = result["reasoning"]
    words = reasoning.split()
    line = "     "
    for word in words:
        if len(line) + len(word) + 1 > 70:
            print(line)
            line = "     " + word
        else:
            line += " " + word
    if line.strip():
        print(line)

    if result.get("comparable_products"):
        print(f"\n  📋 Comparable Products Used ({len(result['comparable_products'])}):")
        for i, comp in enumerate(result["comparable_products"], 1):
            print(f"     {i}. {comp['title'][:50]} — ₹{comp['selling_price']:,.0f} ({comp['similarity_score']:.0%} match)")

    print("=" * 60)

    # Also save full result to file
    output_file = Path(__file__).parent / "data" / "last_pricing_result.json"
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False, default=str)
    print(f"\n  Full result saved to: {output_file}\n")


def cmd_status(args) -> None:
    """Check the current status of the benchmark index."""
    from ML.pricing.config import BENCHMARK_PRODUCTS_FILE, CHROMADB_DIR, DATA_DIR
    from ML.pricing.embeddings.vector_store import VectorStore

    print("\n📊 Pricing Pipeline Status")
    print("=" * 50)

    # Check data directory
    if DATA_DIR.exists():
        print(f"  📁 Data directory: ✅ {DATA_DIR}")
    else:
        print(f"  📁 Data directory: ❌ Not created yet")

    # Check benchmark products
    if BENCHMARK_PRODUCTS_FILE.exists():
        import json

        with open(BENCHMARK_PRODUCTS_FILE) as f:
            products = json.load(f)
        print(f"  📦 Benchmark products: ✅ {len(products)} products")
    else:
        print("  📦 Benchmark products: ❌ No data (run 'build' first)")

    # Check ChromaDB
    if CHROMADB_DIR.exists():
        try:
            store = VectorStore()
            count = store.get_count()
            print(f"  🗄️  ChromaDB vectors: ✅ {count} vectors indexed")
        except Exception as e:
            print(f"  🗄️  ChromaDB vectors: ⚠️  Error: {e}")
    else:
        print("  🗄️  ChromaDB vectors: ❌ Not initialized")

    # Check pricing results log
    results_log = DATA_DIR / "pricing_results.jsonl"
    if results_log.exists():
        line_count = sum(1 for _ in open(results_log))
        print(f"  📝 Pricing results log: ✅ {line_count} entries")
    else:
        print("  📝 Pricing results log: ❌ No pricing runs yet")

    print("=" * 50)
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Karigar Setu — AI Pricing Pipeline CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Enable debug logging"
    )

    subparsers = parser.add_subparsers(dest="command", help="Pipeline command")

    # ── build ────────────────────────────────────────────────────────────
    build_parser = subparsers.add_parser(
        "build", help="Build the benchmark product index"
    )
    build_parser.add_argument(
        "--seed",
        action="store_true",
        help="Use seed data only (no live scraping)",
    )
    build_parser.add_argument(
        "--force",
        action="store_true",
        help="Force reindex (clear existing ChromaDB data)",
    )

    # ── price ────────────────────────────────────────────────────────────
    price_parser = subparsers.add_parser(
        "price", help="Get a price suggestion for an artisan product"
    )
    price_parser.add_argument(
        "--image", required=True, help="Path to the product image"
    )
    price_parser.add_argument(
        "--description", required=True, help="English product description"
    )
    price_parser.add_argument("--category", help="Product category")
    price_parser.add_argument(
        "--materials", type=float, help="Raw material cost (INR)"
    )
    price_parser.add_argument(
        "--labor-hours", type=float, help="Hours of labor"
    )
    price_parser.add_argument(
        "--hourly-rate", type=float, help="Hourly rate (INR)"
    )
    price_parser.add_argument(
        "--transport", type=float, help="Transport cost (INR)"
    )
    price_parser.add_argument(
        "--overhead", type=float, help="Overhead cost (INR)"
    )

    # ── status ───────────────────────────────────────────────────────────
    subparsers.add_parser("status", help="Check benchmark index status")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    setup_logging(args.verbose)

    if args.command == "build":
        cmd_build(args)
    elif args.command == "price":
        cmd_price(args)
    elif args.command == "status":
        cmd_status(args)


if __name__ == "__main__":
    main()
