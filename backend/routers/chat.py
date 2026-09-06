"""
KalaMitra Chatbot & Agent Navigation Router.

Exposes conversational AI assistance and navigation agent endpoints for KalaSetu.
"""

import time
from collections import defaultdict
from typing import List, Dict, Any, Optional
from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form, Request

from ..models.schemas import (
    ChatRequestSchema,
    ChatResponseSchema,
    VoiceChatResponseSchema,
)
from ..services.chat_service import ChatService
from ..services.catalog_service import CatalogService
from ..services.storage_service import StorageService

router = APIRouter(prefix="/api/v1/chat", tags=["KalaMitra Assistant"])
chat_service = ChatService()
catalog_service = CatalogService()
storage_service = StorageService()

# ── In-Memory Rate Limiter (20 requests per minute per client IP) ─────────────
RATE_LIMIT_WINDOW_SECONDS = 60
MAX_REQUESTS_PER_WINDOW = 20
_client_request_timestamps: Dict[str, List[float]] = defaultdict(list)


def _enforce_rate_limit(req: Request) -> None:
    client_ip = req.client.host if req.client else "127.0.0.1"
    now = time.time()
    cutoff = now - RATE_LIMIT_WINDOW_SECONDS
    _client_request_timestamps[client_ip] = [
        t for t in _client_request_timestamps[client_ip] if t > cutoff
    ]
    if len(_client_request_timestamps[client_ip]) >= MAX_REQUESTS_PER_WINDOW:
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. KalaMitra is limited to 20 requests per minute to prevent key abuse.",
        )
    _client_request_timestamps[client_ip].append(now)


@router.post("/message", response_model=ChatResponseSchema)
async def send_chat_message(
    request: ChatRequestSchema,
    raw_req: Request,
) -> ChatResponseSchema:
    """
    Process a user message with KalaMitra AI assistant.
    Returns an informative answer, optional in-app navigation action, and follow-up suggestion chips.
    Protected by domain guardrails and rate limiting.
    """
    _enforce_rate_limit(raw_req)
    try:
        response = await chat_service.process_message(request)
        return response
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to process chat message: {str(e)}",
        )


@router.get("/quick-topics")
async def get_quick_topics() -> Dict[str, Any]:
    """
    Returns curated starter topics and sample queries for new chat conversations.
    """
    return {
        "welcome_message": "Namaste! I am KalaMitra, your guide for KalaSetu. How can I assist you today?",
        "welcome_message_hi": "नमस्ते! मैं कला-मित्र हूँ, कलासेतु में आपका सहायक। आज मैं आपकी क्या मदद कर सकता हूँ?",
        "topics": [
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
                "id": "offline",
                "label": "Offline Mode",
                "label_hi": "ऑफ़लाइन मोड",
                "query": "Can I list products without internet?",
                "query_hi": "क्या बिना इंटरनेट के काम कर सकते हैं?",
                "icon": "cloud_off",
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
    language_code: str = Form("hi", description="Spoken language code (e.g. hi, en)"),
    current_screen: Optional[str] = Form(None, description="Screen context where audio was recorded"),
) -> VoiceChatResponseSchema:
    """
    Process an artisan's spoken voice note with KalaMitra using Whisper STT.
    Transcribes audio using the configured Whisper API, then generates conversational answer + navigation action.
    Protected by rate limits.
    """
    _enforce_rate_limit(raw_req)
    is_hi = language_code == "hi"

    try:
        audio_url = await storage_service.save_upload(audio, subfolder="chat_audio")
        local_path = storage_service.get_local_path_from_url(audio_url)
        if not local_path:
            raise HTTPException(status_code=500, detail="Failed to locate saved chat audio file")

        # Transcribe with Whisper (category_hint=None for natural conversation)
        try:
            transcribe_res = await catalog_service.transcribe_audio(
                audio_file_path=str(local_path),
                language_code=language_code,
                category_hint=None,
            )
            user_transcript = (transcribe_res.transcript or "").strip()
        except ValueError as ve:
            # Silent audio or empty speech
            return VoiceChatResponseSchema(
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

        if not user_transcript:
            return VoiceChatResponseSchema(
                user_transcript="",
                reply=(
                    "कोई आवाज़ रिकॉर्ड नहीं हुई। कृपया दोबारा बोलकर प्रश्न पूछें।"
                    if is_hi
                    else "No speech was detected. Please tap the mic and try asking your question again."
                ),
                action=None,
                suggested_queries=[],
            )

        # Process user question with KalaMitra AI Chatbot
        chat_req = ChatRequestSchema(
            message=user_transcript,
            language_code=language_code,
            current_screen=current_screen,
        )
        chat_res = await chat_service.process_message(chat_req)

        return VoiceChatResponseSchema(
            user_transcript=user_transcript,
            reply=chat_res.reply,
            action=chat_res.action,
            suggested_queries=chat_res.suggested_queries,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Voice chat transcription and answering failed: {str(e)}",
        )

