"""
Karigar Setu — Voice Pipeline.

Public API for the voice transcription engine. Import from here for clean usage:

    from ML.voice_pipeline import process_voice_note, transcribe

Pipeline stages:
    1. Transcribe an artisan's voice note in its source language (Bhashini ASR)
    2. Optionally translate to English for languages the catalog service does
       not handle natively — skipped for Hindi

The pipeline ends at the transcript. Listing generation belongs to the backend
catalog service, and text-to-speech read-back runs on the artisan's device, so
neither is implemented here.

    voice pipeline → transcript → backend catalog service → listing → device TTS
"""

from .orchestrator.processor import ArtisanVoiceProcessor
from .config import get_settings, needs_translation
from .glossary import build_prompt_hint, get_glossary_terms
from .transcription.runner import TranscriptionRunner

__all__ = [
    "process_voice_note",
    "transcribe",
    "ArtisanVoiceProcessor",
    "TranscriptionRunner",
    "get_settings",
    "needs_translation",
    "get_glossary_terms",
    "build_prompt_hint",
]


def transcribe(
    audio_path: str,
    language_code: str = "hi",
    category_hint: str | None = None,
) -> dict:
    """
    Transcribe a voice note without the translation stage.

    Useful for verifying speech recognition quality in isolation.

    Args:
        audio_path: Path to the recorded audio file.
        language_code: Language the artisan spoke in.
        category_hint: Optional craft category.

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

    This is the main entry point — it transcribes the recording and, for
    languages that need it, translates the transcript to English. The result
    is text ready to hand to the backend catalog service.

    Args:
        audio_path: Path to the recorded audio file (.m4a, .wav, .mp3).
        language_code: Language the artisan selected before recording.
        category_hint: Optional craft category, returned to the caller.
        product_draft_id: Draft this recording belongs to.

    Returns:
        Dict with status, transcript, optional translation, and
        `text_for_listing` — the string the catalog service should consume.
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
