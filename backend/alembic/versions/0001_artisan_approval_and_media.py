"""Artisan approval workflow, media assets, otp challenges, and integer paise migration.

Revision ID: 0001_artisan_approval_and_media
Revises: 
Create Date: 2026-09-13 00:30:00

"""
import hashlib
import json
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0001_artisan_approval_and_media"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def compute_legacy_hash(title, title_hi, description, description_hi, price_paise, category, tags, floor_price_paise, media_id=""):
    try:
        tag_list = json.loads(tags) if tags else []
    except Exception:
        tag_list = []
    canonical = {
        "category": (category or "").strip(),
        "description": (description or "").strip(),
        "description_hi": (description_hi or "").strip(),
        "floor_price_paise": int(floor_price_paise or 0),
        "media_id": (media_id or "").strip(),
        "price_paise": int(price_paise or 0),
        "tags": sorted([t.strip() for t in tag_list if t.strip()]),
        "title": (title or "").strip(),
        "title_hi": (title_hi or "").strip(),
    }
    payload = json.dumps(canonical, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = inspector.get_table_names()

    # 1. Create otp_challenges table if missing
    if "otp_challenges" not in existing_tables:
        op.create_table(
            "otp_challenges",
            sa.Column("id", sa.String(length=64), primary_key=True),
            sa.Column("phone", sa.String(length=15), nullable=False),
            sa.Column("otp_hash", sa.String(length=128), nullable=False),
            sa.Column("salt", sa.String(length=32), nullable=False),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
            sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("max_attempts", sa.Integer(), nullable=False, server_default="3"),
            sa.Column("used", sa.Boolean(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        )
        op.create_index("ix_otp_challenges_id", "otp_challenges", ["id"])
        op.create_index("ix_otp_challenges_phone", "otp_challenges", ["phone"])

    # 2. Create media_assets table if missing
    if "media_assets" not in existing_tables:
        op.create_table(
            "media_assets",
            sa.Column("id", sa.String(length=64), primary_key=True),
            sa.Column(
                "artisan_id",
                sa.String(length=64),
                sa.ForeignKey("artisans.id", ondelete="CASCADE"),
                nullable=True,
            ),
            sa.Column("file_path", sa.String(length=512), nullable=False),
            sa.Column("file_url", sa.String(length=512), nullable=False),
            sa.Column("mime_type", sa.String(length=64), nullable=False),
            sa.Column("byte_size", sa.Integer(), nullable=False),
            sa.Column("sha256_checksum", sa.String(length=64), nullable=False),
            sa.Column("processing_provenance", sa.String(length=128), server_default="raw_upload"),
            sa.Column("status", sa.String(length=32), server_default="ready"),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        )
        op.create_index("ix_media_assets_id", "media_assets", ["id"])
        op.create_index("ix_media_assets_artisan_id", "media_assets", ["artisan_id"])
        op.create_index("ix_media_assets_status", "media_assets", ["status"])

    # 3. Add artisan_id to social_drafts if missing
    if "social_drafts" in existing_tables:
        cols = [c["name"] for c in inspector.get_columns("social_drafts")]
        if "artisan_id" not in cols:
            with op.batch_alter_table("social_drafts") as batch_op:
                batch_op.add_column(sa.Column("artisan_id", sa.String(length=64), nullable=True))
                batch_op.create_foreign_key(
                    "fk_social_drafts_artisan_id",
                    "artisans",
                    ["artisan_id"],
                    ["id"],
                    ondelete="CASCADE",
                )
                batch_op.create_index("ix_social_drafts_artisan_id", ["artisan_id"])

    # 4. Alter products table
    if "products" in existing_tables:
        # Sanitize orphaned artisan_id references so SQLite foreign key integrity is preserved
        bind.execute(
            sa.text(
                "UPDATE products SET artisan_id = NULL "
                "WHERE artisan_id IS NOT NULL AND artisan_id != '' AND artisan_id NOT IN (SELECT id FROM artisans)"
            )
        )

        product_cols = [c["name"] for c in inspector.get_columns("products")]
        with op.batch_alter_table("products") as batch_op:
            if "price_paise" not in product_cols:
                batch_op.add_column(sa.Column("price_paise", sa.Integer(), nullable=False, server_default="0"))
            if "floor_price_paise" not in product_cols:
                batch_op.add_column(sa.Column("floor_price_paise", sa.Integer(), nullable=False, server_default="0"))
            if "materials_paise" not in product_cols:
                batch_op.add_column(sa.Column("materials_paise", sa.Integer(), nullable=False, server_default="0"))
            if "labor_hours" not in product_cols:
                batch_op.add_column(sa.Column("labor_hours", sa.Float(), nullable=False, server_default="0.0"))
            if "hourly_rate_paise" not in product_cols:
                batch_op.add_column(sa.Column("hourly_rate_paise", sa.Integer(), nullable=False, server_default="5000"))
            if "transport_paise" not in product_cols:
                batch_op.add_column(sa.Column("transport_paise", sa.Integer(), nullable=False, server_default="0"))
            if "overhead_paise" not in product_cols:
                batch_op.add_column(sa.Column("overhead_paise", sa.Integer(), nullable=False, server_default="0"))
            if "revision" not in product_cols:
                batch_op.add_column(sa.Column("revision", sa.Integer(), nullable=False, server_default="1"))
            if "approved_revision" not in product_cols:
                batch_op.add_column(sa.Column("approved_revision", sa.Integer(), nullable=True))
            if "approved_at" not in product_cols:
                batch_op.add_column(sa.Column("approved_at", sa.DateTime(), nullable=True))
            if "approved_by_artisan_id" not in product_cols:
                batch_op.add_column(sa.Column("approved_by_artisan_id", sa.String(length=64), nullable=True))
            if "published_at" not in product_cols:
                batch_op.add_column(sa.Column("published_at", sa.DateTime(), nullable=True))
            if "content_hash" not in product_cols:
                batch_op.add_column(sa.Column("content_hash", sa.String(length=64), nullable=False, server_default=""))
            if "media_id" not in product_cols:
                batch_op.add_column(sa.Column("media_id", sa.String(length=64), nullable=True))
                batch_op.create_foreign_key(
                    "fk_products_media_id",
                    "media_assets",
                    ["media_id"],
                    ["id"],
                    ondelete="SET NULL",
                )
                batch_op.create_index("ix_products_media_id", ["media_id"])

        # 5. Data Migration & Audit Note:
        # Migrate legacy price to price_paise
        bind.execute(
            sa.text(
                "UPDATE products SET price_paise = CAST(ROUND(price * 100) AS INTEGER) "
                "WHERE (price_paise = 0 OR price_paise IS NULL) AND price IS NOT NULL"
            )
        )

        # Audit Note:
        # Legacy prototype listings were created with client-controlled status 'live' without server-enforced
        # artisan review or cryptographic approval. Under the new lifecycle, they are safely transitioned
        # to 'legacy_unverified' so they are not exposed to public/marketplace channels until explicitly
        # reviewed and approved by the artisan. Approval fields remain strictly NULL.
        bind.execute(
            sa.text(
                "UPDATE products SET status = 'legacy_unverified' "
                "WHERE status = 'live'"
            )
        )

        # Compute content_hash for any existing rows that have empty content_hash
        rows = bind.execute(
            sa.text(
                "SELECT id, title, title_hi, description, description_hi, price_paise, category, tags, floor_price_paise, media_id "
                "FROM products WHERE content_hash = '' OR content_hash IS NULL"
            )
        ).fetchall()

        for r in rows:
            chash = compute_legacy_hash(
                title=r[1],
                title_hi=r[2],
                description=r[3],
                description_hi=r[4],
                price_paise=r[5],
                category=r[6],
                tags=r[7],
                floor_price_paise=r[8],
                media_id=r[9] or "",
            )
            bind.execute(
                sa.text("UPDATE products SET content_hash = :hash WHERE id = :id"),
                {"hash": chash, "id": r[0]},
            )


def downgrade() -> None:
    pass
