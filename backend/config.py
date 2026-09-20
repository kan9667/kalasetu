"""
KalaSetu Backend Configuration.

Loads environment variables from the root .env file and provides
centralized application settings.
"""

from functools import lru_cache
from pathlib import Path
from typing import List, Optional, Union
from pydantic_settings import BaseSettings
from pydantic import Field, model_validator

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

    # Groq Cloud LLM Settings
    groq_api_key: str = Field(
        default="",
        description="API key for Groq Cloud chat completions.",
    )
    groq_base_url: str = Field(
        default="https://api.groq.com/openai/v1",
        description="Base URL for Groq Cloud API.",
    )
    groq_chat_model: str = Field(
        default="openai/gpt-oss-120b",
        description="Groq model identifier for chat, cataloging, and assistance.",
    )
    llm_provider: str = Field(
        default="groq",
        description="Primary LLM provider: groq or gemini.",
    )

    def get_active_groq_key(self) -> str:
        """Resolve active Groq API key from groq_api_key or whisper_api_key."""
        return self.groq_api_key.strip() or self.whisper_api_key.strip()

    # Models
    llm_model: str = "gemini-3.6-flash"
    embedding_model: str = "gemini-embedding-001"

    # Database
    database_url: str = f"sqlite:///{BACKEND_ROOT / 'kalasetu.db'}"

    # Media Storage
    upload_dir: str = str(UPLOAD_DIR)
    static_url_prefix: str = "/uploads"

    # CORS
    cors_origins: Union[List[str], str] = ["*"]
    cors_allow_credentials: bool = True
    cors_allow_methods: Union[List[str], str] = ["*"]
    cors_allow_headers: Union[List[str], str] = ["*"]

    # Environment & Auth
    environment: str = Field(default="development", description="Runtime environment: development, test, production")
    allow_demo_otp: bool = Field(default=False, description="Whether fixed demo OTP is permitted (forbidden in production)")
    jwt_secret_key: str = Field(
        default="",
        description="High-entropy secret key (min 32 chars) for HS256 JWT signing/verification",
    )
    jwt_algorithm: str = "HS256"
    jwt_issuer: str = "kalasetu-backend"
    jwt_audience: str = "kalasetu-app"
    jwt_access_token_expire_minutes: int = 60 * 24 * 30  # 30 days

    # SMS Provider Configuration
    sms_provider: str = Field(default="console", description="SMS delivery provider: console, mock, http, 2factor")
    sms_api_url: Optional[str] = Field(default="", description="SMS gateway HTTP endpoint URL")
    sms_api_key: Optional[str] = Field(default="", description="SMS gateway API key")
    sms_sender_id: Optional[str] = Field(default="", description="SMS sender identifier")
    sms_template_name: Optional[str] = Field(default="", description="Optional 2Factor SMS DLT template name")
    enable_real_sms: bool = Field(default=False, description="Explicit authorization switch required to dispatch real HTTP SMS.")
    daily_sms_cap: int = Field(default=20, description="Server-wide daily SMS dispatch limit over rolling 24-hour window.")
    daily_phone_sms_cap: int = Field(default=3, description="Per-phone daily SMS dispatch limit over rolling 24-hour window.")

    @model_validator(mode="before")
    @classmethod
    def parse_cors_origins(cls, data: Any) -> Any:
        if isinstance(data, dict):
            raw = data.get("cors_origins") or data.get("CORS_ORIGINS")
            if isinstance(raw, str):
                origins = [o.strip() for o in raw.split(",") if o.strip()]
                data["cors_origins"] = origins
        return data

    @model_validator(mode="after")
    def validate_production_security(self) -> "Settings":
        env = (self.environment or "").strip().lower()
        is_prod = env == "production"
        is_test = env == "test"

        # Fail closed if JWT secret is missing or weak outside explicit test mode
        if not is_test:
            if not self.jwt_secret_key or len(self.jwt_secret_key) < 32:
                raise ValueError("JWT_SECRET_KEY must be configured and at least 32 characters long outside test mode.")
            weak_keys = {"secret", "changeme", "password", "12345678901234567890123456789012"}
            if self.jwt_secret_key in weak_keys:
                raise ValueError("JWT_SECRET_KEY cannot be a known weak secret.")

        if is_prod:
            if self.allow_demo_otp:
                raise ValueError("ALLOW_DEMO_OTP cannot be enabled in production.")
            provider = (self.sms_provider or "").lower().strip()
            if provider in {"console", "mock"}:
                raise ValueError("Production environment must configure a real external SMS provider (e.g. 'http' or '2factor').")
            if provider == "http":
                if not self.sms_api_url or not self.sms_api_key:
                    raise ValueError("SMS_API_URL and SMS_API_KEY must be configured for HTTP SMS provider in production.")
            elif provider == "2factor":
                if not self.sms_api_key:
                    raise ValueError("SMS_API_KEY must be configured for 2Factor SMS provider in production.")
            else:
                raise ValueError(f"Unsupported SMS provider '{provider}' for production.")
            if self.cors_allow_credentials and ("*" in self.cors_origins or not self.cors_origins):
                raise ValueError(
                    "Production environment cannot use wildcard CORS origins ('*') when credentials are enabled. "
                    "Configure explicit allowed domains in CORS_ORIGINS."
                )
        return self

    model_config = {
        "env_file": str(PROJECT_ROOT / ".env"),
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }


@lru_cache()
def get_settings() -> Settings:
    """Return cached application settings."""
    return Settings()


def validate_production_secrets(settings: Settings = None) -> None:
    """Explicitly validate that production secrets and security flags are sound."""
    if settings is None:
        settings = get_settings()
    settings.validate_production_security()


def ensure_upload_dir() -> Path:
    """Ensure media upload directory exists."""
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    return UPLOAD_DIR
