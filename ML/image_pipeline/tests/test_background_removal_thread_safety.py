# ============================================================
# test_background_removal_thread_safety.py
# ============================================================
# Proves three concurrency guarantees for the rembg session:
#
#   1. Concurrent callers initialize exactly ONE session.
#   2. Enhancement calls through remove_background() are serialized
#      by the lock (no duplicate ONNX loads during inference).
#   3. A startup warm-up thread and a simultaneous enhancement
#      request cannot create two sessions concurrently.
#   4. MemoryError surfaces as RuntimeError, not a process crash.
#
# All tests mock rembg.new_session so no ML model is downloaded.
# ============================================================

import sys
import os
import threading
import time
import types
from unittest.mock import MagicMock
from PIL import Image
import pytest

# Ensure the processors package is importable
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _fresh_module():
    """
    Return a freshly imported copy of background_removal with its module-level
    state (_session, _session_lock) reset, so tests cannot bleed into each other.
    """
    mod_name = "processors.background_removal"
    if mod_name in sys.modules:
        del sys.modules[mod_name]
    import processors.background_removal as br
    return br


def _rembg_stub(new_session_fn, remove_fn=None):
    """Build a minimal rembg module stub."""
    stub = types.ModuleType("rembg")
    stub.new_session = new_session_fn
    stub.remove = remove_fn or (lambda img, session=None: Image.new("RGBA", (10, 10)))
    return stub


# ─────────────────────────────────────────────────────────────
# 1. Concurrent get_rembg_session() creates exactly one session
# ─────────────────────────────────────────────────────────────

class TestSingleSessionUnderConcurrency:

    def test_two_threads_share_one_session(self, monkeypatch):
        br = _fresh_module()
        call_count = {"n": 0}
        sentinel = MagicMock(name="session")

        def _slow_new(model, **kwargs):
            call_count["n"] += 1
            time.sleep(0.05)   # wide race window
            return sentinel

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_slow_new))
        results = []

        def _call():
            results.append(br.get_rembg_session())

        t1 = threading.Thread(target=_call)
        t2 = threading.Thread(target=_call)
        t1.start(); t2.start()
        t1.join(); t2.join()

        assert call_count["n"] == 1, (
            f"new_session() called {call_count['n']} times — expected exactly 1. "
            "Duplicate ONNX load would OOM Railway's 1 GB container."
        )
        assert results[0] is results[1] is sentinel

    def test_ten_threads_share_one_session(self, monkeypatch):
        br = _fresh_module()
        call_count = {"n": 0}
        sentinel = MagicMock(name="session")

        def _slow_new(model, **kwargs):
            call_count["n"] += 1
            time.sleep(0.02)
            return sentinel

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_slow_new))
        results = []

        def _call():
            results.append(br.get_rembg_session())

        threads = [threading.Thread(target=_call) for _ in range(10)]
        for t in threads: t.start()
        for t in threads: t.join()

        assert call_count["n"] == 1, f"Expected 1 new_session() call, got {call_count['n']}"
        assert all(s is sentinel for s in results)

    def test_repeated_calls_after_init_use_fast_path(self, monkeypatch):
        br = _fresh_module()
        call_count = {"n": 0}
        sentinel = MagicMock(name="session")

        def _new(model, **kwargs):
            call_count["n"] += 1
            return sentinel

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_new))

        for _ in range(20):
            br.get_rembg_session()

        assert call_count["n"] == 1, (
            f"new_session() was called {call_count['n']} times after first init."
        )


# ─────────────────────────────────────────────────────────────
# 2. Concurrent remove_background() calls share a single session
# ─────────────────────────────────────────────────────────────

class TestEnhancementSerialization:

    def test_concurrent_calls_trigger_one_session(self, monkeypatch):
        br = _fresh_module()
        call_count = {"n": 0}
        sentinel = MagicMock(name="session")

        def _slow_new(model, **kwargs):
            call_count["n"] += 1
            time.sleep(0.03)
            return sentinel

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_slow_new))
        errors, results = [], []

        def _enhance():
            try:
                img = Image.new("RGB", (50, 50))
                results.append(br.remove_background(img))
            except Exception as e:
                errors.append(e)

        t1 = threading.Thread(target=_enhance)
        t2 = threading.Thread(target=_enhance)
        t1.start(); t2.start()
        t1.join(); t2.join()

        assert not errors, f"remove_background() raised: {errors}"
        assert len(results) == 2
        assert call_count["n"] == 1, (
            f"Expected 1 session during concurrent remove_background, got {call_count['n']}"
        )


# ─────────────────────────────────────────────────────────────
# 3. Startup warm-up thread + simultaneous request = one session
# ─────────────────────────────────────────────────────────────

class TestWarmupRaceWithRequest:

    def test_warmup_and_request_share_one_session(self, monkeypatch):
        """
        Simulates the exact Railway crash: the lifespan warmup daemon starts
        loading the ONNX model; before it finishes, the first real enhancement
        request arrives.  Only one ONNX session must be created.
        """
        br = _fresh_module()
        call_count = {"n": 0}
        sentinel = MagicMock(name="session")

        def _slow_new(model, **kwargs):
            call_count["n"] += 1
            time.sleep(0.08)   # simulates real ONNX model load latency
            return sentinel

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_slow_new))
        errors = []

        def _warmup():
            """Mirrors backend/main.py lifespan warmup thread."""
            try:
                br.get_rembg_session()
            except Exception as e:
                errors.append(("warmup", e))

        def _api_request():
            """Arrives 10 ms after warmup starts, mid-init."""
            time.sleep(0.01)
            try:
                img = Image.new("RGB", (40, 40))
                br.remove_background(img)
            except Exception as e:
                errors.append(("request", e))

        warmup_t = threading.Thread(target=_warmup, name="startup-warmup")
        request_t = threading.Thread(target=_api_request, name="api-request")
        warmup_t.start()
        request_t.start()
        warmup_t.join()
        request_t.join()

        assert not errors, f"Unexpected errors in warmup+request race: {errors}"
        assert call_count["n"] == 1, (
            f"new_session() called {call_count['n']} times in warmup+request race. "
            "Two concurrent sessions would OOM Railway's 1 GB container."
        )

    def test_warmup_oom_raises_runtime_error_not_crash(self, monkeypatch):
        """
        MemoryError during session init is re-raised as RuntimeError.
        The process must remain alive so FastAPI can return a degraded result.
        """
        br = _fresh_module()

        def _oom_new(model, **kwargs):
            raise MemoryError("simulated ONNX OOM")

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_oom_new))

        with pytest.raises(RuntimeError, match="[Oo]ut of memory"):
            br.get_rembg_session()
        # Reaching here proves the process did not exit.

    def test_inference_oom_raises_runtime_error(self, monkeypatch):
        """
        MemoryError during rembg.remove() is surfaced as RuntimeError so the
        FastAPI route handler can catch it and return a degraded response.
        """
        br = _fresh_module()
        sentinel = MagicMock(name="session")

        def _ok_new(model, **kwargs):
            return sentinel

        def _oom_remove(img, session=None):
            raise MemoryError("simulated inference OOM")

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_ok_new, _oom_remove))

        img = Image.new("RGB", (100, 100))
        with pytest.raises(RuntimeError, match="[Oo]ut of memory"):
            br.remove_background(img)
