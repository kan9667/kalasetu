"""
KalaSetu Backend Configuration.

Loads environment variables from the root .env file and provides
centralized application settings.
"""

from pathlib import Path
from typing import List
from pydantic_settings import BaseSettings
from pydantic import Field

# Directories
BACKEND_ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = BACKEND_ROOT.parent
UPLOAD_DIR = BACKEND_ROOT / "uploads"


class Settings(BaseSettings):
    """Application settings with environment variable overrides."""

    app_name: str = "KalaSetu API"
    app_version: str = "1.0.0"
    app_description: str = "AI-Driven Market Linkage & Smart Cataloging Backend for Marginalized Artisans"
    debug: bool = False

    # Server
    host: str = "0.0.0.0"
    port: int = 8000

    # API Keys
    gemini_api_key: str = Field(
        default="",
        description="Google Gemini API key for multimodal embeddings and LLM pricing/cataloging.",
    )
    whisper_api_key: str = Field(
        default="",
        description="API key for Whisper speech-to-text transcription endpoint.",
    )

    # Voice Pipeline / Speech-to-Text Settings
    whisper_base_url: str = Field(
        default="https://api.openai.com/v1",
        description="Base URL of OpenAI-compatible Whisper transcription API.",
    )
    whisper_model: str = Field(
        default="whisper-large-v3",
        description="Whisper model identifier for audio transcription.",
    )
    stt_provider: str = Field(
        default="whisper",
        description="Transcription backend provider (whisper).",
    )
    default_language: str = Field(
        default="hi",
        description="Default source language code for voice notes.",
    )
    supported_languages: List[str] = Field(
        default=["hi", "ta", "bn", "mr", "te", "gu", "kn", "ml", "pa", "or"],
        description="Language codes accepted by the voice pipeline.",
    )

    # Models
    llm_model: str = "gemini-2.5-flash"
    embedding_model: str = "gemini-embedding-001"

    # Database
    database_url: str = f"sqlite:///{BACKEND_ROOT / 'kalasetu.db'}"

    # Media Storage
    upload_dir: str = str(UPLOAD_DIR)
    static_url_prefix: str = "/uploads"

    # CORS
    cors_origins: List[str] = ["*"]
    cors_allow_credentials: bool = True
    cors_allow_methods: List[str] = ["*"]
    cors_allow_headers: List[str] = ["*"]

    model_config = {
        "env_file": str(PROJECT_ROOT / ".env"),
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }


def get_settings() -> Settings:
    """Return application settings."""
    return Settings()


def ensure_upload_dir() -> Path:
    """Ensure media upload directory exists."""
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    return UPLOAD_DIR
