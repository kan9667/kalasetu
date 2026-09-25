"""Catalog uses Groq first and honors the explicit Gemini fallback policy."""

import asyncio
import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import httpx
from pydantic import ValidationError

from backend.config import Settings
from backend.models.schemas import ListingGenerateRequest
from backend.services.catalog_service import CatalogService
from backend.services.groq_client import GroqClient


LISTING = {
    "title_en": "Handmade Clay Pot",
    "title_hi": "मिट्टी का घड़ा",
    "description_en": "A handmade clay pot.",
    "description_hi": "हाथ से बना मिट्टी का घड़ा।",
    "category": "Pottery",
    "tags": ["clay", "handmade"],
    "materials": 100,
    "labor_hours": 2,
    "hourly_rate": 50,
}
REQUEST = ListingGenerateRequest(
    transcript="Handmade clay pot with material cost 100 rupees", language_code="en"
)


@pytest.fixture
def catalog():
    settings = Settings(
        _env_file=None,
        llm_provider="groq",
        catalog_gemini_fallback_enabled=False,
        groq_api_key="gsk_fixture_not_a_real_key",
        whisper_api_key="",
        gemini_api_key="fixture_not_a_real_key",
    )
    with (
        patch("backend.services.catalog_service.get_settings", return_value=settings),
        patch("backend.services.catalog_service.GroqClient") as groq_factory,
        patch("backend.services.catalog_service.genai.Client") as gemini_factory,
        patch("backend.services.catalog_service.ArtisanVoiceProcessor"),
    ):
        groq = groq_factory.return_value
        groq.is_available.return_value = True
        groq.chat_json = AsyncMock(return_value=LISTING)
        service = CatalogService()
        # Even with Gemini credentials present, Groq mode never initializes it.
        gemini_factory.assert_not_called()
        assert service.client is None
        # Defend against an already-created/stale Gemini client, too.
        service.client = MagicMock()
        service.client.models.generate_content.return_value = MagicMock(text=json.dumps(LISTING))
        yield service


def test_groq_success_uses_only_groq_for_listing_and_costs(catalog):
    result = asyncio.run(catalog.generate_listing(REQUEST))
    assert result.status == "success"
    assert result.is_degraded is False
    assert result.title_en == LISTING["title_en"]
    assert result.cost_inputs.materials == 100
    assert catalog.groq_client.chat_json.await_count == 2
    assert any(call.kwargs.get("max_tokens") == 2400 for call in catalog.groq_client.chat_json.await_args_list)
    catalog.client.models.generate_content.assert_not_called()


@pytest.mark.parametrize("failure", [TimeoutError, RuntimeError, ValueError])
def test_groq_errors_never_fall_through_to_gemini(catalog, failure, caplog):
    catalog.groq_client.chat_json.side_effect = failure("sensitive-provider-response")
    result = asyncio.run(catalog.generate_listing(REQUEST))
    assert result.status == "fallback"
    assert result.is_degraded is True
    assert "unavailable" in result.degraded_reason
    assert result.cost_inputs.materials >= 0
    catalog.client.models.generate_content.assert_not_called()
    assert "sensitive-provider-response" not in caplog.text


def test_missing_groq_credentials_produces_actionable_local_fallback(catalog):
    catalog.groq_client.is_available.return_value = False
    result = asyncio.run(catalog.generate_listing(REQUEST))
    assert result.status == "fallback"
    assert result.is_degraded is True
    assert "GROQ_API_KEY" in result.degraded_reason
    catalog.groq_client.chat_json.assert_not_awaited()
    catalog.client.models.generate_content.assert_not_called()


def test_malformed_groq_result_does_not_switch_provider(catalog):
    catalog.groq_client.chat_json.return_value = ["not a JSON object"]
    result = asyncio.run(catalog.generate_listing(REQUEST))
    assert result.status == "fallback"
    assert result.is_degraded is True
    catalog.client.models.generate_content.assert_not_called()


def test_null_provider_category_uses_detected_category_instead_of_500(catalog):
    async def response(messages, **kwargs):
        if "cost extraction" in messages[0]["content"]:
            return LISTING
        return {**LISTING, "category": None}

    catalog.groq_client.chat_json.side_effect = response
    result = asyncio.run(catalog.generate_listing(REQUEST))
    assert result.status == "success"
    assert result.category == "Pottery"


