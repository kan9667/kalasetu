"""
Transcriber Base Class.

Defines the contract every speech-to-text backend must satisfy:
1. Accept a VoiceNote pointing at a saved audio file
2. Return a Transcript in the source language
3. Never raise on provider failure — return a flagged fallback instead

Transcription is a swappable tool, not a fixed vendor. Backends are selected
by configuration, so the rest of the pipeline is unaware of which one ran.
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from pathlib import Path

from ..models import STTProvider, Transcript, VoiceNote

logger = logging.getLogger(__name__)


# ── Audio Formats ────────────────────────────────────────────────────────────

# Extension → the format name declared to the ASR service.
# The mobile client records .m4a (AAC). Services that accept only WAV or FLAC
# will need the file converted before it is sent — see the README.
AUDIO_FORMATS: dict[str, str] = {
    ".wav": "wav",
    ".flac": "flac",
    ".mp3": "mp3",
    ".m4a": "m4a",
    ".aac": "aac",
    ".ogg": "ogg",
}


class BaseTranscriber(ABC):
    """Abstract base for all speech-to-text backends."""

    provider: STTProvider = STTProvider.MANUAL

    @abstractmethod
    def transcribe(self, note: VoiceNote, category_hint: str | None = None) -> Transcript:
        """
        Convert a voice note into text in its source language.

        Args:
            note: The recording to transcribe.
            category_hint: Optional craft category, used to select the most
                           relevant glossary terms for the prompt.

        Returns:
            A Transcript. On provider failure, returns one with is_fallback=True
            rather than raising.
        """
        raise NotImplementedError

    # ── Shared helpers ───────────────────────────────────────────────────

    def validate_audio(self, note: VoiceNote, max_duration: int) -> None:
        """
        Reject an unusable recording before spending an API call.

        Raises:
            FileNotFoundError: The audio file is missing.
            ValueError: The file is empty or exceeds the duration limit.
        """
        path = Path(note.audio_path)
        if not path.exists():
            raise FileNotFoundError(f"Audio file not found: {note.audio_path}")

        if path.stat().st_size == 0:
            raise ValueError(f"Audio file is empty: {note.audio_path}")

        if note.duration_seconds and note.duration_seconds > max_duration:
            raise ValueError(
                f"Recording is {note.duration_seconds:.0f}s, "
                f"which exceeds the {max_duration}s limit."
            )

    @staticmethod
    def detect_format(note: VoiceNote) -> str:
        """
        Determine the audio format from the file extension.

        Returns the format name the ASR service expects. An unrecognised
        extension is logged and passed through as-is rather than guessed at,
        so a rejection names the real format instead of a substituted one.
        """
        suffix = Path(note.audio_path).suffix.lower()
        fmt = AUDIO_FORMATS.get(suffix)
        if fmt is None:
            logger.warning(
                "Unrecognised audio extension '%s' for %s — sending as-is.",
                suffix,
                note.id,
            )
            return suffix.lstrip(".")
        return fmt

    def fallback_transcript(self, note: VoiceNote, reason: str) -> Transcript:
        """
        Build a flagged placeholder for a failed transcription.

        The is_fallback flag must be checked before publishing. A silent
        fallback that looks like a successful transcript will produce a
        listing describing a product the artisan never mentioned.
        """
        logger.error("Transcription failed for %s: %s", note.id, reason)
        return Transcript(
            text="",
            language_code=note.language_code,
            provider=self.provider,
            is_fallback=True,
        )
