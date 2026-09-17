"""
Cryptographic OTP Challenge & Delivery Service.

Enforces:
- Cryptographically random OTP generation.
- Salted SHA-256 storage; plaintext OTP is never persisted.
- 5-minute challenge expiration.
- Max 3 verification attempts per challenge before permanent burn.
- Single-use invalidation upon successful verification.
- Dual-layer rate limiting: per-phone and per-IP.
- Pluggable SMS delivery abstraction.
- Demo mode isolation: fixed OTP permitted ONLY when ALLOW_DEMO_OTP=true and ENVIRONMENT != "production".
"""

import abc
import hashlib
import hmac
import logging
import secrets
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, List

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from ..config import get_settings
from ..models.db_models import OtpChallengeDB

import re
import httpx

logger = logging.getLogger(__name__)
settings = get_settings()


def validate_indian_phone(phone: str) -> str:
    """
    Validate and normalize Indian mobile phone number.
    Accepts: +91XXXXXXXXXX, 0XXXXXXXXXX, XXXXXXXXXX.
    Requires: Exactly 10 digits starting with 6, 7, 8, or 9.
    Returns: Canonical 10-digit string.
    """
    if not phone or not isinstance(phone, str):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid phone number: Phone number is required.",
        )

    cleaned = re.sub(r"[\s\-\(\)]", "", phone.strip())
    if cleaned.startswith("+91"):
        cleaned = cleaned[3:]
    elif cleaned.startswith("0") and len(cleaned) == 11:
        cleaned = cleaned[1:]

    if not re.match(r"^[6-9]\d{9}$", cleaned):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Indian mobile number. Must be a 10-digit number starting with 6, 7, 8, or 9.",
        )
    return cleaned


# ── Pluggable SMS Provider Abstraction ───────────────────────────────────────


class SmsProvider(abc.ABC):
    """Abstract interface for dispatching OTPs via SMS."""

    @abc.abstractmethod
    async def send_otp(self, phone: str, otp: str) -> bool:
        """Send OTP to the given phone number."""
        pass


class ConsoleSmsProvider(SmsProvider):
    """Development / staging SMS provider."""

    async def send_otp(self, phone: str, otp: str) -> bool:
        current_settings = get_settings()
        if current_settings.environment == "test" and current_settings.allow_demo_otp:
            logger.info(f"[SMS DISPATCH] Secure OTP for {phone}: {otp}")
        else:
            masked = f"{phone[:2]}******{phone[-2:]}" if len(phone) >= 4 else "***"
            logger.info(f"[SMS DISPATCH] Secure OTP dispatched to {masked} (code masked)")
        return True


class MockSmsProvider(SmsProvider):
    """In-memory testing SMS provider recording sent messages."""

    def __init__(self):
        self.sent_messages: List[Dict[str, str]] = []

    async def send_otp(self, phone: str, otp: str) -> bool:
        self.sent_messages.append({"phone": phone, "otp": otp})
        return True


class HttpSmsProvider(SmsProvider):
    """Production HTTP REST API SMS provider."""

    def __init__(self, api_url: str, api_key: str, sender_id: str = ""):
        self.api_url = api_url
        self.api_key = api_key
        self.sender_id = sender_id

    async def send_otp(self, phone: str, otp: str) -> bool:
        if not self.api_url or not self.api_key:
            logger.error("HTTP SMS provider missing api_url or api_key configuration.")
            return False
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(
                    self.api_url,
                    json={
                        "phone": phone,
                        "message": f"Your KalaSetu verification code is {otp}. Valid for 5 minutes.",
                        "sender_id": self.sender_id,
                    },
                    headers={"Authorization": f"Bearer {self.api_key}"},
                )
                return resp.status_code in (200, 201, 202)
        except Exception as e:
            logger.error(f"Failed to dispatch SMS via HTTP provider: {e}")
            return False


# ── In-Memory IP Rate Limiting Store ─────────────────────────────────────────


class IpRateLimiter:
    """Sliding-window in-memory IP rate limiter."""

    def __init__(self):
        self.requests_per_ip: Dict[str, List[datetime]] = defaultdict(list)

    def check_and_record(self, client_ip: str, max_per_minute: int = 10, max_per_hour: int = 30) -> None:
        now = datetime.now(timezone.utc)
        one_min_ago = now - timedelta(minutes=1)
        one_hour_ago = now - timedelta(hours=1)

        history = self.requests_per_ip[client_ip]
        # Filter history
        self.requests_per_ip[client_ip] = [t for t in history if t > one_hour_ago]
        history = self.requests_per_ip[client_ip]

        recent_minute = sum(1 for t in history if t > one_min_ago)
        if recent_minute >= max_per_minute:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many OTP requests from this network. Please wait a minute.",
            )

        if len(history) >= max_per_hour:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Hourly OTP request limit exceeded for this network. Please try again later.",
            )

        self.requests_per_ip[client_ip].append(now)


