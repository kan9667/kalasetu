"""
Shared Groq Client Utility.

Provides asynchronous, resilient chat completions via Groq Cloud REST API
(OpenAI-compatible) using httpx.
Includes regex-based reasoning tag removal (<think>...</think>), markdown fence
stripping, and automatic JSON extraction.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any, Dict, List, Optional
import httpx

from ..config import get_settings

logger = logging.getLogger(__name__)

# Pattern to strip out thinking/reasoning blocks (e.g., from deepseek/qwen reasoning models)
THINKING_PATTERN = re.compile(r"<think>.*?</think>", re.DOTALL)


class GroqClient:
    """Lightweight async client for Groq Cloud chat completions."""

    def __init__(self, api_key: Optional[str] = None, base_url: Optional[str] = None):
        self.settings = get_settings()
        self.api_key = api_key or self.settings.get_active_groq_key()
        self.base_url = (base_url or self.settings.groq_base_url).rstrip("/")
        self.default_model = self.settings.groq_chat_model

    def is_available(self) -> bool:
        """Check whether an active Groq API key is present."""
        return bool(self.api_key and self.api_key.startswith("gsk_"))

    @staticmethod
    def clean_response_text(raw_text: str) -> str:
        """Strip reasoning tags, extra whitespace, and markdown formatting."""
        if not raw_text:
            return ""
        # 1. Remove <think>...</think> blocks
        cleaned = THINKING_PATTERN.sub("", raw_text).strip()
        return cleaned

    @staticmethod
    def extract_json_payload(text: str) -> Dict[str, Any]:
        """Extract and parse a JSON dictionary from LLM response text."""
        cleaned = GroqClient.clean_response_text(text)
        
        # 1. Check for markdown code fence ```json ... ```
        fence_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", cleaned, re.DOTALL)
        if fence_match:
            candidate = fence_match.group(1).strip()
            try:
                return json.loads(candidate)
            except json.JSONDecodeError:
                pass

        # 2. Check for outermost { ... }
        brace_match = re.search(r"(\{.*\})", cleaned, re.DOTALL)
        if brace_match:
            candidate = brace_match.group(1).strip()
            try:
                return json.loads(candidate)
            except json.JSONDecodeError:
                pass

        # 3. Direct parse
        return json.loads(cleaned)

    async def chat_completion(
        self,
        messages: List[Dict[str, str]],
        model: Optional[str] = None,
        temperature: float = 0.2,
        max_tokens: int = 1024,
        response_format_json: bool = False,
        timeout: float = 20.0,
    ) -> str:
        """
        Send a chat completion request to Groq Cloud.
        Returns the raw string output from the model.
        """
        if not self.is_available():
            raise RuntimeError("Groq API key is not configured. Set GROQ_API_KEY in .env.")

        active_model = model or self.default_model
        fallback_models = ["openai/gpt-oss-120b", "groq/compound-mini", "qwen/qwen3.6-27b"]

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

        payload: Dict[str, Any] = {
            "model": active_model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if response_format_json:
            payload["response_format"] = {"type": "json_object"}

        models_to_try = [active_model] + [m for m in fallback_models if m != active_model]

        async with httpx.AsyncClient(timeout=timeout) as client:
            last_error: Optional[Exception] = None

            for attempt_model in models_to_try:
                payload["model"] = attempt_model
                try:
                    url = f"{self.base_url}/chat/completions"
                    resp = await client.post(url, headers=headers, json=payload)
                    
                    if resp.status_code == 200:
                        data = resp.json()
                        choices = data.get("choices", [])
                        if choices:
                            raw_content = choices[0].get("message", {}).get("content", "")
                            return self.clean_response_text(raw_content)
                        raise RuntimeError("Groq returned empty choices list.")

                    # Never log provider bodies: they can echo prompts or credentials.
                    category = {
                        400: "invalid_request", 401: "authentication", 403: "permission",
                        404: "model_or_endpoint_not_found", 429: "rate_limit_or_quota",
                    }.get(resp.status_code, "provider_error")
                    if resp.status_code == 400:
                        try:
                            if (resp.json().get("error") or {}).get("code") == "json_validate_failed":
                                category = "output_json_validation"
                        except (ValueError, AttributeError):
                            pass
                    logger.warning(
                        "[GroqClient] Model '%s' HTTP %s category=%s",
                        attempt_model,
                        resp.status_code,
                        category,
                    )
                    last_error = RuntimeError(f"Groq HTTP {resp.status_code}: {category}")
                    if resp.status_code in (401, 403):
                        break
                    
                    # If model not found or forbidden, try next fallback model
                    if resp.status_code in (404, 400):
                        continue
                    # For rate limit or server error on the primary, retry once with fallback
                    if resp.status_code in (429, 500, 502, 503):
                        continue

                except Exception as e:
                    logger.warning("[GroqClient] Request to '%s' failed: %s", attempt_model, type(e).__name__)
                    last_error = e

            raise last_error or RuntimeError("All Groq model attempts failed.")

    async def chat_json(
        self,
        messages: List[Dict[str, str]],
        model: Optional[str] = None,
        temperature: float = 0.2,
        max_tokens: int = 800,
    ) -> Dict[str, Any]:
        """
        Send a chat completion and parse the output directly as a JSON dict.
        """
        raw_text = await self.chat_completion(
            messages=messages,
            model=model,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format_json=True,
        )
        try:
            return self.extract_json_payload(raw_text)
        except Exception as e:
            logger.error("[GroqClient] Invalid structured response: %s", type(e).__name__)
            raise RuntimeError("Failed to parse structured JSON from Groq output") from e

    def chat_completion_sync(
        self,
        messages: List[Dict[str, str]],
        model: Optional[str] = None,
        temperature: float = 0.2,
        max_tokens: int = 800,
        response_format_json: bool = False,
        timeout: float = 20.0,
    ) -> str:
        """Synchronous chat completion for non-async ML pipeline modules."""
        if not self.is_available():
            raise RuntimeError("Groq API key is not configured.")

        active_model = model or self.default_model
        fallback_models = ["openai/gpt-oss-120b", "groq/compound-mini", "qwen/qwen3.6-27b"]
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload: Dict[str, Any] = {
            "model": active_model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if response_format_json:
            payload["response_format"] = {"type": "json_object"}

        models_to_try = [active_model] + [m for m in fallback_models if m != active_model]

        with httpx.Client(timeout=timeout) as client:
            last_error: Optional[Exception] = None
            for attempt_model in models_to_try:
                payload["model"] = attempt_model
                try:
                    url = f"{self.base_url}/chat/completions"
                    resp = client.post(url, headers=headers, json=payload)
                    if resp.status_code == 200:
                        choices = resp.json().get("choices", [])
                        if choices:
                            raw_content = choices[0].get("message", {}).get("content", "")
                            return self.clean_response_text(raw_content)
                    if resp.status_code in (404, 400, 429, 500, 502, 503):
                        continue
                except Exception as e:
                    last_error = e
            raise last_error or RuntimeError("All Groq sync model attempts failed.")

    def chat_json_sync(
        self,
        messages: List[Dict[str, str]],
        model: Optional[str] = None,
        temperature: float = 0.2,
        max_tokens: int = 1024,
    ) -> Dict[str, Any]:
        """Synchronous JSON chat completion for ML pricer."""
        raw_text = self.chat_completion_sync(
            messages=messages,
            model=model,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format_json=True,
        )
        return self.extract_json_payload(raw_text)
