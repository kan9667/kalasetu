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

# Validated audio metadata: format_name -> (canonical_extension, mime_type)
AUDIO_METADATA: dict[str, tuple[str, str]] = {
    "m4a": (".m4a", "audio/mp4"),
    "wav": (".wav", "audio/wav"),
    "mp3": (".mp3", "audio/mpeg"),
    "ogg": (".ogg", "audio/ogg"),
    "flac": (".flac", "audio/flac"),
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

    @classmethod
    def inspect_audio_format(cls, path: Path) -> tuple[str, str, str]:
        """
        Inspect the audio format of the given file path.
        Returns (format_name, canonical_extension, mime_type).
        Raises ValueError on raw AAC or inconclusive/unsupported formats.
        """
        if path.exists():
            try:
                with path.open("rb") as f:
                    header = f.read(32)
                if len(header) >= 8 and header[4:8] == b"ftyp":
                    return ("m4a", ".m4a", "audio/mp4")
                # Check raw ADTS AAC BEFORE MP3 syncword check because (0xF0 & 0xE0) == 0xE0
                # ADTS syncword is 12 bits 0xFFF with layer bits (bits 2..1) == 00
                if len(header) >= 2 and header[0] == 0xFF and (header[1] & 0xF6) == 0xF0:
                    raise ValueError(
                        "Raw AAC streams without container are unsupported. "
                        "Please provide containerized audio (M4A, WAV, MP3, FLAC, OGG)."
                    )
                if len(header) >= 12 and header.startswith(b"RIFF") and header[8:12] == b"WAVE":
                    return ("wav", ".wav", "audio/wav")
                if header.startswith(b"ID3") or (
                    len(header) >= 2
                    and header[0] == 0xFF
                    and (header[1] & 0xE0) == 0xE0
                    and (header[1] & 0x06) != 0x00
                ):
                    return ("mp3", ".mp3", "audio/mpeg")
                if header.startswith(b"OggS"):
                    return ("ogg", ".ogg", "audio/ogg")
                if header.startswith(b"fLaC"):
                    return ("flac", ".flac", "audio/flac")
            except ValueError:
                raise
            except Exception:
                pass

        suffix = path.suffix.lower()
        if suffix == ".tmp" or not suffix:
            raise ValueError(
                f"Inconclusive audio format for staged file '{path.name}'. "
                "Unable to identify valid audio stream from magic bytes."
            )

        fmt = AUDIO_FORMATS.get(suffix)
        if fmt is not None:
            ext, mime = AUDIO_METADATA.get(fmt, (suffix, f"audio/{fmt}"))
            return (fmt, ext, mime)

        # For unrecognised non-tmp extension (passed through for explicit service rejection)
        clean_ext = suffix.lstrip(".")
        return (clean_ext, suffix, f"audio/{clean_ext}")

    @classmethod
    def detect_format(cls, note: VoiceNote) -> str:
        """
        Determine the audio format name from the voice note.
        """
        fmt, _, _ = cls.inspect_audio_format(Path(note.audio_path))
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
            fallback_reason=reason,
        )
