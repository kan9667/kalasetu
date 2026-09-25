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
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB
from backend.utils.auth import create_access_token
from ML.voice_pipeline.models import (
    Transcript,
    VoicePipelineResult,
    STTProvider,
    JobStatus,
)

init_db()
_db = SessionLocal()
if not _db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_voice_test").first():
    _db.add(ArtisanDB(id="artisan_voice_test", name="Voice Artisan", phone="+919876543213"))
    _db.commit()
_db.close()

token = create_access_token("artisan_voice_test")
client = TestClient(app, headers={"Authorization": f"Bearer {token}"})

import uuid
_orig_post = client.post
def _auto_idem_post(url, *args, **kwargs):
    headers = kwargs.get("headers") or {}
    if "Idempotency-Key" not in headers:
        headers = {**headers, "Idempotency-Key": f"test_auto_{uuid.uuid4().hex}"}
    kwargs["headers"] = headers
    return _orig_post(url, *args, **kwargs)
client.post = _auto_idem_post


@pytest.fixture(autouse=True)
def isolate_voice_tests(monkeypatch):
    """Ensure tests run isolated from developer .env and external credentials."""
    monkeypatch.setenv("DISABLE_DOTENV", "1")
    monkeypatch.setenv("TESTING", "1")
    from ML.voice_pipeline.config import get_settings as get_voice_settings
    get_voice_settings.cache_clear()
    yield
    get_voice_settings.cache_clear()



def generate_synthetic_wav_bytes(duration_seconds: float = 1.0, framerate: int = 16000) -> bytes:
    """Generate a clean synthetic mono WAV in memory with audible sound (440Hz tone)."""
    import math, struct
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(framerate)
        total_samples = int(framerate * duration_seconds)
        data = bytearray()
        for i in range(total_samples):
            sample = int(10000 * math.sin(2 * math.pi * 440 * i / framerate))
            data.extend(struct.pack("<h", sample))
        w.writeframes(data)
    return buf.getvalue()


from backend.models.schemas import (
    ListingGenerateResponse,
    PriceSuggestResponse,
    ComparableProductSchema,
    CostInputsSchema,
)


@pytest.fixture
def mock_voice_processor():
    """Mock ArtisanVoiceProcessor and downstream LLMs to return realistic data offline."""
    def mock_process(audio_path, language_code="auto", category_hint=None, note_id=None, product_draft_id=None):
        effective_lang = "en" if language_code == "en" else "hi"
        text = (
            "This is a handcrafted terracotta flower vase made on traditional potter's wheel"
            if effective_lang == "en"
            else "यह हाथ से बना मिट्टी का सुराहीदार फूलदान है, 200 रुपये का मटेरियल और 4 घंटे का काम लगा"
        )
        return VoicePipelineResult(
            voice_note_id=note_id or "voice_mock_123",
            status=JobStatus.COMPLETED,
            transcript=Transcript(
                text=text,
                language_code=effective_lang,
                provider=STTProvider.WHISPER,
                duration_seconds=3.5,
            ),
            elapsed_seconds=0.45,
        )

    async def mock_gen_listing(self, request):
        return ListingGenerateResponse(
            title_en="Handcrafted Terracotta Flower Vase",
            title_hi="मिट्टी का सुराहीदार फूलदान",
            description_en="Beautiful handcrafted terracotta vase made on traditional potter's wheel.",
            description_hi="पारंपरिक कुम्हार के चाक पर बना सुंदर हस्तनिर्मित मिट्टी का फूलदान।",
            category=request.category_hint or "Pottery",
            tags=["terracotta", "pottery", "handmade", "artisan"],
            cost_inputs=CostInputsSchema(raw_material_cost=200.0, labor_hours=4.0, hourly_wage=60.0),
        )

    def mock_suggest_price(self, request, db=None):
        c = request.to_cost_inputs()
        materials = c.materials or 250.0
        labor_hours = c.labor_hours or 3.0
        hourly_rate = c.hourly_rate or 60.0
        floor = float(materials + labor_hours * hourly_rate)
        return PriceSuggestResponse(
            suggested_price=floor + 120.0,
            min_price=floor + 50.0,
            max_price=floor + 200.0,
            floor_price=floor,
            confidence_score=0.92,
            market_position="mid-range",
            reasoning="Fair cost floor plus artisanal labor value.",
            reasoning_hi="लागत और कारीगरी का उचित मूल्य।",
            comparable_products=[
                ComparableProductSchema(
                    id="comp_pottery_1",
                    title="Handcrafted Terracotta Vase",
                    selling_price=floor + 150.0,
                    category="Pottery",
                    source_platform="Amazon Karigar",
                    similarity_score=0.89,
                )
            ],
        )

    with patch("backend.services.catalog_service.ArtisanVoiceProcessor.process_voice_note", side_effect=mock_process), \
         patch("backend.services.catalog_service.CatalogService._is_audio_silent", return_value=False), \
         patch("backend.services.catalog_service.CatalogService.generate_listing", new=mock_gen_listing), \
         patch("backend.services.pricing_service.PricingService.suggest_price", new=mock_suggest_price):
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


