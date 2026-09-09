"""
Test Catalog Generation Rules & Confidentiality Quarantine.

Verifies:
1. _sanitize_customer_facing_text removes making cost, raw materials cost, wage, and hourly statements in English and Hindi.
2. _sanitize_tags strips out price, cost, and numeric tags.
3. /api/v1/catalog/generate-listing excludes internal production costs from customer-facing titles, descriptions, and tags.
"""

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.services.catalog_service import CatalogService

client = TestClient(app)


def test_sanitize_customer_facing_text_english():
    sample_text = (
        "Masterfully hand-carved decorative elephant made of seasoned rosewood. "
        "Total cost of making was ₹450 and raw material cost was 300 rupees. "
        "It took 4 hours to make this piece. "
        "Perfect for traditional home decor and living room showcase."
    )
    sanitized = CatalogService._sanitize_customer_facing_text(sample_text)

    # Asserts that all internal cost and hours statements are stripped
    assert "450" not in sanitized
    assert "₹450" not in sanitized
    assert "300" not in sanitized
    assert "rupees" not in sanitized.lower()
    assert "cost of making" not in sanitized.lower()
    assert "raw material cost" not in sanitized.lower()
    assert "took 4 hours" not in sanitized.lower()

    # Asserts that legitimate product description content remains intact
    assert "hand-carved" in sanitized.lower()
    assert "seasoned rosewood" in sanitized.lower()
    assert "home decor" in sanitized.lower()


def test_sanitize_customer_facing_text_hindi():
    sample_text = (
        "यह पारंपरिक शीशम की लकड़ी से बना सुंदर हाथी है। "
        "इसको बनाने में ₹500 का खर्च आया और 4 घंटे लगे। "
        "कारीगर ने इस पर बारीक नक्काशी की है।"
    )
    sanitized = CatalogService._sanitize_customer_facing_text(sample_text)

    assert "500" not in sanitized
    assert "₹500" not in sanitized
    assert "खर्च" not in sanitized
    assert "घंटे" not in sanitized
    assert "शीशम की लकड़ी" in sanitized
    assert "बारीक नक्काशी" in sanitized


def test_sanitize_tags():
    raw_tags = [
        "hand-carved",
        "sheesham-wood",
        "cost-400",
        "price-500",
        "₹300",
        "cheap",
        "home-decor",
        "4-hours",
    ]
    cleaned = CatalogService._sanitize_tags(raw_tags)

    assert "hand-carved" in cleaned
    assert "sheesham-wood" in cleaned
    assert "home-decor" in cleaned
    for tag in cleaned:
        assert not any(c.isdigit() for c in tag)
        assert "cost" not in tag
        assert "price" not in tag


def test_generate_listing_api_quarantines_cost():
    payload = {
        "transcript": (
            "Yeh lakdi ka hand-carved elephant figurine hai sheesham wood se bana hua. "
            "Iski making cost ₹350 aayi hai aur banane me 4 ghante lage hain. "
            "Living room table decor ke liye bohot sundar hai."
        ),
        "language_code": "hi",
        "category_hint": "Woodwork",
    }

    response = client.post("/api/v1/catalog/generate-listing", json=payload)
    assert response.status_code == 200
    data = response.json()

    title_en = data.get("title_en", "")
    desc_en = data.get("description_en", "")
    desc_hi = data.get("description_hi", "")
    tags = data.get("tags", [])

    # The customer-facing listing must NOT contain internal cost figures
    assert "350" not in title_en
    assert "350" not in desc_en
    assert "350" not in desc_hi
    assert "making cost" not in desc_en.lower()

    # Category and tags should be relevant and clean
    assert data.get("category") == "Woodwork"
    for tag in tags:
        assert not any(c.isdigit() for c in tag)
        assert "cost" not in tag.lower()


def test_sanitize_preserves_marketing_investment_phrasing():
    """
    Verifies that customer marketing language like 'worthy investment for your home'
    is preserved, while internal cost statements like 'invested ₹500 in materials' are removed.
    """
    # 1. Legitimate marketing copy containing "investment"
    marketing_text = (
        "Handcrafted blue pottery floral vase from Jaipur. "
        "A worthy investment for your home decor that brings timeless Rajasthani elegance. "
        "Crafted using traditional quartz stone and natural multani mitti."
    )
    sanitized = CatalogService._sanitize_customer_facing_text(marketing_text)
    assert "worthy investment" in sanitized
    assert "home decor" in sanitized
    assert "blue pottery" in sanitized

    # 2. Mixed: internal cost statement + marketing statement
    mixed_text = (
        "I invested ₹500 in premium materials and pigments for this vase. "
        "A wonderful investment for any contemporary living room showcase."
    )
    sanitized_mixed = CatalogService._sanitize_customer_facing_text(mixed_text)
    assert "500" not in sanitized_mixed
    assert "₹500" not in sanitized_mixed
    assert "investment for any contemporary living room" in sanitized_mixed


def test_generate_listing_api_offline_fallback_quarantines_cost(monkeypatch):
    """
    Verifies the offline / no-LLM path (spotty wifi / unavailable Groq and Gemini):
    1. Customer-facing title, description, and tags quarantine cost/hours leakage.
    2. Legitimate marketing language ('timeless investment') is preserved.
    3. cost_inputs is still correctly populated via deterministic regex fallback.
    """
    from backend.routers.catalog import catalog_service

    # Simulate completely offline environment: both Groq and Gemini are unavailable
    monkeypatch.setattr(catalog_service.groq_client, "is_available", lambda: False)
    monkeypatch.setattr(catalog_service, "client", None)

    payload = {
        "transcript": (
            "I spent ₹450 on materials to carve this rosewood elephant. "
            "It took 6 hours of work. "
            "A timeless investment for home decor lovers."
        ),
        "language_code": "en",
        "category_hint": "Woodwork",
    }

    response = client.post("/api/v1/catalog/generate-listing", json=payload)
    assert response.status_code == 200
    data = response.json()

    title_en = data.get("title_en", "")
    desc_en = data.get("description_en", "")
    tags = data.get("tags", [])
    cost_inputs = data.get("cost_inputs")

    # Production costs & labor hours must be quarantined from customer-facing text
    assert "450" not in title_en
    assert "450" not in desc_en
    assert "spent ₹450" not in desc_en
    assert "6 hours" not in desc_en
    for tag in tags:
        assert not any(c.isdigit() for c in tag)
        assert "cost" not in tag.lower()

    # Marketing statement ('investment for home decor lovers') must survive
    assert "investment for home decor lovers" in desc_en

    # Cost inputs must still be populated via regex extraction
    assert cost_inputs is not None
    assert cost_inputs["materials"] == 450.0
    assert cost_inputs["labor_hours"] == 6.0
    assert cost_inputs["hourly_rate"] == 50.0