def test_explicit_gemini_mode_does_not_call_groq(catalog):
    catalog.settings.llm_provider = "gemini"
    result = asyncio.run(catalog.generate_listing(REQUEST))
    assert result.status == "success"
    assert catalog.client.models.generate_content.call_count == 2
    catalog.groq_client.chat_json.assert_not_awaited()


def test_gemini_failure_does_not_call_groq(catalog):
    catalog.settings.llm_provider = "gemini"
    catalog.client.models.generate_content.side_effect = RuntimeError("provider error")
    result = asyncio.run(catalog.generate_listing(REQUEST))
    assert result.status == "fallback"
    assert result.is_degraded is True
    catalog.groq_client.chat_json.assert_not_awaited()


def test_invalid_provider_is_rejected():
    with pytest.raises(ValidationError):
        Settings(_env_file=None, llm_provider="unsupported")


def test_enabled_gemini_fallback_recovers_groq_failure(catalog):
    catalog.settings.catalog_gemini_fallback_enabled = True
    catalog.groq_client.chat_json.side_effect = TimeoutError()
    result = asyncio.run(catalog.generate_listing(REQUEST))
    assert result.status == "success"
    assert result.title_en == LISTING["title_en"]
    assert catalog.client.models.generate_content.call_count == 2


def test_enabled_fallback_does_not_bypass_healthy_groq(catalog):
    catalog.settings.catalog_gemini_fallback_enabled = True
    result = asyncio.run(catalog.generate_listing(REQUEST))
    assert result.status == "success"
    catalog.client.models.generate_content.assert_not_called()


def test_both_providers_failing_returns_labelled_template(catalog):
    catalog.settings.catalog_gemini_fallback_enabled = True
    catalog.groq_client.chat_json.side_effect = TimeoutError()
    catalog.client.models.generate_content.side_effect = RuntimeError()
    result = asyncio.run(catalog.generate_listing(REQUEST))
    assert result.status == "fallback"
    assert result.is_degraded is True


def test_default_policy_initializes_configured_gemini_fallback():
    settings = Settings(_env_file=None, llm_provider="groq", gemini_api_key="fixture")
    assert settings.catalog_gemini_fallback_enabled is True
    with (
        patch("backend.services.catalog_service.get_settings", return_value=settings),
        patch("backend.services.catalog_service.GroqClient"),
        patch("backend.services.catalog_service.genai.Client") as factory,
        patch("backend.services.catalog_service.ArtisanVoiceProcessor"),
    ):
        CatalogService()
        factory.assert_called_once_with(api_key="fixture")


@pytest.mark.parametrize("status,category", [(401, "authentication"), (429, "rate_limit_or_quota"), (400, "invalid_request")])
def test_groq_http_diagnostics_do_not_log_response_bodies(status, category, caplog):
    transport = httpx.MockTransport(
        lambda request: httpx.Response(status, text="sensitive-provider-response")
    )
    client = httpx.AsyncClient(transport=transport)
    with patch("backend.services.groq_client.httpx.AsyncClient", return_value=client):
        groq = GroqClient(api_key="gsk_fixture", base_url="https://groq.test/v1")
        with pytest.raises(RuntimeError):
            asyncio.run(groq.chat_completion([{"role": "user", "content": "fixture"}]))
    assert f"HTTP {status} category={category}" in caplog.text
    assert "sensitive-provider-response" not in caplog.text


def test_groq_json_validation_error_is_identified_without_logging_body(caplog):
    transport = httpx.MockTransport(
        lambda request: httpx.Response(
            400,
            json={"error": {"code": "json_validate_failed", "message": "sensitive-provider-response"}},
        )
    )
    client = httpx.AsyncClient(transport=transport)
    with patch("backend.services.groq_client.httpx.AsyncClient", return_value=client):
        groq = GroqClient(api_key="gsk_fixture", base_url="https://groq.test/v1")
        with pytest.raises(RuntimeError):
            asyncio.run(groq.chat_completion([{"role": "user", "content": "fixture"}]))
    assert "category=output_json_validation" in caplog.text
    assert "sensitive-provider-response" not in caplog.text
