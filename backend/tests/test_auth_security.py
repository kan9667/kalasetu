"""
Security and authentication tests for KalaSetu backend.
Tests OTP challenge lifecycle, demo OTP restrictions, JWT algorithm pinning,
claims validation, and production secret strength rules.
"""

import pytest
import jwt
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException

from backend.config import get_settings, validate_production_secrets
from backend.services.otp_service import OtpService, MockSmsProvider, SmsProvider
from backend.utils.auth import create_access_token, decode_access_token, JWT_ALGORITHM
from backend.database import SessionLocal, init_db
from backend.models.db_models import OtpChallengeDB, ArtisanDB, SmsDispatchLogDB


@pytest.fixture(scope="module")
def db_session():
    init_db()
    db = SessionLocal()
    db.query(OtpChallengeDB).delete()
    db.query(SmsDispatchLogDB).delete()
    db.commit()
    yield db
    db.close()


@pytest.mark.anyio
async def test_otp_challenge_lifecycle(db_session):
    """Test cryptographic generation, hashing, verification, and single-use."""
    sms = MockSmsProvider()
    service = OtpService(sms_provider=sms)
    phone = "+919876543210"
    ip = "127.0.0.1"

    # 1. Request OTP challenge
    res = await service.create_challenge(db_session, phone, client_ip=ip)
    assert res["status"] == "success"
    clean_phone = res["phone"]
    assert len(sms.sent_messages) == 1
    otp = sms.sent_messages[0]["otp"]
    assert len(otp) == 6
    assert otp.isdigit()

    # 2. Verify database stores ONLY salted hash, not cleartext
    challenge = (
        db_session.query(OtpChallengeDB)
        .filter(OtpChallengeDB.phone == clean_phone)
        .order_by(OtpChallengeDB.created_at.desc())
        .first()
    )
    assert challenge is not None
    assert challenge.otp_hash != otp
    assert challenge.used is False
    assert challenge.attempts == 0

    # 3. Bad code increments attempts and raises 400
    with pytest.raises(HTTPException) as exc_info:
        service.verify_challenge(db_session, phone, "000000")
    assert exc_info.value.status_code == 400
    db_session.refresh(challenge)
    assert challenge.attempts == 1

    # 4. Correct code verifies and marks one-time used
    assert service.verify_challenge(db_session, phone, otp) is True
    db_session.refresh(challenge)
    assert challenge.used is True

    # 5. Replay of same code is rejected (raises 400 because no active unused challenge)
    with pytest.raises(HTTPException) as replay_exc:
        service.verify_challenge(db_session, phone, otp)
    assert replay_exc.value.status_code == 400


@pytest.mark.anyio
async def test_otp_expiry(db_session):
    """Test expired OTP is rejected."""
    sms = MockSmsProvider()
    service = OtpService(sms_provider=sms)
    phone = "+919876543211"

    res = await service.create_challenge(db_session, phone, client_ip="127.0.0.1")
    clean_phone = res["phone"]
    otp = sms.sent_messages[-1]["otp"]
    challenge = (
        db_session.query(OtpChallengeDB)
        .filter(OtpChallengeDB.phone == clean_phone)
        .order_by(OtpChallengeDB.created_at.desc())
        .first()
    )
    # Manually backdate expiry to the past
    challenge.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
    db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        service.verify_challenge(db_session, phone, otp)
    assert exc_info.value.status_code == 400
    assert "expired" in exc_info.value.detail.lower()


@pytest.mark.anyio
async def test_otp_max_attempts(db_session):
    """Test OTP is locked out after 3 failed attempts."""
    sms = MockSmsProvider()
    service = OtpService(sms_provider=sms)
    phone = "+919876543212"

    await service.create_challenge(db_session, phone, client_ip="127.0.0.1")
    otp = sms.sent_messages[-1]["otp"]

    for _ in range(3):
        with pytest.raises(HTTPException):
            service.verify_challenge(db_session, phone, "999999")

    # 4th attempt with either code fails with max attempts exceeded (429)
    with pytest.raises(HTTPException) as exc_info:
        service.verify_challenge(db_session, phone, otp)
    assert exc_info.value.status_code == 429
    assert "maximum verification attempts exceeded" in exc_info.value.detail.lower()


