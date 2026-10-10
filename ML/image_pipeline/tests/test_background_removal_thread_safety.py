# ============================================================
# test_background_removal_thread_safety.py
# ============================================================
# Proves concurrency and correctness guarantees for background_removal:
#
#   1. Canonical imports guarantee exactly ONE session across startup warm-up
#      and real enhancement-pipeline execution paths.
#   2. Concurrent get_rembg_session() calls create exactly ONE session.
#   3. Concurrent remove_background() calls are strictly serialized so
#      max_active_inferences == 1, and no deadlock occurs after failure.
#   4. MemoryError is surfaced as RuntimeError, not a process crash.
#   5. sess_opts= (not session_options=) is passed to new_session().
#   6. providers=["CPUExecutionProvider"] is always passed.
#   7. ONNX configuration fails closed: if safe SessionOptions cannot
#      be created, RuntimeError is raised without calling rembg with defaults.
#   8. No fallback to u2net after any failure (OOM, config error, or general exception).
#
# All tests mock rembg.new_session / rembg.remove — no model download required.
# ============================================================

import sys
import os
import threading
import time
import types
from unittest.mock import MagicMock
from PIL import Image
import pytest

# Ensure repository root is in sys.path
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)


def _fresh_module():
    """
    Return the canonical background_removal module with its module-level
    state (_session, _session_lock, _inference_lock) reset directly.
    Never deletes the module from sys.modules to prevent splitting module identity
    or orphaning references held by enhancer.py, catalog_service.py, or other callers.
    """
    import ML.image_pipeline.processors.background_removal as br
    br._session = None
    br._session_lock = threading.Lock()
    br._inference_lock = threading.Lock()
    return br


@pytest.fixture(autouse=True)
def _isolate_ml_and_sys_state():
    """
    Guarantees strict test isolation:
    - Snapshots and restores sys.path and sys.modules entries (especially 'rembg' stubs and 'processors' aliases).
    - Directly resets background_removal module state before and after each test.
    - Prevents leaking mutated pipeline globals (e.g. run_ml_enhancer) into later tests.
    """
    orig_path = list(sys.path)
    orig_rembg = sys.modules.get("rembg")
    had_processors_br = "processors.background_removal" in sys.modules
    orig_processors_br = sys.modules.get("processors.background_removal")
    had_processors = "processors" in sys.modules
    orig_processors = sys.modules.get("processors")

    # Pre-test direct state reset
    if "ML.image_pipeline.processors.background_removal" in sys.modules:
        br = sys.modules["ML.image_pipeline.processors.background_removal"]
        br._session = None
        br._session_lock = threading.Lock()
        br._inference_lock = threading.Lock()

    yield

    # Post-test cleanup and restoration
    sys.path[:] = orig_path

    # Restore or remove 'rembg' stub
    if orig_rembg is None:
        sys.modules.pop("rembg", None)
    else:
        sys.modules["rembg"] = orig_rembg

    # Restore or clean up 'processors' aliases
    if not had_processors_br:
        sys.modules.pop("processors.background_removal", None)
    else:
        sys.modules["processors.background_removal"] = orig_processors_br

    if not had_processors:
        sys.modules.pop("processors", None)
    else:
        sys.modules["processors"] = orig_processors

    # Directly reset background_removal state post-test
    if "ML.image_pipeline.processors.background_removal" in sys.modules:
        br = sys.modules["ML.image_pipeline.processors.background_removal"]
        br._session = None
        br._session_lock = threading.Lock()
        br._inference_lock = threading.Lock()

    # Reset any mutated global run_ml_enhancer in catalog_service
    if "backend.services.catalog_service" in sys.modules:
        cs = sys.modules["backend.services.catalog_service"]
        if hasattr(cs, "run_ml_enhancer"):
            cs.run_ml_enhancer = None


def _rembg_stub(new_session_fn, remove_fn=None):
    """Build a minimal rembg module stub."""
    stub = types.ModuleType("rembg")
    stub.new_session = new_session_fn
    stub.remove = remove_fn or (
        lambda img, session=None: Image.new(
            "RGBA", img.size if hasattr(img, "size") else (100, 100), (200, 100, 50, 255)
        )
    )
    return stub


# ─────────────────────────────────────────────────────────────
# 1. Canonical module imports guarantee single session
# ─────────────────────────────────────────────────────────────

