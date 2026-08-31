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

from ML.voice_pipeline.config import get_settings, needs_translation
from ML.voice_pipeline.glossary import build_prompt_hint, get_glossary_terms
from ML.voice_pipeline.models import (
    JobStatus,
    STTProvider,
    TranslatedTranscript,
    Transcript,
    VoiceNote,
    VoicePipelineResult,
)
from ML.voice_pipeline.transcription.base_transcriber import BaseTranscriber
from ML.voice_pipeline.transcription.runner import TranscriptionRunner


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


# ---- Language routing ----


def test_hindi_is_not_translated():
    """Hindi must reach the catalog service untranslated, or the Hindi
    listing becomes a back-translation of English."""
    assert needs_translation("hi") is False


@pytest.mark.parametrize("code", ["ta", "bn", "mr", "te", "gu", "kn", "ml", "pa", "or"])
def test_regional_languages_are_translated(code):
    assert needs_translation(code) is True


def test_unknown_language_is_not_translated():
    """An unrecognised code falls through untranslated rather than erroring."""
    assert needs_translation("xx") is False


def test_supported_languages_include_hindi():
    assert "hi" in get_settings().supported_languages


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


def test_prompt_hint_contains_terms():
    hint = build_prompt_hint(category="Pottery", limit=5)
    assert "Terracotta" in hint
    assert hint.endswith(".")


# ---- Transcript usability ----


def test_usable_transcript():
    t = Transcript(text="यह मिट्टी का बर्तन है", language_code="hi",
                   provider=STTProvider.BHASHINI)
    assert t.is_usable() is True


def test_fallback_transcript_is_rejected():
    """A fallback must never reach listing generation — it would produce a
    confident listing for a product the artisan never described."""
    t = Transcript(text="anything", language_code="hi",
                   provider=STTProvider.BHASHINI, is_fallback=True)
    assert t.is_usable() is False


def test_empty_transcript_is_rejected():
    t = Transcript(text="   ", language_code="hi", provider=STTProvider.BHASHINI)
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
        TranscriptionRunner(provider="bashini")


# ---- Handoff to the catalog service ----


def test_handoff_uses_transcript_when_not_translated():
    result = VoicePipelineResult(
        voice_note_id="1",
        status=JobStatus.COMPLETED,
        transcript=Transcript(text="मिट्टी का बर्तन", language_code="hi",
                              provider=STTProvider.BHASHINI),
    )
    assert result.text_for_listing == "मिट्टी का बर्तन"


def test_handoff_uses_translation_when_present():
    result = VoicePipelineResult(
        voice_note_id="1",
        status=JobStatus.COMPLETED,
        transcript=Transcript(text="மண் பானை", language_code="ta",
                              provider=STTProvider.BHASHINI),
        translation=TranslatedTranscript(
            source_text="மண் பானை",
            source_language="ta",
            translated_text="clay pot",
            target_language="en",
        ),
    )
    assert result.text_for_listing == "clay pot"


def test_handoff_is_empty_when_transcription_failed():
    result = VoicePipelineResult(voice_note_id="1", status=JobStatus.FAILED)
    assert result.text_for_listing == ""
