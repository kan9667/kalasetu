# ============================================================
# background_removal.py — Stage 2: AI-based background removal
# ============================================================
# Uses rembg to remove the background from a product photo.
# The output is an RGBA image where the background is transparent
# and only the product remains visible.
#
# Thread-safety: _session_lock ensures that concurrent callers
# (e.g. startup warm-up thread + first API request) can never
# race to create two ONNX sessions simultaneously.  On a Railway
# free tier with 1 GB RAM, two concurrent rembg/ONNX loads push
# peak usage over the limit and cause OOM crashes.
#
# ONNX conservatism: CPU-only execution provider, 1 intra-op
# thread, 1 inter-op thread, and arena-shrink after inference to
# keep the resident-set as small as possible.
# ============================================================

import gc
import logging
import threading

from PIL import Image

logger = logging.getLogger(__name__)

# Module-level lock: guarantees at most one thread enters the
# session-initialisation critical section at a time.
_session_lock = threading.Lock()
_session = None


def _make_onnx_session_options():
    """
    Return conservative ONNX Runtime session options tuned for
    constrained cloud instances (≤1 GB RAM).

    Falls back gracefully when onnxruntime is unavailable so that
    the rembg new_session() call still works via its own defaults.
    """
    try:
        import onnxruntime as ort  # type: ignore

        opts = ort.SessionOptions()
        # CPU-only: avoids any GPU memory initialisation overhead.
        opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        # One thread for intra-op parallelism (within a single op).
        opts.intra_op_num_threads = 1
        # One thread for inter-op parallelism (between ops).
        opts.inter_op_num_threads = 1
        # Release memory arenas after each run where supported.
        try:
            opts.enable_mem_arena = False  # type: ignore[attr-defined]
        except AttributeError:
            pass  # Older ONNX Runtime versions may not expose this flag
        return opts
    except Exception:
        return None


def get_rembg_session():
    """Lazily initialize and reuse the ONNX session to avoid model reload penalty.

    Uses u2netp (4 MB lightweight model) for fast inference and low RAM usage.

    Thread-safety: a module-level lock prevents concurrent threads from each
    entering the initialisation block, which would briefly load two ONNX
    sessions into memory and OOM-crash on Railway's 1 GB tier.
    """
    global _session

    # Fast-path: session already exists — no lock needed for reads of a
    # reference that Python's GIL makes atomic.
    if _session is not None:
        return _session

    with _session_lock:
        # Re-check inside the lock: another thread may have initialized
        # the session while we waited to acquire the lock.
        if _session is not None:
            return _session

        try:
            from rembg import new_session
        except ImportError as e:
            raise RuntimeError(f"rembg is not installed or available: {e}")

        onnx_opts = _make_onnx_session_options()

        try:
            if onnx_opts is not None:
                _session = new_session("u2netp", session_options=onnx_opts)
            else:
                _session = new_session("u2netp")
            logger.info("[background_removal] rembg u2netp session initialized (conservative ONNX settings)")
        except TypeError:
            # Older rembg versions do not accept session_options keyword.
            try:
                _session = new_session("u2netp")
                logger.info("[background_removal] rembg u2netp session initialized (legacy API)")
            except Exception:
                _session = new_session("u2net")
                logger.warning("[background_removal] u2netp unavailable; fell back to u2net")
        except MemoryError as exc:
            raise RuntimeError(
                "Out of memory while initializing rembg ONNX session. "
                "Falling back to degraded mode."
            ) from exc
        except Exception as exc:
            # Last-resort fallback to the heavier u2net model in case u2netp
            # model file is corrupt or missing.
            try:
                _session = new_session("u2net")
                logger.warning("[background_removal] u2netp failed (%s); fell back to u2net", exc)
            except MemoryError as mem_exc:
                raise RuntimeError(
                    "Out of memory while initializing rembg fallback ONNX session."
                ) from mem_exc

    return _session


def remove_background(image):
    """
    Remove the background from a product photograph using rembg.

    This removes walls, furniture, clutter, and other distracting
    elements while preserving the main product/subject.

    Args:
        image (PIL.Image): Input image in RGB mode.

    Returns:
        PIL.Image: RGBA image with transparent background.

    Raises:
        RuntimeError: If the rembg session cannot be created due to OOM or
                      import failure.  The caller (catalog_service) catches
                      this and returns an explicit degraded result instead of
                      crashing the FastAPI process.
    """
    # Ensure the image is in RGB mode for rembg
    if image.mode != "RGB":
        image = image.convert("RGB")

    # Downscale for fast rembg processing if image is large.
    # 768px provides crisp edge detection while using minimal RAM on cloud containers.
    max_dim = max(image.size)
    if max_dim > 768:
        ratio = 768.0 / max_dim
        new_size = (int(image.size[0] * ratio), int(image.size[1] * ratio))
        process_img = image.resize(new_size, Image.Resampling.BILINEAR)
    else:
        process_img = image

    try:
        from rembg import remove
    except ImportError as e:
        raise RuntimeError(f"rembg is not installed or available: {e}")

    try:
        session = get_rembg_session()
    except RuntimeError:
        # OOM or import failure — propagate so the caller can degrade gracefully.
        raise

    try:
        result = remove(process_img, session=session)
    except MemoryError as exc:
        raise RuntimeError(
            "Out of memory during rembg inference. Degraded result will be used."
        ) from exc

    # Make sure the result is in RGBA mode
    if result.mode != "RGBA":
        result = result.convert("RGBA")

    # Free temporary buffers
    gc.collect()

    return result
