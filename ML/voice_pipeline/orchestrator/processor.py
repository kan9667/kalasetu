"""
Artisan Voice Processor.

The main entry point for processing an artisan's voice note:
1. Transcribes the recording in its source language
2. Optionally translates the transcript to English

The pipeline stops here. Listing generation is owned by the backend catalog
service, which consumes the transcript this module produces — see the README
for the handoff contract.

This is triggered when the mobile app drains its offline queue and uploads a
recording. The artisan is never blocked waiting on it — the recording is saved
locally first and processed whenever connectivity allows.
"""

from __future__ import annotations

import json
import logging
import time
from datetime import datetime
from typing import Optional

from ..config import DATA_DIR, ensure_data_dirs, get_settings, needs_translation
from ..models import JobStatus, PipelineStage, VoiceNote, VoicePipelineResult
from ..transcription.runner import TranscriptionRunner
from ..translation.bhashini_translator import BhashiniTranslator

logger = logging.getLogger(__name__)


class ArtisanVoiceProcessor:
    """
    Processes an artisan's voice note through the pipeline:
    transcribe → optionally translate → return text ready for the catalog service.
    """

    def __init__(self):
        self.settings = get_settings()
        self.transcriber = TranscriptionRunner()
        self.translator = BhashiniTranslator()

    def process_voice_note(
        self,
        audio_path: str,
        language_code: str = "hi",
        category_hint: Optional[str] = None,
        note_id: Optional[str] = None,
        product_draft_id: Optional[str] = None,
    ) -> VoicePipelineResult:
        """
        Process a single voice note and return a transcript ready for cataloging.

        Args:
            audio_path: Path to the recorded audio file (.m4a, .wav, .mp3).
            language_code: Language the artisan selected before recording.
            category_hint: Optional craft category, passed through to the caller.
            note_id: Idempotency key from the client. Generated if absent.
            product_draft_id: Draft this recording belongs to.

        Returns:
            VoicePipelineResult carrying the transcript and optional translation.
            Failures are reported in the result rather than raised, so a queued
            job can be retried without losing context.
        """
        ensure_data_dirs()
        started = time.perf_counter()

        note = VoiceNote(
            id=note_id or f"voice-{int(time.time() * 1000)}",
            audio_path=audio_path,
            language_code=language_code,
            product_draft_id=product_draft_id,
        )
        logger.info("Processing voice note %s (lang=%s)", note.id, language_code)

        # ── Step 1: Transcribe ───────────────────────────────────────────
        logger.info("Step 1: Transcribing audio...")
        transcript = self.transcriber.run(note, category_hint=category_hint)

        if not transcript.is_usable():
            logger.error("Transcription unusable for %s — aborting.", note.id)
            return self._failed(
                note,
                PipelineStage.TRANSCRIPTION,
                "Transcription failed or returned empty text.",
                started,
                transcript=transcript,
            )

        logger.info("Transcript: %d characters", len(transcript.text))

        # ── Step 2: Translate (only where required) ──────────────────────
        translation = None

        if needs_translation(language_code):
            logger.info("Step 2: Translating '%s' → English...", language_code)
            translation = self.translator.translate(transcript)
        else:
            logger.info(
                "Step 2: Skipping translation — the catalog service handles '%s' natively.",
                language_code,
            )

        elapsed = time.perf_counter() - started
        result = VoicePipelineResult(
            voice_note_id=note.id,
            status=JobStatus.COMPLETED,
            transcript=transcript,
            translation=translation,
            elapsed_seconds=round(elapsed, 2),
        )

        logger.info(
            "Pipeline complete for %s: %d characters ready for cataloging (%.1fs)",
            note.id,
            len(result.text_for_listing),
            elapsed,
        )

        # ── Save result for audit trail ──────────────────────────────────
        self._save_result(result)

        return result

    def process_batch(self, notes: list[dict]) -> list[VoicePipelineResult]:
        """
        Process multiple voice notes.

        Args:
            notes: List of dicts, each with keys:
                   audio_path, language_code (optional), category_hint (optional).

        Returns:
            List of VoicePipelineResult instances, one per input.
        """
        results = []
        for i, note in enumerate(notes):
            logger.info("Processing voice note %d/%d...", i + 1, len(notes))
            results.append(
                self.process_voice_note(
                    audio_path=note["audio_path"],
                    language_code=note.get("language_code", self.settings.default_language),
                    category_hint=note.get("category_hint"),
                    note_id=note.get("id"),
                    product_draft_id=note.get("product_draft_id"),
                )
            )
        return results

    # ── Internals ────────────────────────────────────────────────────────

    def _failed(
        self,
        note: VoiceNote,
        stage: PipelineStage,
        error: str,
        started: float,
        transcript=None,
        translation=None,
    ) -> VoicePipelineResult:
        """Build a failed result, preserving whatever the run produced."""
        return VoicePipelineResult(
            voice_note_id=note.id,
            status=JobStatus.FAILED,
            transcript=transcript,
            translation=translation,
            failed_stage=stage,
            error=error,
            elapsed_seconds=round(time.perf_counter() - started, 2),
        )

    def _save_result(self, result: VoicePipelineResult) -> None:
        """Append the run outcome to the local audit log."""
        log_file = DATA_DIR / "voice_results.jsonl"
        entry = {
            "timestamp": datetime.now().isoformat(),
            "voice_note_id": result.voice_note_id,
            "status": result.status.value,
            "language": result.transcript.language_code if result.transcript else None,
            "transcript_preview": (
                result.transcript.text[:100] if result.transcript else None
            ),
            "was_translated": result.translation is not None,
            "elapsed_seconds": result.elapsed_seconds,
        }

        with open(log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
