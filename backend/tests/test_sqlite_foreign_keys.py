"""
SQLite Foreign Key Enforcement Tests.
Verifies that SQLite PRAGMA foreign_keys=ON is active on all engine connections
and rejects broken references with IntegrityError.
"""

import uuid
import pytest
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from backend.database import SessionLocal, init_db, engine
from backend.models.db_models import ProductDB, MediaAssetDB, ArtisanDB, ProductStatus


@pytest.fixture(scope="module")
def db_session():
    init_db()
    db = SessionLocal()
    # Ensure a test artisan exists
    artisan = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_fk_test").first()
    if not artisan:
        artisan = ArtisanDB(
            id="artisan_fk_test",
            name="FK Test Artisan",
            phone="+919876540001",
            craft_type="Pottery",
        )
        db.add(artisan)
        db.commit()
    yield db
    db.close()


def test_sqlite_foreign_keys_pragma_enabled():
    """Verify that SQLite connection pragma foreign_keys is ON (1)."""
    with engine.connect() as conn:
        result = conn.execute(text("PRAGMA foreign_keys;")).scalar()
        assert result == 1, "PRAGMA foreign_keys must be enabled (1) on SQLite connections"


def test_invalid_media_id_foreign_key_rejected(db_session):
    """Verify that assigning a non-existent media_id raises IntegrityError."""
    fake_media_id = f"nonexistent_{uuid.uuid4().hex}"
    invalid_product = ProductDB(
        id=f"prod_fk_invalid_{uuid.uuid4().hex[:8]}",
        artisan_id="artisan_fk_test",
        title="Test FK Violation",
        description="Should fail",
        legacy_price=500.0,
        price_paise=50000,
        status=ProductStatus.DRAFT.value,
        media_id=fake_media_id,
        revision=1,
    )

    db_session.add(invalid_product)
    with pytest.raises(IntegrityError):
        db_session.commit()

    db_session.rollback()


def test_valid_media_id_foreign_key_accepted(db_session):
    """Verify that assigning an existing media_id succeeds."""
    valid_media_id = f"media_{uuid.uuid4().hex[:12]}"
    media = MediaAssetDB(
        id=valid_media_id,
        artisan_id="artisan_fk_test",
        file_path=f"/fake/path/{valid_media_id}.jpg",
        file_url=f"/uploads/{valid_media_id}.jpg",
        mime_type="image/jpeg",
        byte_size=1024,
        sha256_checksum="abc123def456",
        status="ready",
    )
    db_session.add(media)
    db_session.commit()

    valid_product = ProductDB(
        id=f"prod_fk_valid_{uuid.uuid4().hex[:8]}",
        artisan_id="artisan_fk_test",
        title="Test FK Success",
        description="Should succeed",
        legacy_price=500.0,
        price_paise=50000,
        status=ProductStatus.DRAFT.value,
        media_id=valid_media_id,
        revision=1,
    )
    db_session.add(valid_product)
    db_session.commit()

    assert valid_product.id is not None
    assert valid_product.media_id == valid_media_id
