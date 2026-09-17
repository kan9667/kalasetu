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
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB
from backend.utils.auth import create_access_token

init_db()
_db = SessionLocal()
if not _db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_01").first():
    _db.add(ArtisanDB(id="artisan_01", name="Ramesh", phone="+919876543210"))
    _db.commit()
_db.close()

from backend.tests.conftest import IdempotentTestClient
token = create_access_token("artisan_01")
client = IdempotentTestClient(app, headers={"Authorization": f"Bearer {token}"})


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
    """Test product listing, creation, and offline batch sync with bearer authentication."""
    from backend.utils.auth import create_access_token
    from backend.database import SessionLocal
    from backend.models.db_models import ArtisanDB

    db = SessionLocal()
    artisan = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_01").first()
    if not artisan:
        artisan = ArtisanDB(id="artisan_01", name="Ramesh", phone="+919876543210")
        db.add(artisan)
        db.commit()
    db.close()

    token = create_access_token("artisan_01")
    headers = {"Authorization": f"Bearer {token}"}

    # 1. List initial products
    res = client.get("/api/v1/products", headers=headers)
    assert res.status_code == 200
    initial_products = res.json()
    assert isinstance(initial_products, list)
    print(f"✅ Product List Passed: Found {len(initial_products)} products")

    # 2. Create a product
    new_prod = {
        "title": "Test Dokra Brass Figurine",
        "description": "Lost wax cast brass craft",
        "price": 1500.0,
        "category": "Jewelry",
        "tags": ["dokra", "brass", "tribal"],
        "materials": 200.0,
        "labor_hours": 2.0,
        "hourly_rate": 100.0,
    }
    import uuid
    test_run_id = uuid.uuid4().hex[:8]
    create_headers = {**headers, "Idempotency-Key": f"test_create_{test_run_id}"}
    res_create = client.post("/api/v1/products", json=new_prod, headers=create_headers)
    assert res_create.status_code == 201
    created = res_create.json()
    prod_id = created["id"]
    print(f"✅ Product Create Passed: Created ID {prod_id}")

    # 3. Get single product
    res_get = client.get(f"/api/v1/products/{prod_id}", headers=headers)
    assert res_get.status_code == 200
    assert res_get.json()["title"] == "Test Dokra Brass Figurine"

    # 4. Offline Batch Sync (drafts)
    sync_id = f"offline_prod_{uuid.uuid4().hex[:8]}"
    sync_payload = {
        "products": [
            {
                "id": sync_id,
                "title": "Offline Queued Saree",
                "description": "Handloom silk saree captured offline",
                "price": 4200.0,
                "category": "Textiles",
                "tags": ["offline", "sync"],
                "materials": 500.0,
                "labor_hours": 4.0,
                "hourly_rate": 200.0,
                "expected_revision": None,
            }
        ]
    }
    sync_headers = {**headers, "Idempotency-Key": f"test_sync_{test_run_id}"}
    res_sync = client.post("/api/v1/products/sync", json=sync_payload, headers=sync_headers)
    assert res_sync.status_code == 200
    sync_data = res_sync.json()
    assert sync_data["synced_count"] == 1
    assert sync_data["products"][0]["id"] == sync_id
    print("✅ Product Offline Sync Batch Passed")

    # 5. Delete products
    del_headers_1 = {**headers, "Idempotency-Key": f"test_del_1_{test_run_id}"}
    res_del = client.delete(f"/api/v1/products/{prod_id}", headers=del_headers_1)
    assert res_del.status_code == 200
    del_headers_2 = {**headers, "Idempotency-Key": f"test_del_2_{test_run_id}"}
    client.delete(f"/api/v1/products/{sync_id}", headers=del_headers_2)
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


def test_voice_glossary_api():
    """Test /api/v1/voice/glossary endpoint."""
    response = client.get("/api/v1/voice/glossary?category=Pottery")
    assert response.status_code == 200
    data = response.json()
    assert data["total_terms"] > 0
    assert "Terracotta" in data["terms"]
    print("✅ Voice Glossary API Passed")


if __name__ == "__main__":
    print("\n🚀 Running KalaSetu Backend Integration Tests...\n")
    test_health()
    test_pricing_status()
    test_products_crud_and_sync()
    test_catalog_listing_generation()
    test_pricing_suggest()
    test_voice_glossary_api()
    print("\n🎉 ALL BACKEND TESTS PASSED SUCCESSFULLY!\n")

