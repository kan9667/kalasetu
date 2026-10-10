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
# thread, 1 inter-op thread, and CPU memory arena disabled to
# keep the resident-set as small as possible.
# ============================================================

import gc
import logging
import sys
import threading

from PIL import Image

logger = logging.getLogger(__name__)

# Module-level locks:
# _session_lock guarantees at most one thread enters the session-initialisation critical section.
# _inference_lock guarantees at most one thread executes rembg.remove inference at a time.
if "ML.image_pipeline.processors.background_removal" in sys.modules:
    _canonical = sys.modules["ML.image_pipeline.processors.background_removal"]
    _session_lock = getattr(_canonical, "_session_lock", threading.Lock())
    _inference_lock = getattr(_canonical, "_inference_lock", threading.Lock())
else:
    _session_lock = threading.Lock()
    _inference_lock = threading.Lock()

_session = None

# Defense-in-depth: Ensure both canonical and legacy module paths share the same module instance
# in sys.modules so any stray import of processors.background_removal cannot create a duplicate session.
if __name__ == "ML.image_pipeline.processors.background_removal":
    sys.modules.setdefault("processors.background_removal", sys.modules[__name__])
elif __name__ == "processors.background_removal":
    sys.modules.setdefault("ML.image_pipeline.processors.background_removal", sys.modules[__name__])


def _make_onnx_session_options():
    """
    Return conservative ONNX Runtime SessionOptions tuned for
    constrained cloud instances (<=1 GB RAM).

    Enforces:
    - ORT_SEQUENTIAL execution
    - 1 intra-op thread
    - 1 inter-op thread
    - enable_cpu_mem_arena = False

    Raises RuntimeError if safe ONNX configuration cannot be created,
    failing closed rather than running with unconstrained defaults.
    """
    try:
        import onnxruntime as ort  # type: ignore
    except Exception as exc:
        logger.error("[background_removal] onnxruntime import failed: %s", exc)
        raise RuntimeError(f"onnxruntime is not available: {exc}") from exc

    try:
        opts = ort.SessionOptions()
        # Sequential execution: no inter-op thread pool overhead.
        opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        # One thread for intra-op parallelism (within a single op).
        opts.intra_op_num_threads = 1
        # One thread for inter-op parallelism (between ops).
        opts.inter_op_num_threads = 1
    except Exception as exc:
        logger.error("[background_removal] Failed to initialize basic SessionOptions: %s", exc)
        raise RuntimeError(f"Failed to configure safe ONNX SessionOptions: {exc}") from exc

    # Disable CPU memory arena allocator to reduce peak RSS.
    # Handle older/alternate onnxruntime builds that may lack this attribute narrowly.
    try:
        opts.enable_cpu_mem_arena = False
    except AttributeError:
        logger.warning(
            "[background_removal] enable_cpu_mem_arena attribute not found on SessionOptions; continuing with conservative threads."
        )

    return opts


def get_rembg_session():
    """Lazily initialize and reuse the rembg/ONNX session.

    Uses u2netp (4 MB lightweight model) with CPU-only execution and
    conservative thread/memory settings for Railway's 1 GB tier.

    Thread-safety: a module-level lock prevents concurrent threads from
    each entering the initialisation block, which would briefly load two
    ONNX sessions into memory and OOM-crash the process.

    On any failure (MemoryError, model load error, import error, or failure
    to create safe ONNX options) a RuntimeError is raised so
    catalog_service.enhance_product_photo() can return the original image
    marked degraded without crashing FastAPI.

    Fail-closed: Unconstrained ONNX defaults are NEVER used. If safe ONNX
    configuration cannot be created, initialization fails immediately with
    RuntimeError.

    No fallback to the heavier u2net model is attempted: if u2netp cannot
    be loaded due to memory pressure, u2net would only make things worse.
    """
    global _session

    # Fast-path: session already exists — GIL makes the reference read atomic.
    if _session is not None:
        return _session

    with _session_lock:
        # Re-check inside the lock: another thread may have initialized
        # the session while we waited to acquire it.
        if _session is not None:
            return _session

        try:
            from rembg import new_session
        except ImportError as e:
            raise RuntimeError(f"rembg is not installed or available: {e}")

        # Fail closed: must obtain safe ONNX session options.
        try:
            onnx_opts = _make_onnx_session_options()
        except Exception as exc:
            logger.error("[background_removal] Safe ONNX configuration failed: %s", exc)
            raise RuntimeError(
                f"Safe ONNX configuration cannot be created: {exc}. "
                "Image enhancement will be degraded."
            ) from exc

        if onnx_opts is None:
            logger.error("[background_removal] Safe ONNX configuration returned None.")
            raise RuntimeError(
                "Safe ONNX configuration cannot be created. "
                "Image enhancement will be degraded."
            )

        try:
            # Correct rembg keyword is sess_opts= (not session_options=).
            # Explicit CPUExecutionProvider prevents any GPU memory allocation.
            _session = new_session(
                "u2netp",
                sess_opts=onnx_opts,
                providers=["CPUExecutionProvider"],
            )
            logger.info(
                "[background_removal] rembg u2netp session initialized "
                "(CPU-only, 1 intra/inter-op thread, arena disabled)"
            )
        except MemoryError as exc:
            # Do NOT attempt u2net — it is larger and would worsen OOM pressure.
            raise RuntimeError(
                "Out of memory while initializing rembg u2netp ONNX session. "
                "Image enhancement will be degraded."
            ) from exc
        except Exception as exc:
            # Any other model-load failure (corrupt file, missing weights, etc.)
            # is also non-retryable with a heavier model.
            raise RuntimeError(
                f"Failed to initialize rembg u2netp session: {exc}. "
                "Image enhancement will be degraded."
            ) from exc

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
        RuntimeError: If the rembg session cannot be created (OOM, import
                      failure, model error) or if inference runs out of
                      memory.  The caller (catalog_service) catches this
                      and returns the original image marked degraded rather
                      than crashing the FastAPI process.
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

    # Propagates RuntimeError from OOM / import failure — caller degrades gracefully.
    session = get_rembg_session()

    # Inference serialization: ensure at most 1 inference runs concurrently in this process.
    with _inference_lock:
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
