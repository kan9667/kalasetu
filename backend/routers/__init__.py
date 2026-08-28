"""Routers package."""

from .health import router as health_router
from .pricing import router as pricing_router
from .products import router as products_router
from .catalog import router as catalog_router

__all__ = [
    "health_router",
    "pricing_router",
    "products_router",
    "catalog_router",
]
