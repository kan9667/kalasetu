"""
Database Configuration and Session Management.

Uses SQLite with SQLAlchemy 2.0. Creates tables on startup.
"""

from typing import Generator
from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import declarative_base, sessionmaker, Session

from .config import get_settings

settings = get_settings()

# Connect SQLite engine
engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False} if "sqlite" in settings.database_url else {},
    echo=settings.debug,
)


@event.listens_for(Engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    """Enforce SQLite foreign key constraints."""
    if "sqlite" in settings.database_url:
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


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
    """Ensure baseline seed data (demo artisan) exists for local development and testing."""
    from .models.db_models import ArtisanDB
    from datetime import datetime

    # Ensure demo artisan exists so demo login and FK constraints always succeed
    db = SessionLocal()
    try:
        demo_phone = "9876543210"
        existing = db.query(ArtisanDB).filter(ArtisanDB.phone == demo_phone).first()
        if not existing:
            demo_artisan = ArtisanDB(
                id="artisan_01",
                name="Rameshwar Lal Kumhar",
                phone=demo_phone,
                craft_type="Terracotta Pottery",
                location_cluster="Kumhar Gram, Delhi NCR",
                state="Delhi",
                experience_years="25",
                pehchan_id="PEHCHAN-DL-0042",
                preferred_language="en",
                created_at=datetime.now(),
            )
            db.add(demo_artisan)
            db.commit()
    except Exception as e:
        db.rollback()
        print(f"Warning: Could not seed demo artisan: {e}")
    finally:
        db.close()