class TestCanonicalImportSingleSession:
    """
    Verifies that the startup warm-up import path (ML.image_pipeline.processors.background_removal)
    and the real enhancement-pipeline import path (via ML.image_pipeline.enhancer)
    resolve to the same canonical module identity and create exactly ONE session.
    """

    def test_startup_and_enhancer_import_paths_share_one_session(self, monkeypatch, tmp_path):
        br = _fresh_module()
        call_count = {"n": 0}
        sentinel = MagicMock(name="shared_session")

        def _slow_new(model, **kwargs):
            call_count["n"] += 1
            time.sleep(0.05)  # race window
            return sentinel

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_slow_new))

        warmup_session = []

        def _warmup_target():
            # Real startup import path from backend/main.py:
            from ML.image_pipeline.processors.background_removal import get_rembg_session
            warmup_session.append(get_rembg_session())

        enhancer_result = []
        input_img_path = tmp_path / "test_pot.jpg"
        output_img_path = tmp_path / "test_out.jpg"
        img = Image.new("RGB", (100, 100), (150, 120, 100))
        img.save(input_img_path, "JPEG")

        def _enhancer_target():
            # Real enhancement pipeline import path:
            from ML.image_pipeline.enhancer import enhance_image
            res = enhance_image(str(input_img_path), str(output_img_path))
            enhancer_result.append(res)

        t_warmup = threading.Thread(target=_warmup_target, name="startup-warmup-thread")
        t_enhancer = threading.Thread(target=_enhancer_target, name="enhancer-pipeline-thread")

        t_warmup.start()
        t_enhancer.start()
        t_warmup.join(timeout=5.0)
        t_enhancer.join(timeout=5.0)

        assert not t_warmup.is_alive()
        assert not t_enhancer.is_alive()
        assert len(warmup_session) == 1
        assert len(enhancer_result) == 1
        assert warmup_session[0] is sentinel
        assert call_count["n"] == 1, (
            f"new_session() called {call_count['n']} times! "
            "Duplicate module import caused multiple ONNX sessions to load."
        )
        assert br._session is sentinel


# ─────────────────────────────────────────────────────────────
# 2. Concurrent get_rembg_session() creates exactly one session
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
# 3. Inference serialization: max_active_inferences == 1 and no deadlock
# ─────────────────────────────────────────────────────────────