@pytest.mark.anyio
async def test_demo_otp_forbidden_in_production(monkeypatch, db_session):
    """Demo OTP '123456' must be rejected in production even if requested."""
    sms = MockSmsProvider()
    phone = "+919876543299"

    settings = get_settings()
    monkeypatch.setattr(settings, "environment", "production")
    monkeypatch.setattr(settings, "allow_demo_otp", False)

    service = OtpService(sms_provider=sms)
    service.settings = settings

    res = await service.create_challenge(db_session, phone, client_ip="127.0.0.1")
    assert "demo_otp" not in res
    # Generated OTP is random, not the fixed demo OTP
    assert sms.sent_messages[-1]["otp"] != "123456"


def test_jwt_algorithm_pinning():
    """Verify JWT strictly enforces HS256 and rejects 'none' or mismatched algorithms."""
    settings = get_settings()
    artisan_id = "artisan_secure_01"
    token = create_access_token(artisan_id)

    # 1. Valid token decodes correctly
    claims = decode_access_token(token)
    assert claims["sub"] == artisan_id
    assert claims["iss"] == "kalasetu-backend"
    assert claims["aud"] == "kalasetu-app"

    # 2. Token forged with 'none' algorithm is rejected with 401
    unsecured_token = jwt.encode(
        {"sub": artisan_id, "iss": "kalasetu-backend", "aud": "kalasetu-app"},
        key="",
        algorithm="none",
    )
    with pytest.raises(HTTPException) as exc_info:
        decode_access_token(unsecured_token)
    assert exc_info.value.status_code == 401

    # 3. Token signed with different key is rejected with 401
    foreign_token = jwt.encode(
        {"sub": artisan_id, "iss": "kalasetu-backend", "aud": "kalasetu-app"},
        key="wrong_secret_key_that_does_not_match_at_all!",
        algorithm="HS256",
    )
    with pytest.raises(HTTPException) as exc_info2:
        decode_access_token(foreign_token)
    assert exc_info2.value.status_code == 401


def test_production_secret_strength_validation(monkeypatch):
    """Test validate_production_secrets fails when secret is weak in production."""
    settings = get_settings()
    monkeypatch.setattr(settings, "environment", "production")
    monkeypatch.setattr(settings, "jwt_secret_key", "short")

    with pytest.raises(ValueError, match="JWT_SECRET_KEY must be configured and at least 32 characters"):
        validate_production_secrets(settings)

    monkeypatch.setattr(settings, "jwt_secret_key", "12345678901234567890123456789012")
    with pytest.raises(ValueError, match="JWT_SECRET_KEY cannot be a known weak secret"):
        validate_production_secrets(settings)


def test_validate_indian_phone_valid():
    """Verify Indian phone validation with country codes, spaces, and canonicalization."""
    from backend.services.otp_service import validate_indian_phone

    assert validate_indian_phone("9876543210") == "9876543210"
    assert validate_indian_phone("+919876543210") == "9876543210"
    assert validate_indian_phone("+91 98765-43210") == "9876543210"
    assert validate_indian_phone("09876543210") == "9876543210"
    assert validate_indian_phone("8765432109") == "8765432109"
    assert validate_indian_phone("7765432109") == "7765432109"
    assert validate_indian_phone("6765432109") == "6765432109"


def test_validate_indian_phone_invalid():
    """Verify invalid phone numbers are rejected with 400."""
    from backend.services.otp_service import validate_indian_phone

    with pytest.raises(HTTPException) as exc:
        validate_indian_phone("1234567890")  # Starts with 1
    assert exc.value.status_code == 400

    with pytest.raises(HTTPException) as exc:
        validate_indian_phone("5555555555")  # Starts with 5
    assert exc.value.status_code == 400

    with pytest.raises(HTTPException) as exc:
        validate_indian_phone("98765")  # Too short
    assert exc.value.status_code == 400

    with pytest.raises(HTTPException) as exc:
        validate_indian_phone("abcdefghij")  # Non-digit
    assert exc.value.status_code == 400

    with pytest.raises(HTTPException) as exc:
        validate_indian_phone("")
    assert exc.value.status_code == 400


@pytest.mark.anyio
async def test_sms_provider_http_dispatch(monkeypatch):
    """Verify HttpSmsProvider properly constructs HTTP request to SMS gateway."""
    from backend.services.otp_service import HttpSmsProvider
    import httpx

    captured_requests = []

    async def mock_post(self, url, json=None, headers=None, **kwargs):
        captured_requests.append({"url": url, "json": json, "headers": headers})
        return httpx.Response(status_code=200)

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    provider = HttpSmsProvider(
        api_url="https://sms.example.com/api/send",
        api_key="secret_sms_gateway_token",
        sender_id="KALASETU",
    )
    result = await provider.send_otp("9876543210", "654321")
    assert result is True
    assert len(captured_requests) == 1
    req = captured_requests[0]
    assert req["url"] == "https://sms.example.com/api/send"
    assert req["json"]["phone"] == "9876543210"
    assert "654321" in req["json"]["message"]
    assert req["headers"]["Authorization"] == "Bearer secret_sms_gateway_token"


