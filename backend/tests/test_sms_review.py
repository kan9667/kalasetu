import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import httpx
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from backend.config import get_settings
from backend.database import Base
from backend.models.db_models import SmsDispatchLogDB
from backend.services.otp_service import MockSmsProvider, OtpService, TwoFactorSmsProvider


def test_real_httpx_logging_does_not_expose_fixture_credentials(monkeypatch, caplog):
    real_client = httpx.AsyncClient
    transport = httpx.MockTransport(lambda req: httpx.Response(200, json={"Status": "Success", "Details": "fixture-session"}))
    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kw: real_client(transport=transport, **kw))
    with caplog.at_level(logging.INFO):
        assert asyncio.run(TwoFactorSmsProvider(api_key='FAKE_REVIEW_SECRET', enable_real_sms=True).send_otp('9876543210', '654321'))
    assert 'FAKE_REVIEW_SECRET' not in caplog.text, 'The HTTP client itself must not log the credential-bearing URL'


def test_global_sms_cap_is_atomic_across_concurrent_sessions(tmp_path, monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, 'daily_sms_cap', 1)
    monkeypatch.setattr(settings, 'daily_phone_sms_cap', 3)
    engine = create_engine(f"sqlite:///{tmp_path / 'budget.sqlite'}", connect_args={'check_same_thread': False, 'timeout': 15})
    Base.metadata.create_all(engine)
    barrier = Barrier(2)

    class ConcurrentSession(Session):
        def add(self, instance, _warn=True):
            if isinstance(instance, SmsDispatchLogDB):
                # Both workers finish the budget reads before either inserts.
                barrier.wait(timeout=5)
            return super().add(instance, _warn=_warn)

    def send(index):
        provider = MockSmsProvider()
        with ConcurrentSession(engine, autoflush=False) as db:
            try:
                asyncio.run(OtpService(sms_provider=provider).create_challenge(db, f'98765432{index:02d}', client_ip=f'127.8.0.{index}'))
            except HTTPException:
                pass
        return len(provider.sent_messages)

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            sent = list(pool.map(send, [1, 2]))
        assert sum(sent) <= 1, f'Configured cap=1, but dispatched {sum(sent)} mocked SMS'
    finally:
        engine.dispose()
