"""Durable SMS dispatch logs and budget tracking.

Revision ID: 0004_sms_dispatch_logs
Revises: 0003_media_asset_lineage_and_degradation
Create Date: 2026-09-19 00:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0004_sms_dispatch_logs"
down_revision: Union[str, None] = "0003_media_asset_lineage_and_degradation"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = inspector.get_table_names()

    if "sms_dispatch_logs" not in existing_tables:
        op.create_table(
            "sms_dispatch_logs",
            sa.Column("id", sa.String(length=64), primary_key=True),
            sa.Column("phone_hash", sa.String(length=64), nullable=False),
            sa.Column("provider", sa.String(length=32), nullable=False),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="reserved"),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("error_detail", sa.String(length=255), nullable=True),
        )
        op.create_index("ix_sms_dispatch_logs_id", "sms_dispatch_logs", ["id"])
        op.create_index("ix_sms_dispatch_logs_phone_hash", "sms_dispatch_logs", ["phone_hash"])
        op.create_index("ix_sms_dispatch_logs_status", "sms_dispatch_logs", ["status"])
        op.create_index("ix_sms_dispatch_logs_created_at", "sms_dispatch_logs", ["created_at"])


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = inspector.get_table_names()

    if "sms_dispatch_logs" in existing_tables:
        op.drop_index("ix_sms_dispatch_logs_created_at", table_name="sms_dispatch_logs")
        op.drop_index("ix_sms_dispatch_logs_status", table_name="sms_dispatch_logs")
        op.drop_index("ix_sms_dispatch_logs_phone_hash", table_name="sms_dispatch_logs")
        op.drop_index("ix_sms_dispatch_logs_id", table_name="sms_dispatch_logs")
        op.drop_table("sms_dispatch_logs")
