"""
Backend Test Isolation & Storage Invariant Tests.
Verifies:
- Process-owned test storage creation in system temp directory.
- Fail-closed validation if database engine points outside test-owned storage.
- Safe cleanup guarantees: never recursively deletes non-temp paths or system temp root.
- Verification that database engine and upload_dir strictly point inside test-owned storage.
"""

import os
import sys
import tempfile
from pathlib import Path
import pytest
from sqlalchemy import create_engine

from backend.config import get_settings
from backend.database import engine
from backend.tests.conftest import validate_engine_storage, safe_cleanup_test_storage


def test_active_test_storage_is_process_owned():
    """Verify that current test process owns a dedicated storage dir strictly inside system temp."""
    test_storage = getattr(sys, "_kalasetu_test_storage_dir", None)
    assert test_storage is not None, "sys._kalasetu_test_storage_dir must be set by conftest.py"

    storage_path = Path(test_storage).resolve()
    system_temp = Path(tempfile.gettempdir()).resolve()
    assert storage_path.is_relative_to(system_temp), "Test storage must reside inside system temp"
    assert storage_path != system_temp, "Test storage must not be system temp root"
    assert storage_path.exists(), "Test storage dir must exist on disk"


def test_database_engine_and_uploads_inside_test_storage():
    """Verify that the active SQLAlchemy engine and upload_dir reside strictly within test storage."""
    test_storage = Path(sys._kalasetu_test_storage_dir).resolve()

    # Engine database path
    assert engine.url.database is not None
    engine_db = Path(engine.url.database).resolve()
    assert engine_db.is_relative_to(test_storage), (
        f"Active engine database ({engine_db}) must be within test storage ({test_storage})"
    )

    # Upload dir path
    settings = get_settings()
    upload_dir = Path(settings.upload_dir).resolve()
    assert upload_dir.is_relative_to(test_storage), (
        f"Active upload_dir ({upload_dir}) must be within test storage ({test_storage})"
    )


def test_validate_engine_storage_fails_closed_on_outside_path(tmp_path):
    """Verify validate_engine_storage raises RuntimeError if engine points outside storage_dir."""
    outside_dir = tmp_path / "outside"
    outside_dir.mkdir()
    outside_db = outside_dir / "outside.sqlite"
    outside_engine = create_engine(f"sqlite:///{outside_db}")

    test_dir = tmp_path / "owned_test_dir"
    test_dir.mkdir()

    try:
        with pytest.raises(RuntimeError, match="Fail-closed: Database engine points outside test-owned storage"):
            validate_engine_storage(outside_engine, test_dir)
    finally:
        outside_engine.dispose()


def test_validate_engine_storage_allows_in_memory_and_inside_path(tmp_path):
    """Verify validate_engine_storage passes for in-memory and inside-storage databases."""
    inside_dir = tmp_path / "inside"
    inside_dir.mkdir()
    inside_db = inside_dir / "inside.sqlite"
    inside_engine = create_engine(f"sqlite:///{inside_db}")

    mem_engine = create_engine("sqlite:///:memory:")

    try:
        # Inside path succeeds
        validate_engine_storage(inside_engine, inside_dir)
        # Memory engine succeeds
        validate_engine_storage(mem_engine, inside_dir)
    finally:
        inside_engine.dispose()
        mem_engine.dispose()


def test_safe_cleanup_never_deletes_outside_system_temp(tmp_path):
    """Verify safe_cleanup_test_storage rejects directories outside system temp and never touches them."""
    # Create a non-temp mock path simulation (e.g. mock project path)
    # Never execute destructive cases against real directories
    fake_outside = Path("/nonexistent_or_protected/developer/kalasetu")
    assert not safe_cleanup_test_storage(fake_outside)

    # System temp root itself must never be deleted
    system_temp = Path(tempfile.gettempdir()).resolve()
    assert not safe_cleanup_test_storage(system_temp)
    assert not safe_cleanup_test_storage(None)


def test_safe_cleanup_deletes_owned_temp_directory():
    """Verify safe_cleanup_test_storage successfully removes a process-created temp folder."""
    created = tempfile.mkdtemp(prefix="kalasetu_test_cleanup_verify_")
    created_path = Path(created)
    assert created_path.exists()

    result = safe_cleanup_test_storage(created)
    assert result is True
    assert not created_path.exists()
