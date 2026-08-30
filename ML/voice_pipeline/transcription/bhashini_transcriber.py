"""
Bhashini ASR Transcriber.

Transcribes artisan voice notes using Bhashini, the Government of India
language stack, via its ULCA pipeline API:
1. Request a pipeline configuration for the source language
2. Submit base64-encoded audio to the returned inference endpoint
3. Return the transcript in the source language

Bhashini exposes ASR, translation, and text-to-speech as chainable pipeline
tasks. This class runs ASR only — translation is a separate stage so it can
be skipped for languages the listing model already handles natively.
"""

from __future__ import annotations

import base64
import logging
from pathlib import Path

import requests

from ..config import get_settings
from ..models import STTProvider, Transcript, VoiceNote
from .base_transcriber import BaseTranscriber

logger = logging.getLogger(__name__)


class BhashiniTranscriber(BaseTranscriber):
    """Speech-to-text backed by Bhashini ASR."""

    provider = STTProvider.BHASHINI

    ASR_TASK = "asr"

    def __init__(self):
        self.settings = get_settings()

    def transcribe(self, note: VoiceNote, category_hint: str | None = None) -> Transcript:
        """
        Transcribe a voice note using Bhashini ASR.

        Args:
            note: The recording to transcribe.
            category_hint: Accepted for interface compatibility. Bhashini ASR
                           takes no prompt hint, so craft-term correction is
                           applied downstream in the listing stage.

        Returns:
            A Transcript in the source language, or a flagged fallback on failure.
        """
        try:
            self.validate_audio(note, self.settings.max_audio_duration_seconds)
        except (FileNotFoundError, ValueError) as e:
            return self.fallback_transcript(note, str(e))

        # ── Step 1: Resolve the ASR pipeline for this language ───────────
        logger.info(
            "Step 1: Resolving Bhashini ASR pipeline for '%s'...", note.language_code
        )
        try:
            endpoint, service_id, auth = self._resolve_pipeline(note.language_code)
        except Exception as e:
            return self.fallback_transcript(note, f"pipeline resolution failed: {e}")

        # ── Step 2: Submit audio for transcription ───────────────────────
        audio_format = self.detect_format(note)
        logger.info(
            "Step 2: Submitting audio (%s, format=%s)...", note.audio_path, audio_format
        )
        audio_b64 = base64.b64encode(Path(note.audio_path).read_bytes()).decode()

        asr_config: dict = {
            "language": {"sourceLanguage": note.language_code},
            "serviceId": service_id,
        }
        if self.settings.declare_audio_format:
            asr_config["audioFormat"] = audio_format
            asr_config["samplingRate"] = self.settings.sampling_rate

        payload = {
            "pipelineTasks": [
                {
                    "taskType": self.ASR_TASK,
                    "config": asr_config,
                }
            ],
            "inputData": {"audio": [{"audioContent": audio_b64}]},
        }

        for attempt in range(1, self.settings.stt_retry_attempts + 1):
            try:
                response = requests.post(
                    endpoint,
                    json=payload,
                    headers=auth,
                    timeout=self.settings.stt_request_timeout,
                )
                response.raise_for_status()
                text = self._extract_transcript(response.json())

                if not text.strip():
                    return self.fallback_transcript(note, "empty transcript returned")

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

    # ── Internals ────────────────────────────────────────────────────────

    def _resolve_pipeline(self, language_code: str) -> tuple[str, str, dict]:
        """
        Ask Bhashini which ASR service handles this language.

        Returns:
            Tuple of (inference endpoint URL, service ID, auth headers).
        """
        response = requests.post(
            self.settings.bhashini_pipeline_url,
            json={
                "pipelineTasks": [
                    {
                        "taskType": self.ASR_TASK,
                        "config": {"language": {"sourceLanguage": language_code}},
                    }
                ],
                "pipelineRequestConfig": {"pipelineId": ""},
            },
            headers={
                "userID": self.settings.bhashini_user_id,
                "ulcaApiKey": self.settings.bhashini_api_key,
            },
            timeout=self.settings.stt_request_timeout,
        )
        response.raise_for_status()
        data = response.json()

        service_id = data["pipelineResponseConfig"][0]["config"][0]["serviceId"]
        endpoint_config = data["pipelineInferenceAPIEndPoint"]
        endpoint = endpoint_config["callbackUrl"]
        auth_key = endpoint_config["inferenceApiKey"]

        return endpoint, service_id, {auth_key["name"]: auth_key["value"]}

    @staticmethod
    def _extract_transcript(payload: dict) -> str:
        """Pull the transcript string out of a Bhashini pipeline response."""
        for output in payload.get("pipelineResponse", []):
            if output.get("taskType") == "asr":
                return output["output"][0].get("source", "")
        return ""