def test_voice_auto_language_detection(mock_voice_processor):
    """Test auto language detection: English voice produces English, Hindi produces Hindi."""
    wav_bytes = generate_synthetic_wav_bytes(duration_seconds=2.0)

    # 1. Spoken English voice note
    files_en = {"audio": ("english_desc.wav", wav_bytes, "audio/wav")}
    res_en = client.post("/api/v1/voice/transcribe", files=files_en, data={"language_code": "en"})
    assert res_en.status_code == 200
    json_en = res_en.json()
    assert "handcrafted terracotta flower vase" in json_en["transcript"].lower()
    assert json_en["language_code"] == "en"

    # 2. Default auto parameter without explicit language code
    files_auto = {"audio": ("auto_desc.wav", wav_bytes, "audio/wav")}
    res_auto = client.post("/api/v1/voice/transcribe", files=files_auto)
    assert res_auto.status_code == 200
    json_auto = res_auto.json()
    assert json_auto["status"] == "completed"
    assert json_auto["transcript"] != ""


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
    assert res.status_code in [400, 422]
    print("✅ Voice Error Handling Passed: Empty audio properly rejected")


def test_voice_transcribe_multipart_boundary_metadata_and_bytes():
    """Test boundary multipart metadata and unchanged byte forwarding to Whisper."""
    from unittest.mock import MagicMock, patch
    import requests
    from ML.voice_pipeline.transcription.whisper_transcriber import WhisperTranscriber

    wav_bytes = generate_synthetic_wav_bytes(duration_seconds=1.5)
    captured_files = {}

    def mock_whisper_post(url, headers=None, files=None, data=None, timeout=None):
        nonlocal captured_files
        captured_files = files
        # Read stream
        file_tuple = files["file"]
        filename, stream, mime = file_tuple
        read_bytes = stream.read()
        captured_files["_read_bytes"] = read_bytes
        captured_files["_filename"] = filename
        captured_files["_mime"] = mime

        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"text": "हाथ से बना मिट्टी का घड़ा", "language": "hindi"}
        return mock_resp

    with patch.object(WhisperTranscriber, "_is_audio_silent", return_value=False), \
         patch("requests.post", side_effect=mock_whisper_post), \
         patch("ML.voice_pipeline.transcription.whisper_transcriber.get_settings") as mock_settings:
        settings_obj = mock_settings.return_value
        settings_obj.whisper_api_key = "test-mock-boundary-key"
        settings_obj.whisper_base_url = "https://mock.transcribe.api/v1"
        settings_obj.whisper_model = "whisper-large-v3"
        settings_obj.stt_retry_attempts = 3
        settings_obj.stt_retry_backoff_seconds = 0.01
        settings_obj.stt_request_timeout = 5
        settings_obj.max_audio_duration_seconds = 180
        settings_obj.glossary_terms_in_prompt = 10

        res = client.post(
            "/api/v1/voice/transcribe",
            files={"audio": ("artisan_pot.wav", wav_bytes, "audio/wav")},
            data={"language_code": "hi"},
        )
        assert res.status_code == 200
        assert res.json()["status"] == "completed"
        assert res.json()["transcript"] == "हाथ से बना मिट्टी का घड़ा"

        # Assert provider received correct metadata and unchanged bytes
        assert captured_files["_filename"].endswith(".wav")
        assert captured_files["_mime"] == "audio/wav"
        assert captured_files["_read_bytes"] == wav_bytes


def test_voice_transcribe_transient_retry_and_exhaustion():
    """Test transient 503 retry and graceful service unavailable response when retries exhaust."""
    from unittest.mock import MagicMock, patch
    import requests
    from ML.voice_pipeline.transcription.whisper_transcriber import WhisperTranscriber

    wav_bytes = generate_synthetic_wav_bytes(duration_seconds=1.0)
    mock_fail = MagicMock()
    mock_fail.status_code = 503
    mock_fail_err = requests.exceptions.HTTPError("503 Service Unavailable", response=mock_fail)

    with patch.object(WhisperTranscriber, "_is_audio_silent", return_value=False), \
         patch("requests.post", side_effect=mock_fail_err), \
         patch("time.sleep"), \
         patch("ML.voice_pipeline.transcription.whisper_transcriber.get_settings") as mock_settings:
        settings_obj = mock_settings.return_value
        settings_obj.whisper_api_key = "test-key"
        settings_obj.whisper_base_url = "https://mock.api/v1"
        settings_obj.whisper_model = "whisper-large-v3"
        settings_obj.stt_retry_attempts = 2
        settings_obj.stt_retry_backoff_seconds = 0.01
        settings_obj.stt_request_timeout = 5
        settings_obj.max_audio_duration_seconds = 180
        settings_obj.glossary_terms_in_prompt = 5

        res = client.post(
            "/api/v1/voice/transcribe",
            files={"audio": ("test.wav", wav_bytes, "audio/wav")},
            data={"language_code": "hi"},
        )
        # Expected failure contract: 503 Service Unavailable (NOT unhandled 500)
        assert res.status_code == 503
        data = res.json()
        assert data["detail"]["code"] == "SERVICE_UNAVAILABLE"


