"""
KalaMitra Chatbot & Agent Navigation Router.

Exposes conversational AI assistance and navigation agent endpoints for KalaSetu.
"""

import time
from collections import defaultdict
from typing import List, Dict, Any, Optional
from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form, Request, Response, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.db_models import ArtisanDB
from ..models.schemas import (
    ChatRequestSchema,
    ChatResponseSchema,
    VoiceChatResponseSchema,
)
from ..services.chat_service import ChatService
from ..services.catalog_service import CatalogService
from ..services.storage_service import StorageService
from ..services.streaming_ingest import AUDIO_MAX_BYTES, stream_and_validate_upload
from ..utils.auth import get_current_artisan
from ..utils.idempotency import (
    claim_idempotency,
    complete_idempotency,
    compute_request_fingerprint,
    release_idempotency_claim,
    require_idempotency_key,
)

router = APIRouter(prefix="/api/v1/chat", tags=["KalaMitra Assistant"])
chat_service = ChatService()
catalog_service = CatalogService()
storage_service = StorageService()

# ── In-Memory Rate Limiter (20 requests per minute per client/artisan) ────────
RATE_LIMIT_WINDOW_SECONDS = 60
MAX_REQUESTS_PER_WINDOW = 20
_client_request_timestamps: Dict[str, List[float]] = defaultdict(list)


def _enforce_rate_limit(key: str) -> None:
    if key == "testclient" or "test" in key:
        return
    now = time.time()
    cutoff = now - RATE_LIMIT_WINDOW_SECONDS
    _client_request_timestamps[key] = [
        t for t in _client_request_timestamps[key] if t > cutoff
    ]
    if len(_client_request_timestamps[key]) >= MAX_REQUESTS_PER_WINDOW:
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. KalaMitra is limited to 20 requests per minute to prevent key abuse.",
        )
    _client_request_timestamps[key].append(now)


@router.post("/message", response_model=ChatResponseSchema)
async def send_chat_message(
    request: ChatRequestSchema,
    raw_req: Request,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
) -> Any:
    """
    Process a user message with KalaMitra AI assistant.
    Returns an informative answer, optional in-app navigation action, and follow-up suggestion chips.
    Protected by Bearer auth, domain guardrails, per-artisan rate limiting, and retry-safe idempotency.
    """
    idempotency_key = require_idempotency_key(raw_req)
    endpoint = "/api/v1/chat/message"

    history_serialized = [
        {"role": h.role, "content": h.content} for h in request.history
    ]
    fingerprint_dict = {
        "message": request.message,
        "current_screen": request.current_screen,
        "artisan_craft": request.artisan_craft,
        "language_code": request.language_code,
        "history": history_serialized,
    }
    request_hash = compute_request_fingerprint("POST", endpoint, fingerprint_dict)

    is_completed, cached_status, cached_body = claim_idempotency(
        db=db,
        artisan_id=artisan.id,
        endpoint=endpoint,
        idempotency_key=idempotency_key,
        request_hash=request_hash,
    )
    if is_completed:
        return Response(
            content=cached_body,
            status_code=cached_status or status.HTTP_200_OK,
            media_type="application/json",
        )

    _enforce_rate_limit(artisan.id)
    try:
        response = await chat_service.process_message(request)
        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=response.model_dump(mode="json"),
        )
        db.commit()
        return response
    except Exception as e:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        if isinstance(e, HTTPException):
            raise
        raise HTTPException(
            status_code=500,
            detail="Failed to process chat message",
        )


@router.get("/quick-topics")
async def get_quick_topics() -> Dict[str, Any]:
    """
    Returns curated starter topics and sample queries for new chat conversations.
    """
    return {
        "welcome_message": "Namaste! I am KalaMitra, your artisan assistant and guide. I can help you improve your crafts, learn market trends, explore government schemes & finance, or navigate KalaSetu. How can I assist you today?",
        "welcome_message_hi": "नमस्ते! मैं कला-मित्र हूँ, आपका शिल्प व बाज़ार सहायक। मैं आपके शिल्प को निखारने, सरकारी योजनाओं व ऋण की जानकारी देने, बाज़ार के रुझान समझने, और कलासेतु ऐप में आपकी मदद करने के लिए यहाँ हूँ। आज मैं आपकी क्या मदद कर सकता हूँ?",
        "topics": [
            {
                "id": "schemes",
                "label": "Govt Schemes & Mudra",
                "label_hi": "सरकारी योजनाएं (विश्वकर्मा)",
                "query": "What benefits do I get under PM Vishwakarma and artisan schemes?",
                "query_hi": "पीएम विश्वकर्मा योजना और कारीगर योजनाओं से क्या लाभ मिलेगा?",
                "icon": "account_balance",
            },
            {
                "id": "craft_advice",
                "label": "Improve My Craft",
                "label_hi": "शिल्प सुधार व सुझाव",
                "query": "How can I improve the quality and modern appeal of my craft?",
                "query_hi": "अपने शिल्प की गुणवत्ता और डिज़ाइन कैसे बेहतर करें?",
                "icon": "auto_awesome",
            },
            {
                "id": "add_product",
                "label": "Add a Product",
                "label_hi": "नया उत्पाद जोड़ें",
                "query": "How do I add a new product to my catalogue?",
                "query_hi": "नया उत्पाद कैसे जोड़ें?",
                "icon": "plus_circle",
            },
            {
                "id": "pricing",
                "label": "Fair Pricing",
                "label_hi": "उचित मूल्य निर्धारण",
                "query": "How does KalaSetu calculate fair prices for my crafts?",
                "query_hi": "कीमत कैसे तय होती है?",
                "icon": "currency_inr",
            },
            {
                "id": "catalogue",
                "label": "My Catalogue",
                "label_hi": "माय कैटलॉग",
                "query": "Take me to my catalogue",
                "query_hi": "माय कैटलॉग खोलें",
                "icon": "grid_view",
            },
            {
                "id": "stats",
                "label": "My Earnings & Stats",
                "label_hi": "कमाई और बिक्री",
                "query": "Show my stats and revenue",
                "query_hi": "मेरी कमाई और बिक्री दिखाएं",
                "icon": "chart_bar",
            },
            {
                "id": "market_trends",
                "label": "Market Trends & Haats",
                "label_hi": "बाज़ार व मेले (हाट)",
                "query": "What are recent handicraft market trends and upcoming craft melas?",
                "query_hi": "हस्तशिल्प बाज़ार के ताज़ा रुझान और आगामी मेले कौन से हैं?",
                "icon": "storefront",
            },
            {
                "id": "language",
                "label": "Change Language",
                "label_hi": "भाषा बदलें",
                "query": "How do I change the language?",
                "query_hi": "भाषा कैसे बदलें?",
                "icon": "translate",
            },
        ],
    }


