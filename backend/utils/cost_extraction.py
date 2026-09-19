"""
Shared Cost Cue Extraction Utilities.

Provides a unified, deterministic regex extractor and helper functions
for parsing artisan base costs, making expenses, labor hours, and hourly rates
from voice transcripts and text descriptions.

ReDoS safety: all regexes here run against individual short tokens (≤50 chars)
produced by splitting on whitespace, never against the full free-text string.
This guarantees linear worst-case complexity regardless of input length or
adversarial repetition, satisfying CodeQL CWE-1333 requirements.
"""

from __future__ import annotations

import re
from typing import Dict, Optional

DEFAULT_HOURLY_RATE = 50.0

# ---------------------------------------------------------------------------
# Compiled atomic patterns — each matches a SINGLE TOKEN only.
# No optional groups that overlap with mandatory quantifiers; no \s* chains.
# ---------------------------------------------------------------------------

# Matches a bare number token: integer or decimal (e.g. "450", "3.5", "1,200")
_NUM = re.compile(r"^[0-9]{1,10}(?:,[0-9]{1,3})*(?:\.[0-9]{1,6})?$")

# Currency prefix token: ₹, Rs, Rs., INR (case-insensitive)
_CURRENCY_PREFIX = re.compile(r"^(?:₹|rs\.?|inr)$", re.IGNORECASE)

# Currency suffix token: rupees, rs, inr, rupaye, रुपये, रुपया, रु (not followed by / or per)
_CURRENCY_SUFFIX = re.compile(
    r"^(?:rupees?|rs\.?|inr|rupaye?|रुपये|रुपया|रु)$", re.IGNORECASE
)

# Hourly-rate separator token: /, per, प्रति
_RATE_SEP = re.compile(r"^(?:\/|per|प्रति)$", re.IGNORECASE)

# Time unit token: hr, hrs, hour, hours, ghante, ghanta, घंटे, घण्टे, घंटा
_HOUR_UNIT = re.compile(
    r"^(?:hours?|hrs?|ghante|ghanta|घंटे|घण्टे|घंटा)$", re.IGNORECASE
)

# Day unit token: day, days, दिन
_DAY_UNIT = re.compile(r"^(?:days?|दिन)$", re.IGNORECASE)

# Contextual cost-keyword tokens (any one of these triggers "next number = materials")
_COST_KEYWORD = re.compile(
    r"^(?:making|cost|base|raw|materials?|production|manufacturing|लागत|खर्च)$",
    re.IGNORECASE,
)

# Separator tokens that appear between keyword phrase and the number
_KW_SEP = re.compile(r"^(?:[:=\-]|is|was|around|approx|roughly|लगभग|of|total)$", re.IGNORECASE)

# Hindi/Devanagari rate-per-hour phrase token
_HINDI_RATE = re.compile(r"^(?:रुपये?|rupaye?)$", re.IGNORECASE)
_HINDI_PER = re.compile(r"^(?:प्रति)$", re.IGNORECASE)


def _parse_number(token: str) -> Optional[float]:
    """Parse a number token, handling thousands-comma separators."""
    if _NUM.match(token):
        try:
            return float(token.replace(",", ""))
        except ValueError:
            return None
    return None


