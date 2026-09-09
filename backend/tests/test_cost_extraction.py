"""
Test Cost Cue Extraction & Cost Floor Calculation (Issue 2).

Validates:
1. Shared regex cost extraction across multiple currencies, decimals, Hindi/English, and dual cost/hours sentences.
2. Default hourly rate fallback when hours are provided without wage.
3. Precedence in PriceSuggestRequest.to_cost_inputs().
4. /api/v1/catalog/generate-listing returns structured cost_inputs.
5. /api/v1/pricing/suggest honors base_cost and calculates non-zero cost floor.
"""

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.models.schemas import PriceSuggestRequest, CostInputsSchema
from backend.utils.cost_extraction import regex_extract_cost_cues, DEFAULT_HOURLY_RATE

client = TestClient(app)


def test_regex_cost_phrasing_variants():
    """Stress-test shared regex utility across real-world vernacular phrasing."""
    # 1. Decimal cost and hours in single sentence
    t1 = "making cost is ₹450.50 and took 3.5 hours"
    r1 = regex_extract_cost_cues(t1)
    assert r1["materials"] == 450.50
    assert r1["labor_hours"] == 3.5
    assert r1["hourly_rate"] == DEFAULT_HOURLY_RATE
    assert r1["cost_floor"] == 450.50 + (3.5 * DEFAULT_HOURLY_RATE)

    # 2. Rs. notation with hours
    t2 = "total cost of making was Rs 400 and 4 hrs work"
    r2 = regex_extract_cost_cues(t2)
    assert r2["materials"] == 400.0
    assert r2["labor_hours"] == 4.0
    assert r2["cost_floor"] == 400.0 + (4.0 * DEFAULT_HOURLY_RATE)

    # 3. Hinglish 'rupaye' and 'ghante'
    t3 = "400 rupaye ki lagat aayi aur 5 ghante lage"
    r3 = regex_extract_cost_cues(t3)
    assert r3["materials"] == 400.0
    assert r3["labor_hours"] == 5.0

    # 4. Hours-only (Point 4: default hourly rate fallback ensures non-zero floor)
    t4 = "sirf 4 ghante lage banane me"
    r4 = regex_extract_cost_cues(t4)
    assert r4["materials"] == 0.0
    assert r4["labor_hours"] == 4.0
    assert r4["hourly_rate"] == DEFAULT_HOURLY_RATE
    assert r4["cost_floor"] == 4.0 * DEFAULT_HOURLY_RATE  # 200.0, NOT 0.0!

    # 5. Hindi Devanagari transcript
    t5 = "इस लकड़ी के हाथी को बनाने में 500 रुपये की लागत आई और 5 घंटे लगे"
    r5 = regex_extract_cost_cues(t5)
    assert r5["materials"] == 500.0
    assert r5["labor_hours"] == 5.0
    assert r5["cost_floor"] == 500.0 + (5.0 * DEFAULT_HOURLY_RATE)

    # 6. Explicit hourly wage
    t6 = "₹500 raw materials aur 100 per hour rate pe 2 hours"
    r6 = regex_extract_cost_cues(t6)
    assert r6["materials"] == 500.0
    assert r6["labor_hours"] == 2.0
    assert r6["hourly_rate"] == 100.0
    assert r6["cost_floor"] == 500.0 + (2.0 * 100.0)


def test_price_suggest_request_precedence_and_aliases():
    """Verify precedence: materials > raw_material_cost > base_cost > making_cost."""
    # base_cost alone
    req1 = PriceSuggestRequest(description="Wood carving", base_cost=350.0)
    costs1 = req1.to_cost_inputs()
    assert costs1.materials == 350.0

    # making_cost alone
    req2 = PriceSuggestRequest(description="Wood carving", making_cost=280.0)
    costs2 = req2.to_cost_inputs()
    assert costs2.materials == 280.0

    # raw_material_cost overrides base_cost
    req3 = PriceSuggestRequest(description="Wood carving", raw_material_cost=400.0, base_cost=300.0)
    costs3 = req3.to_cost_inputs()
    assert costs3.materials == 400.0

    # materials overrides all
    req4 = PriceSuggestRequest(description="Wood carving", materials=500.0, raw_material_cost=400.0, base_cost=300.0)
    costs4 = req4.to_cost_inputs()
    assert costs4.materials == 500.0

    # labor_hours with missing hourly_rate gets DEFAULT_HOURLY_RATE (50.0)
    req5 = PriceSuggestRequest(description="Wood carving", labor_hours=3.0)
    costs5 = req5.to_cost_inputs()
    assert costs5.hourly_rate == DEFAULT_HOURLY_RATE


def test_generate_listing_api_returns_cost_inputs():
    """Verify /api/v1/catalog/generate-listing extracts and returns structured cost_inputs."""
    payload = {
        "transcript": "Handmade wooden toy cart. Making cost was ₹350 and took 3 hours to craft.",
        "language_code": "en",
        "category_hint": "Woodwork",
    }
    response = client.post("/api/v1/catalog/generate-listing", json=payload)
    assert response.status_code == 200
    data = response.json()

    assert "cost_inputs" in data
    assert data["cost_inputs"] is not None
    cost_inputs = data["cost_inputs"]
    assert cost_inputs["materials"] == 350.0
    assert cost_inputs["labor_hours"] == 3.0
    assert cost_inputs["hourly_rate"] == DEFAULT_HOURLY_RATE


def test_pricing_suggest_honors_base_cost_and_calculates_non_zero_floor():
    """Verify /api/v1/pricing/suggest computes non-zero cost floor when given base_cost."""
    payload = {
        "description": "Handcrafted decorative wooden box with brass inlay",
        "category": "Woodwork",
        "base_cost": 400.0,
        "labor_hours": 3.0,
        "tags": ["woodwork", "handcrafted"],
    }
    response = client.post("/api/v1/pricing/suggest", json=payload)
    assert response.status_code == 200
    data = response.json()

    # Cost floor: 400 + (3 * 50) = 550.0
    expected_floor = 400.0 + (3.0 * DEFAULT_HOURLY_RATE)
    assert data["floor_price"] == expected_floor
    assert data["suggested_price"] >= data["floor_price"]
    assert data["min_price"] >= data["floor_price"]


def test_pricing_suggest_defensive_description_extraction():
    """Verify defensive fallback: if cost fields are omitted, pricing extracts cues from description."""
    payload = {
        "description": "Intricate wooden elephant. Total cost of making was ₹450 and took 2 hours.",
        "category": "Woodwork",
        "tags": ["woodwork"],
    }
    response = client.post("/api/v1/pricing/suggest", json=payload)
    assert response.status_code == 200
    data = response.json()

    assert data["floor_price"] > 0
    assert data["floor_price"] == 450.0 + (2.0 * DEFAULT_HOURLY_RATE)
    assert data["suggested_price"] >= data["floor_price"]
