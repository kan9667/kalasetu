"""
Voice Pipeline — Central Configuration.

All settings are loaded from environment variables / .env file.
"""

import os
from pathlib import Path
from pydantic_settings import BaseSettings
from pydantic import Field


# ── Paths ────────────────────────────────────────────────────────────────────

# Root of the voice pipeline module
VOICE_ROOT = Path(__file__).resolve().parent

# Runtime data directory (gitignored)
DATA_DIR = VOICE_ROOT / "data"
RECORDINGS_DIR = DATA_DIR / "recordings"
TRANSCRIPTS_FILE = DATA_DIR / "transcripts.jsonl"
PIPELINE_LOG_FILE = DATA_DIR / "pipeline_runs.log"


class Settings(BaseSettings):
    """
    Application settings loaded from environment variables.

    Create a .env file in the project root with these values,
    or export them in your shell.
    """

    # ── API Keys ─────────────────────────────────────────────────────────
    bhashini_api_key: str = Field(
        default="",
        description="Bhashini (ULCA) API key for ASR and translation.",
    )
    bhashini_user_id: str = Field(
        default="",
        description="Bhashini ULCA user ID issued on registration.",
    )

    # ── Endpoints ────────────────────────────────────────────────────────
    bhashini_pipeline_url: str = Field(
        default="https://meity-auth.ulcacontrib.org/ulca/apis/v0/model/getModelsPipeline",
        description="Bhashini pipeline configuration endpoint.",
    )

    # ── Model Configuration ──────────────────────────────────────────────
    stt_provider: str = Field(
        default="bhashini",
        description="Transcription backend to use (bhashini).",
    )

    # ── Language ─────────────────────────────────────────────────────────
    default_language: str = Field(
        default="hi",
        description="Default source language code for transcription.",
    )
    supported_languages: list[str] = Field(
        default=["hi", "ta", "bn", "mr", "te", "gu", "kn", "ml", "pa", "or"],
        description="Language codes accepted by the pipeline.",
    )
    languages_needing_translation: list[str] = Field(
        default=["ta", "bn", "mr", "te", "gu", "kn", "ml", "pa", "or"],
        description=(
            "Languages translated to English before handing off to the catalog "
            "service. Hindi is excluded — the catalog service handles it "
            "natively, and translating first would degrade the Hindi output."
        ),
    )
    translation_target: str = Field(
        default="en",
        description="Target language for the optional translation stage.",
    )

    # ── Transcription ────────────────────────────────────────────────────
    stt_request_timeout: int = Field(
        default=60,
        description="HTTP request timeout in seconds for transcription calls.",
    )
    stt_retry_attempts: int = Field(
        default=3,
        description="Number of retry attempts for failed transcription requests.",
    )
    max_audio_duration_seconds: int = Field(
        default=180,
        description="Reject recordings longer than this before spending an API call.",
    )

    # ── Audio ────────────────────────────────────────────────────────────
    sampling_rate: int = Field(
        default=16000,
        description="Sampling rate declared to the ASR service, in Hz.",
    )
    declare_audio_format: bool = Field(
        default=True,
        description=(
            "Send the detected audio format in the ASR request. Disable if the "
            "service rejects the field."
        ),
    )

    # ── Glossary ─────────────────────────────────────────────────────────
    glossary_terms_in_prompt: int = Field(
        default=40,
        description=(
            "Craft glossary terms exposed to the backend catalog service, "
            "which injects them into its listing prompt to correct misheard "
            "handicraft terminology."
        ),
    )

    model_config = {
        "env_file": str(VOICE_ROOT.parents[1] / ".env"),
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }


from functools import lru_cache


@lru_cache()
def get_settings() -> Settings:
    """Return a cached Settings instance."""
    return Settings()


def ensure_data_dirs() -> None:
    """Create runtime data directories if they don't exist."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)


def needs_translation(language_code: str) -> bool:
    """
    Decide whether a transcript should be translated before handoff.

    Hindi is passed through untranslated — the catalog service writes Hindi
    natively, and translating first would produce a back-translated Hindi
    listing rather than an original one.
    """
    return language_code in get_settings().languages_needing_translation
