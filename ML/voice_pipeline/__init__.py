"""
Karigar Setu — Voice Pipeline.

Public API for the voice transcription engine. Import from here for clean usage:

    from ML.voice_pipeline import process_voice_note, transcribe

Pipeline stages:
    1. Validate the recording
    2. Transcribe it in its source language (Whisper)

The pipeline ends at the transcript. Listing generation belongs to the backend
catalog service, and text-to-speech read-back runs on the artisan's device, so
neither is implemented here.

    voice pipeline → transcript → backend catalog service → listing → device TTS
"""

from .config import get_settings
from .glossary import build_prompt_hint, get_glossary_terms
from .orchestrator.processor import ArtisanVoiceProcessor
from .transcription.runner import TranscriptionRunner

__all__ = [
    "process_voice_note",
    "transcribe",
    "ArtisanVoiceProcessor",
    "TranscriptionRunner",
    "get_settings",
    "get_glossary_terms",
    "build_prompt_hint",
]


def transcribe(
    audio_path: str,
    language_code: str = "hi",
    category_hint: str | None = None,
) -> dict:
    """
    Transcribe a voice note, returning the raw transcript only.

    Useful for verifying speech recognition quality in isolation.

    Args:
        audio_path: Path to the recorded audio file.
        language_code: Language the artisan spoke in.
        category_hint: Craft category, used to prioritise glossary terms.

    Returns:
        Dict with the transcript text, language, provider, and fallback flag.
    """
    from .models import VoiceNote

    runner = TranscriptionRunner()
    note = VoiceNote(
        id=f"transcribe-{abs(hash(audio_path))}",
        audio_path=audio_path,
        language_code=language_code,
    )
    return runner.run(note, category_hint=category_hint).model_dump()


def process_voice_note(
    audio_path: str,
    language_code: str = "hi",
    category_hint: str | None = None,
    product_draft_id: str | None = None,
) -> dict:
    """
    Run an artisan's voice note through the pipeline.

    This is the main entry point — it validates and transcribes the recording
    and returns text ready to hand to the backend catalog service.

    Args:
        audio_path: Path to the recorded audio file (.m4a, .wav, .mp3).
        language_code: Language the artisan selected before recording.
        category_hint: Craft category, used to prioritise glossary terms.
        product_draft_id: Draft this recording belongs to.

    Returns:
        Dict with status, transcript, and `text_for_listing` — the string the
        catalog service should consume.
    """
    processor = ArtisanVoiceProcessor()
    result = processor.process_voice_note(
        audio_path=audio_path,
        language_code=language_code,
        category_hint=category_hint,
        product_draft_id=product_draft_id,
    )
    payload = result.model_dump()
    payload["text_for_listing"] = result.text_for_listing
    return payload
