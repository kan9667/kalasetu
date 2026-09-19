"""
Product Management Router.

Enforces:
- Complete tenant isolation across all private routes.
- Required Idempotency-Key header on all mutating endpoints (create, update, delete, approve, sync).
- Server-enforced lifecycle: draft -> awaiting_approval -> approved -> published -> deleted.
- Rejection of client-controlled status and client image URLs (HTTP 422).
- Server-resolved media assets and deterministic content hashing bound to byte checksums.
- Immutable revision snapshots in ProductRevisionDB upon explicit approval.
- Derivation of public catalogue content strictly from ProductRevisionDB.
- Atomic unpublishing on any product mutation before applying edits.
- Integer paise pricing and authoritative server cost floor enforcement.
- Optimistic locking concurrency control via expected_revision.
- Soft-delete tombstone policy preserving audit history in ProductRevisionDB.
"""

import json
import uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.db_models import (
    ArtisanDB,
    MediaAssetDB,
    ProductDB,
    ProductRevisionDB,
    ProductStatus,
)
from ..models.schemas import (
    ProductApproveAndPublishRequest,
    ProductCreate,
    ProductResponse,
    ProductSyncBatch,
    ProductSyncItem,
    ProductSyncResponse,
    ProductUnpublishRequest,
    ProductUpdate,
    PublicProductResponse,
)
from ..utils.auth import get_current_artisan
from ..utils.hashing import compute_content_hash
from ..utils.idempotency import (
    claim_idempotency,
    complete_idempotency,
    compute_request_fingerprint,
    release_idempotency_claim,
    require_idempotency_key,
)
from ..utils.pricing import (
    calculate_cost_floor_paise,
    paise_to_rupees,
    rupees_to_paise,
    validate_price_against_floor,
)

router = APIRouter(prefix="/api/v1/products", tags=["Products"])