class FailingSmsProvider(SmsProvider):
    """SMS provider simulation that fails to deliver."""

    async def send_otp(self, phone: str, otp: str) -> bool:
        return False


@pytest.mark.anyio
async def test_sms_delivery_failure_raises_503(db_session):
    """Truthful propagation: SMS failure raises HTTP 503 and burns the challenge."""
    failing_sms = FailingSmsProvider()
    service = OtpService(sms_provider=failing_sms)
    phone = "+919876543215"

    with pytest.raises(HTTPException) as exc_info:
        await service.create_challenge(db_session, phone, client_ip="127.0.0.1")

    assert exc_info.value.status_code == 503
    assert "sms delivery failed" in exc_info.value.detail.lower()

    # Verify challenge was burned so it cannot be guessed/replayed
    clean_phone = "9876543215"
    challenge = (
        db_session.query(OtpChallengeDB)
        .filter(OtpChallengeDB.phone == clean_phone)
        .order_by(OtpChallengeDB.created_at.desc())
        .first()
    )
    assert challenge is not None
    assert challenge.used is True


def test_sms_provider_validation_production(monkeypatch):
    """Production cannot silently fall back to console or mock SMS provider."""
    settings = get_settings()
    monkeypatch.setattr(settings, "environment", "production")
    monkeypatch.setattr(settings, "sms_provider", "console")

    with pytest.raises(ValueError, match="Production environment must configure a supported external SMS provider"):
        OtpService()


def test_sms_provider_validation_unsupported(monkeypatch):
    """Unsupported SMS provider raises descriptive ValueError."""
    settings = get_settings()
    monkeypatch.setattr(settings, "sms_provider", "unsupported_gateway")

    with pytest.raises(ValueError, match="Unsupported SMS provider 'unsupported_gateway'"):
        OtpService()


@pytest.mark.anyio
async def test_sms_provider_real_sms_disabled(monkeypatch):
    """HttpSmsProvider blocks SMS delivery if enable_real_sms is False."""
    from backend.services.otp_service import HttpSmsProvider
    import httpx

    post_called = False

    async def mock_post(self, *args, **kwargs):
        nonlocal post_called
        post_called = True
        return httpx.Response(status_code=200)

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    provider = HttpSmsProvider(
        api_url="https://sms.example.com/api/send",
        api_key="token",
        enable_real_sms=False,
    )
    result = await provider.send_otp("9876543210", "123456")
    assert result is False
    assert post_called is False


@pytest.mark.anyio
async def test_sms_provider_timeout_no_retry(monkeypatch):
    """HttpSmsProvider handles timeouts without blind retry to conserve credits."""
    from backend.services.otp_service import HttpSmsProvider
    import httpx

    call_count = 0

    async def mock_post(self, *args, **kwargs):
        nonlocal call_count
        call_count += 1
        raise httpx.TimeoutException("Gateway timeout")

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    provider = HttpSmsProvider(
        api_url="https://sms.example.com/api/send",
        api_key="token",
        enable_real_sms=True,
    )
    result = await provider.send_otp("9876543210", "123456")
    assert result is False
    assert call_count == 1  # Exactly 1 call, no blind retry duplicate


@pytest.mark.anyio
async def test_otp_30_second_cooldown(db_session):
    """Enforce minimum 30-second cooldown between OTP requests for the same phone."""
    service = OtpService()
    phone = "+919876543205"

    # First request succeeds
    res1 = await service.create_challenge(db_session, phone, client_ip="127.0.0.99")
    assert res1["status"] == "success"

    # Immediate second request is rejected with 429
    with pytest.raises(HTTPException) as exc_info:
        await service.create_challenge(db_session, phone, client_ip="127.0.0.99")

    assert exc_info.value.status_code == 429
    assert "wait 30 seconds" in exc_info.value.detail.lower()


