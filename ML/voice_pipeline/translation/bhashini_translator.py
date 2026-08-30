"""
Bhashini Translation Stage.

Translates a transcript into English before listing generation, using the
Bhashini NMT pipeline task.

This stage is optional and skipped for Hindi. The listing model writes Hindi
natively, so translating first would make the Hindi output a back-translation
of English rather than an original — losing craft terminology twice and
reading like machine text. It runs for languages the listing model does not
handle natively, where a weaker English transcript still beats a failed one.
"""

from __future__ import annotations

import logging

import requests

from ..config import get_settings
from ..models import TranslatedTranscript, Transcript

logger = logging.getLogger(__name__)


class BhashiniTranslator:
    """Text-to-text translation backed by Bhashini NMT."""

    NMT_TASK = "translation"

    def __init__(self):
        self.settings = get_settings()

    def translate(
        self,
        transcript: Transcript,
        target_language: str | None = None,
    ) -> TranslatedTranscript:
        """
        Translate a transcript into the target language.

        Args:
            transcript: The source-language transcript.
            target_language: Target code. Defaults to the configured target.

        Returns:
            A TranslatedTranscript. On failure, the translation falls back to
            the source text so the pipeline can continue rather than stall.
        """
        target = target_language or self.settings.translation_target

        if transcript.language_code == target:
            logger.info("Source already in '%s' — skipping translation.", target)
            return TranslatedTranscript(
                source_text=transcript.text,
                source_language=transcript.language_code,
                translated_text=transcript.text,
                target_language=target,
            )

        logger.info(
            "Translating transcript '%s' → '%s'...", transcript.language_code, target
        )

        try:
            endpoint, service_id, auth = self._resolve_pipeline(
                transcript.language_code, target
            )

            response = requests.post(
                endpoint,
                json={
                    "pipelineTasks": [
                        {
                            "taskType": self.NMT_TASK,
                            "config": {
                                "language": {
                                    "sourceLanguage": transcript.language_code,
                                    "targetLanguage": target,
                                },
                                "serviceId": service_id,
                            },
                        }
                    ],
                    "inputData": {"input": [{"source": transcript.text}]},
                },
                headers=auth,
                timeout=self.settings.stt_request_timeout,
            )
            response.raise_for_status()
            translated = self._extract_translation(response.json())

            logger.info("Translation complete (%d characters)", len(translated))
            return TranslatedTranscript(
                source_text=transcript.text,
                source_language=transcript.language_code,
                translated_text=translated or transcript.text,
                target_language=target,
            )

        except Exception as e:
            logger.error("Translation failed, passing source text through: %s", e)
            return TranslatedTranscript(
                source_text=transcript.text,
                source_language=transcript.language_code,
                translated_text=transcript.text,
                target_language=transcript.language_code,
            )

    # ── Internals ────────────────────────────────────────────────────────

    def _resolve_pipeline(self, source: str, target: str) -> tuple[str, str, dict]:
        """Ask Bhashini which NMT service handles this language pair."""
        response = requests.post(
            self.settings.bhashini_pipeline_url,
            json={
                "pipelineTasks": [
                    {
                        "taskType": self.NMT_TASK,
                        "config": {
                            "language": {
                                "sourceLanguage": source,
                                "targetLanguage": target,
                            }
                        },
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
        auth_key = endpoint_config["inferenceApiKey"]

        return (
            endpoint_config["callbackUrl"],
            service_id,
            {auth_key["name"]: auth_key["value"]},
        )

    @staticmethod
    def _extract_translation(payload: dict) -> str:
        """Pull the translated string out of a Bhashini pipeline response."""
        for output in payload.get("pipelineResponse", []):
            if output.get("taskType") == "translation":
                return output["output"][0].get("target", "")
        return ""
