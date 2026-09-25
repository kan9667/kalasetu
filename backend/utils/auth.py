"""
Authentication and JWT Verification Utilities.

Enforces:
- Pinned HS256 algorithm.
- Strict claim validation: sub, iat, exp, iss, aud.
- High-entropy secret key from Settings (validated on startup).
- get_current_artisan dependency rejecting missing/invalid/expired credentials.
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from ..config import get_settings
from ..database import get_db
from ..models.db_models import ArtisanDB

settings = get_settings()
security = HTTPBearer(auto_error=False)
JWT_ALGORITHM = settings.jwt_algorithm


def create_access_token(artisan_id: str, expires_delta: Optional[timedelta] = None) -> str:
    """
    Generate a signed JWT for the authenticated artisan.
    Strictly uses HS256 with issuer and audience claims.
    """
    now = datetime.now(timezone.utc)
    expire = now + (expires_delta or timedelta(minutes=settings.jwt_access_token_expire_minutes))

    payload = {
        "sub": artisan_id,
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": now,
        "exp": expire,
    }

    return jwt.encode(
        payload,
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )


def decode_access_token(token: str) -> dict:
    """
    Validate and decode JWT access token.
    Enforces algorithm HS256 and validates exp, iss, aud.
    """
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
            issuer=settings.jwt_issuer,
            audience=settings.jwt_audience,
            options={"require": ["exp", "iat", "sub", "iss", "aud"]},
        )
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication token has expired. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.InvalidTokenError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid authentication token: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )


def get_current_artisan(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> ArtisanDB:
    """
    FastAPI dependency for verifying authenticated artisan identity.
    Extracts Bearer token, validates signature/claims, and fetches ArtisanDB.
    """
    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required. Missing Bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_access_token(credentials.credentials)
    artisan_id = payload.get("sub")
    if not artisan_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing subject claim.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    artisan = db.query(ArtisanDB).filter(ArtisanDB.id == artisan_id).first()
    if not artisan:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Artisan account not found.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return artisan