def _db_to_response(item: ProductDB) -> ProductResponse:
    """Serialize ProductDB to ProductResponse schema with server-derived media URL."""
    display_image_url = ""
    if item.media_id:
        if item.status == ProductStatus.PUBLISHED.value and item.approved_revision == item.revision:
            display_image_url = f"/api/v1/media/{item.media_id}/public"
        else:
            display_image_url = f"/api/v1/media/{item.media_id}"

    return ProductResponse(
        id=item.id,
        artisan_id=item.artisan_id,
        title=item.title,
        title_hi=item.title_hi or "",
        description=item.description or "",
        description_hi=item.description_hi or "",
        price=item.get_price_rupees(),
        image_url=display_image_url,
        media_id=item.media_id,
        category=item.category or "General",
        tags=item.tags_list,
        materials=item.get_materials_rupees(),
        labor_hours=item.labor_hours or 0.0,
        hourly_rate=item.get_hourly_rate_rupees(),
        transport=item.get_transport_rupees(),
        overhead=item.get_overhead_rupees(),
        status=item.status,
        revision=item.revision,
        approved_revision=item.approved_revision,
        approved_at=item.approved_at,
        approved_by_artisan_id=item.approved_by_artisan_id,
        published_at=item.published_at,
        content_hash=item.content_hash,
        floor_price=item.get_floor_price_rupees(),
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


# ── Public Catalogue Endpoint ────────────────────────────────────────────────


@router.get("/public", response_model=List[PublicProductResponse])
async def list_public_catalogue(
    category: Optional[str] = Query(None, description="Filter by craft category"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """
    Public catalogue endpoint for marketplace and external shoppers.
    Returns ONLY active published listings derived strictly from ProductRevisionDB.
    Strictly excludes drafts, unapproved revisions, soft-deleted items, and legacy unverified items.
    """
    query = (
        db.query(ProductRevisionDB)
        .join(ProductDB, ProductDB.id == ProductRevisionDB.product_id)
        .filter(
            ProductDB.status == ProductStatus.PUBLISHED.value,
            ProductDB.is_deleted == False,
            ProductDB.approved_revision == ProductRevisionDB.revision,
        )
    )

    if category:
        query = query.filter(ProductRevisionDB.category.ilike(f"%{category}%"))

    revisions = query.order_by(ProductRevisionDB.published_at.desc()).offset(offset).limit(limit).all()

    return [
        PublicProductResponse(
            id=rev.product_id,
            title=rev.title,
            title_hi=rev.title_hi or "",
            description=rev.description or "",
            description_hi=rev.description_hi or "",
            price=rev.get_price_rupees(),
            image_url=rev.public_media_url,
            category=rev.category or "General",
            tags=rev.tags_list,
            status=ProductStatus.PUBLISHED.value,
            published_at=rev.published_at,
        )
        for rev in revisions
    ]


# ── Private Artisan Routes (Strict Tenant Isolation) ────────────────────────


@router.get("", response_model=List[ProductResponse])
async def list_artisan_products(
    category: Optional[str] = Query(None, description="Filter by craft category"),
    limit: int = Query(100, ge=1, le=200),
    offset: int = Query(0, ge=0),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """List authenticated artisan's products (excluding soft-deleted)."""
    query = db.query(ProductDB).filter(
        ProductDB.artisan_id == artisan.id,
        ProductDB.is_deleted == False,
    )
    if category:
        query = query.filter(ProductDB.category.ilike(f"%{category}%"))

    items = query.order_by(ProductDB.created_at.desc()).offset(offset).limit(limit).all()
    return [_db_to_response(item) for item in items]


@router.get("/{product_id}", response_model=ProductResponse)
async def get_product(
    product_id: str,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """Retrieve single product by ID. Enforces tenant ownership."""
    item = (
        db.query(ProductDB)
        .filter(
            ProductDB.id == product_id,
            ProductDB.artisan_id == artisan.id,
            ProductDB.is_deleted == False,
        )
        .first()
    )
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Product not found",
        )

    return _db_to_response(item)


@router.post("", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
async def create_product(
    request: Request,
    product: ProductCreate,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Create a new artisan product draft.
    Requires Idempotency-Key.
    Enforces:
    - Status is strictly forced to 'draft'.
    - Server-resolved media asset verification.
    - Authoritative server cost floor calculation and validation.
    - Deterministic initial content_hash with revision=1.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = "/api/v1/products"
    request_hash = compute_request_fingerprint("POST", endpoint, product.model_dump(mode="json"))

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
            status_code=cached_status or status.HTTP_201_CREATED,
            media_type="application/json",
        )

    try:
        prod_id = product.id if product.id else f"prod_{uuid.uuid4().hex[:10]}"

        price_paise = rupees_to_paise(product.price)
        materials_paise = rupees_to_paise(product.materials)
        hourly_rate_paise = rupees_to_paise(product.hourly_rate) if product.hourly_rate > 0 else 5000
        transport_paise = rupees_to_paise(product.transport)
        overhead_paise = rupees_to_paise(product.overhead)

        floor_paise = calculate_cost_floor_paise(
            materials_paise=materials_paise,
            labor_hours=product.labor_hours,
            hourly_rate_paise=hourly_rate_paise,
            transport_paise=transport_paise,
            overhead_paise=overhead_paise,
        )
        validate_price_against_floor(price_paise, floor_paise)

        # Resolve media asset if provided
        media_checksum = ""
        if product.media_id:
            media_asset = (
                db.query(MediaAssetDB)
                .filter(
                    MediaAssetDB.id == product.media_id,
                    MediaAssetDB.artisan_id == artisan.id,
                    MediaAssetDB.status == "ready",
                )
                .first()
            )
            if not media_asset:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Provided media_id is not ready or does not belong to this artisan.",
                )
            media_checksum = media_asset.sha256_checksum

        chash = compute_content_hash(
            title=product.title,
            title_hi=product.title_hi,
            description=product.description,
            description_hi=product.description_hi,
            price_paise=price_paise,
            category=product.category,
            tags=product.tags,
            floor_price_paise=floor_paise,
            media_id=product.media_id or "",
            media_checksum=media_checksum,
        )

        now = datetime.now(timezone.utc)
        db_item = ProductDB(
            id=prod_id,
            artisan_id=artisan.id,
            title=product.title,
            title_hi=product.title_hi or "",
            description=product.description,
            description_hi=product.description_hi or "",
            legacy_price=product.price,
            price_paise=price_paise,
            floor_price_paise=floor_paise,
            materials_paise=materials_paise,
            labor_hours=product.labor_hours,
            hourly_rate_paise=hourly_rate_paise,
            transport_paise=transport_paise,
            overhead_paise=overhead_paise,
            image_url="",
            media_id=product.media_id,
            category=product.category,
            tags=json.dumps(product.tags),
            status=ProductStatus.DRAFT.value,
            revision=1,
            approved_revision=None,
            approved_at=None,
            approved_by_artisan_id=None,
            published_at=None,
            content_hash=chash,
            is_deleted=False,
            created_at=product.created_at or now,
            updated_at=now,
        )

        db.add(db_item)
        db.flush()

        res = _db_to_response(db_item)
        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_201_CREATED,
            response_data=res.model_dump(mode="json"),
        )
        db.commit()
        db.refresh(db_item)

        return res
    except Exception:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        raise


@router.put("/{product_id}", response_model=ProductResponse)
async def update_product(
    request: Request,
    product_id: str,
    update_data: ProductUpdate,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Update product draft attributes.
    Requires Idempotency-Key.
    Enforces:
    - Optimistic locking concurrency control via expected_revision.
    - If currently published, atomically unpublishes before applying edits.
    - Increments revision, recomputes hash with server-verified media checksum.
    - Invalidate approvals and resets status strictly to 'draft'.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = f"/api/v1/products/{product_id}"
    request_hash = compute_request_fingerprint("PUT", endpoint, update_data.model_dump(mode="json"))

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

    try:
        db_item = (
            db.query(ProductDB)
            .filter(
                ProductDB.id == product_id,
                ProductDB.artisan_id == artisan.id,
                ProductDB.is_deleted == False,
            )
            .first()
        )
        if not db_item:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Product not found",
            )

        # Concurrency control: verify expected_revision
        if update_data.expected_revision is not None and update_data.expected_revision != db_item.revision:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Revision conflict: expected revision {update_data.expected_revision} but current server revision is {db_item.revision}.",
            )

        # Atomically unpublish if currently published
        if db_item.status == ProductStatus.PUBLISHED.value:
            db_item.status = ProductStatus.DRAFT.value
            db_item.approved_revision = None
            db_item.approved_at = None
            db_item.published_at = None
            db_item.approved_by_artisan_id = None

        # Compute updated price & cost fields in integer paise
        new_price_paise = (
            rupees_to_paise(update_data.price) if update_data.price is not None else db_item.price_paise
        )
        new_materials_paise = (
            rupees_to_paise(update_data.materials)
            if update_data.materials is not None
            else db_item.materials_paise
        )
        new_labor_hours = (
            update_data.labor_hours if update_data.labor_hours is not None else db_item.labor_hours
        )
        new_hourly_rate_paise = (
            rupees_to_paise(update_data.hourly_rate)
            if update_data.hourly_rate is not None
            else db_item.hourly_rate_paise
        )
        new_transport_paise = (
            rupees_to_paise(update_data.transport)
            if update_data.transport is not None
            else db_item.transport_paise
        )
        new_overhead_paise = (
            rupees_to_paise(update_data.overhead)
            if update_data.overhead is not None
            else db_item.overhead_paise
        )

        new_floor_paise = calculate_cost_floor_paise(
            materials_paise=new_materials_paise,
            labor_hours=new_labor_hours,
            hourly_rate_paise=new_hourly_rate_paise,
            transport_paise=new_transport_paise,
            overhead_paise=new_overhead_paise,
        )
        validate_price_against_floor(new_price_paise, new_floor_paise)

        # Resolve media asset identity & server checksum
        if update_data.media_id is not None:
            media_asset = (
                db.query(MediaAssetDB)
                .filter(
                    MediaAssetDB.id == update_data.media_id,
                    MediaAssetDB.artisan_id == artisan.id,
                    MediaAssetDB.status == "ready",
                )
                .first()
            )
            if not media_asset:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Provided media_id is not ready or does not belong to this artisan.",
                )
            new_media_id = update_data.media_id
            new_media_checksum = media_asset.sha256_checksum
        else:
            new_media_id = db_item.media_id
            if new_media_id:
                asset = (
                    db.query(MediaAssetDB)
                    .filter(
                        MediaAssetDB.id == new_media_id,
                        MediaAssetDB.artisan_id == artisan.id,
                        MediaAssetDB.status == "ready",
                    )
                    .first()
                )
                new_media_checksum = asset.sha256_checksum if asset else ""
            else:
                new_media_checksum = ""

        new_title = update_data.title if update_data.title is not None else db_item.title
        new_title_hi = update_data.title_hi if update_data.title_hi is not None else db_item.title_hi
        new_desc = update_data.description if update_data.description is not None else db_item.description
        new_desc_hi = update_data.description_hi if update_data.description_hi is not None else db_item.description_hi
        new_category = update_data.category if update_data.category is not None else db_item.category
        new_tags = update_data.tags if update_data.tags is not None else db_item.tags_list

        new_hash = compute_content_hash(
            title=new_title,
            title_hi=new_title_hi,
            description=new_desc,
            description_hi=new_desc_hi,
            price_paise=new_price_paise,
            category=new_category,
            tags=new_tags,
            floor_price_paise=new_floor_paise,
            media_id=new_media_id or "",
            media_checksum=new_media_checksum,
        )

        # Apply updates
        db_item.title = new_title
        db_item.title_hi = new_title_hi
        db_item.description = new_desc
        db_item.description_hi = new_desc_hi
        db_item.category = new_category
        db_item.tags = json.dumps(new_tags)
        db_item.price_paise = new_price_paise
        db_item.legacy_price = paise_to_rupees(new_price_paise)
        db_item.floor_price_paise = new_floor_paise
        db_item.materials_paise = new_materials_paise
        db_item.labor_hours = new_labor_hours
        db_item.hourly_rate_paise = new_hourly_rate_paise
        db_item.transport_paise = new_transport_paise
        db_item.overhead_paise = new_overhead_paise
        db_item.media_id = new_media_id
        db_item.image_url = ""

        # Content mutations bump revision, update hash, and clear approval metadata
        db_item.revision += 1
        db_item.content_hash = new_hash
        db_item.approved_revision = None
        db_item.approved_at = None
        db_item.approved_by_artisan_id = None
        db_item.published_at = None
        db_item.status = ProductStatus.DRAFT.value
        db_item.updated_at = datetime.now(timezone.utc)

        db.flush()
        res = _db_to_response(db_item)

        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=res.model_dump(mode="json"),
        )
        db.commit()
        db.refresh(db_item)

        return res
    except Exception:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        raise


