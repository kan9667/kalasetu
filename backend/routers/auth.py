"""
Authentication and User Profile Router for KalaSetu.

Uses the ArtisanDB table for persistent artisan registration and lookup.
OTP verification is still demo-mode (accepts any 6-digit code).
"""

from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.db_models import ArtisanDB
from ..models.schemas import (
    ArtisanRegisterRequest,
    ArtisanLoginRequest,
    OtpVerifyRequest,
    ArtisanProfileResponse,
)

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication & Artisans"])


@router.post(
    "/register",
    response_model=ArtisanProfileResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new artisan",
    description="Registers a new artisan profile with craft details and initiates phone verification.",
)
async def register_artisan(
    request: ArtisanRegisterRequest,
    db: Session = Depends(get_db),
):
    phone_clean = request.phone.strip()
    if len(phone_clean) < 10:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid phone number. Must be at least 10 digits.",
        )

    # Check if phone already registered
    existing = db.query(ArtisanDB).filter(ArtisanDB.phone == phone_clean).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An artisan with this phone number is already registered.",
        )

    artisan = ArtisanDB(
        id=f"artisan_{int(datetime.now().timestamp())}",
        name=request.name,
        phone=phone_clean,
        craft_type=request.craft_type,
        location_cluster=request.location_cluster,
        state=request.state or "",
        experience_years=request.experience_years or "",
        pehchan_id=request.pehchan_id,
        preferred_language=request.preferred_language or "en",
        created_at=datetime.now(),
    )
    db.add(artisan)
    db.commit()
    db.refresh(artisan)

    return artisan


@router.post(
    "/login",
    summary="Request login OTP",
    description="Requests an OTP for an existing registered phone number.",
)
async def login_artisan(
    request: ArtisanLoginRequest,
    db: Session = Depends(get_db),
):
    phone_clean = request.phone.strip()
    if len(phone_clean) < 10:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid phone number.",
        )

    # Verify phone exists in database
    artisan = db.query(ArtisanDB).filter(ArtisanDB.phone == phone_clean).first()
    if not artisan:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No artisan registered with this phone number.",
        )

    return {
        "status": "success",
        "message": "OTP sent for login.",
        "phone": phone_clean,
        "otp_sent": True,
        "demo_otp": "123456",
    }


@router.post(
    "/verify-otp",
    summary="Verify phone OTP",
    description="Validates OTP and returns artisan session profile.",
)
async def verify_otp(
    request: OtpVerifyRequest,
    db: Session = Depends(get_db),
):
    phone_clean = request.phone.strip()
    if len(request.otp) != 6:
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

    return {
        "status": "success",
        "access_token": f"mock_jwt_token_{phone_clean}",
        "token_type": "bearer",
        "artisan": ArtisanProfileResponse.model_validate(artisan).model_dump(),
    }


@router.get(
    "/profile/{artisan_id}",
    response_model=ArtisanProfileResponse,
    summary="Get artisan profile",
    description="Fetch an artisan profile by their unique ID.",
)
async def get_artisan_profile(
    artisan_id: str,
    db: Session = Depends(get_db),
):
    artisan = db.query(ArtisanDB).filter(ArtisanDB.id == artisan_id).first()
    if not artisan:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Artisan not found.",
        )
    return artisan
