"""
Social Media Helper Router.

Endpoints:
  POST /api/v1/listings/{listing_id}/social-draft   — generate for a saved listing
  POST /api/v1/listings/unsaved/social-draft         — generate for an unsaved add-flow draft
  PUT  /api/v1/social-drafts/{draft_id}              — save / update caption + hashtags
  GET  /api/v1/social-drafts/{draft_id}              — reload an existing draft
"""

import json
import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.db_models import SocialDraftDB
from ..models.schemas import (
    SocialDraftRequest,
    SocialDraftUnsavedRequest,
    SocialDraftSaveRequest,
    SocialDraftResponse,
)
from ..services.social_media_service import SocialMediaService

router = APIRouter(tags=["Social Media Helper"])

# Lazily shared service instance (one per worker process)
_service: Optional[SocialMediaService] = None


def _get_service() -> SocialMediaService:
    global _service
    if _service is None:
        _service = SocialMediaService()
    return _service


# ── Helpers ──────────────────────────────────────────────────────────────────


def _draft_to_response(draft: SocialDraftDB) -> SocialDraftResponse:
    return SocialDraftResponse(
        draft_id=draft.id,
        caption=draft.caption or "",
        hashtags=draft.hashtags_list,
    )


def _upsert_draft(
    db: Session,
    *,
    caption: str,
    hashtags: list[str],
    image_url: str,
    source: str,
    listing_id: Optional[str] = None,
    draft_key: Optional[str] = None,
    edited_by_user: bool = False,
) -> SocialDraftDB:
    """
    Find an existing draft for (listing_id, image_url) or (draft_key, image_url)
    and update it; otherwise create a new row.
    """
    existing: Optional[SocialDraftDB] = None

    if listing_id:
        existing = (
            db.query(SocialDraftDB)
            .filter(
                SocialDraftDB.listing_id == listing_id,
                SocialDraftDB.image_url == image_url,
            )
            .first()
        )
    elif draft_key:
        existing = (
            db.query(SocialDraftDB)
            .filter(
                SocialDraftDB.draft_key == draft_key,
                SocialDraftDB.image_url == image_url,
            )
            .first()
        )

    if existing:
        existing.caption = caption
        existing.hashtags = json.dumps(hashtags)
        existing.source = source
        existing.edited_by_user = edited_by_user
        existing.updated_at = datetime.now()
        db.commit()
        db.refresh(existing)
        return existing

    new_draft = SocialDraftDB(
        id=f"sd_{uuid.uuid4().hex[:16]}",
        listing_id=listing_id,
        draft_key=draft_key,
        image_url=image_url,
        caption=caption,
        hashtags=json.dumps(hashtags),
        source=source,
        edited_by_user=edited_by_user,
    )
    db.add(new_draft)
    db.commit()
    db.refresh(new_draft)
    return new_draft


# ── Endpoints ────────────────────────────────────────────────────────────────


@router.get(
    "/api/v1/social-drafts/lookup",
    response_model=SocialDraftResponse,
    summary="Find a saved social draft by listing or draft key and image",
)
async def lookup_draft(
    image_url: str = Query(...),
    listing_id: Optional[str] = Query(None),
    draft_key: Optional[str] = Query(None),
    db: Session = Depends(get_db),
) -> SocialDraftResponse:
    """Return a saved draft for an image, or 404 when none exists."""
    if not listing_id and not draft_key:
        raise HTTPException(
            status_code=400,
            detail="Either listing_id or draft_key is required.",
        )

    query = db.query(SocialDraftDB).filter(SocialDraftDB.image_url == image_url)
    if listing_id:
        query = query.filter(SocialDraftDB.listing_id == listing_id)
    else:
        query = query.filter(SocialDraftDB.draft_key == draft_key)

    draft = query.order_by(SocialDraftDB.updated_at.desc()).first()
    if not draft and listing_id:
        draft = (
            db.query(SocialDraftDB)
            .filter(SocialDraftDB.listing_id == listing_id)
            .order_by(SocialDraftDB.updated_at.desc())
            .first()
        )
    if not draft:
        raise HTTPException(status_code=404, detail="Social draft not found.")
    return _draft_to_response(draft)


