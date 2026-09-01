"""Glossary package — craft vocabulary hints for transcription."""

from .craft_terms import (
    ALL_TERMS,
    CATEGORIES,
    DEVANAGARI_TERMS,
    build_prompt_hint,
    get_glossary_terms,
)

__all__ = [
    "ALL_TERMS",
    "CATEGORIES",
    "DEVANAGARI_TERMS",
    "build_prompt_hint",
    "get_glossary_terms",
]
