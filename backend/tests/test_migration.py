"""
Alembic migration isolated test.
Tests upgrading an isolated legacy SQLite database to the current revision,
verifying that legacy 'live' rows transition to 'legacy_unverified' without
fabricated approval timestamps or approver identities.
"""

import os
from pathlib import Path
import tempfile
import pytest
from sqlalchemy import create_engine, text
from alembic.config import Config
from alembic import command


def _get_alembic_config(db_url: str) -> Config:
    backend_dir = Path(__file__).resolve().parent.parent
    ini_path = backend_dir / "alembic.ini"
    cfg = Config(str(ini_path))
    cfg.set_main_option("sqlalchemy.url", db_url)
    cfg.set_main_option("script_location", str(backend_dir / "alembic"))
    return cfg


@pytest.fixture
def isolated_legacy_db():
    fd, db_path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    db_url = f"sqlite:///{db_path}"

    engine = create_engine(db_url)
    with engine.connect() as conn:
        conn.execute(
            text(
                """
                CREATE TABLE artisans (
                    id VARCHAR(64) PRIMARY KEY,
                    name VARCHAR(128) NOT NULL,
                    phone VARCHAR(32) NOT NULL,
                    craft_type VARCHAR(128) DEFAULT 'Handicraft',
                    location_cluster VARCHAR(128) DEFAULT 'India',
                    preferred_language VARCHAR(8) DEFAULT 'en',
                    upi_id VARCHAR(64) DEFAULT '',
                    created_at DATETIME
                );
                """
            )
        )
        conn.execute(
            text(
                """
                CREATE TABLE products (
                    id VARCHAR(64) PRIMARY KEY,
                    artisan_id VARCHAR(64),
                    title VARCHAR(256) NOT NULL,
                    title_hi VARCHAR(256) DEFAULT '',
                    description TEXT DEFAULT '',
                    description_hi TEXT DEFAULT '',
                    price FLOAT NOT NULL,
                    image_url VARCHAR(512) DEFAULT '',
                    category VARCHAR(128) DEFAULT 'General',
                    tags TEXT DEFAULT '[]',
                    status VARCHAR(32) DEFAULT 'live',
                    created_at DATETIME,
                    updated_at DATETIME,
                    FOREIGN KEY(artisan_id) REFERENCES artisans(id)
                );
                """
            )
        )
        conn.execute(
            text(
                """
                INSERT INTO artisans (id, name, phone, created_at)
                VALUES ('artisan_mig_1', 'Legacy Artisan', '+919999988888', CURRENT_TIMESTAMP);
                """
            )
        )
        conn.execute(
            text(
                """
                INSERT INTO products (id, artisan_id, title, price, status, created_at)
                VALUES ('prod_legacy_1', 'artisan_mig_1', 'Legacy Brass Pot', 350.50, 'live', CURRENT_TIMESTAMP);
                """
            )
        )
        conn.commit()

    yield db_path, db_url
    if os.path.exists(db_path):
        os.remove(db_path)


def test_alembic_upgrade_migrates_legacy_rows(isolated_legacy_db):
    db_path, db_url = isolated_legacy_db

    # Configure Alembic to use the isolated database
    alembic_cfg = _get_alembic_config(db_url)

    # Run Alembic upgrade head
    command.upgrade(alembic_cfg, "head")

    # Verify schema and data transformations
    engine = create_engine(db_url)
    with engine.connect() as conn:
        # 1. Verify tables exist
        tables = conn.execute(text("SELECT name FROM sqlite_master WHERE type='table';")).scalars().all()
        assert "media_assets" in tables
        assert "otp_challenges" in tables
        assert "products" in tables

        # 2. Verify legacy row migration
        row = conn.execute(
            text(
                """
                SELECT id, price, price_paise, status, revision, content_hash,
                       approved_revision, approved_at, approved_by_artisan_id, published_at
                FROM products WHERE id = 'prod_legacy_1';
                """
            )
        ).mappings().first()

        assert row is not None
        assert row["id"] == "prod_legacy_1"
        assert row["price_paise"] == 35050
        assert row["status"] == "legacy_unverified", "Legacy live products must become legacy_unverified"
        assert row["revision"] == 1
        assert len(row["content_hash"]) == 64
        # CRITICAL INVARIANT: No fabricated approval metadata
        assert row["approved_revision"] is None
        assert row["approved_at"] is None
        assert row["approved_by_artisan_id"] is None
        assert row["published_at"] is None

        # 3. Verify product_revisions and idempotency_records tables exist
        assert "product_revisions" in tables
        assert "idempotency_records" in tables

        # 4. Verify is_deleted column exists on products
        columns = [c[1] for c in conn.execute(text("PRAGMA table_info(products);")).fetchall()]
        assert "is_deleted" in columns


