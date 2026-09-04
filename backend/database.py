"""
Database Configuration and Session Management.

Uses SQLite with SQLAlchemy 2.0. Creates tables on startup.
"""

from typing import Generator
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker, Session

from .config import get_settings

settings = get_settings()

# Connect SQLite engine
engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False} if "sqlite" in settings.database_url else {},
    echo=settings.debug,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db() -> Generator[Session, None, None]:
    """FastAPI Dependency for database sessions."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """Create all tables (ArtisanDB + ProductDB)."""
    # Import models so SQLAlchemy registers them with Base.metadata
    from .models.db_models import ArtisanDB, ProductDB  # noqa: F401

    Base.metadata.create_all(bind=engine)