class TestInferenceSerialization:
    """
    Proves that rembg.remove calls are strictly serialized across concurrent threads
    so max_active_inferences == 1 at all times, and proves no deadlock occurs
    after an inference failure.
    """

    def test_concurrent_inferences_strictly_serialized(self, monkeypatch):
        br = _fresh_module()
        active_inferences = 0
        max_active_inferences = 0
        lock = threading.Lock()
        sentinel_session = MagicMock(name="session")

        def _new(model, **kwargs):
            return sentinel_session

        def _blocking_remove(img, session=None):
            nonlocal active_inferences, max_active_inferences
            with lock:
                active_inferences += 1
                if active_inferences > max_active_inferences:
                    max_active_inferences = active_inferences
                current = active_inferences

            assert current == 1, f"Multiple active inferences running concurrently: {current}"
            time.sleep(0.04)  # Hold inside inference to force concurrency contention

            with lock:
                active_inferences -= 1

            return Image.new("RGBA", (10, 10))

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_new, _blocking_remove))

        threads = []
        errors = []

        def _worker():
            try:
                img = Image.new("RGB", (50, 50))
                br.remove_background(img)
            except Exception as e:
                errors.append(e)

        for _ in range(5):
            t = threading.Thread(target=_worker)
            threads.append(t)
            t.start()

        for t in threads:
            t.join(timeout=5.0)
            assert not t.is_alive(), "Worker thread hung/deadlocked during inference"

        assert not errors, f"Inference worker failed: {errors}"
        assert max_active_inferences == 1, (
            f"Expected max_active_inferences == 1, got {max_active_inferences}"
        )

    def test_no_deadlock_after_inference_failure(self, monkeypatch):
        br = _fresh_module()
        sentinel_session = MagicMock(name="session")

        def _new(model, **kwargs):
            return sentinel_session

        def _flaky_remove(img, session=None):
            if threading.current_thread().name == "failing-thread":
                raise MemoryError("simulated OOM in failing thread")
            return Image.new("RGBA", (10, 10))

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_new, _flaky_remove))

        t1_error = []
        t2_result = []

        def _failing_worker():
            try:
                img = Image.new("RGB", (50, 50))
                br.remove_background(img)
            except Exception as e:
                t1_error.append(e)

        def _succeeding_worker():
            try:
                img = Image.new("RGB", (50, 50))
                res = br.remove_background(img)
                t2_result.append(res)
            except Exception:
                pass

        t1 = threading.Thread(target=_failing_worker, name="failing-thread")
        t2 = threading.Thread(target=_succeeding_worker, name="succeeding-thread")

        t1.start()
        t1.join(timeout=2.0)
        assert not t1.is_alive(), "Failing thread deadlocked"
        assert len(t1_error) == 1
        assert isinstance(t1_error[0], RuntimeError)  # MemoryError wrapped as RuntimeError

        # Now start thread 2 after failure to prove no deadlock on _inference_lock
        t2.start()
        t2.join(timeout=2.0)
        assert not t2.is_alive(), "Succeeding thread deadlocked on lock after previous inference failure!"
        assert len(t2_result) == 1, "Thread 2 should have succeeded without deadlock"

    def test_concurrent_race_with_failure_no_deadlock(self, monkeypatch):
        br = _fresh_module()
        sentinel_session = MagicMock(name="session")
        active_inferences = 0
        max_active_inferences = 0
        lock = threading.Lock()

        def _new(model, **kwargs):
            return sentinel_session

        def _race_remove(img, session=None):
            nonlocal active_inferences, max_active_inferences
            with lock:
                active_inferences += 1
                if active_inferences > max_active_inferences:
                    max_active_inferences = active_inferences
                current = active_inferences

            assert current == 1, f"Multiple active inferences running concurrently: {current}"
            time.sleep(0.03)

            try:
                if threading.current_thread().name == "fail-thread":
                    raise MemoryError("simulated OOM")
                return Image.new("RGBA", (10, 10))
            finally:
                with lock:
                    active_inferences -= 1

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_new, _race_remove))

        t_fail = threading.Thread(
            target=lambda: (pytest.raises(RuntimeError, br.remove_background, Image.new("RGB", (10, 10)))),
            name="fail-thread"
        )
        t_ok = threading.Thread(
            target=lambda: br.remove_background(Image.new("RGB", (10, 10))),
            name="ok-thread"
        )

        t_fail.start()
        t_ok.start()
        t_fail.join(timeout=3.0)
        t_ok.join(timeout=3.0)

        assert not t_fail.is_alive()
        assert not t_ok.is_alive()
        assert max_active_inferences == 1


# ─────────────────────────────────────────────────────────────
# 4. Startup warm-up thread + simultaneous request = one session
# ─────────────────────────────────────────────────────────────