def test_voice_transcribe_explicit_silence():
    """Test silence check returns 200 with status='no_speech' and fallback_reason='no_speech'."""
    from unittest.mock import patch
    from backend.services.catalog_service import CatalogService

    wav_bytes = generate_synthetic_wav_bytes(duration_seconds=1.0)
    with patch.object(CatalogService, "_is_audio_silent", return_value=True):
        res = client.post(
            "/api/v1/voice/transcribe",
            files={"audio": ("silent.wav", wav_bytes, "audio/wav")},
            data={"language_code": "hi"},
        )
        assert res.status_code == 200
        body = res.json()
        assert body["status"] == "no_speech"
        assert body["is_fallback"] is True
        assert body["fallback_reason"] == "no_speech"
        assert body["transcript"] == ""


def test_voice_transcribe_rejects_raw_aac():
    """Test raw AAC stream is rejected with 422 rather than sent as audio/tmp or guessed."""
    raw_aac_bytes = b"\xff\xf1\x50\x80" + b"\x00" * 60
    res = client.post(
        "/api/v1/voice/transcribe",
        files={"audio": ("stream.aac", raw_aac_bytes, "audio/aac")},
        data={"language_code": "hi"},
    )
    assert res.status_code == 422
    assert "Raw AAC streams without container are unsupported" in str(res.json()["detail"])


def test_voice_transcribe_permanent_failure_does_not_retry():
    """Test permanent 401/403/400 error does not retry and releases idempotency claim."""
    from unittest.mock import MagicMock, patch
    import requests
    from ML.voice_pipeline.transcription.whisper_transcriber import WhisperTranscriber

    wav_bytes = generate_synthetic_wav_bytes(duration_seconds=1.0)
    mock_resp = MagicMock()
    mock_resp.status_code = 401
    mock_err = requests.exceptions.HTTPError("401 Unauthorized", response=mock_resp)
    mock_post = MagicMock(side_effect=mock_err)

    idem_key = "test_perm_fail_release_key"

    with patch.object(WhisperTranscriber, "_is_audio_silent", return_value=False), \
         patch("requests.post", new=mock_post), \
         patch("ML.voice_pipeline.transcription.whisper_transcriber.get_settings") as mock_settings:
        settings_obj = mock_settings.return_value
        settings_obj.whisper_api_key = "bad-key"
        settings_obj.whisper_base_url = "https://mock.api/v1"
        settings_obj.whisper_model = "whisper-large-v3"
        settings_obj.stt_retry_attempts = 3
        settings_obj.stt_retry_backoff_seconds = 0.01
        settings_obj.stt_request_timeout = 5
        settings_obj.max_audio_duration_seconds = 180
        settings_obj.glossary_terms_in_prompt = 5

        res = client.post(
            "/api/v1/voice/transcribe",
            files={"audio": ("test.wav", wav_bytes, "audio/wav")},
            data={"language_code": "hi"},
            headers={"Idempotency-Key": idem_key},
        )
        assert res.status_code == 503
        assert mock_post.call_count == 1  # Exactly 1 attempt, NO retries!

        # Verify idempotency claim was released so the key is not stuck in-flight
        # (A subsequent call with the same key should not receive 409 In-Flight)
        res2 = client.post(
            "/api/v1/voice/transcribe",
            files={"audio": ("test.wav", wav_bytes, "audio/wav")},
            data={"language_code": "hi"},
            headers={"Idempotency-Key": idem_key},
        )
        assert res2.status_code == 503
        assert mock_post.call_count == 2


