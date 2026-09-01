"""
Voice Pipeline — Data Models.

All structured data types used across transcription and artisan processing
are defined here for consistency.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


# ── Enums ────────────────────────────────────────────────────────────────────


class STTProvider(str, Enum):
    """Backends capable of transcribing an artisan voice note."""

    WHISPER = "whisper"
    MANUAL = "manual"


class PipelineStage(str, Enum):
    """Pipeline execution stages for logging."""

    INGESTION = "ingestion"
    TRANSCRIPTION = "transcription"
    HANDOFF = "handoff"


class JobStatus(str, Enum):
    """Lifecycle of a queued voice note."""

    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


# ── Voice Notes ──────────────────────────────────────────────────────────────


class VoiceNote(BaseModel):
    """A raw voice recording captured by an artisan in the mobile app."""

    id: str = Field(description="Unique identifier (idempotency key from the client).")
    audio_path: str = Field(description="Local file path to the recorded audio.")
    language_code: str = Field(
        default="hi",
        description="Language the artisan selected before recording.",
    )
    mime_type: str = Field(
        default="audio/mp4",
        description="Media type of the recording (m4a/AAC from the mobile client).",
    )
    duration_seconds: Optional[float] = Field(
        default=None, description="Recording length, when known."
    )
    product_draft_id: Optional[str] = Field(
        default=None, description="Draft this recording belongs to."
    )
    recorded_at: datetime = Field(
        default_factory=datetime.now,
        description="Timestamp when the artisan recorded this note.",
    )


# ── Transcription ────────────────────────────────────────────────────────────


class Transcript(BaseModel):
    """Text produced from a voice note by a transcription backend."""

    text: str = Field(description="Transcribed text in the source language.")
    language_code: str = Field(description="Language the text is written in.")
    provider: STTProvider = Field(description="Backend that produced this transcript.")
    is_fallback: bool = Field(
        default=False,
        description=(
            "True when transcription failed and placeholder text was substituted. "
            "Never publish a listing built from a fallback transcript."
        ),
    )
    duration_seconds: Optional[float] = Field(
        default=None, description="Length of the source audio."
    )
    transcribed_at: datetime = Field(
        default_factory=datetime.now,
        description="Timestamp when transcription completed.",
    )

    def is_usable(self) -> bool:
        """Whether this transcript is safe to feed into listing generation."""
        return not self.is_fallback and len(self.text.strip()) > 0


# ── Pipeline Result ──────────────────────────────────────────────────────────


class VoicePipelineResult(BaseModel):
    """
    The outcome of running one voice note through the pipeline.

    The pipeline stops at the transcript. Listing generation is owned by the
    backend catalog service, which consumes `text_for_listing`.
    """

    voice_note_id: str = Field(description="Identifier of the source recording.")
    status: JobStatus = Field(description="Terminal status of this run.")
    transcript: Optional[Transcript] = Field(default=None)
    failed_stage: Optional[PipelineStage] = Field(
        default=None, description="Stage that failed, when status is failed."
    )
    error: Optional[str] = Field(
        default=None, description="Error detail, when status is failed."
    )
    elapsed_seconds: float = Field(
        default=0.0, description="Wall-clock duration of the run."
    )

    @property
    def text_for_listing(self) -> str:
        """The text the backend should send to the catalog service."""
        return self.transcript.text if self.transcript else ""
