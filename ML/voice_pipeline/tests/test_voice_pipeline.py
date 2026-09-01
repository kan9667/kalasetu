# ============================================================
# test_voice_pipeline.py — Tests for the voice pipeline
# ============================================================
# Every test runs offline. No API key, no network, no audio
# files are required — recordings are synthesised with the
# standard library. Run with: python -m pytest tests/ -v
# ============================================================

import os
import sys
import wave
from pathlib import Path

import pytest

# Add the project root to sys.path so `ML.voice_pipeline` resolves
sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from ML.voice_pipeline.config import get_settings
from ML.voice_pipeline.glossary import build_prompt_hint, get_glossary_terms
from ML.voice_pipeline.models import (
    JobStatus,
    STTProvider,
    Transcript,
    VoiceNote,
    VoicePipelineResult,
)
from ML.voice_pipeline.transcription.base_transcriber import BaseTranscriber
from ML.voice_pipeline.transcription.runner import TRANSCRIBERS, TranscriptionRunner
from ML.voice_pipeline.transcription.whisper_transcriber import WhisperTranscriber


# ---- Helpers: Create synthetic audio and stub transcribers ----


def create_wav(path: Path, seconds: float = 1.0, framerate: int = 16000) -> Path:
    """Write a silent mono WAV file so tests need no real recordings."""
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(framerate)
        w.writeframes(b"\x00\x00" * int(framerate * seconds))
    return path


class StubTranscriber(BaseTranscriber):
    """Concrete transcriber used to exercise the shared base-class helpers."""

    provider = STTProvider.MANUAL

    def transcribe(self, note, category_hint=None):
        return Transcript(
            text="test transcript",
            language_code=note.language_code,
            provider=self.provider,
        )


@pytest.fixture
def voice_note(tmp_path):
    """A VoiceNote pointing at a valid one-second recording."""
    audio = create_wav(tmp_path / "note.wav")
    return VoiceNote(id="test-1", audio_path=str(audio), language_code="hi")


# ---- Configuration ----


def test_supported_languages_include_hindi():
    assert "hi" in get_settings().supported_languages


def test_default_language_is_hindi():
    assert get_settings().default_language == "hi"


def test_whisper_is_the_configured_backend():
    assert get_settings().stt_provider == "whisper"


def test_endpoint_is_configured():
    """A blank base URL would post to a relative path and fail confusingly."""
    assert get_settings().whisper_base_url.startswith("http")


# ---- Craft glossary ----


def test_glossary_returns_terms():
    terms = get_glossary_terms()
    assert len(terms) > 0
    assert "Bandhani" in terms or "Dhokra" in terms


def test_glossary_respects_limit():
    assert len(get_glossary_terms(limit=5)) == 5


def test_glossary_prioritises_category():
    """A pottery hint must surface pottery vocabulary first, or the most
    relevant terms get cut by the limit."""
    terms = get_glossary_terms(category="Pottery", limit=6)
    assert "Terracotta" in terms


def test_glossary_category_is_case_insensitive():
    assert get_glossary_terms(category="pottery", limit=6) == get_glossary_terms(
        category="POTTERY", limit=6
    )


def test_glossary_has_no_duplicates():
    terms = get_glossary_terms(category="Textiles", limit=60)
    assert len(terms) == len(set(terms))


def test_prompt_hint_is_a_bare_term_list():
    """Whisper reads the prompt as context, not instruction. An English
    sentence wrapped around the terms dilutes the bias — measured on a Hindi
    sample, the wrapped form failed to recover a craft word the bare list did."""
    hint = build_prompt_hint(category="Pottery", limit=5)
    assert "Terracotta" in hint
    assert "Transcribe" not in hint
    assert hint.count(",") == 4


def test_hindi_gets_devanagari_terms():
    """A Hindi transcript comes back in Devanagari, so Latin hints cannot
    match it."""
    hint = build_prompt_hint(limit=10, language_code="hi")
    assert "मिट्टी" in hint


def test_non_devanagari_language_gets_latin_terms():
    hint = build_prompt_hint(category="Pottery", limit=10, language_code="ta")
    assert "Terracotta" in hint


# ---- Transcript usability ----


def test_usable_transcript():
    t = Transcript(text="यह मिट्टी का बर्तन है", language_code="hi",
                   provider=STTProvider.WHISPER)
    assert t.is_usable() is True