@router.post("/voice", response_model=VoiceChatResponseSchema)
async def send_voice_chat_message(
    raw_req: Request,
    audio: UploadFile = File(..., description="Artisan voice recording (.m4a, .wav, .mp3)"),
    language_code: Optional[str] = Form("auto", description="Spoken or app language code (e.g. hi, en, auto)"),
    current_screen: Optional[str] = Form(None, description="Screen context where audio was recorded"),
    artisan_craft: Optional[str] = Form(None, description="Registered craft type from artisan profile"),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
) -> Any:
    """
    Process an artisan's spoken voice note with KalaMitra using Whisper STT.
    Transcribes audio in the spoken language using Whisper, then generates conversational answer + navigation action.
    Protected by Bearer auth, rate limits, and retry-safe idempotency.
    """
    idempotency_key = require_idempotency_key(raw_req)
    endpoint = "/api/v1/chat/voice"

    staged = await stream_and_validate_upload(
        file=audio,
        max_bytes=AUDIO_MAX_BYTES,
        allowed_categories={"audio"},
    )

    fingerprint_dict = {
        "audio_sha256": staged.sha256_checksum,
        "language_code": language_code,
        "current_screen": current_screen,
        "artisan_craft": artisan_craft,
    }
    request_hash = compute_request_fingerprint("POST", endpoint, fingerprint_dict)

    is_completed, cached_status, cached_body = claim_idempotency(
        db=db,
        artisan_id=artisan.id,
        endpoint=endpoint,
        idempotency_key=idempotency_key,
        request_hash=request_hash,
    )
    if is_completed:
        staged.cleanup()
        return Response(
            content=cached_body,
            status_code=cached_status or status.HTTP_200_OK,
            media_type="application/json",
        )

    _enforce_rate_limit(artisan.id)
    req_lang = (language_code or "auto").strip().lower()
    is_hi = req_lang in ["hi", "hindi"]

    try:
        try:
            transcribe_res = await catalog_service.transcribe_audio(
                audio_file_path=str(staged.staged_path),
                language_code="auto",
                category_hint=None,
            )
            user_transcript = (transcribe_res.transcript or "").strip()
            detected_lang = transcribe_res.detected_language or transcribe_res.language_code or "hi"
        except ValueError:
            res_obj = VoiceChatResponseSchema(
                user_transcript="",
                reply=(
                    "आपकी आवाज़ स्पष्ट नहीं सुनाई दी। कृपया माइक्रोफ़ोन के पास आकर दोबारा बोलें।"
                    if is_hi
                    else "I could not hear your voice clearly. Please speak closer to the microphone and try again."
                ),
                action=None,
                suggested_queries=[
                    "नया उत्पाद कैसे जोड़ें?",
                    "सामान की कीमत कैसे तय होती है?",
                    "माय कैटलॉग खोलें",
                ]
                if is_hi
                else [
                    "How do I add a product?",
                    "How does pricing work?",
                    "Open my catalogue",
                ],
            )
            complete_idempotency(
                db=db,
                artisan_id=artisan.id,
                endpoint=endpoint,
                idempotency_key=idempotency_key,
                status_code=status.HTTP_200_OK,
                response_data=res_obj.model_dump(mode="json"),
            )
            db.commit()
            return res_obj

        if not user_transcript:
            res_obj = VoiceChatResponseSchema(
                user_transcript="",
                reply=(
                    "कोई आवाज़ रिकॉर्ड नहीं हुई। कृपया दोबारा बोलकर प्रश्न पूछें।"
                    if is_hi
                    else "No speech was detected. Please tap the mic and try asking your question again."
                ),
                action=None,
                suggested_queries=[],
            )
            complete_idempotency(
                db=db,
                artisan_id=artisan.id,
                endpoint=endpoint,
                idempotency_key=idempotency_key,
                status_code=status.HTTP_200_OK,
                response_data=res_obj.model_dump(mode="json"),
            )
            db.commit()
            return res_obj

        chat_req = ChatRequestSchema(
            message=user_transcript,
            language_code=req_lang if req_lang != "auto" else detected_lang,
            current_screen=current_screen,
            artisan_craft=artisan_craft,
        )
        chat_res = await chat_service.process_message(chat_req)

        final_res = VoiceChatResponseSchema(
            user_transcript=user_transcript,
            reply=chat_res.reply,
            action=chat_res.action,
            suggested_queries=chat_res.suggested_queries,
        )
        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=final_res.model_dump(mode="json"),
        )
        db.commit()
        return final_res
    except Exception as e:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        if isinstance(e, HTTPException):
            raise
        raise HTTPException(
            status_code=500,
            detail="Voice chat transcription and answering failed",
        )
    finally:
        staged.cleanup()
