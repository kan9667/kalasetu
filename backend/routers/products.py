"""
Product Management Router.

Provides product CRUD endpoints and batch sync for Flutter offline queue.
"""

import json
import uuid
from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.db_models import ProductDB
from ..models.schemas import (
    ProductCreate,
    ProductUpdate,
    ProductResponse,
    ProductSyncBatch,
    ProductSyncResponse,
)

router = APIRouter(prefix="/api/v1/products", tags=["Products"])


@router.get("", response_model=List[ProductResponse])
async def list_products(
    artisan_id: Optional[str] = Query(None, description="Filter by owner artisan ID"),
    category: Optional[str] = Query(None, description="Filter by craft category"),
    status: Optional[str] = Query(None, description="Filter by status (live, draft)"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """
    List all catalog products with optional category/status filters.
    """
    query = db.query(ProductDB)
    if artisan_id:
        query = query.filter(ProductDB.artisan_id == artisan_id)
    if category:
        query = query.filter(ProductDB.category.ilike(f"%{category}%"))
    if status:
        query = query.filter(ProductDB.status == status)

    items = query.order_by(ProductDB.created_at.desc()).offset(offset).limit(limit).all()

    return [
        ProductResponse(
            id=item.id,
            artisan_id=item.artisan_id,
            title=item.title,
            title_hi=item.title_hi or "",
            description=item.description or "",
            description_hi=item.description_hi or "",
            price=item.price,
            image_url=item.image_url,
            category=item.category,
            tags=item.tags_list,
            status=item.status,
            created_at=item.created_at,
            updated_at=item.updated_at,
        )
        for item in items
    ]


@router.get("/{product_id}", response_model=ProductResponse)
async def get_product(product_id: str, db: Session = Depends(get_db)):
    """Fetch a single product by ID."""
    item = db.query(ProductDB).filter(ProductDB.id == product_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Product not found")

    return ProductResponse(
        id=item.id,
        artisan_id=item.artisan_id,
        title=item.title,
        title_hi=item.title_hi or "",
        description=item.description or "",
        description_hi=item.description_hi or "",
        price=item.price,
        image_url=item.image_url,
        category=item.category,
        tags=item.tags_list,
        status=item.status,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


@router.post("", response_model=ProductResponse, status_code=201)
async def create_product(product: ProductCreate, db: Session = Depends(get_db)):
    """Create a new artisan product listing."""
    prod_id = product.id if product.id else f"prod_{uuid.uuid4().hex[:10]}"
    
    # Check if exists (idempotent for offline sync)
    existing = db.query(ProductDB).filter(ProductDB.id == prod_id).first()
    if existing:
        # Update existing
        existing.title = product.title
        existing.title_hi = product.title_hi or ""
        existing.description = product.description
        existing.description_hi = product.description_hi or ""
        existing.price = product.price
        existing.image_url = product.image_url
        existing.category = product.category
        existing.tags = json.dumps(product.tags)
        existing.status = product.status
        existing.updated_at = datetime.now()
        db.commit()
        db.refresh(existing)
        db_item = existing
    else:
        db_item = ProductDB(
            id=prod_id,
            artisan_id=product.artisan_id,
            title=product.title,
            title_hi=product.title_hi or "",
            description=product.description,
            description_hi=product.description_hi or "",
            price=product.price,
            image_url=product.image_url,
            category=product.category,
            tags=json.dumps(product.tags),
            status=product.status,
            created_at=product.created_at or datetime.now(),
        )
        db.add(db_item)
        db.commit()
        db.refresh(db_item)

    return ProductResponse(
        id=db_item.id,
        artisan_id=db_item.artisan_id,
        title=db_item.title,
        title_hi=db_item.title_hi or "",
        description=db_item.description or "",
        description_hi=db_item.description_hi or "",
        price=db_item.price,
        image_url=db_item.image_url,
        category=db_item.category,
        tags=db_item.tags_list,
        status=db_item.status,
        created_at=db_item.created_at,
        updated_at=db_item.updated_at,
    )


@router.put("/{product_id}", response_model=ProductResponse)
async def update_product(
    product_id: str,
    update_data: ProductUpdate,
    db: Session = Depends(get_db),
):
    """Update product fields."""
    db_item = db.query(ProductDB).filter(ProductDB.id == product_id).first()
    if not db_item:
        raise HTTPException(status_code=404, detail="Product not found")

    if update_data.title is not None:
        db_item.title = update_data.title
    if update_data.title_hi is not None:
        db_item.title_hi = update_data.title_hi
    if update_data.description is not None:
        db_item.description = update_data.description
    if update_data.description_hi is not None:
        db_item.description_hi = update_data.description_hi
    if update_data.price is not None:
        db_item.price = update_data.price
    if update_data.image_url is not None:
        db_item.image_url = update_data.image_url
    if update_data.category is not None:
        db_item.category = update_data.category
    if update_data.tags is not None:
        db_item.tags = json.dumps(update_data.tags)
    if update_data.status is not None:
        db_item.status = update_data.status

    db_item.updated_at = datetime.now()
    db.commit()
    db.refresh(db_item)

    return ProductResponse(
        id=db_item.id,
        artisan_id=db_item.artisan_id,
        title=db_item.title,
        title_hi=db_item.title_hi or "",
        description=db_item.description or "",
        description_hi=db_item.description_hi or "",
        price=db_item.price,
        image_url=db_item.image_url,
        category=db_item.category,
        tags=db_item.tags_list,
        status=db_item.status,
        created_at=db_item.created_at,
        updated_at=db_item.updated_at,
    )


@router.delete("/{product_id}")
async def delete_product(product_id: str, db: Session = Depends(get_db)):
    """Delete product from database."""
    db_item = db.query(ProductDB).filter(ProductDB.id == product_id).first()
    if not db_item:
        raise HTTPException(status_code=404, detail="Product not found")

    db.delete(db_item)
    db.commit()
    return {"success": True, "deleted_id": product_id}


@router.post("/sync", response_model=ProductSyncResponse)
async def sync_offline_products(
    batch: ProductSyncBatch,
    db: Session = Depends(get_db),
):
    """
    Batch drain endpoint for Flutter's offline queue.
    Accepts products captured while offline and persists them.
    """
    synced_items = []
    for item in batch.products:
        prod_id = item.id if item.id else f"prod_{uuid.uuid4().hex[:10]}"
        existing = db.query(ProductDB).filter(ProductDB.id == prod_id).first()
        if existing:
            existing.title = item.title
            existing.title_hi = item.title_hi or ""
            existing.description = item.description
            existing.description_hi = item.description_hi or ""
            existing.price = item.price
            existing.image_url = item.image_url
            existing.category = item.category
            existing.tags = json.dumps(item.tags)
            existing.status = "live"
            existing.updated_at = datetime.now()
            db_item = existing
        else:
            db_item = ProductDB(
                id=prod_id,
                artisan_id=item.artisan_id,
                title=item.title,
                title_hi=item.title_hi or "",
                description=item.description,
                description_hi=item.description_hi or "",
                price=item.price,
                image_url=item.image_url,
                category=item.category,
                tags=json.dumps(item.tags),
                status="live",
                created_at=item.created_at or datetime.now(),
            )
            db.add(db_item)
        synced_items.append(db_item)

    db.commit()
    for s in synced_items:
        db.refresh(s)

    responses = [
        ProductResponse(
            id=s.id,
            artisan_id=s.artisan_id,
            title=s.title,
            title_hi=s.title_hi or "",
            description=s.description or "",
            description_hi=s.description_hi or "",
            price=s.price,
            image_url=s.image_url,
            category=s.category,
            tags=s.tags_list,
            status=s.status,
            created_at=s.created_at,
            updated_at=s.updated_at,
        )
        for s in synced_items
    ]

    return ProductSyncResponse(synced_count=len(responses), products=responses)