def test_streaming_ingest_mp3_acceptance_and_adts_rejection():
    """Verify streaming ingest accepts valid MP3 (ID3, 0xFFFB, 0xFFFA) and rejects raw ADTS AAC."""
    # 1. Valid MP3 with ID3
    mp3_id3_bytes = b"ID3\x03\x00\x00\x00\x00\x00\x00" + b"\x00" * 200
    res = client.post(
        "/api/v1/voice/transcribe",
        files={"audio": ("test_id3.mp3", mp3_id3_bytes, "audio/mpeg")},
        data={"language_code": "hi"},
        headers={"Idempotency-Key": f"idem_mp3_id3_{uuid.uuid4().hex}"},
    )
    # Rejection should NOT be 422 format error (it proceeds to Whisper mock/handler)
    assert res.status_code != 422

    # 2. Valid raw MP3 frame without ID3 (MPEG-1 Layer 3, no CRC: 0xFFFB)
    mp3_raw_bytes = b"\xff\xfb\x90\x64" + b"\x00" * 200
    res = client.post(
        "/api/v1/voice/transcribe",
        files={"audio": ("test_raw.mp3", mp3_raw_bytes, "audio/mpeg")},
        data={"language_code": "hi"},
        headers={"Idempotency-Key": f"idem_mp3_raw_{uuid.uuid4().hex}"},
    )
    assert res.status_code != 422

    # 3. Raw ADTS AAC frames (0xFFF0, 0xFFF1, 0xFFF8, 0xFFF9) must be rejected with 422
    for b1 in [0xF0, 0xF1, 0xF8, 0xF9]:
        raw_aac_bytes = bytes([0xFF, b1, 0x40, 0x20]) + b"\x00" * 100
        res = client.post(
            "/api/v1/voice/transcribe",
            files={"audio": ("stream.aac", raw_aac_bytes, "audio/aac")},
            data={"language_code": "hi"},
            headers={"Idempotency-Key": f"idem_aac_{b1:02x}_{uuid.uuid4().hex}"},
        )
        assert res.status_code == 422
        assert "Raw AAC streams without container are unsupported" in res.json()["detail"]


def test_generate_listing_insufficient_product_info_truthful():
    """Verify input such as 'Hello, hello, hello' truthfully requests product details without inventing attributes."""
    idem_key = f"idem_insufficient_{uuid.uuid4().hex}"
    res = client.post(
        "/api/v1/catalog/generate-listing",
        json={"transcript": "Hello, hello, hello", "language_code": "en", "category_hint": "General"},
        headers={"Idempotency-Key": idem_key},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "needs_clarification"
    assert data["is_degraded"] is True
    assert data["tags"] == []  # MUST NOT invent craft tags
    assert "Product Details Needed" in data["title_en"]
    assert "उत्पाद विवरण" in data["title_hi"]
    assert "Please provide details about your handcrafted product" in data["description_en"]


@pytest.mark.anyio
async def test_generate_listing_fast_success_with_failed_cost_extraction():
    """Verify listing generation succeeds with regex fallback when concurrent cost extraction fails."""
    from backend.services.catalog_service import CatalogService
    from backend.models.schemas import ListingGenerateRequest

    service = CatalogService()

    # Mock extract_cost_cues to fail
    async def mock_failed_costs(transcript):
        raise RuntimeError("Cost extraction provider timeout")

    # Mock listing content generation to succeed
    async def mock_listing_text(*args, **kwargs):
        return (
            "Handcrafted Rosewood Bowl",
            "हाथ से बना शीशम का कटोरा",
            "Carved from single block of rosewood.",
            "शीशम की लकड़ी से बना कटोरा।",
            "Woodwork",
            ["rosewood", "bowl", "woodwork"],
        )

    with patch.object(service, "extract_cost_cues", side_effect=mock_failed_costs), \
         patch.object(service, "_generate_listing_text", side_effect=mock_listing_text):
        req = ListingGenerateRequest(
            transcript="This is a hand-carved rosewood bowl made in 5 hours with 300 rupees wood",
            language_code="en",
        )
        result = await service.generate_listing(req)

        assert result.status == "success"
        assert result.is_degraded is False
        assert result.title_en == "Handcrafted Rosewood Bowl"
        assert result.category == "Woodwork"
        assert "rosewood" in result.tags
        # Cost extraction failed gracefully into regex fallback:
        assert result.cost_inputs is not None
        assert result.cost_inputs.materials == 300.0
        assert result.cost_inputs.labor_hours == 5.0



if __name__ == "__main__":
    print("\n🚀 Running KalaSetu Voice Integration Tests...\n")
    test_craft_glossary_endpoint()
    test_voice_error_handling()
    test_voice_transcribe_multipart_boundary_metadata_and_bytes()
    test_voice_transcribe_transient_retry_and_exhaustion()
    test_voice_transcribe_permanent_failure_does_not_retry()
    test_voice_transcribe_explicit_silence()
    test_voice_transcribe_rejects_raw_aac()
    print("\n🎉 ALL VOICE TESTS PASSED SUCCESSFULLY!\n")