@router.post(
    "/api/v1/social-drafts/link",
    response_model=dict,
    summary="Link add-flow social drafts to a newly published listing",
)
async def link_drafts_to_listing(
    draft_key: str = Query(...),
    listing_id: str = Query(...),
    db: Session = Depends(get_db),
) -> dict:
    """Associate all drafts from an add-flow draft key with its listing."""
    updated = (
        db.query(SocialDraftDB)
        .filter(SocialDraftDB.draft_key == draft_key)
        .update({SocialDraftDB.listing_id: listing_id}, synchronize_session=False)
    )
    db.commit()
    return {"linked_count": updated}


@router.post(
    "/api/v1/listings/unsaved/social-draft",
    response_model=SocialDraftResponse,
    summary="Generate social-media caption + hashtags for an unsaved add-flow draft",
)
async def generate_for_unsaved_priority(
    body: SocialDraftUnsavedRequest,
    db: Session = Depends(get_db),
    service: SocialMediaService = Depends(_get_service),
) -> SocialDraftResponse:
    """Handle the static unsaved path before the dynamic listing path."""
    rate_key = f"{body.draft_key}:{body.image_url}"
    result = await service.generate(
        image_url=body.image_url,
        title=body.title or "",
        category=body.category or "",
        materials=body.materials or [],
        description=body.description or "",
        tone=body.tone or "warm and authentic",
        locale=body.locale or "en-US",
        rate_limit_key=rate_key,
    )
    draft = _upsert_draft(
        db,
        caption=result["caption"],
        hashtags=result["hashtags"],
        image_url=body.image_url,
        source=body.source,
        draft_key=body.draft_key,
    )
    return _draft_to_response(draft)


@router.post(
    "/api/v1/listings/{listing_id}/social-draft",
    response_model=SocialDraftResponse,
    summary="Generate social-media caption + hashtags for a saved listing",
)
async def generate_for_listing(
    listing_id: str,
    body: SocialDraftRequest,
    db: Session = Depends(get_db),
    service: SocialMediaService = Depends(_get_service),
) -> SocialDraftResponse:
    """
    Call the Gemini vision model to produce an AI-drafted caption and
    hashtag set for the given image/listing.  Rate-limited to
    5 regenerations per (listing, image) per hour.
    """
    rate_key = f"{listing_id}:{body.image_url}"
    result = await service.generate(
        image_url=body.image_url,
        title=body.title or "",
        category=body.category or "",
        materials=body.materials or [],
        description=body.description or "",
        tone=body.tone or "warm and authentic",
        locale=body.locale or "en-US",
        rate_limit_key=rate_key,
    )

    draft = _upsert_draft(
        db,
        caption=result["caption"],
        hashtags=result["hashtags"],
        image_url=body.image_url,
        source=body.source,
        listing_id=listing_id,
    )
    return _draft_to_response(draft)


@router.put(
    "/api/v1/social-drafts/{draft_id}",
    response_model=SocialDraftResponse,
    summary="Save / update caption and hashtags (user edits)",
)
async def save_draft(
    draft_id: str,
    body: SocialDraftSaveRequest,
    db: Session = Depends(get_db),
) -> SocialDraftResponse:
    """
    Persist the user's edits to an existing draft.
    Sets edited_by_user = True when the user has made changes.
    """
    draft = db.query(SocialDraftDB).filter(SocialDraftDB.id == draft_id).first()
    if not draft:
        raise HTTPException(status_code=404, detail="Social draft not found.")

    draft.caption = body.caption
    draft.hashtags = json.dumps(body.hashtags)
    draft.edited_by_user = body.edited_by_user
    draft.updated_at = datetime.now()
    db.commit()
    db.refresh(draft)
    return _draft_to_response(draft)


@router.get(
    "/api/v1/social-drafts/{draft_id}",
    response_model=SocialDraftResponse,
    summary="Reload an existing social-media draft",
)
async def get_draft(
    draft_id: str,
    db: Session = Depends(get_db),
) -> SocialDraftResponse:
    """Return a previously generated / saved social-media draft by its ID."""
    draft = db.query(SocialDraftDB).filter(SocialDraftDB.id == draft_id).first()
    if not draft:
        raise HTTPException(status_code=404, detail="Social draft not found.")
    return _draft_to_response(draft)