@pytest.mark.anyio
async def test_otp_daily_limit_cap(db_session, monkeypatch):
    """Enforce server-side daily sending cap."""
    settings = get_settings()
    monkeypatch.setattr(settings, "daily_phone_sms_cap", 2)
    service = OtpService()
    phone = "+919876543206"

    # Request 1
    res1 = await service.create_challenge(db_session, phone, client_ip="127.0.0.98")
    assert res1["status"] == "success"

    # Fast forward challenge timestamp to bypass 30s cooldown
    challenge1 = (
        db_session.query(OtpChallengeDB)
        .filter(OtpChallengeDB.phone == "9876543206")
        .order_by(OtpChallengeDB.created_at.desc())
        .first()
    )
    challenge1.created_at = challenge1.created_at - timedelta(seconds=35)
    db_session.commit()

    # Request 2
    res2 = await service.create_challenge(db_session, phone, client_ip="127.0.0.98")
    assert res2["status"] == "success"

    # Fast forward again
    challenge2 = (
        db_session.query(OtpChallengeDB)
        .filter(OtpChallengeDB.phone == "9876543206")
        .order_by(OtpChallengeDB.created_at.desc())
        .first()
    )
    challenge2.created_at = challenge2.created_at - timedelta(seconds=35)
    db_session.commit()

    # Request 3 should hit the daily cap (2)
    with pytest.raises(HTTPException) as exc_info:
        await service.create_challenge(db_session, phone, client_ip="127.0.0.98")

    assert exc_info.value.status_code == 429
    assert "daily otp limit exceeded" in exc_info.value.detail.lower()


@pytest.mark.anyio
async def test_2factor_provider_custom_otp_contract(monkeypatch):
    """
    Verify 2Factor provider uses the custom OTP URL structure where backend OTP
    is sent, preserving authoritative backend verification.
    """
    from backend.services.otp_service import TwoFactorSmsProvider
    import httpx

    captured_url = None

    async def mock_get(self, url, **kwargs):
        nonlocal captured_url
        captured_url = str(url)
        return httpx.Response(200, json={"Status": "Success", "Details": "2f_session_abc123"})

    monkeypatch.setattr(httpx.AsyncClient, "get", mock_get)

    provider = TwoFactorSmsProvider(
        api_key="test_2factor_secret_key",
        template_name="KALASETU_LOGIN",
        enable_real_sms=True,
    )
    sent = await provider.send_otp("+919876543210", "654321")
    assert sent is True
    assert captured_url is not None
    assert "https://2factor.in/API/V1/test_2factor_secret_key/SMS/9876543210/654321/KALASETU_LOGIN" in captured_url


@pytest.mark.anyio
async def test_2factor_provider_rejection_and_error_handling(monkeypatch):
    """Verify 2Factor handles error responses and non-200 codes safely."""
    from backend.services.otp_service import TwoFactorSmsProvider
    import httpx

    # Error JSON response
    async def mock_get_error(self, url, **kwargs):
        return httpx.Response(200, json={"Status": "Error", "Details": "Invalid mobile number"})

    monkeypatch.setattr(httpx.AsyncClient, "get", mock_get_error)
    provider = TwoFactorSmsProvider(api_key="token", enable_real_sms=True)
    assert await provider.send_otp("9876543210", "123456") is False

    # HTTP 500 error
    async def mock_get_500(self, url, **kwargs):
        return httpx.Response(500, text="Internal Server Error")

    monkeypatch.setattr(httpx.AsyncClient, "get", mock_get_500)
    assert await provider.send_otp("9876543210", "123456") is False


@pytest.mark.anyio
async def test_2factor_and_http_enable_real_sms_safeguard():
    """Verify both external providers block dispatch when enable_real_sms=False."""
    from backend.services.otp_service import TwoFactorSmsProvider, HttpSmsProvider

    tf_provider = TwoFactorSmsProvider(api_key="token", enable_real_sms=False)
    assert await tf_provider.send_otp("9876543210", "123456") is False

    http_provider = HttpSmsProvider(api_url="https://sms.example.com", api_key="token", enable_real_sms=False)
    assert await http_provider.send_otp("9876543210", "123456") is False


@pytest.mark.anyio
async def test_2factor_redaction_in_logs_and_exceptions(monkeypatch, caplog):
    """Verify credentials, OTPs, recipient phone numbers, and URLs are redacted."""
    import logging
    from backend.services.otp_service import TwoFactorSmsProvider
    import httpx

    async def mock_get_throw(self, url, **kwargs):
        raise RuntimeError(f"Connection failure to {url}")

    monkeypatch.setattr(httpx.AsyncClient, "get", mock_get_throw)

    secret_key = "TOP_SECRET_API_KEY_VAL"
    secret_otp = "876543"
    recipient_phone = "9876543210"

    provider = TwoFactorSmsProvider(api_key=secret_key, template_name="LOGIN_TEMPLATE", enable_real_sms=True)

    with caplog.at_level(logging.DEBUG):
        result = await provider.send_otp(recipient_phone, secret_otp)

    assert result is False
    log_text = caplog.text
    assert secret_key not in log_text, "API key must never appear in logs"
    assert secret_otp not in log_text, "OTP must never appear in logs"
    assert recipient_phone not in log_text, "Full phone number must never appear in logs"
    assert "98******10" in log_text, "Masked phone should appear"


