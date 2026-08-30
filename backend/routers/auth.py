"""
Authentication and User Profile Router for KalaSetu.
"""

from typing import Optional
from datetime import datetime
from pydantic import BaseModel, Field
from fastapi import APIRouter, HTTPException, status

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication & Artisans"])


class ArtisanRegisterRequest(BaseModel):
    name: str = Field(..., description="Artisan full name")
    phone: str = Field(..., description="10-digit mobile number")
    craft_type: str = Field(..., description="Primary craft category")
    location_cluster: str = Field(..., description="Artisan cluster / town location")
    state: Optional[str] = Field(default="", description="State / Region")
    experience_years: Optional[str] = Field(default=None, description="Craft experience in years")
    pehchan_id: Optional[str] = Field(default=None, description="Pehchan card / Artisan ID")
    preferred_language: Optional[str] = Field(default="en", description="Preferred app language")


class ArtisanLoginRequest(BaseModel):
    phone: str = Field(..., description="10-digit mobile number")


class OtpVerifyRequest(BaseModel):
    phone: str = Field(..., description="10-digit mobile number")
    otp: str = Field(..., description="6-digit OTP code")


class ArtisanProfileResponse(BaseModel):
    id: str
    name: str
    phone: str
    craft_type: str
    location_cluster: str
    state: str
    experience_years: Optional[str] = None
    pehchan_id: Optional[str] = None
    preferred_language: str
    created_at: datetime


# In-memory mock store for demo sessions
_ARTISAN_PROFILES = {}


@router.post(
    "/register",
    status_code=status.HTTP_201_CREATED,
    summary="Register a new artisan",
    description="Registers a new artisan profile with craft details and initiates phone verification.",
)
async def register_artisan(request: ArtisanRegisterRequest):
    phone_clean = request.phone.strip()
    if len(phone_clean) < 10:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid phone number. Must be at least 10 digits.",
        )

    artisan_id = f"artisan_{int(datetime.now().timestamp())}"
    profile = {
        "id": artisan_id,
        "name": request.name,
        "phone": phone_clean,
        "craft_type": request.craft_type,
        "location_cluster": request.location_cluster,
        "state": request.state or "",
        "experience_years": request.experience_years,
        "pehchan_id": request.pehchan_id,
        "preferred_language": request.preferred_language or "en",
        "created_at": datetime.now(),
    }
    _ARTISAN_PROFILES[phone_clean] = profile

    return {
        "status": "success",
        "message": "Artisan registered successfully. OTP sent for phone verification.",
        "user_id": artisan_id,
        "phone": phone_clean,
        "otp_sent": True,
        "demo_otp": "123456",
    }


@router.post(
    "/login",
    summary="Request login OTP",
    description="Requests an OTP for an existing registered phone number.",
)
async def login_artisan(request: ArtisanLoginRequest):
    phone_clean = request.phone.strip()
    if len(phone_clean) < 10:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid phone number.",
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
async def verify_otp(request: OtpVerifyRequest):
    phone_clean = request.phone.strip()
    # In demo mode, accept 123456 or any 6-digit OTP
    if len(request.otp) != 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid OTP format. Must be 6 digits.",
        )

    profile = _ARTISAN_PROFILES.get(
        phone_clean,
        {
            "id": f"artisan_{int(datetime.now().timestamp())}",
            "name": "Artisan",
            "phone": phone_clean,
            "craft_type": "Terracotta Pottery",
            "location_cluster": "Kumhar Gram",
            "state": "Delhi",
            "experience_years": "5",
            "pehchan_id": None,
            "preferred_language": "en",
            "created_at": datetime.now(),
        },
    )

    return {
        "status": "success",
        "access_token": f"mock_jwt_token_{phone_clean}",
        "token_type": "bearer",
        "artisan": profile,
    }