@router.delete("/{product_id}")
async def delete_product(
    request: Request,
    product_id: str,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Soft-delete / tombstone a product.
    Requires Idempotency-Key.
    Policy:
    - Retains ProductRevisionDB records for immutable audit history.
    - Sets is_deleted=True, status='deleted', and clears publication metadata.
    - Product is permanently excluded from public catalogue and artisan listings.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = f"/api/v1/products/{product_id}"
    request_hash = compute_request_fingerprint("DELETE", endpoint, "")

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

    try:
        db_item = (
            db.query(ProductDB)
            .filter(
                ProductDB.id == product_id,
                ProductDB.artisan_id == artisan.id,
                ProductDB.is_deleted == False,
            )
            .first()
        )
        if not db_item:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Product not found",
            )

        now = datetime.now(timezone.utc)
        db_item.is_deleted = True
        db_item.status = ProductStatus.DELETED.value
        db_item.approved_revision = None
        db_item.published_at = None
        db_item.updated_at = now

        res_body = {"status": "success", "id": product_id, "deleted": True}
        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=res_body,
        )
        db.commit()

        return res_body
    except Exception:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        raise


@router.post("/{product_id}/approve-and-publish", response_model=ProductResponse)
async def approve_and_publish_product(
    request: Request,
    product_id: str,
    payload: ProductApproveAndPublishRequest,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Explicit Artisan Approval and Publication Boundary.
    Requires Idempotency-Key.
    Enforces:
    1. Tenant Ownership.
    2. Exact revision matching.
    3. Required validated MediaAsset with status='ready'.
    4. Deterministic content hash validation incorporating media byte checksum.
    5. Server-authoritative floor price check.
    6. Creates immutable snapshot in ProductRevisionDB.
    7. Atomically transitions state to 'published' and commits idempotency record.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = f"/api/v1/products/{product_id}/approve-and-publish"
    request_hash = compute_request_fingerprint("POST", endpoint, payload.model_dump(mode="json"))

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

    try:
        db_item = (
            db.query(ProductDB)
            .filter(
                ProductDB.id == product_id,
                ProductDB.artisan_id == artisan.id,
                ProductDB.is_deleted == False,
            )
            .first()
        )
        if not db_item:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Product not found",
            )

        # Concurrency / revision freshness check
        if payload.revision != db_item.revision:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Product revision is stale. "
                    f"Server revision={db_item.revision}, requested revision={payload.revision}. "
                    f"The draft has been modified since it was reviewed. Please review the updated draft before approving."
                ),
            )

        # State validation
        allowed_source_states = {
            ProductStatus.DRAFT.value,
            ProductStatus.AWAITING_APPROVAL.value,
            ProductStatus.APPROVED.value,
            ProductStatus.LEGACY_UNVERIFIED.value,
            ProductStatus.PENDING_APPROVAL_SYNC.value,
        }
        if db_item.status not in allowed_source_states:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Cannot publish product in '{db_item.status}' state.",
            )

        # Content requirements
        if not db_item.title or not db_item.title.strip():
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Product title is required before publication.",
            )
        if not db_item.description or not db_item.description.strip():
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Product description is required before publication.",
            )
        if db_item.price_paise <= 0:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Product price must be greater than zero.",
            )

        # Media Asset Verification: must have a server-owned MediaAsset with status='ready'
        if not db_item.media_id:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Publication requires a verified server-owned media asset. Phone-local or unconfirmed media cannot be published.",
            )

        media_asset = (
            db.query(MediaAssetDB)
            .filter(
                MediaAssetDB.id == db_item.media_id,
                MediaAssetDB.artisan_id == artisan.id,
                MediaAssetDB.status == "ready",
            )
            .first()
        )
        if not media_asset:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Server media asset is not ready or does not belong to this artisan.",
            )

        # Recompute authoritative server content hash with verified media checksum
        server_hash = compute_content_hash(
            title=db_item.title,
            title_hi=db_item.title_hi,
            description=db_item.description,
            description_hi=db_item.description_hi,
            price_paise=db_item.price_paise,
            category=db_item.category,
            tags=db_item.tags_list,
            floor_price_paise=db_item.floor_price_paise,
            media_id=media_asset.id,
            media_checksum=media_asset.sha256_checksum,
        )

        if payload.content_hash != server_hash:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Content hash mismatch. The approved draft content or media checksum does not match server state. "
                    f"Please inspect and approve the latest revision."
                ),
            )

        # Authoritative floor price check
        authoritative_floor_paise = calculate_cost_floor_paise(
            materials_paise=db_item.materials_paise,
            labor_hours=db_item.labor_hours,
            hourly_rate_paise=db_item.hourly_rate_paise,
            transport_paise=db_item.transport_paise,
            overhead_paise=db_item.overhead_paise,
        )
        validate_price_against_floor(db_item.price_paise, authoritative_floor_paise)

        now = datetime.now(timezone.utc)

        # Create immutable snapshot in ProductRevisionDB
        rev_snapshot = ProductRevisionDB(
            id=f"rev_{uuid.uuid4().hex[:12]}",
            product_id=db_item.id,
            artisan_id=artisan.id,
            revision=db_item.revision,
            title=db_item.title,
            title_hi=db_item.title_hi or "",
            description=db_item.description or "",
            description_hi=db_item.description_hi or "",
            price_paise=db_item.price_paise,
            floor_price_paise=db_item.floor_price_paise,
            category=db_item.category,
            tags=db_item.tags,
            media_id=media_asset.id,
            media_checksum=media_asset.sha256_checksum,
            media_mime_type=media_asset.mime_type,
            media_byte_size=media_asset.byte_size,
            public_media_url=f"/api/v1/media/{media_asset.id}/public",
            content_hash=server_hash,
            approved_by_artisan_id=artisan.id,
            approved_at=now,
            published_at=now,
            created_at=now,
        )
        db.add(rev_snapshot)

        # Transition product state to published
        db_item.approved_revision = db_item.revision
        db_item.approved_at = now
        db_item.approved_by_artisan_id = artisan.id
        db_item.published_at = now
        db_item.status = ProductStatus.PUBLISHED.value
        db_item.content_hash = server_hash
        db_item.updated_at = now

        db.flush()
        res = _db_to_response(db_item)

        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=res.model_dump(mode="json"),
        )
        db.commit()
        db.refresh(db_item)

        return res
    except Exception:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        raise


