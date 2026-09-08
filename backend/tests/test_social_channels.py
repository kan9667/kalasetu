import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.database import get_db, Base, engine
from backend.models.db_models import SocialDraftDB

client = TestClient(app)

def test_independent_channels_generation_and_lookup():
    # 1. Generate WhatsApp draft
    wa_payload = {
        "image_url": "https://example.com/test_pottery.jpg",
        "listing_id": "prod_test_123",
        "title": "Terracotta Chai Cup",
        "category": "Pottery",
        "materials": ["Clay", "Terracotta"],
        "channel": "whatsapp",
    }
    res_wa = client.post("/api/v1/social-drafts/generate", json=wa_payload)
    assert res_wa.status_code == 200, res_wa.text
    data_wa = res_wa.json()
    assert "draft_id" in data_wa
    assert len(data_wa["hashtags"]) <= 2

    # 2. Generate Instagram draft for SAME product & image
    ig_payload = {
        "image_url": "https://example.com/test_pottery.jpg",
        "listing_id": "prod_test_123",
        "title": "Terracotta Chai Cup",
        "category": "Pottery",
        "materials": ["Clay", "Terracotta"],
        "channel": "instagram",
    }
    res_ig = client.post("/api/v1/social-drafts/generate", json=ig_payload)
    assert res_ig.status_code == 200, res_ig.text
    data_ig = res_ig.json()
    assert data_ig["draft_id"] != data_wa["draft_id"]
    assert len(data_ig["hashtags"]) >= 3

    # 3. Generate Facebook draft for SAME product & image
    fb_payload = {
        "image_url": "https://example.com/test_pottery.jpg",
        "listing_id": "prod_test_123",
        "title": "Terracotta Chai Cup",
        "category": "Pottery",
        "materials": ["Clay", "Terracotta"],
        "channel": "facebook",
    }
    res_fb = client.post("/api/v1/social-drafts/generate", json=fb_payload)
    assert res_fb.status_code == 200, res_fb.text
    data_fb = res_fb.json()
    assert data_fb["draft_id"] != data_wa["draft_id"]
    assert data_fb["draft_id"] != data_ig["draft_id"]

    # 4. Independent Lookup Tests
    # Lookup WhatsApp
    lookup_wa = client.get(
        "/api/v1/social-drafts/lookup",
        params={
            "image_url": "https://example.com/test_pottery.jpg",
            "listing_id": "prod_test_123",
            "channel": "whatsapp",
        },
    )
    assert lookup_wa.status_code == 200
    assert lookup_wa.json()["draft_id"] == data_wa["draft_id"]

    # Lookup Instagram
    lookup_ig = client.get(
        "/api/v1/social-drafts/lookup",
        params={
            "image_url": "https://example.com/test_pottery.jpg",
            "listing_id": "prod_test_123",
            "channel": "instagram",
        },
    )
    assert lookup_ig.status_code == 200
    assert lookup_ig.json()["draft_id"] == data_ig["draft_id"]

    # Lookup Facebook
    lookup_fb = client.get(
        "/api/v1/social-drafts/lookup",
        params={
            "image_url": "https://example.com/test_pottery.jpg",
            "listing_id": "prod_test_123",
            "channel": "facebook",
        },
    )
    assert lookup_fb.status_code == 200
    assert lookup_fb.json()["draft_id"] == data_fb["draft_id"]

    # Clean up test rows
    db = next(get_db())
    db.query(SocialDraftDB).filter(SocialDraftDB.listing_id == "prod_test_123").delete()
    db.commit()
