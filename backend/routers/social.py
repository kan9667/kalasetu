"""
Social Media Helper Router.

Endpoints with complete tenant isolation:
  GET  /api/v1/social-drafts/lookup    — find a saved draft by (listing/draft_key, image)
  POST /api/v1/social-drafts/generate  — generate caption + hashtags for listing or draft
  POST /api/v1/social-drafts/link      — link add-flow drafts to a published listing
  PUT  /api/v1/social-drafts/{draft_id}— persist manual caption / hashtag edits
"""

import json
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.db_models import ArtisanDB, ProductDB, SocialDraftDB
from ..models.schemas import (
    SocialDraftRequest,
    SocialDraftUnsavedRequest,
    SocialDraftSaveRequest,
    SocialDraftResponse,
)
from ..services.social_media_service import SocialMediaService
from ..utils.auth import get_current_artisan

router = APIRouter(tags=["Social Media Helper"])

# Lazily shared service instance (one per worker process)
_service: Optional[SocialMediaService] = None


def _get_service() -> SocialMediaService:
    global _service
    if _service is None:
        _service = SocialMediaService()
    return _service


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
    artisan_id: str,
    channel: str = "instagram",
    listing_id: Optional[str] = None,
    draft_key: Optional[str] = None,
    edited_by_user: bool = False,
) -> SocialDraftDB:
    existing: Optional[SocialDraftDB] = None

    if listing_id:
        existing = (
            db.query(SocialDraftDB)
            .filter(
                SocialDraftDB.listing_id == listing_id,
                SocialDraftDB.image_url == image_url,
                SocialDraftDB.channel == channel,
                SocialDraftDB.artisan_id == artisan_id,
            )
            .first()
        )
    elif draft_key:
        existing = (
            db.query(SocialDraftDB)
            .filter(
                SocialDraftDB.draft_key == draft_key,
                SocialDraftDB.image_url == image_url,
                SocialDraftDB.channel == channel,
                SocialDraftDB.artisan_id == artisan_id,
            )
            .first()
        )

    now = datetime.now(timezone.utc)
    if existing:
        existing.caption = caption
        existing.hashtags = json.dumps(hashtags)
        existing.source = source
        existing.channel = channel
        existing.edited_by_user = edited_by_user
        existing.updated_at = now
        db.commit()
        db.refresh(existing)
        return existing

    new_draft = SocialDraftDB(
        id=f"sd_{uuid.uuid4().hex[:16]}",
        artisan_id=artisan_id,
        listing_id=listing_id,
        draft_key=draft_key,
        image_url=image_url,
        channel=channel,
        caption=caption,
        hashtags=json.dumps(hashtags),
        source=source,
        edited_by_user=edited_by_user,
        created_at=now,
        updated_at=now,
    )
    db.add(new_draft)
    db.commit()
    db.refresh(new_draft)
    return new_draft


# ── Endpoints ────────────────────────────────────────────────────────────────


@router.get(
    "/api/v1/social-drafts/lookup",
    response_model=SocialDraftResponse,
    summary="Find a saved social draft with tenant ownership check",
)
async def lookup_draft(
    image_url: str = Query(...),
    listing_id: Optional[str] = Query(None),
    draft_key: Optional[str] = Query(None),
    channel: Optional[str] = Query(None),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
) -> SocialDraftResponse:
    """Return a saved draft for an image and channel owned by the caller."""
    if not listing_id and not draft_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Either listing_id or draft_key is required.",
        )

    if listing_id:
        # Verify product ownership
        product = db.query(ProductDB).filter(ProductDB.id == listing_id).first()
        if not product or product.artisan_id != artisan.id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Social draft not found.",
            )

    query = (
        db.query(SocialDraftDB)
        .filter(
            SocialDraftDB.image_url == image_url,
            SocialDraftDB.artisan_id == artisan.id,
        )
    )
    if listing_id:
        query = query.filter(SocialDraftDB.listing_id == listing_id)
    else:
        query = query.filter(SocialDraftDB.draft_key == draft_key)
    if channel:
        query = query.filter(SocialDraftDB.channel == channel)

    draft = query.order_by(SocialDraftDB.updated_at.desc()).first()
    if draft:
        return _draft_to_response(draft)

    # Fallback for listing
    if listing_id:
        fallback_query = db.query(SocialDraftDB).filter(
            SocialDraftDB.listing_id == listing_id,
            SocialDraftDB.artisan_id == artisan.id,
        )
        if channel:
            fallback_query = fallback_query.filter(SocialDraftDB.channel == channel)
        fallback = fallback_query.order_by(SocialDraftDB.updated_at.desc()).first()
        if fallback:
            return _draft_to_response(fallback)

    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Social draft not found.")