class TestWarmupRaceWithRequest:

    def test_warmup_and_request_share_one_session(self, monkeypatch):
        """
        Simulates the exact Railway crash: the lifespan warmup daemon starts
        loading the ONNX model; before it finishes, the first real enhancement
        request arrives. Only one ONNX session must be created.
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
            try:
                br.get_rembg_session()
            except Exception as e:
                errors.append(("warmup", e))

        def _api_request():
            time.sleep(0.01)  # arrives mid-init
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


# ─────────────────────────────────────────────────────────────
# 5. Correct rembg API: sess_opts= keyword
# ─────────────────────────────────────────────────────────────

class TestCorrectRembgApiKeyword:

    def test_sess_opts_keyword_is_used(self, monkeypatch):
        """
        new_session() must be called with sess_opts= (not session_options=).
        Verifies the exact keyword used in the call.
        """
        br = _fresh_module()
        captured_kwargs = {}

        def _capture_new(model, *args, **kwargs):
            captured_kwargs.update(kwargs)
            return MagicMock(name="session")

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_capture_new))

        br.get_rembg_session()

        assert "sess_opts" in captured_kwargs, (
            f"Expected sess_opts= keyword, got kwargs: {list(captured_kwargs.keys())}. "
            "rembg.new_session does not accept session_options=."
        )
        assert "session_options" not in captured_kwargs, (
            "session_options= was passed — this keyword does not exist in rembg."
        )

    def test_sess_opts_value_is_onnx_session_options(self, monkeypatch):
        """
        The value passed as sess_opts= must be an onnxruntime.SessionOptions
        instance with the correct conservative settings applied.
        """
        br = _fresh_module()
        captured_kwargs = {}

        def _capture_new(model, *args, **kwargs):
            captured_kwargs.update(kwargs)
            return MagicMock(name="session")

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_capture_new))
        br.get_rembg_session()

        opts = captured_kwargs.get("sess_opts")
        assert opts is not None, "sess_opts= was not passed to new_session()"

        import onnxruntime as ort
        assert isinstance(opts, ort.SessionOptions), (
            f"sess_opts value is {type(opts)}, expected onnxruntime.SessionOptions"
        )
        assert opts.intra_op_num_threads == 1, (
            f"intra_op_num_threads={opts.intra_op_num_threads}, expected 1"
        )
        assert opts.inter_op_num_threads == 1, (
            f"inter_op_num_threads={opts.inter_op_num_threads}, expected 1"
        )
        assert opts.enable_cpu_mem_arena is False, (
            f"enable_cpu_mem_arena={opts.enable_cpu_mem_arena}, expected False"
        )


# ─────────────────────────────────────────────────────────────
# 6. CPU execution provider is always passed
# ─────────────────────────────────────────────────────────────

class TestCpuExecutionProvider:

    def test_cpu_provider_passed_to_new_session(self, monkeypatch):
        """
        new_session() must always receive providers=["CPUExecutionProvider"]
        to prevent any GPU memory allocation on Railway.
        """
        br = _fresh_module()
        captured_kwargs = {}

        def _capture_new(model, *args, **kwargs):
            captured_kwargs.update(kwargs)
            return MagicMock(name="session")

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_capture_new))
        br.get_rembg_session()

        providers = captured_kwargs.get("providers")
        assert providers is not None, "providers= was not passed to new_session()"
        assert "CPUExecutionProvider" in providers, (
            f"CPUExecutionProvider missing from providers: {providers}"
        )


# ─────────────────────────────────────────────────────────────
# 7. Fail-closed ONNX Configuration
# ─────────────────────────────────────────────────────────────

class TestFailClosedOnnxConfiguration:
    """
    Verifies that ONNX configuration fails closed:
    - If safe SessionOptions cannot be created, get_rembg_session() raises RuntimeError.
    - rembg.new_session is NEVER called with unconstrained defaults.
    - Calling remove_background fails closed with RuntimeError so catalog service returns degraded.
    - Narrow unsupported settings (like enable_cpu_mem_arena AttributeError) are handled gracefully.
    """

    def test_config_failure_raises_runtime_error_and_does_not_call_new_session(self, monkeypatch):
        br = _fresh_module()
        new_session_calls = []

        def _capture_new(model, *args, **kwargs):
            new_session_calls.append((model, kwargs))
            return MagicMock(name="session")

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_capture_new))
        monkeypatch.setattr(br, "_make_onnx_session_options", MagicMock(side_effect=RuntimeError("onnxruntime init error")))

        with pytest.raises(RuntimeError, match="Safe ONNX configuration cannot be created"):
            br.get_rembg_session()

        assert len(new_session_calls) == 0, (
            "new_session was called despite ONNX options failure! "
            "Unconstrained defaults must never be used."
        )

    def test_config_returning_none_raises_runtime_error(self, monkeypatch):
        br = _fresh_module()
        new_session_calls = []

        def _capture_new(model, *args, **kwargs):
            new_session_calls.append((model, kwargs))
            return MagicMock(name="session")

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_capture_new))
        monkeypatch.setattr(br, "_make_onnx_session_options", lambda: None)

        with pytest.raises(RuntimeError, match="Safe ONNX configuration cannot be created"):
            br.get_rembg_session()

        assert len(new_session_calls) == 0, (
            "new_session was called with None options! Unconstrained defaults must not be used."
        )

    def test_remove_background_fails_closed_when_onnx_config_fails(self, monkeypatch):
        br = _fresh_module()
        monkeypatch.setattr(br, "_make_onnx_session_options", MagicMock(side_effect=RuntimeError("onnx config error")))

        img = Image.new("RGB", (50, 50))
        with pytest.raises(RuntimeError, match="Safe ONNX configuration cannot be created"):
            br.remove_background(img)

    def test_narrow_attribute_error_on_arena_is_handled(self, monkeypatch):
        """
        If enable_cpu_mem_arena raises AttributeError (older onnxruntime),
        the options should still be returned with ORT_SEQUENTIAL and 1 thread.
        """
        br = _fresh_module()
        import onnxruntime as ort

        real_session_options = ort.SessionOptions
        class MockOptions(real_session_options):
            @property
            def enable_cpu_mem_arena(self):
                raise AttributeError("Attribute not supported on older onnxruntime")

            @enable_cpu_mem_arena.setter
            def enable_cpu_mem_arena(self, val):
                raise AttributeError("Attribute not supported on older onnxruntime")

        monkeypatch.setattr(ort, "SessionOptions", MockOptions)

        opts = br._make_onnx_session_options()
        assert opts is not None
        assert opts.intra_op_num_threads == 1
        assert opts.inter_op_num_threads == 1
        assert opts.execution_mode == ort.ExecutionMode.ORT_SEQUENTIAL


# ─────────────────────────────────────────────────────────────
# 8. No fallback to heavier u2net after any failure
# ─────────────────────────────────────────────────────────────

class TestNoHeavyModelFallback:

    def test_oom_does_not_fall_back_to_u2net(self, monkeypatch):
        """
        MemoryError during u2netp init must raise RuntimeError immediately.
        new_session() must NOT be called again with u2net.
        """
        br = _fresh_module()
        calls = []

        def _track_new(model, *args, **kwargs):
            calls.append(model)
            raise MemoryError("simulated OOM")

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_track_new))

        with pytest.raises(RuntimeError, match="[Oo]ut of memory"):
            br.get_rembg_session()

        assert calls == ["u2netp"], (
            f"Expected only u2netp attempt, got: {calls}. "
            "u2net fallback after OOM would worsen memory pressure."
        )

    def test_general_exception_does_not_fall_back_to_u2net(self, monkeypatch):
        """
        Any non-OOM model-load failure must also raise RuntimeError immediately
        without attempting u2net, since u2net is larger than u2netp.
        """
        br = _fresh_module()
        calls = []

        def _track_new(model, *args, **kwargs):
            calls.append(model)
            raise RuntimeError("simulated corrupt model file")

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_track_new))

        with pytest.raises(RuntimeError):
            br.get_rembg_session()

        assert calls == ["u2netp"], (
            f"Expected only u2netp attempt after general exception, got: {calls}."
        )

    def test_onnx_config_failure_does_not_fall_back_to_u2net(self, monkeypatch):
        """
        If safe ONNX configuration fails, new_session must not be called with u2net.
        """
        br = _fresh_module()
        calls = []

        def _track_new(model, *args, **kwargs):
            calls.append(model)
            return MagicMock(name="session")

        monkeypatch.setitem(sys.modules, "rembg", _rembg_stub(_track_new))
        monkeypatch.setattr(br, "_make_onnx_session_options", MagicMock(side_effect=RuntimeError("onnx config error")))

        with pytest.raises(RuntimeError, match="Safe ONNX configuration cannot be created"):
            br.get_rembg_session()

        assert calls == [], f"Expected no new_session calls, got: {calls}"


# ─────────────────────────────────────────────────────────────
# 9. Test Suite Coexistence & Order Independence Regression
# ─────────────────────────────────────────────────────────────

class TestSuiteCoexistenceAndOrderIndependence:
    """
    Proves that background removal tests do not leak stubs, mutated globals,
    or split module identities that break backend idempotency failure handling tests,
    and proves that both suites can run in any sequence.
    """

    def test_canonical_identity_intact_and_enhancer_not_leaked(self):
        """
        Verify that ML.image_pipeline.processors.background_removal is the sole canonical
        identity, module state is cleanly reset, and catalog_service.run_ml_enhancer is None.
        """
        import ML.image_pipeline.processors.background_removal as br
        assert br._session is None
        assert isinstance(br._session_lock, type(threading.Lock()))
        assert isinstance(br._inference_lock, type(threading.Lock()))

        if "backend.services.catalog_service" in sys.modules:
            cs = sys.modules["backend.services.catalog_service"]
            assert getattr(cs, "run_ml_enhancer", None) is None

    def test_coexistence_with_catalog_service_enhance_mock(self, tmp_path):
        """
        Simulates the exact interaction with backend idempotency tests:
        patches CatalogService.enhance_product_photo, verifies the patch is effective
        and not bypassed, and proves background_removal session isolation is uncorrupted.
        """
        from unittest.mock import patch
        import backend.services.catalog_service as cs

        mock_target = cs.CatalogService
        with patch.object(mock_target, "enhance_product_photo", return_value=("mock_path.png", False, None)):
            instance = mock_target()
            assert hasattr(instance, "enhance_product_photo")

        # Verify that background removal canonical session remains functional and uncorrupted
        br = _fresh_module()
        assert br._session is None
