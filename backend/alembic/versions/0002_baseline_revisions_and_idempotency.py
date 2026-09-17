"""Baseline tables, product revisions, idempotency records, and legacy media quarantine.

Revision ID: 0002_baseline_revisions_and_idempotency
Revises: 0001_artisan_approval_and_media
Create Date: 2026-09-13 20:50:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0002_baseline_revisions_and_idempotency"
down_revision: Union[str, None] = "0001_artisan_approval_and_media"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = inspector.get_table_names()

    # 1. Create artisans table if missing (for fresh database deployments)
    if "artisans" not in existing_tables:
        op.create_table(
            "artisans",
            sa.Column("id", sa.String(length=64), primary_key=True),
            sa.Column("name", sa.String(length=255), nullable=False),
            sa.Column("phone", sa.String(length=15), unique=True, nullable=False),
            sa.Column("craft_type", sa.String(length=128), server_default=""),
            sa.Column("location_cluster", sa.String(length=255), server_default=""),
            sa.Column("state", sa.String(length=128), server_default=""),
            sa.Column("experience_years", sa.String(length=16), server_default=""),
            sa.Column("pehchan_id", sa.String(length=64), nullable=True),
            sa.Column("preferred_language", sa.String(length=8), server_default="en"),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
        )
        op.create_index("ix_artisans_id", "artisans", ["id"])
        op.create_index("ix_artisans_phone", "artisans", ["phone"])

    # 2. Create products table if missing (for fresh database deployments)
    if "products" not in existing_tables:
        op.create_table(
            "products",
            sa.Column("id", sa.String(length=64), primary_key=True),
            sa.Column("artisan_id", sa.String(length=64), sa.ForeignKey("artisans.id", ondelete="SET NULL"), nullable=True),
            sa.Column("title", sa.String(length=255), nullable=False),
            sa.Column("title_hi", sa.String(length=255), server_default=""),
            sa.Column("description", sa.Text(), server_default=""),
            sa.Column("description_hi", sa.Text(), server_default=""),
            sa.Column("price", sa.Float(), nullable=True, server_default="0.0"),
            sa.Column("price_paise", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("floor_price_paise", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("materials_paise", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("labor_hours", sa.Float(), nullable=False, server_default="0.0"),
            sa.Column("hourly_rate_paise", sa.Integer(), nullable=False, server_default="5000"),
            sa.Column("transport_paise", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("overhead_paise", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("image_url", sa.String(length=512), server_default=""),
            sa.Column("media_id", sa.String(length=64), sa.ForeignKey("media_assets.id", ondelete="SET NULL"), nullable=True),
            sa.Column("category", sa.String(length=128), server_default="General"),
            sa.Column("tags", sa.Text(), server_default="[]"),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="draft"),
            sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("approved_revision", sa.Integer(), nullable=True),
            sa.Column("approved_at", sa.DateTime(), nullable=True),
            sa.Column("approved_by_artisan_id", sa.String(length=64), nullable=True),
            sa.Column("published_at", sa.DateTime(), nullable=True),
            sa.Column("content_hash", sa.String(length=64), nullable=False, server_default=""),
            sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now()),
        )
        op.create_index("ix_products_id", "products", ["id"])
        op.create_index("ix_products_artisan_id", "products", ["artisan_id"])
        op.create_index("ix_products_category", "products", ["category"])
        op.create_index("ix_products_status", "products", ["status"])
        op.create_index("ix_products_media_id", "products", ["media_id"])
        op.create_index("ix_products_is_deleted", "products", ["is_deleted"])
    else:
        # If products table already exists, add is_deleted if not present
        product_cols = [c["name"] for c in inspector.get_columns("products")]
        if "is_deleted" not in product_cols:
            with op.batch_alter_table("products") as batch_op:
                batch_op.add_column(sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default="0"))
                batch_op.create_index("ix_products_is_deleted", ["is_deleted"])

    # 3. Create social_drafts table if missing
    if "social_drafts" not in existing_tables:
        op.create_table(
            "social_drafts",
            sa.Column("id", sa.String(length=64), primary_key=True),
            sa.Column("artisan_id", sa.String(length=64), sa.ForeignKey("artisans.id", ondelete="CASCADE"), nullable=True),
            sa.Column("listing_id", sa.String(length=64), sa.ForeignKey("products.id", ondelete="SET NULL"), nullable=True),
            sa.Column("draft_key", sa.String(length=128), nullable=True),
            sa.Column("image_url", sa.String(length=512), nullable=False),
            sa.Column("caption", sa.Text(), server_default=""),
            sa.Column("hashtags", sa.Text(), server_default="[]"),
            sa.Column("channel", sa.String(length=32), server_default="instagram"),
            sa.Column("source", sa.String(length=32), server_default="catalogue"),
            sa.Column("edited_by_user", sa.Boolean(), server_default="0"),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now()),
        )
        op.create_index("ix_social_drafts_id", "social_drafts", ["id"])
        op.create_index("ix_social_drafts_artisan_id", "social_drafts", ["artisan_id"])
        op.create_index("ix_social_drafts_listing_id", "social_drafts", ["listing_id"])
        op.create_index("ix_social_drafts_draft_key", "social_drafts", ["draft_key"])

    # 4. Create product_revisions table
    if "product_revisions" not in existing_tables:
        op.create_table(
            "product_revisions",
            sa.Column("id", sa.String(length=64), primary_key=True),
            sa.Column(
                "product_id",
                sa.String(length=64),
                sa.ForeignKey("products.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "artisan_id",
                sa.String(length=64),
                sa.ForeignKey("artisans.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("revision", sa.Integer(), nullable=False),
            sa.Column("title", sa.String(length=255), nullable=False),
            sa.Column("title_hi", sa.String(length=255), server_default=""),
            sa.Column("description", sa.Text(), server_default=""),
            sa.Column("description_hi", sa.Text(), server_default=""),
            sa.Column("price_paise", sa.Integer(), nullable=False),
            sa.Column("floor_price_paise", sa.Integer(), nullable=False),
            sa.Column("category", sa.String(length=128), nullable=False),
            sa.Column("tags", sa.Text(), server_default="[]"),
            sa.Column(
                "media_id",
                sa.String(length=64),
                sa.ForeignKey("media_assets.id"),
                nullable=False,
            ),
            sa.Column("media_checksum", sa.String(length=64), nullable=False),
            sa.Column("media_mime_type", sa.String(length=64), nullable=False),
            sa.Column("media_byte_size", sa.Integer(), nullable=False),
            sa.Column("public_media_url", sa.String(length=512), nullable=False),
            sa.Column("content_hash", sa.String(length=64), nullable=False),
            sa.Column(
                "approved_by_artisan_id",
                sa.String(length=64),
                sa.ForeignKey("artisans.id"),
                nullable=False,
            ),
            sa.Column("approved_at", sa.DateTime(), nullable=False),
            sa.Column("published_at", sa.DateTime(), nullable=False),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.UniqueConstraint("product_id", "revision", name="uq_product_revisions_product_id_revision"),
        )
        op.create_index("ix_product_revisions_id", "product_revisions", ["id"])
        op.create_index("ix_product_revisions_product_id", "product_revisions", ["product_id"])
        op.create_index("ix_product_revisions_artisan_id", "product_revisions", ["artisan_id"])
        op.create_index("ix_product_revisions_media_id", "product_revisions", ["media_id"])

    # 5. Create idempotency_records table
    if "idempotency_records" not in existing_tables:
        op.create_table(
            "idempotency_records",
            sa.Column("id", sa.String(length=64), primary_key=True),
            sa.Column(
                "artisan_id",
                sa.String(length=64),
                sa.ForeignKey("artisans.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("idempotency_key", sa.String(length=128), nullable=False),
            sa.Column("endpoint", sa.String(length=256), nullable=False),
            sa.Column("request_hash", sa.String(length=64), nullable=False),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="in_progress"),
            sa.Column("lease_expires_at", sa.DateTime(), nullable=False),
            sa.Column("response_status_code", sa.Integer(), nullable=True),
            sa.Column("response_body", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.UniqueConstraint("artisan_id", "endpoint", "idempotency_key", name="uq_idempotency_artisan_endpoint_key"),
        )
        op.create_index("ix_idempotency_records_id", "idempotency_records", ["id"])
        op.create_index("ix_idempotency_records_artisan_id", "idempotency_records", ["artisan_id"])
        op.create_index("ix_idempotency_records_idempotency_key", "idempotency_records", ["idempotency_key"])
        op.create_index("ix_idempotency_records_endpoint", "idempotency_records", ["endpoint"])

    # 6. Legacy Media Quarantine / Backfill
    # Any product without a verified media_id must be kept in legacy_unverified state,
    # approval metadata cleared, and image_url quarantined so no unverified static media is served.
    bind.execute(
        sa.text(
            "UPDATE products SET status = 'legacy_unverified', "
            "approved_revision = NULL, approved_at = NULL, published_at = NULL, approved_by_artisan_id = NULL, "
            "image_url = '' "
            "WHERE media_id IS NULL OR media_id = ''"
        )
    )


def downgrade() -> None:
    pass
