from .health import router as health_router
from .pricing import router as pricing_router
from .products import router as products_router
from .catalog import router as catalog_router
from .auth import router as auth_router
from .voice import router as voice_router
from .social import router as social_router

__all__ = [
    "health_router",
    "pricing_router",
    "products_router",
    "catalog_router",
    "auth_router",
    "voice_router",
    "social_router",
]
