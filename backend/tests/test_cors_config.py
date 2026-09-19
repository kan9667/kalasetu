"""Tests for CORS configuration and production origin validation."""

import pytest
from backend.config import Settings


def test_cors_origins_parsing_from_string():
    settings = Settings(
        jwt_secret_key="a" * 32,
        environment="development",
        CORS_ORIGINS="https://kalasetu.in, https://app.kalasetu.in",
    )
    assert settings.cors_origins == ["https://kalasetu.in", "https://app.kalasetu.in"]


def test_production_rejects_wildcard_cors():
    with pytest.raises(ValueError, match="Production environment cannot use wildcard CORS origins"):
        Settings(
            jwt_secret_key="a" * 32,
            environment="production",
            allow_demo_otp=False,
            sms_provider="http",
            sms_api_url="https://sms.example.com",
            sms_api_key="valid-api-key",
            cors_origins=["*"],
            cors_allow_credentials=True,
        )


def test_production_accepts_explicit_cors_origins():
    settings = Settings(
        jwt_secret_key="a" * 32,
        environment="production",
        allow_demo_otp=False,
        sms_provider="http",
        sms_api_url="https://sms.example.com",
        sms_api_key="valid-api-key",
        cors_origins=["https://kalasetu.in", "https://app.kalasetu.in"],
        cors_allow_credentials=True,
    )
    assert settings.cors_origins == ["https://kalasetu.in", "https://app.kalasetu.in"]