_ip_rate_limiter = IpRateLimiter()


# ── Core OTP Challenge Service ──────────────────────────────────────────────


class OtpService:
    """Manages secure OTP challenge lifecycle and verification."""

    def __init__(self, sms_provider: Optional[SmsProvider] = None):
        self.settings = get_settings()
        if sms_provider:
            self.sms_provider = sms_provider
        elif (self.settings.sms_provider or "").lower() == "http":
            self.sms_provider = HttpSmsProvider(
                api_url=self.settings.sms_api_url,
                api_key=self.settings.sms_api_key,
                sender_id=self.settings.sms_sender_id or "",
            )
        elif (self.settings.sms_provider or "").lower() == "mock":
            self.sms_provider = MockSmsProvider()
        else:
            self.sms_provider = ConsoleSmsProvider()

    def _hash_otp(self, salt: str, otp: str) -> str:
        return hashlib.sha256(f"{salt}{otp}".encode("utf-8")).hexdigest()

    async def create_challenge(
        self,
        db: Session,
        phone: str,
        client_ip: str = "127.0.0.1",
    ) -> Dict[str, any]:
        """
        Rate-limit, generate, hash, and dispatch a new OTP challenge.
        """
        clean_phone = validate_indian_phone(phone)

        # 1. IP rate limiting
        _ip_rate_limiter.check_and_record(client_ip)

        # 2. Per-phone rate limiting: max 5 requests per hour
        one_hour_ago = datetime.now(timezone.utc) - timedelta(hours=1)
        recent_challenges_count = (
            db.query(OtpChallengeDB)
            .filter(
                OtpChallengeDB.phone == clean_phone,
                OtpChallengeDB.created_at > one_hour_ago,
            )
            .count()
        )
        if recent_challenges_count >= 5:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many OTP requests for this phone number. Please wait an hour.",
            )

        # 3. Invalidate any existing unused challenges for this phone
        db.query(OtpChallengeDB).filter(
            OtpChallengeDB.phone == clean_phone,
            OtpChallengeDB.used == False,
        ).update({"used": True})
        db.commit()

        # 4. Generate random OTP
        is_prod = (self.settings.environment or "").strip().lower() == "production"
        if not is_prod and self.settings.allow_demo_otp and clean_phone == "9876543210":
            otp = "123456"
        else:
            otp = str(secrets.randbelow(900000) + 100000)

        salt = secrets.token_hex(16)
        otp_hash = self._hash_otp(salt, otp)
        challenge_id = f"otp_{uuid.uuid4().hex[:12]}"
        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(minutes=5)

        challenge = OtpChallengeDB(
            id=challenge_id,
            phone=clean_phone,
            otp_hash=otp_hash,
            salt=salt,
            expires_at=expires_at,
            attempts=0,
            max_attempts=3,
            used=False,
            created_at=now,
        )
        db.add(challenge)
        db.commit()

        # 5. Dispatch through SMS provider
        await self.sms_provider.send_otp(clean_phone, otp)

        response = {
            "status": "success",
            "message": "OTP challenge issued successfully.",
            "phone": clean_phone,
            "expires_in_seconds": 300,
        }

        # In non-production with ALLOW_DEMO_OTP=true, include demo_otp for automated testing
        if not is_prod and self.settings.allow_demo_otp:
            response["demo_otp"] = otp

        return response

    def verify_challenge(self, db: Session, phone: str, otp: str) -> bool:
        """
        Verify submitted OTP against active, non-expired challenge.
        Enforces max attempts, constant-time comparison, and marks used on success.
        """
        clean_phone = validate_indian_phone(phone)
        now = datetime.now(timezone.utc)

        challenge = (
            db.query(OtpChallengeDB)
            .filter(
                OtpChallengeDB.phone == clean_phone,
                OtpChallengeDB.used == False,
            )
            .order_by(OtpChallengeDB.created_at.desc())
            .first()
        )

        if not challenge:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No active OTP challenge found. Please request a new code.",
            )

        # Check expiration
        exp = challenge.expires_at.replace(tzinfo=timezone.utc) if challenge.expires_at.tzinfo is None else challenge.expires_at
        if now > exp:
            challenge.used = True
            db.commit()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="OTP challenge has expired. Please request a new code.",
            )

        # Check attempts
        if challenge.attempts >= challenge.max_attempts:
            challenge.used = True
            db.commit()
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Maximum verification attempts exceeded. Please request a new OTP.",
            )

        challenge.attempts += 1
        expected_hash = self._hash_otp(challenge.salt, otp.strip())
        is_valid = hmac.compare_digest(challenge.otp_hash, expected_hash)

        if not is_valid:
            db.commit()
            remaining = challenge.max_attempts - challenge.attempts
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid OTP code. {remaining} attempt(s) remaining.",
            )

        # Successful verification: mark single-use immediately
        challenge.used = True
        db.commit()
        return True