@router.post("/{product_id}/unpublish", response_model=ProductResponse)
async def unpublish_product(
    request: Request,
    product_id: str,
    payload: ProductUnpublishRequest,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Unpublish a published product and return it to 'draft' status.
    Requires Idempotency-Key.
    Requires expected_revision and content_hash for optimistic concurrency control.
    Clears approval metadata, increments revision, recomputes content_hash.
    Any subsequent relisting/publishing requires explicit artisan review and approval.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = f"/api/v1/products/{product_id}/unpublish"
    request_hash = compute_request_fingerprint(
        "POST",
        endpoint,
        {
            "product_id": product_id,
            "expected_revision": payload.expected_revision,
            "content_hash": payload.content_hash,
        },
    )

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

    try:
        item = (
            db.query(ProductDB)
            .filter(
                ProductDB.id == product_id,
                ProductDB.artisan_id == artisan.id,
                ProductDB.is_deleted.is_(False),
            )
            .first()
        )
        if not item:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Product not found",
            )

        # Concurrency / revision freshness check
        if payload.expected_revision != item.revision or payload.content_hash != (item.content_hash or ""):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Product revision is stale. "
                    f"Server revision={item.revision}, expected={payload.expected_revision}. "
                    f"Content hash matching={'yes' if payload.content_hash == (item.content_hash or '') else 'no'}. "
                    f"The product has been modified since it was loaded. Please refresh before unpublishing."
                ),
            )

        now = datetime.now(timezone.utc)
        if item.status == ProductStatus.PUBLISHED.value:
            item.status = ProductStatus.DRAFT.value
            item.revision += 1
            item.approved_revision = None
            item.approved_at = None
            item.approved_by_artisan_id = None
            item.published_at = None
            item.updated_at = now

            media_checksum = ""
            if item.media_id:
                asset = (
                    db.query(MediaAssetDB)
                    .filter(
                        MediaAssetDB.id == item.media_id,
                        MediaAssetDB.artisan_id == artisan.id,
                        MediaAssetDB.status == "ready",
                    )
                    .first()
                )
                media_checksum = asset.sha256_checksum if asset else ""

            item.content_hash = compute_content_hash(
                title=item.title,
                title_hi=item.title_hi or "",
                description=item.description or "",
                description_hi=item.description_hi or "",
                price_paise=item.price_paise,
                category=item.category or "General",
                tags=item.tags_list,
                floor_price_paise=item.floor_price_paise or 0,
                media_id=item.media_id or "",
                media_checksum=media_checksum,
            )

        db.flush()
        res = _db_to_response(item)

        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=res.model_dump(mode="json"),
        )
        db.commit()
        db.refresh(item)
        return res
    except Exception:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        raise


