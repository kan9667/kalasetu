"""
FastAPI Backend Integration Tests.

Validates:
1. Health check endpoint
2. Pricing status & Pricing suggestion (integrated with ML engine)
3. Product catalog CRUD & Offline batch sync
4. AI Catalog listing generation
"""

import sys
from pathlib import Path

# Fix Windows console encoding for emoji output
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from fastapi.testclient import TestClient

# Ensure root is on path
PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from backend.main import app

client = TestClient(app)


def test_health():
    """Test /api/v1/health endpoint."""
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    print("✅ Health Check Passed")


def test_pricing_status():
    """Test /api/v1/pricing/status endpoint."""
    response = client.get("/api/v1/pricing/status")
    assert response.status_code == 200
    data = response.json()
    assert "indexed_benchmark_products" in data
    print(f"✅ Pricing Status Passed: {data['indexed_benchmark_products']} benchmark products indexed")


def test_pricing_suggest():
    """Test /api/v1/pricing/suggest endpoint calling our ML engine."""
    payload = {
        "description": "Handcrafted terracotta floral vase sculpted on traditional potter wheel",
        "category": "Pottery",
        "raw_material_cost": 200.0,
        "labor_hours": 4.0,
        "hourly_wage": 60.0,
    }
    response = client.post("/api/v1/pricing/suggest", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["suggested_price"] > 0
    assert data["floor_price"] == 440.0  # 200 + 4*60
    assert "reasoning" in data
    assert "reasoning_hi" in data
    assert len(data["comparable_products"]) > 0
    print(f"✅ Pricing Suggest Passed: Suggested ₹{data['suggested_price']} (Floor: ₹{data['floor_price']})")


def test_products_crud_and_sync():
    """Test product listing, creation, and offline batch sync."""
    # 1. List initial products
    res = client.get("/api/v1/products")
    assert res.status_code == 200
    initial_products = res.json()
    assert len(initial_products) >= 3
    print(f"✅ Product List Passed: Found {len(initial_products)} products")

    # 2. Create a product
    new_prod = {
        "title": "Test Dokra Brass Figurine",
        "description": "Lost wax cast brass craft",
        "price": 1500.0,
        "image_url": "/uploads/images/test.jpg",
        "category": "Jewelry",
        "tags": ["dokra", "brass", "tribal"],
        "status": "live",
    }
    res_create = client.post("/api/v1/products", json=new_prod)
    assert res_create.status_code == 201
    created = res_create.json()
    prod_id = created["id"]
    print(f"✅ Product Create Passed: Created ID {prod_id}")

    # 3. Get single product
    res_get = client.get(f"/api/v1/products/{prod_id}")
    assert res_get.status_code == 200
    assert res_get.json()["title"] == "Test Dokra Brass Figurine"

    # 4. Offline Batch Sync
    sync_payload = {
        "products": [
            {
                "id": "offline_prod_101",
                "title": "Offline Queued Saree",
                "description": "Handloom silk saree captured offline",
                "price": 4200.0,
                "image_url": "/uploads/images/offline.jpg",
                "category": "Textiles",
                "tags": ["offline", "sync"],
                "status": "pendingSync",
            }
        ]
    }
    res_sync = client.post("/api/v1/products/sync", json=sync_payload)
    assert res_sync.status_code == 200
    sync_data = res_sync.json()
    assert sync_data["synced_count"] == 1
    assert sync_data["products"][0]["id"] == "offline_prod_101"
    print("✅ Product Offline Sync Batch Passed")

    # 5. Delete product
    res_del = client.delete(f"/api/v1/products/{prod_id}")
    assert res_del.status_code == 200
    print("✅ Product Delete Passed")


def test_catalog_listing_generation():
    """Test AI bilingual listing generator."""
    payload = {
        "transcript": "यह हाथ से बुनी चंदेरी सिल्क साड़ी है जिसमें असली सुनहरी ज़री का काम है",
        "language_code": "hi",
        "category_hint": "Textiles",
    }
    response = client.post("/api/v1/catalog/generate-listing", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert "title_en" in data
    assert "title_hi" in data
    assert "description_en" in data
    assert "description_hi" in data
    assert "category" in data
    print(f"✅ Catalog Listing Generation Passed: {data['title_en']}")


if __name__ == "__main__":
    print("\n🚀 Running KalaSetu Backend Integration Tests...\n")
    test_health()
    test_pricing_status()
    test_products_crud_and_sync()
    test_catalog_listing_generation()
    test_pricing_suggest()
    print("\n🎉 ALL BACKEND TESTS PASSED SUCCESSFULLY!\n")