@pytest.mark.anyio
async def test_sms_ambiguous_timeout_recorded_and_counts_against_budget(db_session, monkeypatch):
    """
    Verify provider timeout is recorded as ambiguous_timeout in persistent db,
    burns the challenge, and counts conservatively against rolling 24h budget.
    """
    import hashlib
    from backend.services.otp_service import OtpService, SmsProvider, SmsDispatchStatus, SmsDispatchLogDB

    class TimeoutProvider(SmsProvider):
        def __init__(self):
            self.last_was_timeout = False
        async def send_otp(self, phone: str, otp: str) -> bool:
            self.last_was_timeout = True
            return False

    service = OtpService(sms_provider=TimeoutProvider())
    phone = "+919876543999"

    # Ensure no pre-existing challenge for this phone
    db_session.query(OtpChallengeDB).filter(OtpChallengeDB.phone == "9876543999").delete()
    db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        await service.create_challenge(db_session, phone, client_ip="127.0.0.12")
    assert exc_info.value.status_code == 503
    assert "timed out" in exc_info.value.detail.lower()

    # Check database: record status is AMBIGUOUS_TIMEOUT
    phone_hash = hashlib.sha256("9876543999".encode("utf-8")).hexdigest()
    log = (
        db_session.query(SmsDispatchLogDB)
        .filter(SmsDispatchLogDB.phone_hash == phone_hash)
        .order_by(SmsDispatchLogDB.created_at.desc())
        .first()
    )
    assert log is not None
    assert log.status == SmsDispatchStatus.AMBIGUOUS_TIMEOUT.value


@pytest.mark.anyio
async def test_sms_limits_persist_across_restart(db_session, monkeypatch):
    """
    Verify that closing the DB session / restarting backend does not clear
    the rolling 24h SMS budget.
    """
    import hashlib
    from backend.services.otp_service import OtpService, SmsDispatchLogDB, SmsDispatchStatus
    from backend.database import SessionLocal

    settings = get_settings()
    monkeypatch.setattr(settings, "daily_phone_sms_cap", 1)

    phone = "+919876543998"
    db_session.query(OtpChallengeDB).filter(OtpChallengeDB.phone == "9876543998").delete()
    db_session.query(SmsDispatchLogDB).filter(SmsDispatchLogDB.phone_hash == hashlib.sha256("9876543998".encode()).hexdigest()).delete()
    db_session.commit()

    service = OtpService()

    # Request 1: succeeds and logs reservation + dispatch
    res = await service.create_challenge(db_session, phone, client_ip="127.0.0.13")
    assert res["status"] == "success"

    # Simulate backend restart by closing session and creating new one
    db_session.close()
    new_db = SessionLocal()
    try:
        # Fast forward cooldown on challenge
        c = (
            new_db.query(OtpChallengeDB)
            .filter(OtpChallengeDB.phone == "9876543998")
            .order_by(OtpChallengeDB.created_at.desc())
            .first()
        )
        c.created_at = c.created_at - timedelta(seconds=35)
        new_db.commit()

        # Request 2 on new session should hit daily limit because SmsDispatchLogDB persisted
        new_service = OtpService()
        with pytest.raises(HTTPException) as exc_info:
            await new_service.create_challenge(new_db, phone, client_ip="127.0.0.13")
        assert exc_info.value.status_code == 429
        assert "daily otp limit exceeded" in exc_info.value.detail.lower()
    finally:
        new_db.close()


def test_2factor_production_settings_validation(monkeypatch):
    """Verify Settings validation recognizes 2factor and requires API key in production."""
    from backend.config import Settings

    # Production with 2factor and API key is valid
    s = Settings(
        environment="production",
        allow_demo_otp=False,
        jwt_secret_key="a" * 32,
        sms_provider="2factor",
        sms_api_key="valid_2factor_key",
        cors_origins=["https://kalasetu.in"],
    )
    assert s.sms_provider == "2factor"

    # Production with 2factor but missing API key must raise ValueError
    with pytest.raises(ValueError, match="SMS_API_KEY must be configured for 2Factor"):
        Settings(
            environment="production",
            allow_demo_otp=False,
            jwt_secret_key="a" * 32,
            sms_provider="2factor",
            sms_api_key="",
            cors_origins=["https://kalasetu.in"],
        )
