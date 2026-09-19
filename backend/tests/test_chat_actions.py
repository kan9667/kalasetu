"""
Tests for KalaMitra Direct Action Execution (Tool Calling).
"""

from fastapi.testclient import TestClient
from backend.main import app
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB
from backend.utils.auth import create_access_token

init_db()
_db = SessionLocal()
if not _db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_chat_test").first():
    _db.add(ArtisanDB(id="artisan_chat_test", name="Chat Artisan", phone="9876543230"))
    _db.commit()
_db.close()

from backend.tests.conftest import IdempotentTestClient
token = create_access_token("artisan_chat_test")
client = IdempotentTestClient(app, headers={"Authorization": f"Bearer {token}"})


def test_action_update_product_status():
    """Verify 'Mark my Chanderi Saree as sold' triggers update_product_status action."""
    res = client.post(
        "/api/v1/chat/message",
        json={
            "message": "Mark my Chanderi Saree as sold",
            "language_code": "en",
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert "action" in data and data["action"] is not None
    action = data["action"]
    assert action["type"] == "update_product_status"
    assert "params" in action and action["params"] is not None
    assert action["params"]["status"] == "sold"
    assert "chanderi saree" in action["params"]["target_product"].lower()
    print("✅ Status Update Action Passed:", action)


def test_action_filter_catalogue():
    """Verify 'Show me all my brass items' triggers filter_catalogue action."""
    res = client.post(
        "/api/v1/chat/message",
        json={
            "message": "Show me all my brass items",
            "language_code": "en",
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert "action" in data and data["action"] is not None
    action = data["action"]
    assert action["type"] == "filter_catalogue"
    assert action["params"] is not None
    assert "brass" in action["params"]["query"].lower()
    print("✅ Filter Catalogue Action Passed:", action)


def test_action_sync_pending():
    """Verify 'Sync my pending offline products now' triggers sync_pending action."""
    res = client.post(
        "/api/v1/chat/message",
        json={
            "message": "Sync my pending offline products now",
            "language_code": "en",
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert "action" in data and data["action"] is not None
    action = data["action"]
    assert action["type"] == "sync_pending"
    print("✅ Sync Pending Action Passed:", action)


def test_action_hindi_sold():
    """Verify Hindi utterance 'चंदेरी साड़ी बिक गया' emits update_product_status."""
    res = client.post(
        "/api/v1/chat/message",
        json={
            "message": "चंदेरी साड़ी बिक गया",
            "language_code": "hi",
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert "action" in data and data["action"] is not None
    assert data["action"]["type"] == "update_product_status"
    print("✅ Hindi Status Update Action Passed:", data["action"])