def regex_extract_cost_cues(text: str) -> Dict[str, float]:
    """
    Deterministically extract cost cues from speech transcripts or description text.
    Handles English, Hinglish, and Hindi (Devanagari) phrases, decimals, currency symbols,
    and sentences with both cost and hours.

    Implementation uses token-level matching (split on whitespace) so that no regex
    ever runs against unbounded free text, preventing polynomial ReDoS (CWE-1333).
    """
    if not text:
        return {
            "materials": 0.0,
            "labor_hours": 0.0,
            "hourly_rate": DEFAULT_HOURLY_RATE,
            "transport": 0.0,
            "overhead": 0.0,
            "cost_floor": 0.0,
        }

    # Cap and tokenise — O(n), no regex backtracking on full string.
    tokens = text.strip()[:4000].split()

    materials: float = 0.0
    labor_hours: float = 0.0
    hourly_rate: float = DEFAULT_HOURLY_RATE
    found_hourly_rate = False
    found_materials = False
    found_hours = False

    n = len(tokens)
    i = 0
    while i < n:
        tok = tokens[i]
        # Strip trailing punctuation (period, comma, colon, semicolon, exclamation)
        # so "hours." and "days," match unit patterns correctly.
        tok = tok.rstrip(".,:;!।")

        # ----------------------------------------------------------------
        # 1. Hourly rate detection
        #    Pattern A: <number> / <time_unit>  e.g. "80/hr" (fused token)
        #    Pattern B: <number> per <time_unit>
        #    Pattern C: <number> rupaye per <time_unit>  (Hinglish)
        #    Pattern D: <₹|rs> <number> / <time_unit>
        # ----------------------------------------------------------------
        if not found_hourly_rate:
            # Fused token like "80/hr" or "₹80/hr"
            fused = re.match(
                r"^(?:₹|rs\.?|inr)?([0-9]{1,10}(?:\.[0-9]{1,6})?)(?:/|per)"
                r"(?:hr|hour|ghante|ghanta|घंटा|घंटे)$",
                tok,
                re.IGNORECASE,
            )
            if fused:
                v = _parse_number(fused.group(1))
                if v is not None:
                    hourly_rate = v
                    found_hourly_rate = True
                i += 1
                continue

            # Multi-token: [₹|rs] <num> [rupaye] [per|/|प्रति] <time_unit>
            num_val = _parse_number(tok.lstrip("₹"))
            if num_val is None and _CURRENCY_PREFIX.match(tok) and i + 1 < n:
                num_val = _parse_number(tokens[i + 1])
                if num_val is not None:
                    i += 1  # skip the currency prefix, tok is now the number
                    tok = tokens[i].rstrip(".,:;!।")
            if num_val is not None and not found_hourly_rate:
                j = i + 1
                # Skip optional currency-word token (rupaye, rs, etc.)
                if j < n and _HINDI_RATE.match(tokens[j].rstrip(".,:;!।")):
                    j += 1
                # Expect separator
                if j < n and _RATE_SEP.match(tokens[j].rstrip(".,:;!।")):
                    j += 1
                    # Expect time unit
                    if j < n and _HOUR_UNIT.match(tokens[j].rstrip(".,:;!।")):
                        hourly_rate = num_val
                        found_hourly_rate = True
                        i = j + 1
                        continue

        # ----------------------------------------------------------------
        # 2. Days detection: <number> <day_unit>
        # ----------------------------------------------------------------
        if not found_hours:
            num_val = _parse_number(tok)
            next_tok = tokens[i + 1].rstrip(".,:;!।") if i + 1 < n else ""
            if num_val is not None and next_tok and _DAY_UNIT.match(next_tok):
                labor_hours = num_val * 8.0
                found_hours = True
                i += 2
                continue

            # Hours detection: <number> <hour_unit>
            if num_val is not None and next_tok and _HOUR_UNIT.match(next_tok):
                labor_hours = num_val
                found_hours = True
                i += 2
                continue

        # ----------------------------------------------------------------
        # 3. Materials detection
        # ----------------------------------------------------------------
        if not found_materials:
            # 3a. Contextual keyword phrase followed by optional separators then number
            #     e.g. "making cost is ₹450", "लागत: 500", "base cost = 300"
            if _COST_KEYWORD.match(tok):
                j = i + 1
                # Skip additional keyword and separator tokens (up to 5 lookahead)
                lookahead = 0
                while j < n and lookahead < 5:
                    t = tokens[j]
                    if _COST_KEYWORD.match(t) or _KW_SEP.match(t) or _CURRENCY_PREFIX.match(t):
                        j += 1
                        lookahead += 1
                    else:
                        break
                # Now expect a number token — strip leading ₹/currency prefix if fused (e.g. "₹450")
                if j < n:
                    candidate = tokens[j].lstrip("₹")
                    if not candidate:  # token was just "₹", number is next
                        j += 1
                        candidate = tokens[j] if j < n else ""
                    v = _parse_number(candidate)
                    if v is not None:
                        materials = v
                        found_materials = True
                        i = j + 1
                        continue

            # 3b. Fused ₹<num> token (e.g. "₹500") or standalone currency prefix (e.g. "₹", "Rs")
            stripped = tok.lstrip("₹")
            if stripped and stripped != tok and _parse_number(stripped) is not None:
                # Fused: ₹500 — treat as materials if not followed by rate separator
                v = _parse_number(stripped)
                j = i + 1
                if j >= n or not _RATE_SEP.match(tokens[j]):
                    materials = v
                    found_materials = True
                    i += 1
                    continue
            elif _CURRENCY_PREFIX.match(tok) and i + 1 < n:
                # Standalone prefix: Rs 400
                v = _parse_number(tokens[i + 1])
                if v is not None and not found_materials:
                    j = i + 2
                    if j >= n or not _RATE_SEP.match(tokens[j]):
                        materials = v
                        found_materials = True
                        i += 2
                        continue

            # 3c. Number followed by currency suffix: "400 rupees", "450.50 रुपये"
            num_val = _parse_number(tok)
            if num_val is not None and i + 1 < n and _CURRENCY_SUFFIX.match(tokens[i + 1]):
                # Ensure NOT followed by rate separator (not a per-hour amount)
                j = i + 2
                if j >= n or not _RATE_SEP.match(tokens[j]):
                    if not found_materials:
                        materials = num_val
                        found_materials = True
                        i += 2
                        continue

        i += 1

    effective_rate = hourly_rate if hourly_rate > 0 else DEFAULT_HOURLY_RATE
    floor = materials + (labor_hours * effective_rate)

    return {
        "materials": materials,
        "labor_hours": labor_hours,
        "hourly_rate": effective_rate,
        "transport": 0.0,
        "overhead": 0.0,
        "cost_floor": floor,
    }