@router.post(
    "/api/v1/social-drafts/link",
    response_model=dict,
    summary="Link add-flow social drafts to a newly published listing",
)
async def link_drafts_to_listing(
    draft_key: str = Query(...),
    listing_id: str = Query(...),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
) -> dict:
    """Associate all drafts from an add-flow draft key with its listing with ownership checks."""
    product = db.query(ProductDB).filter(ProductDB.id == listing_id).first()
    if not product or product.artisan_id != artisan.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: Cannot link drafts to a product you do not own.",
        )

    updated = (
        db.query(SocialDraftDB)
        .filter(
            SocialDraftDB.draft_key == draft_key,
            SocialDraftDB.artisan_id == artisan.id,
        )
        .update({SocialDraftDB.listing_id: listing_id}, synchronize_session=False)
    )
    db.commit()
    return {"linked_count": updated}


@router.post(
    "/api/v1/social-drafts/generate",
    response_model=SocialDraftResponse,
    summary="Generate social-media caption + hashtags for a listing or draft",
)
async def generate_draft(
    body: SocialDraftRequest,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
    service: SocialMediaService = Depends(_get_service),
) -> SocialDraftResponse:
    """
    Generate an AI-drafted caption and hashtag set scoped to the authenticated artisan.
    """
    if body.listing_id:
        product = db.query(ProductDB).filter(ProductDB.id == body.listing_id).first()
        if not product or product.artisan_id != artisan.id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Product not found",
            )

    channel = (body.channel or "instagram").lower()
    rate_key = f"{body.listing_id or body.draft_key or 'unknown'}:{body.image_url}:{channel}"
    result = await service.generate(
        image_url=body.image_url,
        title=body.title or "",
        category=body.category or "",
        materials=body.materials or [],
        description=body.description or "",
        tone=body.tone or "warm and authentic",
        locale=body.locale or "en-US",
        channel=channel,
        rate_limit_key=rate_key,
    )

    draft = _upsert_draft(
        db,
        caption=result["caption"],
        hashtags=result["hashtags"],
        image_url=body.image_url,
        source=body.source,
        artisan_id=artisan.id,
        channel=channel,
        listing_id=body.listing_id,
        draft_key=body.draft_key,
    )
    return _draft_to_response(draft)


@router.post(
    "/api/v1/listings/unsaved/social-draft",
    response_model=SocialDraftResponse,
    include_in_schema=False,
)
async def generate_for_unsaved_priority(
    body: SocialDraftUnsavedRequest,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
    service: SocialMediaService = Depends(_get_service),
) -> SocialDraftResponse:
    return await generate_draft(body, artisan, db, service)


@router.post(
    "/api/v1/listings/{listing_id}/social-draft",
    response_model=SocialDraftResponse,
    include_in_schema=False,
)
async def generate_for_listing(
    listing_id: str,
    body: SocialDraftRequest,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
    service: SocialMediaService = Depends(_get_service),
) -> SocialDraftResponse:
    body.listing_id = listing_id
    return await generate_draft(body, artisan, db, service)


@router.put(
    "/api/v1/social-drafts/{draft_id}",
    response_model=SocialDraftResponse,
    summary="Save / update caption and hashtags (user edits)",
)
async def save_draft(
    draft_id: str,
    body: SocialDraftSaveRequest,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
) -> SocialDraftResponse:
    """Persist user edits to a draft with tenant ownership verification."""
    draft = db.query(SocialDraftDB).filter(SocialDraftDB.id == draft_id).first()
    if not draft or draft.artisan_id != artisan.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Social draft not found.")

    draft.caption = body.caption
    draft.hashtags = json.dumps(body.hashtags)
    draft.edited_by_user = body.edited_by_user
    draft.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(draft)
    return _draft_to_response(draft)
