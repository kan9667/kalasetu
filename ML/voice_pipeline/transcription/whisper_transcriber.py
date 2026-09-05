"""
Whisper Transcriber.

Transcribes artisan voice notes using a Whisper model served over an
OpenAI-compatible audio transcription endpoint:
1. Builds a glossary prompt so craft terms are recognised, not guessed at
2. Posts the recording to the configured endpoint
3. Returns the transcript in the source language

Whisper is multilingual by training, so code-mixed speech — an artisan saying
"yeh handmade pottery hai" in one breath — survives better than it does under
single-language models. It also accepts the .m4a the mobile client records, so
no conversion step is needed.

Any OpenAI-compatible host works. Set `whisper_base_url` to point at the one
you use; the request shape does not change.
"""

from __future__ import annotations

import logging
import re
import subprocess
from pathlib import Path

import requests

from ..config import get_settings
from ..glossary import build_prompt_hint
from ..models import STTProvider, Transcript, VoiceNote
from .base_transcriber import BaseTranscriber

logger = logging.getLogger(__name__)


class WhisperTranscriber(BaseTranscriber):
    """Speech-to-text backed by a Whisper model."""

    provider = STTProvider.WHISPER

    def __init__(self):
        self.settings = get_settings()

    @staticmethod
    def _is_audio_silent(path: Path) -> bool:
        """Check if audio has no audible sound using ffmpeg volumedetect."""
        try:
            result = subprocess.run(
                [
                    "ffmpeg", "-i", str(path), "-af", "volumedetect",
                    "-vn", "-sn", "-dn", "-f", "null", "/dev/null"
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
            for line in result.stderr.splitlines():
                if "max_volume:" in line:
                    parts = line.split("max_volume:")
                    if len(parts) > 1:
                        vol_str = parts[1].replace("dB", "").strip()
                        max_vol = float(vol_str)
                        # Inaudible audio or pure silence sits at -40 dB to -91 dB
                        return max_vol < -40.0
        except Exception:
            pass
        return False

    def transcribe(self, note: VoiceNote, category_hint: str | None = None) -> Transcript:
        """
        Transcribe a voice note with Whisper.

        Args:
            note: The recording to transcribe.
            category_hint: Craft category used to prioritise glossary terms in
                           the prompt, so pottery vocabulary is offered for a
                           pottery listing rather than being cut by the limit.

        Returns:
            A Transcript in the source language, or a flagged fallback on failure.
        """
        try:
            self.validate_audio(note, self.settings.max_audio_duration_seconds)
        except (FileNotFoundError, ValueError) as e:
            return self.fallback_transcript(note, str(e))

        if not self.settings.whisper_api_key:
            return self.fallback_transcript(note, "no API key configured")

        # ── Step 1: Build the craft glossary prompt ──────────────────────
        # Whisper accepts a prompt that biases recognition toward expected
        # vocabulary. This is where "Dhokra" stops becoming "doctor".
        prompt = build_prompt_hint(
            category=category_hint,
            limit=self.settings.glossary_terms_in_prompt,
            language_code=note.language_code,
        )

        # ── Step 2: Submit the recording ─────────────────────────────────
        audio_format = self.detect_format(note)
        logger.info(
            "Submitting audio to Whisper (%s, format=%s, lang=%s)...",
            note.audio_path,
            audio_format,
            note.language_code,
        )

        url = f"{self.settings.whisper_base_url.rstrip('/')}/audio/transcriptions"
        path = Path(note.audio_path)
        if self._is_audio_silent(path):
            logger.warning("Audio note %s has no audible sound (silent). Skipping Whisper.", note.id)
            return self.fallback_transcript(
                note, "No audible speech detected. Please speak closer to the microphone."
            )

        for attempt in range(1, self.settings.stt_retry_attempts + 1):
            try:
                with path.open("rb") as audio:
                    response = requests.post(
                        url,
                        headers={"Authorization": f"Bearer {self.settings.whisper_api_key}"},
                        files={"file": (path.name, audio, f"audio/{audio_format}")},
                        data={
                            "model": self.settings.whisper_model,
                            "language": note.language_code,
                            "prompt": prompt,
                            "response_format": "json",
                            "temperature": 0,
                        },
                        timeout=self.settings.stt_request_timeout,
                    )
                response.raise_for_status()
                text = response.json().get("text", "").strip()

                if not text:
                    return self.fallback_transcript(note, "empty transcript returned")

                # Filter known Whisper silence hallucinations (when microphone records silence/ambient noise)
                clean_text = re.sub(r'[\s\.,!?:;\-_"\'()[\]{}।…~*]+', ' ', text).strip().lower()
                silence_artifacts = {
                    "thanks", "thank you", "thanks for watching", "thank you for watching",
                    "thanks for listening", "thank you for listening", "thank you very much",
                    "thank you so much", "please subscribe", "subscribe", "subtitles",
                    "subtitles by", "bye", "bye bye", "you", "goodbye", "peace",
                    "watching", "so", "the end", "see you next time", "thanks guys", "thank you all",
                    "धन्यवाद", "बहुत धन्यवाद", "शुक्रिया", "बहुत शुक्रिया",
                    "प्रस्तुत", "प्रश्नित", "प्रश्नित प्रश्नित", "झाल", "सब्सक्राइब करें",
                    "लाइक करें", "शेयर करें", "चैनल को सब्सक्राइब करें",
                }

                words = clean_text.split()
                is_hallucination = (
                    clean_text in silence_artifacts or
                    (len(words) <= 6 and (
                        (("thank" in clean_text or "thanks" in clean_text) and "watching" in clean_text) or
                        any(clean_text.startswith(prefix) for prefix in [
                            "thanks", "thank you", "bye", "goodbye", "subtitles", "subscribe", "धन्यवाद", "शुक्रिया"
                        ])
                    ))
                )

                if is_hallucination:
                    logger.warning(
                        "Whisper silence hallucination detected: '%s'. Marking as unusable.", text
                    )
                    return self.fallback_transcript(
                        note, "No audible speech detected. Please speak closer to the microphone."
                    )

                logger.info("Transcription complete (%d characters)", len(text))
                return Transcript(
                    text=text,
                    language_code=note.language_code,
                    provider=self.provider,
                    duration_seconds=note.duration_seconds,
                )

            except Exception as e:
                logger.warning(
                    "Transcription attempt %d/%d failed: %s",
                    attempt,
                    self.settings.stt_retry_attempts,
                    e,
                )
                if attempt == self.settings.stt_retry_attempts:
                    return self.fallback_transcript(note, str(e))

        return self.fallback_transcript(note, "exhausted retry attempts")
