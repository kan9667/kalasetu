"""
Transcription Runner.

Selects and runs the configured speech-to-text backend:
1. Reads the provider name from settings
2. Instantiates the matching transcriber
3. Delegates the voice note to it

Adding a new backend means adding a subclass of BaseTranscriber and one entry
in the registry below — no other module changes.
"""

from __future__ import annotations

import logging

from ..config import get_settings
from ..models import Transcript, VoiceNote
from .base_transcriber import BaseTranscriber
from .bhashini_transcriber import BhashiniTranscriber

logger = logging.getLogger(__name__)


# ── Backend Registry ─────────────────────────────────────────────────────────

TRANSCRIBERS: dict[str, type[BaseTranscriber]] = {
    "bhashini": BhashiniTranscriber,
}


class TranscriptionRunner:
    """Resolves the configured transcription backend and runs it."""

    def __init__(self, provider: str | None = None):
        self.settings = get_settings()
        self.provider_name = provider or self.settings.stt_provider

        transcriber_cls = TRANSCRIBERS.get(self.provider_name)
        if transcriber_cls is None:
            raise ValueError(
                f"Unknown STT provider '{self.provider_name}'. "
                f"Available: {', '.join(TRANSCRIBERS)}"
            )

        self.transcriber = transcriber_cls()
        logger.info("Transcription backend: %s", self.provider_name)

    def run(self, note: VoiceNote, category_hint: str | None = None) -> Transcript:
        """Transcribe one voice note with the configured backend."""
        return self.transcriber.transcribe(note, category_hint=category_hint)
