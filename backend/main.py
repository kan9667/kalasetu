"""
KalaSetu FastAPI Application Entrypoint.

AI-Driven Market Linkage & Smart Cataloging Backend for Marginalized Artisans.
"""

import sys
from pathlib import Path
from contextlib import asynccontextmanager

# Fix Windows console encoding for emoji output
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# Ensure project root is in sys.path when running directly
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from backend.config import get_settings, ensure_upload_dir
from backend.database import init_db
from backend.routers import (
    health_router,
    pricing_router,
    products_router,
    catalog_router,
    auth_router,
    voice_router,
)

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application startup and shutdown event lifecycle."""
    # 1. Ensure upload directory exists
    ensure_upload_dir()
    
    # 2. Initialize database tables (artisans + products)
    init_db()

    print("\n" + "=" * 60)
    print(f"  ✨ {settings.app_name} v{settings.app_version} Started")
    print(f"  📖 Swagger UI Docs: http://localhost:{settings.port}/docs")
    print(f"  🔍 Health Status:   http://localhost:{settings.port}/api/v1/health")
    print(f"  🎙️ Voice Pipeline:  http://localhost:{settings.port}/api/v1/voice/process")
    print(f"  💰 Pricing Endpoint: http://localhost:{settings.port}/api/v1/pricing/suggest")
    print(f"  📦 Products API:    http://localhost:{settings.port}/api/v1/products")
    print("=" * 60 + "\n")

    yield


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description=settings.app_description,
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# ── CORS Middleware (Permissive for Flutter Web & Mobile) ────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=settings.cors_allow_credentials,
    allow_methods=settings.cors_allow_methods,
    allow_headers=settings.cors_allow_headers,
)

# ── Mount Uploaded Static Files ──────────────────────────────────────────────
upload_path = ensure_upload_dir()
app.mount(settings.static_url_prefix, StaticFiles(directory=str(upload_path)), name="uploads")

# ── Register Routers ─────────────────────────────────────────────────────────
app.include_router(health_router)
app.include_router(voice_router)
app.include_router(pricing_router)
app.include_router(products_router)
app.include_router(catalog_router)
app.include_router(auth_router)


@app.get("/", tags=["Root"])
async def root():
    """Welcome index endpoint."""
    return {
        "message": "Welcome to KalaSetu API Gateway",
        "version": settings.app_version,
        "docs": "/docs",
        "health": "/api/v1/health",
        "voice_pipeline": "/api/v1/voice/process",
        "pricing_status": "/api/v1/pricing/status",
        "products": "/api/v1/products",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=settings.port,
    )
