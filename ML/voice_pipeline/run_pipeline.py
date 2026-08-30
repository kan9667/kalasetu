"""
Karigar Setu Voice Pipeline — Manual CLI Runner.

Run this script to execute the voice pipeline stages on demand.

Usage:
    # Transcribe a recording only (no listing generation):
    python run_pipeline.py transcribe --audio input/voice-note.m4a

    # Transcribe in a specific language:
    python run_pipeline.py transcribe --audio input/saree.m4a --language ta

    # Run the pipeline (transcribe → translate):
    python run_pipeline.py process --audio input/voice-note.m4a

    # Full pipeline with a category hint:
    python run_pipeline.py process --audio input/pot.m4a --category Pottery

    # Write the result to a JSON file:
    python run_pipeline.py process --audio input/pot.m4a --out result.json

    # Check configuration and language routing:
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
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("requests").setLevel(logging.WARNING)


def cmd_transcribe(args) -> None:
    """Transcribe a voice note without generating a listing."""
    from ML.voice_pipeline import transcribe

    print("\n🎙️  Transcribing voice note...")
    print(f"   Audio:    {args.audio}")
    print(f"   Language: {args.language}")
    print()

    result = transcribe(
        audio_path=args.audio,
        language_code=args.language,
        category_hint=args.category,
    )

    if result.get("is_fallback"):
        print("\n❌ Transcription failed — no usable text was produced.")
        print("   Check the API credentials and the audio file, then retry.")
        sys.exit(1)

    print("\n✅ Transcription complete!")
    print(f"   Provider:  {result.get('provider')}")
    print(f"   Language:  {result.get('language_code')}")
    print(f"   Length:    {len(result.get('text', ''))} characters")
    print(f"\n   {result.get('text')}\n")


def cmd_process(args) -> None:
    """Run the pipeline on a voice note."""
    from ML.voice_pipeline import process_voice_note

    print("\n🎙️  Running the voice pipeline...")
    print(f"   Audio:    {args.audio}")
    print(f"   Language: {args.language}")
    if args.category:
        print(f"   Category hint: {args.category}")
    print()

    result = process_voice_note(
        audio_path=args.audio,
        language_code=args.language,
        category_hint=args.category,
    )

    if result.get("status") != "completed":
        print(f"\n❌ Pipeline failed at stage: {result.get('failed_stage')}")
        print(f"   {result.get('error')}")
        sys.exit(1)

    transcript = result["transcript"]
    print("\n✅ Pipeline complete!")
    print(f"   Elapsed:    {result.get('elapsed_seconds')}s")
    print(f"   Language:   {transcript['language_code']}")
    print(f"   Translated: {result.get('translation') is not None}")
    print()
    print("   Transcript:")
    print(f"   {transcript['text']}")
    print()
    print("   Ready for the catalog service:")
    print(f"   {result['text_for_listing']}")
    print()

    if args.out:
        Path(args.out).write_text(
            json.dumps(result, indent=2, ensure_ascii=False, default=str),
            encoding="utf-8",
        )
        print(f"   Saved to {args.out}\n")


def cmd_status(args) -> None:
    """Show configuration and language routing."""
    from ML.voice_pipeline.config import get_settings, needs_translation

    settings = get_settings()

    print("\n⚙️  Voice pipeline configuration\n")
    print(f"   STT provider:      {settings.stt_provider}")
    print(f"   Default language:  {settings.default_language}")
    print(f"   Max duration:      {settings.max_audio_duration_seconds}s")
    print(f"   Glossary terms:    {settings.glossary_terms_in_prompt}")
    print()
    print("   Credentials:")
    print(f"     Bhashini user ID:  {'set' if settings.bhashini_user_id else 'MISSING'}")
    print(f"     Bhashini API key:  {'set' if settings.bhashini_api_key else 'MISSING'}")
    print()
    print("   Language routing:")
    for code in settings.supported_languages:
        route = "translate → English" if needs_translation(code) else "direct"
        print(f"     {code:<4} {route}")
    print()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Karigar Setu voice pipeline runner.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose logging.")
    sub = parser.add_subparsers(dest="command", required=True)

    # transcribe
    p_tr = sub.add_parser("transcribe", help="Transcribe a voice note only.")
    p_tr.add_argument("--audio", required=True, help="Path to the audio file.")
    p_tr.add_argument("--language", default="hi", help="Source language code.")
    p_tr.add_argument("--category", default=None, help="Craft category hint.")
    p_tr.set_defaults(func=cmd_transcribe)

    # process
    p_pr = sub.add_parser("process", help="Transcribe and prepare text for cataloging.")
    p_pr.add_argument("--audio", required=True, help="Path to the audio file.")
    p_pr.add_argument("--language", default="hi", help="Source language code.")
    p_pr.add_argument("--category", default=None, help="Craft category hint.")
    p_pr.add_argument("--out", default=None, help="Write the result to this JSON file.")
    p_pr.set_defaults(func=cmd_process)

    # status
    p_st = sub.add_parser("status", help="Show configuration and language routing.")
    p_st.set_defaults(func=cmd_status)

    args = parser.parse_args()
    setup_logging(args.verbose)
    args.func(args)


if __name__ == "__main__":
    main()
