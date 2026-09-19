"""
Authentication and User Profile Router for KalaSetu.

Enforces:
- Real cryptographic OTP challenge lifecycle (salted SHA-256, expiration, attempts limit, single-use).
- Rate-limiting (per-phone and per-IP).
- Signed HS256 JWT token issuance.
- Tenant ownership checks on profile lookup.
"""

import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.db_models import ArtisanDB
from ..models.schemas import (
    ArtisanRegisterRequest,
    ArtisanLoginRequest,
    OtpVerifyRequest,
    ArtisanProfileResponse,
)
from ..services.otp_service import OtpService, validate_indian_phone
from ..utils.auth import create_access_token, get_current_artisan

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication & Artisans"])
otp_service = OtpService()


@router.post(
    "/register",
    response_model=ArtisanProfileResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new artisan",
    description="Registers a new artisan profile with craft details.",
)
async def register_artisan(
    request: ArtisanRegisterRequest,
    db: Session = Depends(get_db),
):
    phone_clean = validate_indian_phone(request.phone)

    # Check if phone already registered
    existing = db.query(ArtisanDB).filter(ArtisanDB.phone == phone_clean).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An artisan with this phone number is already registered.",
        )

    artisan = ArtisanDB(
        id=f"artisan_{uuid.uuid4().hex[:10]}",
        name=request.name,
        phone=phone_clean,
        craft_type=request.craft_type,
        location_cluster=request.location_cluster,
        state=request.state or "",
        experience_years=request.experience_years or "",
        pehchan_id=request.pehchan_id,
        preferred_language=request.preferred_language or "en",
        created_at=datetime.now(timezone.utc),
    )
    db.add(artisan)
    db.commit()
    db.refresh(artisan)

    return artisan


@router.post(
    "/login",
    summary="Request login OTP",
    description="Requests a secure OTP challenge for an existing registered phone number.",
)
async def login_artisan(
    payload: ArtisanLoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    phone_clean = validate_indian_phone(payload.phone)

    # Verify phone exists in database
    artisan = db.query(ArtisanDB).filter(ArtisanDB.phone == phone_clean).first()
    if not artisan:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No artisan registered with this phone number.",
        )

    client_ip = request.client.host if request.client else "127.0.0.1"
    challenge_result = await otp_service.create_challenge(db, phone_clean, client_ip=client_ip)
    return challenge_result


@router.post(
    "/verify-otp",
    summary="Verify phone OTP",
    description="Validates cryptographic OTP challenge and issues signed JWT bearer token.",
)
async def verify_otp(
    payload: OtpVerifyRequest,
    db: Session = Depends(get_db),
):
    phone_clean = validate_indian_phone(payload.phone)
    if len(payload.otp) != 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid OTP format. Must be 6 digits.",
        )

    artisan = db.query(ArtisanDB).filter(ArtisanDB.phone == phone_clean).first()
    if not artisan:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No artisan registered with this phone number. Please register first.",
        )

    # Verify cryptographic challenge
    otp_service.verify_challenge(db, phone_clean, payload.otp)

    # Issue cryptographically signed HS256 JWT
    token = create_access_token(artisan.id)

    return {
        "status": "success",
        "access_token": token,
        "token_type": "bearer",
        "artisan": ArtisanProfileResponse.model_validate(artisan).model_dump(),
    }


@router.get(
    "/profile/{artisan_id}",
    response_model=ArtisanProfileResponse,
    summary="Get artisan profile",
    description="Fetch artisan profile with ownership enforcement.",
)
async def get_artisan_profile(
    artisan_id: str,
    authenticated_artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    # Enforce tenant isolation
    if authenticated_artisan.id != artisan_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You cannot access another artisan's profile.",
        )

    return authenticated_artisan
