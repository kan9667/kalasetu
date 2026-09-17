"""
Crash-Safe Transactional Server Idempotency Utility.

Guarantees:
- Required Idempotency-Key header for all mutating API calls.
- Uniqueness scoped to (artisan_id, endpoint, idempotency_key).
- Atomic lease claiming with lease expiration to prevent deadlock on crashes.
- Concurrent claim protection returning HTTP 409 Conflict with Retry-After.
- Atomic commit of business mutation and completed response record.
- Rejection of payload tampering when key is reused with different inputs.
"""

import hashlib
import json
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Optional, Tuple

from fastapi import HTTPException, Request, Response, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models.db_models import IdempotencyRecordDB


def require_idempotency_key(request: Request) -> str:
    """Extract and validate required Idempotency-Key header."""
    key = request.headers.get("Idempotency-Key", "").strip()
    if not key:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Idempotency-Key header is required for this operation.",
        )
    return key


def compute_request_fingerprint(method: str, path: str, payload: Any) -> str:
    """Compute a deterministic SHA-256 fingerprint for a mutating request."""
    if isinstance(payload, dict):
        canonical_str = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    elif isinstance(payload, bytes):
        canonical_str = hashlib.sha256(payload).hexdigest()
    elif isinstance(payload, str):
        canonical_str = payload
    else:
        canonical_str = str(payload)

    combined = f"{method.upper()}:{path}:{canonical_str}"
    return hashlib.sha256(combined.encode("utf-8")).hexdigest()


def claim_idempotency(
    db: Session,
    artisan_id: str,
    endpoint: str,
    idempotency_key: str,
    request_hash: str,
    lease_seconds: int = 60,
) -> Tuple[bool, Optional[int], Optional[str]]:
    """
    Attempt to claim an idempotency key.

    Returns:
        (is_completed, cached_status_code, cached_response_body)
        If is_completed is True, the operation was already processed; replay the result.
        If is_completed is False, the lease was claimed; proceed with mutation.
    """
    now = datetime.now(timezone.utc)

    record = (
        db.query(IdempotencyRecordDB)
        .filter(
            IdempotencyRecordDB.artisan_id == artisan_id,
            IdempotencyRecordDB.endpoint == endpoint,
            IdempotencyRecordDB.idempotency_key == idempotency_key,
        )
        .first()
    )

    if record:
        if record.status == "completed":
            if record.request_hash != request_hash:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Idempotency key reused with mismatched request payload.",
                )
            return (True, record.response_status_code, record.response_body)

        if record.status == "in_progress":
            lease_exp = (
                record.lease_expires_at.replace(tzinfo=timezone.utc)
                if record.lease_expires_at.tzinfo is None
                else record.lease_expires_at
            )
            if now > lease_exp:
                # Expired lease: previous worker/connection died. Reclaim safely.
                record.lease_expires_at = now + timedelta(seconds=lease_seconds)
                record.request_hash = request_hash
                record.updated_at = now
                db.commit()
                return (False, None, None)

            # Active in-progress operation
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An operation with this idempotency key is currently in progress. Please retry shortly.",
                headers={"Retry-After": "5"},
            )

    # Insert new in-progress claim
    new_record = IdempotencyRecordDB(
        id=f"idem_{uuid.uuid4().hex[:12]}",
        artisan_id=artisan_id,
        idempotency_key=idempotency_key,
        endpoint=endpoint,
        request_hash=request_hash,
        status="in_progress",
        lease_expires_at=now + timedelta(seconds=lease_seconds),
        created_at=now,
        updated_at=now,
    )
    db.add(new_record)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        # Lost race to another concurrent request; recurse to handle safely
        return claim_idempotency(
            db, artisan_id, endpoint, idempotency_key, request_hash, lease_seconds
        )

    return (False, None, None)


def complete_idempotency(
    db: Session,
    artisan_id: str,
    endpoint: str,
    idempotency_key: str,
    status_code: int,
    response_data: Any,
) -> None:
    """
    Record completed response state on the active session before final commit.
    This guarantees atomic persistence with the underlying business transaction.
    """
    record = (
        db.query(IdempotencyRecordDB)
        .filter(
            IdempotencyRecordDB.artisan_id == artisan_id,
            IdempotencyRecordDB.endpoint == endpoint,
            IdempotencyRecordDB.idempotency_key == idempotency_key,
        )
        .first()
    )

    if record:
        record.status = "completed"
        record.response_status_code = status_code
        if isinstance(response_data, str):
            record.response_body = response_data
        else:
            record.response_body = json.dumps(response_data, default=str)
        record.updated_at = datetime.now(timezone.utc)


def release_idempotency_claim(
    db: Session,
    artisan_id: str,
    endpoint: str,
    idempotency_key: str,
) -> None:
    """Release an in-progress idempotency claim if validation fails before completion."""
    try:
        db.query(IdempotencyRecordDB).filter(
            IdempotencyRecordDB.artisan_id == artisan_id,
            IdempotencyRecordDB.endpoint == endpoint,
            IdempotencyRecordDB.idempotency_key == idempotency_key,
            IdempotencyRecordDB.status == "in_progress",
        ).delete()
        db.commit()
    except Exception:
        db.rollback()