def test_fallback_transcript_is_rejected():
    """A fallback must never reach listing generation — it would produce a
    confident listing for a product the artisan never described."""
    t = Transcript(text="anything", language_code="hi",
                   provider=STTProvider.WHISPER, is_fallback=True)
    assert t.is_usable() is False


def test_empty_transcript_is_rejected():
    t = Transcript(text="   ", language_code="hi", provider=STTProvider.WHISPER)
    assert t.is_usable() is False


# ---- Audio validation ----


def test_validate_accepts_a_real_file(voice_note):
    StubTranscriber().validate_audio(voice_note, max_duration=180)


def test_validate_rejects_missing_file():
    note = VoiceNote(id="x", audio_path="/does/not/exist.m4a")
    with pytest.raises(FileNotFoundError):
        StubTranscriber().validate_audio(note, max_duration=180)


def test_validate_rejects_empty_file(tmp_path):
    empty = tmp_path / "empty.m4a"
    empty.touch()
    note = VoiceNote(id="x", audio_path=str(empty))
    with pytest.raises(ValueError, match="empty"):
        StubTranscriber().validate_audio(note, max_duration=180)


def test_validate_rejects_overlong_recording(voice_note):
    voice_note.duration_seconds = 500
    with pytest.raises(ValueError, match="exceeds"):
        StubTranscriber().validate_audio(voice_note, max_duration=180)


def test_fallback_transcript_is_flagged(voice_note):
    t = StubTranscriber().fallback_transcript(voice_note, "network down")
    assert t.is_fallback is True
    assert t.is_usable() is False


# ---- Audio format detection ----


@pytest.mark.parametrize(
    "filename,expected",
    [("a.wav", "wav"), ("a.m4a", "m4a"), ("a.mp3", "mp3"),
     ("a.flac", "flac"), ("a.WAV", "wav")],
)
def test_format_detected_from_extension(filename, expected):
    note = VoiceNote(id="x", audio_path=f"/tmp/{filename}")
    assert StubTranscriber().detect_format(note) == expected


def test_unknown_format_passes_through():
    """An unknown extension is sent as-is, so a rejection names the real
    format instead of one we guessed at."""
    note = VoiceNote(id="x", audio_path="/tmp/a.opus")
    assert StubTranscriber().detect_format(note) == "opus"


# ---- Backend selection ----


def test_runner_defaults_to_configured_provider():
    assert TranscriptionRunner().provider_name == get_settings().stt_provider


def test_runner_rejects_unknown_provider():
    """A typo in STT_PROVIDER must fail immediately with a clear message."""
    with pytest.raises(ValueError, match="Unknown STT provider"):
        TranscriptionRunner(provider="wisper")


# ---- Whisper backend ----


def test_whisper_is_registered():
    assert TRANSCRIBERS["whisper"] is WhisperTranscriber


def test_whisper_satisfies_the_contract():
    """Whisper must be usable anywhere a transcriber is expected."""
    from ML.voice_pipeline.transcription.base_transcriber import BaseTranscriber

    assert issubclass(WhisperTranscriber, BaseTranscriber)


def test_whisper_without_a_key_fails_safely(voice_note):
    """No key must produce a flagged fallback, never a silent bad transcript
    that reaches the catalog service looking real.

    The key is blanked on this instance rather than read from the environment,
    so the test behaves the same whether or not one is configured locally.
    """
    transcriber = WhisperTranscriber()
    transcriber.settings.whisper_api_key = ""

    t = transcriber.transcribe(voice_note)
    assert t.is_fallback is True
    assert t.is_usable() is False


def test_whisper_reports_itself_as_provider():
    assert WhisperTranscriber.provider == STTProvider.WHISPER


def test_glossary_reaches_the_transcription_prompt():
    """Craft terms must be offered to Whisper at recognition time, which is
    where "Dhokra" stops becoming "doctor"."""
    hint = build_prompt_hint(category="Textiles", limit=10)
    assert "Bandhani" in hint or "Ajrakh" in hint


# ---- Handoff to the catalog service ----


def test_handoff_uses_transcript_when_not_translated():
    result = VoicePipelineResult(
        voice_note_id="1",
        status=JobStatus.COMPLETED,
        transcript=Transcript(text="मिट्टी का बर्तन", language_code="hi",
                              provider=STTProvider.WHISPER),
    )
    assert result.text_for_listing == "मिट्टी का बर्तन"


def test_handoff_is_empty_when_transcription_failed():
    result = VoicePipelineResult(voice_note_id="1", status=JobStatus.FAILED)
    assert result.text_for_listing == ""
