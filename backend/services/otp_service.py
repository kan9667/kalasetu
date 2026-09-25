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
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..config import get_settings
from ..models.db_models import OtpChallengeDB, SmsDispatchLogDB, SmsDispatchStatus

import re
import httpx
from dataclasses import dataclass

logger = logging.getLogger(__name__)
settings = get_settings()


@dataclass
class SmsDispatchOutcome:
    """Per-dispatch outcome to eliminate shared mutable timeout flags."""
    success: bool
    is_timeout: bool = False
    is_ambiguous: bool = False
    error_detail: Optional[str] = None


class HttpxSensitiveUrlFilter(logging.Filter):
    """
    Prevents transport-level HTTP request logs (httpx/httpcore) from exposing
    API keys, phone numbers, and OTPs in URLs or exception text.
    """

    def filter(self, record: logging.LogRecord) -> bool:
        if record.args:
            new_args = []
            for arg in record.args:
                if isinstance(arg, httpx.URL) or (isinstance(arg, str) and ("2factor.in" in arg or "/API/V1/" in arg)):
                    s = str(arg)
                    s = re.sub(
                        r"(https?://[^/\s]+/API/V1/)[^/\s]+(/SMS/)[^/\s]+/[^/\s]+(?:/[^/\s\?]+)?",
                        r"\1***REDACTED***\2******/***REDACTED***",
                        s,
                    )
                    new_args.append(s)
                elif isinstance(arg, str):
                    s = re.sub(
                        r"(https?://[^/\s]+/API/V1/)[^/\s]+(/SMS/)[^/\s]+/[^/\s]+(?:/[^/\s\?]+)?",
                        r"\1***REDACTED***\2******/***REDACTED***",
                        arg,
                    )
                    new_args.append(s)
                else:
                    new_args.append(arg)
            record.args = tuple(new_args)

        if isinstance(record.msg, str) and ("2factor.in" in record.msg or "/API/V1/" in record.msg):
            record.msg = re.sub(
                r"(https?://[^/\s]+/API/V1/)[^/\s]+(/SMS/)[^/\s]+/[^/\s]+(?:/[^/\s\?]+)?",
                r"\1***REDACTED***\2******/***REDACTED***",
                record.msg,
            )
        return True


# Install filter on httpx and httpcore loggers
_httpx_filter = HttpxSensitiveUrlFilter()
logging.getLogger("httpx").addFilter(_httpx_filter)
logging.getLogger("httpcore").addFilter(_httpx_filter)


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
    """
    Generic HTTP REST API SMS provider adapter.
    Redacts credentials and recipient data from logs and exceptions.
    """

    def __init__(
        self,
        api_url: str,
        api_key: str,
        sender_id: str = "",
        enable_real_sms: bool = True,
    ):
        self.api_url = api_url or ""
        self.api_key = api_key or ""
        self.sender_id = sender_id or ""
        self.enable_real_sms = enable_real_sms

    async def send_otp_with_outcome(self, phone: str, otp: str) -> SmsDispatchOutcome:
        clean_phone = validate_indian_phone(phone)
        masked_phone = f"{clean_phone[:2]}******{clean_phone[-2:]}"

        if not self.enable_real_sms:
            logger.warning(
                "Real SMS delivery disabled by configuration (ENABLE_REAL_SMS=False). "
                f"Dispatch to {masked_phone} prevented."
            )
            return SmsDispatchOutcome(success=False, error_detail="Real SMS delivery disabled")
        if not self.api_url or not self.api_key:
            logger.error("HTTP SMS provider missing api_url or api_key configuration.")
            return SmsDispatchOutcome(success=False, error_detail="Missing api_url or api_key configuration")
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(
                    self.api_url,
                    json={
                        "phone": clean_phone,
                        "message": f"Your KalaSetu verification code is {otp}. Valid for 5 minutes.",
                        "sender_id": self.sender_id,
                    },
                    headers={"Authorization": f"Bearer {self.api_key}"},
                )
                if resp.status_code in (200, 201, 202):
                    return SmsDispatchOutcome(success=True)
                safe_body = resp.text.replace(self.api_key, "***REDACTED***").replace(otp, "***REDACTED***").replace(clean_phone, masked_phone)
                return SmsDispatchOutcome(success=False, error_detail=f"HTTP {resp.status_code}: {safe_body}")
        except httpx.TimeoutException:
            logger.error(
                f"SMS gateway timed out dispatching to {masked_phone}. "
                "Avoiding blind retry to prevent duplicate dispatch and credit drain."
            )
            return SmsDispatchOutcome(success=False, is_timeout=True, error_detail="Gateway timeout")
        except Exception as e:
            safe_msg = str(e).replace(self.api_key, "***REDACTED***").replace(otp, "***REDACTED***").replace(clean_phone, masked_phone)
            logger.error(f"Failed to dispatch SMS via HTTP provider: {safe_msg}")
            return SmsDispatchOutcome(success=False, error_detail=safe_msg)

    async def send_otp(self, phone: str, otp: str) -> bool:
        outcome = await self.send_otp_with_outcome(phone, otp)
        return outcome.success


