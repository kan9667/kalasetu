import sys
import os
import shutil
import tempfile
import uuid
from pathlib import Path
from typing import Optional, Union
import pytest
from starlette.testclient import TestClient


def validate_engine_storage(eng, storage_dir: Union[str, Path]) -> None:
    """Fail closed if database engine points outside test-owned storage."""
    if eng is None or not hasattr(eng, "url") or not eng.url or not eng.url.database:
        return
    if eng.url.database == ":memory:":
        return
    db_path = Path(eng.url.database).resolve()
    storage_path = Path(storage_dir).resolve()
    try:
        is_inside = db_path.is_relative_to(storage_path)
    except AttributeError:
        is_inside = storage_path in db_path.parents
    if not is_inside:
        raise RuntimeError(
            f"Fail-closed: Database engine points outside test-owned storage: "
            f"{db_path} (test storage: {storage_path})"
        )


def safe_cleanup_test_storage(storage_dir: Union[str, Path, None]) -> bool:
    """Safely delete process-owned test storage, strictly verifying it is inside system temp."""
    if not storage_dir:
        return False
    try:
        resolved = Path(storage_dir).resolve()
        system_temp = Path(tempfile.gettempdir()).resolve()
        try:
            is_inside = resolved.is_relative_to(system_temp)
        except AttributeError:
            is_inside = system_temp in resolved.parents
        if is_inside and resolved != system_temp and resolved.exists():
            shutil.rmtree(resolved, ignore_errors=True)
            return True
    except Exception:
        pass
    return False


# 1. Establish isolated storage directory before importing any backend modules
# Guard with process-local attribute to prevent re-initialization within the same test process.
# An inherited KALASETU_TEST_STORAGE_DIR in os.environ must NOT bypass isolation.
if not hasattr(sys, "_kalasetu_test_storage_dir"):
    _created_storage_dir = tempfile.mkdtemp(prefix="kalasetu_test_storage_")
    sys._kalasetu_test_storage_dir = _created_storage_dir

    _TEST_STORAGE_DIR = _created_storage_dir
    _TEST_DB_PATH = Path(_TEST_STORAGE_DIR) / "test_kalasetu.db"
    _TEST_UPLOAD_DIR = Path(_TEST_STORAGE_DIR) / "uploads"
    _TEST_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

    # Save original environment variables to restore in session teardown
    sys._kalasetu_orig_env = {
        "ENVIRONMENT": os.environ.get("ENVIRONMENT"),
        "DATABASE_URL": os.environ.get("DATABASE_URL"),
        "UPLOAD_DIR": os.environ.get("UPLOAD_DIR"),
        "JWT_SECRET_KEY": os.environ.get("JWT_SECRET_KEY"),
        "ALLOW_DEMO_OTP": os.environ.get("ALLOW_DEMO_OTP"),
        "SMS_PROVIDER": os.environ.get("SMS_PROVIDER"),
        "ENABLE_REAL_SMS": os.environ.get("ENABLE_REAL_SMS"),
        "KALASETU_TEST_STORAGE_DIR": os.environ.get("KALASETU_TEST_STORAGE_DIR"),
    }

    os.environ["ENVIRONMENT"] = "test"
    os.environ["DATABASE_URL"] = f"sqlite:///{_TEST_DB_PATH}"
    os.environ["UPLOAD_DIR"] = str(_TEST_UPLOAD_DIR)
    os.environ["JWT_SECRET_KEY"] = "test_secret_key_32_characters_long_min"
    os.environ["ALLOW_DEMO_OTP"] = "true"
    os.environ["SMS_PROVIDER"] = "mock"
    os.environ["ENABLE_REAL_SMS"] = "false"
    os.environ["KALASETU_TEST_STORAGE_DIR"] = _TEST_STORAGE_DIR

    # Fail closed if backend.database was already imported before test isolation setup
    if "backend.database" in sys.modules:
        prev_engine = sys.modules["backend.database"].engine
        validate_engine_storage(prev_engine, _TEST_STORAGE_DIR)

    # Clear settings LRU cache to ensure isolated test env vars are loaded
    from backend.config import get_settings
    get_settings.cache_clear()

    # Initialize schema on isolated test database
    from sqlalchemy import text
    from backend.database import engine, Base, init_db
    import backend.models.db_models  # noqa: F401

    # Invariant: Verify engine.url points strictly inside _TEST_STORAGE_DIR
    validate_engine_storage(engine, _TEST_STORAGE_DIR)

    Base.metadata.create_all(bind=engine)
    with engine.connect() as conn:
        conn.execute(text("CREATE TABLE IF NOT EXISTS alembic_version (version_num VARCHAR(32) NOT NULL PRIMARY KEY);"))
        conn.execute(text("DELETE FROM alembic_version;"))
        conn.execute(text("INSERT INTO alembic_version (version_num) VALUES ('0004_sms_dispatch_logs');"))
        conn.commit()

    init_db()
else:
    _TEST_STORAGE_DIR = sys._kalasetu_test_storage_dir
    _TEST_DB_PATH = Path(_TEST_STORAGE_DIR) / "test_kalasetu.db"
    _TEST_UPLOAD_DIR = Path(_TEST_STORAGE_DIR) / "uploads"
    from backend.config import get_settings
    from backend.database import engine, Base, init_db

    validate_engine_storage(engine, _TEST_STORAGE_DIR)


@pytest.fixture(scope="session", autouse=True)
def isolate_test_storage():
    """Ensure backend tests never access or mutate developer storage."""
    yield
    # Cleanup must own the exact temporary directory created by THIS test process.
    # Never recursively delete a path obtained from an environment variable.
    created_dir = getattr(sys, "_kalasetu_test_storage_dir", None)
    if created_dir:
        try:
            from backend.database import engine
            engine.dispose()
        except Exception:
            pass

        safe_cleanup_test_storage(created_dir)

        try:
            delattr(sys, "_kalasetu_test_storage_dir")
        except AttributeError:
            pass

    orig_env = getattr(sys, "_kalasetu_orig_env", None)
    if orig_env:
        for k, v in orig_env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        try:
            delattr(sys, "_kalasetu_orig_env")
        except AttributeError:
            pass

    try:
        from backend.config import get_settings
        get_settings.cache_clear()
    except Exception:
        pass


@pytest.fixture
def make_idempotency_key():
    """Explicit helper fixture to generate unique Idempotency-Key headers for mutating calls."""
    def _key(prefix="test"):
        return f"{prefix}_{uuid.uuid4().hex}"
    return _key


class IdempotentTestClient(TestClient):
    """Explicit narrowly scoped TestClient helper for tests requiring auto-generated idempotency keys."""
    def request(self, method: str, url: str, *args, **kwargs):
        headers = dict(kwargs.pop("headers", None) or {})
        if method.upper() in ("POST", "PUT", "PATCH", "DELETE"):
            if "Idempotency-Key" not in headers and "idempotency-key" not in headers:
                headers["Idempotency-Key"] = f"test_idemp_{uuid.uuid4().hex}"
        return super().request(method, url, *args, headers=headers, **kwargs)


@pytest.fixture
def idempotent_client():
    from backend.main import app
    return IdempotentTestClient(app)