@router.post("/sync", response_model=ProductSyncResponse)
async def sync_offline_products(
    request: Request,
    batch: ProductSyncBatch,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Authenticated batch drain endpoint for offline sync outbox.
    Requires Idempotency-Key.
    Transaction policy: Strictly transactional all-or-nothing.
    Strictly creates/updates drafts ('draft'). Never auto-publishes.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = "/api/v1/products/sync"
    request_hash = compute_request_fingerprint("POST", endpoint, batch.model_dump(mode="json"))

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

    synced_items = []
    now = datetime.now(timezone.utc)

    try:
        for item in batch.products:
            prod_id = item.id if item.id else f"prod_{uuid.uuid4().hex[:10]}"
            price_paise = rupees_to_paise(item.price)
            materials_paise = rupees_to_paise(item.materials)
            hourly_rate_paise = rupees_to_paise(item.hourly_rate) if item.hourly_rate > 0 else 5000
            transport_paise = rupees_to_paise(item.transport)
            overhead_paise = rupees_to_paise(item.overhead)

            floor_paise = calculate_cost_floor_paise(
                materials_paise=materials_paise,
                labor_hours=item.labor_hours,
                hourly_rate_paise=hourly_rate_paise,
                transport_paise=transport_paise,
                overhead_paise=overhead_paise,
            )
            validate_price_against_floor(price_paise, floor_paise)

            media_checksum = ""
            if item.media_id:
                asset = (
                    db.query(MediaAssetDB)
                    .filter(
                        MediaAssetDB.id == item.media_id,
                        MediaAssetDB.artisan_id == artisan.id,
                        MediaAssetDB.status == "ready",
                    )
                    .first()
                )
                if asset:
                    media_checksum = asset.sha256_checksum

            chash = compute_content_hash(
                title=item.title,
                title_hi=item.title_hi,
                description=item.description,
                description_hi=item.description_hi,
                price_paise=price_paise,
                category=item.category,
                tags=item.tags,
                floor_price_paise=floor_paise,
                media_id=item.media_id or "",
                media_checksum=media_checksum,
            )

            existing = db.query(ProductDB).filter(ProductDB.id == prod_id).first()
            if existing:
                if existing.artisan_id and existing.artisan_id != artisan.id:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail=f"Forbidden: Cannot sync item {prod_id} owned by another artisan.",
                    )
                if item.expected_revision is None or item.expected_revision != existing.revision:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail=f"Conflict: Stale sync for item {prod_id}. Remote revision is {existing.revision}, expected {item.expected_revision}.",
                    )
                if existing.artisan_id is None:
                    existing.artisan_id = artisan.id
                existing.title = item.title
                existing.title_hi = item.title_hi or ""
                existing.description = item.description
                existing.description_hi = item.description_hi or ""
                existing.price_paise = price_paise
                existing.legacy_price = item.price
                existing.floor_price_paise = floor_paise
                existing.materials_paise = materials_paise
                existing.labor_hours = item.labor_hours
                existing.hourly_rate_paise = hourly_rate_paise
                existing.transport_paise = transport_paise
                existing.overhead_paise = overhead_paise
                existing.image_url = ""
                if item.media_id:
                    existing.media_id = item.media_id
                existing.category = item.category
                existing.tags = json.dumps(item.tags)
                existing.status = ProductStatus.DRAFT.value
                existing.revision += 1
                existing.content_hash = chash
                existing.approved_revision = None
                existing.approved_at = None
                existing.approved_by_artisan_id = None
                existing.published_at = None
                existing.is_deleted = False
                existing.updated_at = now
                db_item = existing
            else:
                db_item = ProductDB(
                    id=prod_id,
                    artisan_id=artisan.id,
                    title=item.title,
                    title_hi=item.title_hi or "",
                    description=item.description,
                    description_hi=item.description_hi or "",
                    legacy_price=item.price,
                    price_paise=price_paise,
                    floor_price_paise=floor_paise,
                    materials_paise=materials_paise,
                    labor_hours=item.labor_hours,
                    hourly_rate_paise=hourly_rate_paise,
                    transport_paise=transport_paise,
                    overhead_paise=overhead_paise,
                    image_url="",
                    media_id=item.media_id,
                    category=item.category,
                    tags=json.dumps(item.tags),
                    status=ProductStatus.DRAFT.value,
                    revision=1,
                    approved_revision=None,
                    approved_at=None,
                    approved_by_artisan_id=None,
                    published_at=None,
                    content_hash=chash,
                    is_deleted=False,
                    created_at=item.created_at or now,
                    updated_at=now,
                )
                db.add(db_item)

            synced_items.append(db_item)

        db.flush()
        response_payload = ProductSyncResponse(
            synced_count=len(synced_items),
            products=[_db_to_response(p) for p in synced_items],
        )

        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=response_payload.model_dump(mode="json"),
        )
        db.commit()

        return response_payload
    except Exception:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        raise