def test_fresh_db_alembic_upgrade_head():
    """Tests upgrading a completely empty database from scratch to head."""
    fd, db_path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    db_url = f"sqlite:///{db_path}"

    try:
        alembic_cfg = _get_alembic_config(db_url)

        # Run Alembic upgrade head on completely fresh DB
        command.upgrade(alembic_cfg, "head")

        engine = create_engine(db_url)
        with engine.connect() as conn:
            tables = conn.execute(text("SELECT name FROM sqlite_master WHERE type='table';")).scalars().all()
            assert "artisans" in tables
            assert "products" in tables
            assert "media_assets" in tables
            assert "otp_challenges" in tables
            assert "product_revisions" in tables
            assert "idempotency_records" in tables

            # Verify schema version
            version = conn.execute(text("SELECT version_num FROM alembic_version;")).scalar()
            assert version == "0004_sms_dispatch_logs"

            # Verify media_assets has lineage columns
            media_cols = [c[1] for c in conn.execute(text("PRAGMA table_info(media_assets);")).fetchall()]
            assert "source_media_id" in media_cols
            assert "is_degraded" in media_cols
            assert "degraded_reason" in media_cols

            # Verify sms_dispatch_logs table and columns
            assert "sms_dispatch_logs" in tables
            sms_cols = [c[1] for c in conn.execute(text("PRAGMA table_info(sms_dispatch_logs);")).fetchall()]
            assert "id" in sms_cols
            assert "phone_hash" in sms_cols
            assert "status" in sms_cols
            assert "provider" in sms_cols
            assert "created_at" in sms_cols
            assert "error_detail" in sms_cols
    finally:
        if os.path.exists(db_path):
            os.remove(db_path)


def test_already_stamped_0001_db_upgrades_to_0004_and_downgrades(isolated_legacy_db):
    """Tests upgrading a database that was already stamped at 0001 to 0004 (head), and testing downgrade/re-upgrade."""
    db_path, db_url = isolated_legacy_db

    alembic_cfg = _get_alembic_config(db_url)

    # 1. Upgrade to 0001
    command.upgrade(alembic_cfg, "0001_artisan_approval_and_media")

    engine = create_engine(db_url)
    with engine.connect() as conn:
        version = conn.execute(text("SELECT version_num FROM alembic_version;")).scalar()
        assert version == "0001_artisan_approval_and_media"

    # 2. Upgrade from 0001 to head (0004)
    command.upgrade(alembic_cfg, "head")

    with engine.connect() as conn:
        version = conn.execute(text("SELECT version_num FROM alembic_version;")).scalar()
        assert version == "0004_sms_dispatch_logs"

        tables = conn.execute(text("SELECT name FROM sqlite_master WHERE type='table';")).scalars().all()
        assert "product_revisions" in tables
        assert "idempotency_records" in tables
        assert "sms_dispatch_logs" in tables
        media_cols = [c[1] for c in conn.execute(text("PRAGMA table_info(media_assets);")).fetchall()]
        assert "source_media_id" in media_cols
        assert "is_degraded" in media_cols
        assert "degraded_reason" in media_cols

    # 3. Test downgrade to 0003
    command.downgrade(alembic_cfg, "0003_media_asset_lineage_and_degradation")
    with engine.connect() as conn:
        version = conn.execute(text("SELECT version_num FROM alembic_version;")).scalar()
        assert version == "0003_media_asset_lineage_and_degradation"
        tables = conn.execute(text("SELECT name FROM sqlite_master WHERE type='table';")).scalars().all()
        assert "sms_dispatch_logs" not in tables

    # 4. Re-upgrade back to head
    command.upgrade(alembic_cfg, "head")
    with engine.connect() as conn:
        version = conn.execute(text("SELECT version_num FROM alembic_version;")).scalar()
        assert version == "0004_sms_dispatch_logs"
        tables = conn.execute(text("SELECT name FROM sqlite_master WHERE type='table';")).scalars().all()
        assert "sms_dispatch_logs" in tables

