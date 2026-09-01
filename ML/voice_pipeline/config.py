"""
Voice Pipeline — Central Configuration.

All settings are loaded from environment variables / .env file.
"""

import os
from functools import lru_cache
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
    whisper_api_key: str = Field(
        default="",
        description="API key for the Whisper transcription endpoint.",
    )

    # ── Model Configuration ──────────────────────────────────────────────
    stt_provider: str = Field(
        default="whisper",
        description="Transcription backend to use (whisper).",
    )
    whisper_model: str = Field(
        default="whisper-large-v3",
        description="Whisper model identifier requested from the endpoint.",
    )
    whisper_base_url: str = Field(
        default="https://api.openai.com/v1",
        description=(
            "Base URL of an OpenAI-compatible audio transcription API. Any "
            "compatible host works — only this value changes."
        ),
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

    # ── Glossary ─────────────────────────────────────────────────────────
    glossary_terms_in_prompt: int = Field(
        default=24,
        description=(
            "Craft glossary terms sent as the recognition prompt, and exposed "
            "to the backend catalog service for its listing prompt. Measured on "
            "a Hindi sample, 15-30 terms recovered a misheard craft word that "
            "40 did not — too long a list dilutes the bias."
        ),
    )

    model_config = {
        "env_file": str(VOICE_ROOT.parents[1] / ".env"),
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }


@lru_cache()
def get_settings() -> Settings:
    """Return a cached Settings instance."""
    return Settings()


def ensure_data_dirs() -> None:
    """Create runtime data directories if they don't exist."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)
