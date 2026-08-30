"""
Health and Status Router.
"""

from fastapi import APIRouter
from ..config import get_settings

router = APIRouter(prefix="/api/v1/health", tags=["Health"])
settings = get_settings()


@router.get("")
async def health_check():
    """Service health and version status."""
    return {
        "status": "healthy",
        "app_name": settings.app_name,
        "version": settings.app_version,
        "mode": "development" if settings.debug else "production",
    }
