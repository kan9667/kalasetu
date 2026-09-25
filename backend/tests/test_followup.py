import asyncio
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import httpx
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from backend.config import get_settings
from backend.database import Base
from backend.models.db_models import SmsDispatchLogDB, OtpChallengeDB
from backend.services.otp_service import MockSmsProvider, OtpService, TwoFactorSmsProvider

def test_rejected_concurrent_request_preserves_delivered_otp(tmp_path, monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, 'daily_sms_cap', 20)
    monkeypatch.setattr(settings, 'daily_phone_sms_cap', 3)
    engine = create_engine(f"sqlite:///{tmp_path / 'sms.db'}", connect_args={'check_same_thread': False, 'timeout': 15})
    Base.metadata.create_all(engine)
    barrier = Barrier(2)
    class ConcurrentSession(Session):
        def add(self, instance, _warn=True):
            if isinstance(instance, SmsDispatchLogDB):
                barrier.wait(timeout=5)
            return super().add(instance, _warn=_warn)
    def request(index):
        provider = MockSmsProvider()
        with ConcurrentSession(engine, autoflush=False) as db:
            try:
                asyncio.run(OtpService(sms_provider=provider).create_challenge(db, '9876543210', client_ip=f'127.25.0.{index}'))
            except HTTPException:
                pass
        return provider.sent_messages
    with ThreadPoolExecutor(max_workers=2) as pool:
        messages = [msg for group in pool.map(request, [1, 2]) for msg in group]
    assert len(messages) == 1
    with Session(engine) as db:
        assert db.query(OtpChallengeDB).filter_by(used=False).count() == 1, 'Rejected contender must not invalidate the OTP that was actually sent'
        assert OtpService(sms_provider=MockSmsProvider()).verify_challenge(db, '9876543210', messages[0]['otp'])
    engine.dispose()

def test_post_dispatch_read_error_keeps_budget_reserved(tmp_path, monkeypatch):
    real_client = httpx.AsyncClient
    def delivered_but_response_lost(request):
        raise httpx.ReadError('Connection lost after gateway accepted request', request=request)
    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kw: real_client(transport=httpx.MockTransport(delivered_but_response_lost), **kw))
    engine = create_engine(f"sqlite:///{tmp_path / 'sms.db'}")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        with pytest.raises(HTTPException) as exc_info:
            asyncio.run(OtpService(sms_provider=TwoFactorSmsProvider(api_key='FAKE_KEY', enable_real_sms=True)).create_challenge(db, '9876543209', client_ip='127.26.0.1'))
        assert exc_info.value.status_code == 503
        row = db.query(SmsDispatchLogDB).one()
        assert row.status == 'ambiguous_timeout', 'Potentially charged ReadError must remain counted against quota'
    engine.dispose()

def test_post_dispatch_timeout_keeps_budget_reserved(tmp_path, monkeypatch):
    real_client = httpx.AsyncClient
    def gateway_timeout(request):
        raise httpx.ReadTimeout('Gateway read timeout', request=request)
    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kw: real_client(transport=httpx.MockTransport(gateway_timeout), **kw))
    engine = create_engine(f"sqlite:///{tmp_path / 'sms_timeout.db'}")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        with pytest.raises(HTTPException) as exc_info:
            asyncio.run(OtpService(sms_provider=TwoFactorSmsProvider(api_key='FAKE_KEY', enable_real_sms=True)).create_challenge(db, '9876543208', client_ip='127.26.0.2'))
        assert exc_info.value.status_code == 503
        row = db.query(SmsDispatchLogDB).one()
        assert row.status == 'ambiguous_timeout', 'Gateway timeout must be treated as ambiguous and counted against quota'
    engine.dispose()

def test_post_dispatch_malformed_response_keeps_budget_reserved(tmp_path, monkeypatch):
    real_client = httpx.AsyncClient
    def malformed_response(request):
        return httpx.Response(200, text='<html><title>502 Bad Gateway</title><body>Non-JSON error from intermediary</body></html>')
    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kw: real_client(transport=httpx.MockTransport(malformed_response), **kw))
    engine = create_engine(f"sqlite:///{tmp_path / 'sms_malformed.db'}")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        with pytest.raises(HTTPException) as exc_info:
            asyncio.run(OtpService(sms_provider=TwoFactorSmsProvider(api_key='FAKE_KEY', enable_real_sms=True)).create_challenge(db, '9876543207', client_ip='127.26.0.3'))
        assert exc_info.value.status_code == 503
        row = db.query(SmsDispatchLogDB).one()
        assert row.status == 'ambiguous_timeout', 'Malformed gateway response must be treated as ambiguous delivery'
    engine.dispose()

def test_confirmed_rejection_marks_failed_and_does_not_consume_budget(tmp_path, monkeypatch):
    real_client = httpx.AsyncClient
    def confirmed_rejection(request):
        return httpx.Response(200, json={"Status": "Error", "Details": "Invalid mobile number"})
    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kw: real_client(transport=httpx.MockTransport(confirmed_rejection), **kw))
    engine = create_engine(f"sqlite:///{tmp_path / 'sms_rejected.db'}")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        with pytest.raises(HTTPException) as exc_info:
            asyncio.run(OtpService(sms_provider=TwoFactorSmsProvider(api_key='FAKE_KEY', enable_real_sms=True)).create_challenge(db, '9876543206', client_ip='127.26.0.4'))
        assert exc_info.value.status_code == 503
        row = db.query(SmsDispatchLogDB).one()
        assert row.status == 'failed', 'Confirmed rejection must be marked failed'
        # Verify it does not count towards the active budget
        from sqlalchemy import text
        active_count = db.execute(
            text("SELECT count(*) FROM sms_dispatch_logs WHERE status IN ('reserved', 'dispatched', 'ambiguous_timeout')")
        ).scalar()
        assert active_count == 0, 'Failed dispatches must not consume quota'
    engine.dispose()

def test_ambiguous_delivery_restart_persistence_and_absence_of_resend(tmp_path, monkeypatch):
    real_client = httpx.AsyncClient
    dispatch_attempts = 0
    def dropping_transport(request):
        nonlocal dispatch_attempts
        dispatch_attempts += 1
        raise httpx.ReadError('Gateway connection reset by peer', request=request)
    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kw: real_client(transport=httpx.MockTransport(dropping_transport), **kw))
    db_file = tmp_path / 'persistent_sms.db'
    engine1 = create_engine(f"sqlite:///{db_file}")
    Base.metadata.create_all(engine1)
    with Session(engine1) as db:
        with pytest.raises(HTTPException):
            asyncio.run(OtpService(sms_provider=TwoFactorSmsProvider(api_key='FAKE_KEY', enable_real_sms=True)).create_challenge(db, '9876543205', client_ip='127.26.0.5'))
    engine1.dispose()

    # Verify no automatic retry occurred
    assert dispatch_attempts == 1, 'Ambiguous outcome must NOT trigger automatic resend'

    # Simulate restart by creating a new database engine and session
    engine2 = create_engine(f"sqlite:///{db_file}")
    with Session(engine2) as db:
        row = db.query(SmsDispatchLogDB).one()
        assert row.status == 'ambiguous_timeout', 'Ambiguous delivery status must persist across process restart'
    engine2.dispose()