class TwoFactorSmsProvider(SmsProvider):
    """
    Dedicated 2Factor.in SMS provider for Indian carrier OTP delivery.
    Uses custom OTP endpoints where the backend-generated OTP is sent,
    preserving authoritative backend verification lifecycle.
    """

    def __init__(
        self,
        api_key: str,
        template_name: str = "",
        enable_real_sms: bool = True,
        base_url: str = "https://2factor.in/API/V1",
    ):
        self.api_key = api_key or ""
        self.template_name = template_name or ""
        self.enable_real_sms = enable_real_sms
        self.base_url = (base_url or "https://2factor.in/API/V1").rstrip("/")
        # Ensure HTTPX transport log filter is active on httpx and httpcore loggers
        logging.getLogger("httpx").addFilter(_httpx_filter)
        logging.getLogger("httpcore").addFilter(_httpx_filter)

    async def send_otp_with_outcome(self, phone: str, otp: str) -> SmsDispatchOutcome:
        clean_phone = validate_indian_phone(phone)
        masked_phone = f"{clean_phone[:2]}******{clean_phone[-2:]}"

        if not self.enable_real_sms:
            logger.warning(
                "[2Factor] Real SMS delivery disabled (ENABLE_REAL_SMS=False). "
                f"Simulated dispatch for {masked_phone} prevented."
            )
            return SmsDispatchOutcome(success=False, error_detail="Real SMS delivery disabled (ENABLE_REAL_SMS=False)")

        if not self.api_key:
            logger.error("[2Factor] Missing API key configuration.")
            return SmsDispatchOutcome(success=False, error_detail="Missing API key configuration")

        # Endpoint structure:
        # POST https://2factor.in/API/V1/{api_key}/SMS/{phone}/{otp}/{template_name}
        # 2Factor's custom SMS OTP API documents POST for this endpoint.
        # All logs, URLs, bodies, and exceptions MUST redact the API key, OTP, and full phone.
        if self.template_name:
            target_url = f"{self.base_url}/{self.api_key}/SMS/{clean_phone}/{otp}/{self.template_name}"
            redacted_url = f"{self.base_url}/***REDACTED***/SMS/{masked_phone}/***REDACTED***/{self.template_name}"
        else:
            target_url = f"{self.base_url}/{self.api_key}/SMS/{clean_phone}/{otp}"
            redacted_url = f"{self.base_url}/***REDACTED***/SMS/{masked_phone}/***REDACTED***"

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(target_url)

                if resp.status_code != 200:
                    safe_body = resp.text.replace(self.api_key, "***REDACTED***").replace(otp, "***REDACTED***").replace(clean_phone, masked_phone)
                    logger.warning(
                        f"[2Factor] Gateway returned HTTP {resp.status_code} for dispatch to {masked_phone} at {redacted_url}: {safe_body}."
                    )
                    return SmsDispatchOutcome(success=False, error_detail=f"HTTP {resp.status_code}: {safe_body}")

                try:
                    data = resp.json()
                except Exception:
                    logger.warning(f"[2Factor] Gateway returned non-JSON body for dispatch to {masked_phone}. Delivery status ambiguous.")
                    return SmsDispatchOutcome(success=False, is_ambiguous=True, error_detail="Non-JSON body returned by gateway (ambiguous delivery)")

                status_val = data.get("Status")
                if status_val == "Success":
                    logger.info(f"[2Factor] OTP successfully dispatched to {masked_phone}.")
                    return SmsDispatchOutcome(success=True)
                else:
                    details = str(data.get("Details", "")).replace(self.api_key, "***REDACTED***").replace(otp, "***REDACTED***").replace(clean_phone, masked_phone)
                    logger.warning(
                        f"[2Factor] Gateway rejected OTP dispatch to {masked_phone}: Status='{status_val}', Details='{details}'."
                    )
                    return SmsDispatchOutcome(success=False, is_ambiguous=False, error_detail=f"{status_val}: {details}")

        except httpx.TimeoutException:
            logger.error(
                f"[2Factor] Timeout dispatching to {masked_phone} at {redacted_url}. "
                "Delivery status is ambiguous; will NOT auto-retry to prevent double-charging."
            )
            return SmsDispatchOutcome(success=False, is_timeout=True, is_ambiguous=True, error_detail="Gateway timeout (ambiguous delivery)")
        except (httpx.ReadError, httpx.RemoteProtocolError, httpx.ReadTimeout) as e:
            safe_msg = str(e).replace(self.api_key, "***REDACTED***").replace(otp, "***REDACTED***").replace(clean_phone, masked_phone)
            logger.error(f"[2Factor] Connection dropped post-dispatch for {masked_phone}: {safe_msg}. Delivery status ambiguous.")
            return SmsDispatchOutcome(success=False, is_ambiguous=True, error_detail=f"Post-dispatch read error (ambiguous delivery): {safe_msg}")
        except Exception as e:
            safe_msg = str(e).replace(self.api_key, "***REDACTED***").replace(otp, "***REDACTED***").replace(clean_phone, masked_phone)
            logger.error(f"[2Factor] Dispatch failure for {masked_phone}: {safe_msg}")
            is_ambiguous = isinstance(e, httpx.HTTPError) and not isinstance(e, (httpx.ConnectError, httpx.ConnectTimeout))
            return SmsDispatchOutcome(success=False, is_ambiguous=is_ambiguous, error_detail=safe_msg)

    async def send_otp(self, phone: str, otp: str) -> bool:
        outcome = await self.send_otp_with_outcome(phone, otp)
        return outcome.success


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
    """Manages secure OTP challenge lifecycle, budget enforcement, and verification."""

    def __init__(self, sms_provider: Optional[SmsProvider] = None):
        self.settings = get_settings()
        if sms_provider:
            self.sms_provider = sms_provider
        else:
            provider_name = (self.settings.sms_provider or "").lower().strip()
            if provider_name == "http":
                self.sms_provider = HttpSmsProvider(
                    api_url=self.settings.sms_api_url or "",
                    api_key=self.settings.sms_api_key or "",
                    sender_id=self.settings.sms_sender_id or "",
                    enable_real_sms=self.settings.enable_real_sms,
                )
            elif provider_name == "2factor":
                self.sms_provider = TwoFactorSmsProvider(
                    api_key=self.settings.sms_api_key or "",
                    template_name=self.settings.sms_template_name or "",
                    enable_real_sms=self.settings.enable_real_sms,
                )
            elif provider_name == "mock":
                self.sms_provider = MockSmsProvider()
            elif provider_name == "console" or not provider_name:
                if (self.settings.environment or "").strip().lower() == "production":
                    raise ValueError("Production environment must configure a supported external SMS provider (e.g. 'http' or '2factor').")
                self.sms_provider = ConsoleSmsProvider()
            else:
                raise ValueError(f"Unsupported SMS provider '{provider_name}'. Supported providers: http, 2factor, mock, console.")

    def _hash_otp(self, salt: str, otp: str) -> str:
        return hashlib.sha256(f"{salt}{otp}".encode("utf-8")).hexdigest()

    async def create_challenge(
        self,
        db: Session,
        phone: str,
        client_ip: str = "127.0.0.1",
    ) -> Dict[str, any]:
        """
        Rate-limit, check durable rolling budgets, generate, hash, and dispatch a new OTP challenge.
        Enforces atomic budget reservation in SmsDispatchLogDB before external dispatch.
        """
        clean_phone = validate_indian_phone(phone)

        # 1. IP rate limiting
        _ip_rate_limiter.check_and_record(client_ip)

        # 2. Cooldown check: minimum 30 seconds between requests for this phone
        thirty_seconds_ago = datetime.now(timezone.utc) - timedelta(seconds=30)
        recent_attempt = (
            db.query(OtpChallengeDB)
            .filter(
                OtpChallengeDB.phone == clean_phone,
                OtpChallengeDB.created_at > thirty_seconds_ago,
            )
            .first()
        )
        if recent_attempt:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Please wait 30 seconds before requesting another verification code.",
            )

        # 3. Durable budget limit checks over rolling 24-hour window
        rolling_window_start = datetime.now(timezone.utc) - timedelta(hours=24)
        counted_statuses = [
            SmsDispatchStatus.RESERVED.value,
            SmsDispatchStatus.DISPATCHED.value,
            SmsDispatchStatus.AMBIGUOUS_TIMEOUT.value,
        ]

        # 3a. Global rolling 24-hour limit check
        global_active_count = (
            db.query(SmsDispatchLogDB)
            .filter(
                SmsDispatchLogDB.created_at >= rolling_window_start,
                SmsDispatchLogDB.status.in_(counted_statuses),
            )
            .count()
        )
        if global_active_count >= self.settings.daily_sms_cap:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Daily SMS delivery limit reached. Please try again tomorrow.",
            )

        # 3b. Per-phone rolling 24-hour limit check
        phone_hash = hashlib.sha256(clean_phone.encode("utf-8")).hexdigest()
        phone_active_count = (
            db.query(SmsDispatchLogDB)
            .filter(
                SmsDispatchLogDB.phone_hash == phone_hash,
                SmsDispatchLogDB.created_at >= rolling_window_start,
                SmsDispatchLogDB.status.in_(counted_statuses),
            )
            .count()
        )
        if phone_active_count >= self.settings.daily_phone_sms_cap:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Daily OTP limit exceeded for this phone number. Please try again tomorrow.",
            )

        # 3c. Hourly per-phone limit check (max 5 requests per hour)
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

        # 4. Atomic Budget Reservation (committed before external call)
        provider_name = (self.settings.sms_provider or "console").lower().strip()
        log_id = f"sms_log_{uuid.uuid4().hex[:12]}"
        dispatch_log = SmsDispatchLogDB(
            id=log_id,
            phone_hash=phone_hash,
            provider=provider_name,
            status=SmsDispatchStatus.RESERVED.value,
            created_at=datetime.now(timezone.utc),
        )
        db.add(dispatch_log)
        db.commit()
        db.refresh(dispatch_log)

        # 4a. Post-Commit Atomic Admission Ranking Check using SQLite rowid
        # Enforces atomic admission across concurrent database transactions using deterministic
        # SQLite rowid ordering. SQLite assigns rowid strictly sequentially at INSERT time.
        # If multiple concurrent sessions commit reservations, only winning slots within
        # daily_sms_cap, daily_phone_sms_cap, and cooldown proceed.
        # CRITICAL INVARIANT: Rejections at this stage MUST NOT touch OtpChallengeDB so that
        # an accepted/delivered challenge from a concurrent winner is left completely intact!
        my_rowid = db.execute(
            text("SELECT rowid FROM sms_dispatch_logs WHERE id = :id"),
            {"id": dispatch_log.id},
        ).scalar()

        if my_rowid:
            # 1. Cooldown check: Check if another reservation is concurrently in flight for this phone
            # OR if another challenge was committed for this phone within the 30s cooldown.
            concurrent_reserved = db.execute(
                text("""
                    SELECT count(*) FROM sms_dispatch_logs
                    WHERE phone_hash = :phone_hash
                      AND status = 'reserved'
                      AND rowid < :my_rowid
                """),
                {
                    "phone_hash": phone_hash,
                    "my_rowid": my_rowid,
                },
            ).scalar()

            recent_challenge_cooldown = db.execute(
                text("""
                    SELECT count(*) FROM otp_challenges
                    WHERE phone = :phone
                      AND datetime(created_at) >= datetime(:cooldown_start)
                """),
                {
                    "phone": clean_phone,
                    "cooldown_start": thirty_seconds_ago.strftime("%Y-%m-%d %H:%M:%S"),
                },
            ).scalar()

            if (concurrent_reserved and concurrent_reserved > 0) or (recent_challenge_cooldown and recent_challenge_cooldown > 0):
                logger.warning(
                    f"[OtpService] Cooldown contention detected for phone {clean_phone[:2]}******{clean_phone[-2:]} "
                    f"(concurrent_reserved={concurrent_reserved}, recent_challenge={recent_challenge_cooldown})."
                )
                dispatch_log.status = SmsDispatchStatus.FAILED.value
                dispatch_log.error_detail = "Cooldown limit exceeded (concurrency contention)"
                db.commit()
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Please wait 30 seconds before requesting another verification code.",
                )

            rolling_str = rolling_window_start.strftime("%Y-%m-%d %H:%M:%S")
            # 2. Global cap admission
            global_rank = db.execute(
                text("""
                    SELECT count(*) FROM sms_dispatch_logs
                    WHERE status IN ('reserved', 'dispatched', 'ambiguous_timeout')
                      AND datetime(created_at) >= datetime(:rolling_start)
                      AND rowid <= :my_rowid
                """),
                {
                    "rolling_start": rolling_str,
                    "my_rowid": my_rowid,
                },
            ).scalar()

            if global_rank and global_rank > self.settings.daily_sms_cap:
                logger.warning(
                    f"[OtpService] Global SMS cap exceeded after admission contention (rank={global_rank}, cap={self.settings.daily_sms_cap})."
                )
                dispatch_log.status = SmsDispatchStatus.FAILED.value
                dispatch_log.error_detail = "Daily SMS limit exceeded (concurrency contention)"
                db.commit()
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Daily SMS delivery limit reached. Please try again tomorrow.",
                )

            # 3. Per-phone cap admission
            phone_rank = db.execute(
                text("""
                    SELECT count(*) FROM sms_dispatch_logs
                    WHERE phone_hash = :phone_hash
                      AND status IN ('reserved', 'dispatched', 'ambiguous_timeout')
                      AND datetime(created_at) >= datetime(:rolling_start)
                      AND rowid <= :my_rowid
                """),
                {
                    "phone_hash": phone_hash,
                    "rolling_start": rolling_str,
                    "my_rowid": my_rowid,
                },
            ).scalar()

            if phone_rank and phone_rank > self.settings.daily_phone_sms_cap:
                logger.warning(
                    f"[OtpService] Per-phone SMS cap exceeded after admission contention (rank={phone_rank}, cap={self.settings.daily_phone_sms_cap})."
                )
                dispatch_log.status = SmsDispatchStatus.FAILED.value
                dispatch_log.error_detail = "Daily phone SMS limit exceeded (concurrency contention)"
                db.commit()
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Daily OTP limit exceeded for this phone number. Please try again tomorrow.",
                )

        # 4b. Challenge Creation & Replacement (ONLY for winning contender that passed admission)
        # Invalidate older unused challenges for this phone
        db.query(OtpChallengeDB).filter(
            OtpChallengeDB.phone == clean_phone,
            OtpChallengeDB.used == False,
        ).update({"used": True})

        # Generate random OTP
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
        db.refresh(challenge)

        # 5. External SMS dispatch using per-dispatch outcome (committed before external call;
        # no database locks held during network I/O)
        sent = False
        is_timeout = False
        is_ambiguous = False
        error_detail = None

        try:
            if hasattr(self.sms_provider, "send_otp_with_outcome"):
                outcome = await self.sms_provider.send_otp_with_outcome(clean_phone, otp)
                sent = outcome.success
                is_timeout = outcome.is_timeout
                is_ambiguous = outcome.is_ambiguous or outcome.is_timeout
                error_detail = outcome.error_detail
            else:
                sent = await self.sms_provider.send_otp(clean_phone, otp)
                is_timeout = bool(getattr(self.sms_provider, "last_was_timeout", False))
                is_ambiguous = is_timeout
                error_detail = None
        except httpx.TimeoutException as e:
            sent = False
            is_timeout = True
            is_ambiguous = True
            error_detail = f"Gateway timeout: {e}"
        except httpx.ReadError as e:
            sent = False
            is_ambiguous = True
            error_detail = f"Gateway read error post-dispatch: {e}"
        except Exception as e:
            sent = False
            is_ambiguous = isinstance(e, httpx.HTTPError) and not isinstance(e, (httpx.ConnectError, httpx.ConnectTimeout))
            error_detail = str(e)

        if not sent:
            challenge.used = True
            challenge.attempts = 3
            if is_ambiguous or is_timeout:
                dispatch_log.status = SmsDispatchStatus.AMBIGUOUS_TIMEOUT.value
                dispatch_log.error_detail = error_detail or "Ambiguous delivery (timeout or read error)"
                db.commit()
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="SMS delivery timed out or could not be verified. Please try again later.",
                )
            else:
                dispatch_log.status = SmsDispatchStatus.FAILED.value
                dispatch_log.error_detail = error_detail or "SMS dispatch failed"
                db.commit()
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="SMS delivery failed. Please try again later.",
                )

        # Dispatch succeeded
        dispatch_log.status = SmsDispatchStatus.DISPATCHED.value
        db.commit()

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
