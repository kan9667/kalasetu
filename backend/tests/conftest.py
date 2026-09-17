import os
import uuid
import pytest
from starlette.testclient import TestClient

# Set standard test environment variables before importing settings
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("JWT_SECRET_KEY", "test_secret_key_32_characters_long_min")
os.environ.setdefault("ALLOW_DEMO_OTP", "true")
os.environ.setdefault("SMS_PROVIDER", "mock")


@pytest.fixture
def make_idempotency_key():
    """Explicit helper fixture to generate unique Idempotency-Key headers for mutating calls."""
    def _key(prefix="test"):
        return f"{prefix}_{uuid.uuid4().hex}"
    return _key


class IdempotentTestClient(TestClient):
    """Explicit narrowly scoped TestClient helper for tests requiring auto-generated idempotency keys."""
    def request(self, method: str, url: str, *args, **kwargs):
        headers = dict(kwargs.pop("headers", None) or {})
        if method.upper() in ("POST", "PUT", "PATCH", "DELETE"):
            if "Idempotency-Key" not in headers and "idempotency-key" not in headers:
                headers["Idempotency-Key"] = f"test_idemp_{uuid.uuid4().hex}"
        return super().request(method, url, *args, headers=headers, **kwargs)


@pytest.fixture
def idempotent_client():
    from backend.main import app
    return IdempotentTestClient(app)



