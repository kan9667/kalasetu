"""Media asset lineage and degradation tracking.

Revision ID: 0003_media_asset_lineage_and_degradation
Revises: 0002_baseline_revisions_and_idempotency
Create Date: 2026-09-14 00:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0003_media_asset_lineage_and_degradation"
down_revision: Union[str, None] = "0002_baseline_revisions_and_idempotency"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = inspector.get_table_names()

    if "media_assets" in existing_tables:
        existing_cols = {c["name"] for c in inspector.get_columns("media_assets")}
        with op.batch_alter_table("media_assets") as batch_op:
            if "source_media_id" not in existing_cols:
                batch_op.add_column(
                    sa.Column(
                        "source_media_id",
                        sa.String(length=64),
                        nullable=True,
                    )
                )
                batch_op.create_foreign_key(
                    "fk_media_assets_source_media_id",
                    "media_assets",
                    ["source_media_id"],
                    ["id"],
                    ondelete="SET NULL",
                )
                batch_op.create_index("ix_media_assets_source_media_id", ["source_media_id"])
            if "is_degraded" not in existing_cols:
                batch_op.add_column(
                    sa.Column(
                        "is_degraded",
                        sa.Boolean(),
                        nullable=False,
                        server_default=sa.text("0"),
                    )
                )
            if "degraded_reason" not in existing_cols:
                batch_op.add_column(
                    sa.Column(
                        "degraded_reason",
                        sa.String(length=255),
                        nullable=True,
                    )
                )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = inspector.get_table_names()

    if "media_assets" in existing_tables:
        existing_cols = {c["name"] for c in inspector.get_columns("media_assets")}
        with op.batch_alter_table("media_assets") as batch_op:
            if "source_media_id" in existing_cols:
                batch_op.drop_index("ix_media_assets_source_media_id")
                batch_op.drop_column("source_media_id")
            if "is_degraded" in existing_cols:
                batch_op.drop_column("is_degraded")
            if "degraded_reason" in existing_cols:
                batch_op.drop_column("degraded_reason")
