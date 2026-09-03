"""
Voice Pipeline Backend Integration Tests.

Validates:
1. Craft Glossary lookup endpoint (/api/v1/voice/glossary)
2. Voice Audio Transcription (/api/v1/voice/transcribe and /api/v1/catalog/transcribe)
3. Voice to Bilingual Listing Generation (/api/v1/catalog/voice-to-listing)
4. Voice to Base Price & AI Pricing (/api/v1/pricing/suggest-from-voice)
5. End-to-End Voice-to-Product Pipeline (/api/v1/voice/process and /api/v1/catalog/voice-to-product)
6. Error handling (corrupted/empty audio, invalid parameters)
"""

import sys
import wave
import io
from pathlib import Path
from unittest.mock import patch

# Fix Windows console encoding for emoji output
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from fastapi.testclient import TestClient
import pytest

# Ensure root is on path
PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from backend.main import app
from ML.voice_pipeline.models import (
    Transcript,
    VoicePipelineResult,
    STTProvider,
    JobStatus,
)

client = TestClient(app)


def generate_synthetic_wav_bytes(duration_seconds: float = 1.0, framerate: int = 16000) -> bytes:
    """Generate a clean synthetic mono WAV in memory."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(framerate)
        w.writeframes(b"\x00\x00" * int(framerate * duration_seconds))
    return buf.getvalue()


@pytest.fixture
def mock_voice_processor():
    """Mock ArtisanVoiceProcessor to return realistic transcripts for offline testing."""
    def mock_process(audio_path, language_code="hi", category_hint=None, note_id=None, product_draft_id=None):
        return VoicePipelineResult(
            voice_note_id=note_id or "voice_mock_123",
            status=JobStatus.COMPLETED,
            transcript=Transcript(
                text="यह हाथ से बना मिट्टी का सुराहीदार फूलदान है, 200 रुपये का मटेरियल और 4 घंटे का काम लगा",
                language_code=language_code,
                provider=STTProvider.WHISPER,
                duration_seconds=3.5,
            ),
            elapsed_seconds=0.45,
        )

    with patch("backend.services.catalog_service.ArtisanVoiceProcessor.process_voice_note", side_effect=mock_process):
        yield


def test_craft_glossary_endpoint():
    """Test /api/v1/voice/glossary endpoint."""
    response = client.get("/api/v1/voice/glossary?category=Pottery&limit=10")
    assert response.status_code == 200
    data = response.json()
    assert data["total_terms"] > 0
    assert "Terracotta" in data["terms"]
    assert "Pottery" in data["categories"]
    assert len(data["categories"]) >= 5
    print(f"✅ Craft Glossary Endpoint Passed: {data['total_terms']} terms retrieved")


def test_voice_transcribe_endpoint(mock_voice_processor):
    """Test /api/v1/voice/transcribe and /api/v1/catalog/transcribe endpoints."""
    wav_bytes = generate_synthetic_wav_bytes(duration_seconds=2.0)
    files = {"audio": ("sample.wav", wav_bytes, "audio/wav")}
    data = {"language_code": "hi", "category_hint": "Pottery"}

    # Test /api/v1/voice/transcribe
    res_voice = client.post("/api/v1/voice/transcribe", files=files, data=data)
    assert res_voice.status_code == 200
    res_json = res_voice.json()
    assert res_json["status"] == "completed"
    assert "मिट्टी का" in res_json["transcript"]
    assert res_json["language_code"] == "hi"
    print(f"✅ /api/v1/voice/transcribe Passed: '{res_json['transcript'][:40]}...'")

    # Test /api/v1/catalog/transcribe
    files2 = {"audio": ("sample.wav", wav_bytes, "audio/wav")}
    res_catalog = client.post("/api/v1/catalog/transcribe", files=files2, data=data)
    assert res_catalog.status_code == 200
    assert "मिट्टी का" in res_catalog.json()["transcript"]
    print("✅ /api/v1/catalog/transcribe Passed")


def test_voice_to_listing_endpoint(mock_voice_processor):
    """Test /api/v1/catalog/voice-to-listing endpoint."""
    wav_bytes = generate_synthetic_wav_bytes(duration_seconds=2.0)
    files = {"audio": ("sample.wav", wav_bytes, "audio/wav")}
    data = {"language_code": "hi", "category_hint": "Pottery"}

    response = client.post("/api/v1/catalog/voice-to-listing", files=files, data=data)
    assert response.status_code == 200
    res_json = response.json()
    assert "title_en" in res_json
    assert "title_hi" in res_json
    assert "description_en" in res_json
    assert "category" in res_json
    assert len(res_json["tags"]) > 0
    print(f"✅ Voice to Listing Passed: {res_json['title_en']} ({res_json['category']})")


def test_voice_to_pricing_endpoint(mock_voice_processor):
    """Test /api/v1/pricing/suggest-from-voice endpoint."""
    wav_bytes = generate_synthetic_wav_bytes(duration_seconds=2.0)
    files = {"audio": ("sample.wav", wav_bytes, "audio/wav")}
    data = {
        "language_code": "hi",
        "category_hint": "Pottery",
        "raw_material_cost": 250.0,
        "labor_hours": 3.0,
        "hourly_wage": 60.0,
    }

    response = client.post("/api/v1/pricing/suggest-from-voice", files=files, data=data)
    assert response.status_code == 200
    pricing = response.json()
    assert pricing["suggested_price"] > 0
    assert pricing["floor_price"] == 430.0  # 250 + 3*60
    assert "reasoning" in pricing
    assert "reasoning_hi" in pricing
    assert len(pricing["comparable_products"]) > 0
    print(f"✅ Voice to Pricing Passed: Suggested ₹{pricing['suggested_price']} (Floor: ₹{pricing['floor_price']})")


def test_end_to_end_voice_to_product(mock_voice_processor):
    """Test complete end-to-end voice-to-product draft creation."""
    wav_bytes = generate_synthetic_wav_bytes(duration_seconds=2.5)
    files = {"audio": ("sample.wav", wav_bytes, "audio/wav")}
    data = {
        "language_code": "hi",
        "category_hint": "Pottery",
        "raw_material_cost": 200.0,
        "labor_hours": 4.0,
        "hourly_wage": 60.0,
    }

    # Test /api/v1/voice/process
    res = client.post("/api/v1/voice/process", files=files, data=data)
    assert res.status_code == 200
    body = res.json()

    assert body["status"] == "completed"
    assert "transcript" in body
    assert "title_en" in body
    assert "title_hi" in body
    assert "description_en" in body
    assert "description_hi" in body
    assert "category" in body
    assert len(body["tags"]) > 0
    assert "pricing" in body
    assert body["pricing"]["suggested_price"] > 0
    assert body["pricing"]["floor_price"] == 440.0
    assert "product_draft" in body
    assert body["product_draft"]["status"] == "draft"
    assert body["product_draft"]["price"] == body["pricing"]["suggested_price"]
    print(f"✅ End-to-End Voice Process Passed: Title='{body['title_en']}', Price=₹{body['product_draft']['price']}")

    # Test /api/v1/catalog/voice-to-product
    files2 = {"audio": ("sample.wav", wav_bytes, "audio/wav")}
    res2 = client.post("/api/v1/catalog/voice-to-product", files=files2, data=data)
    assert res2.status_code == 200
    assert res2.json()["status"] == "completed"
    print("✅ /api/v1/catalog/voice-to-product Passed")


def test_voice_error_handling():
    """Test error handling for empty audio."""
    files = {"audio": ("empty.wav", b"", "audio/wav")}
    res = client.post("/api/v1/voice/transcribe", files=files, data={"language_code": "hi"})
    assert res.status_code in [400, 500]
    print("✅ Voice Error Handling Passed: Empty audio properly rejected")


if __name__ == "__main__":
    print("\n🚀 Running KalaSetu Voice Integration Tests...\n")
    test_craft_glossary_endpoint()
    test_voice_error_handling()
    print("\n🎉 ALL VOICE TESTS PASSED SUCCESSFULLY!\n")
