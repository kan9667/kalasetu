"""
Shared Cost Cue Extraction Utilities.

Provides a unified, deterministic regex extractor and helper functions
for parsing artisan base costs, making expenses, labor hours, and hourly rates
from voice transcripts and text descriptions.
"""

from __future__ import annotations

import re
from typing import Dict, Any

DEFAULT_HOURLY_RATE = 50.0


def regex_extract_cost_cues(text: str) -> Dict[str, float]:
    """
    Deterministically extract cost cues from speech transcripts or description text.
    Handles English, Hinglish, and Hindi (Devanagari) phrases, decimals, currency symbols,
    and sentences with both cost and hours.
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

    clean = text.strip()[:4000]
    materials = 0.0
    labor_hours = 0.0
    hourly_rate = DEFAULT_HOURLY_RATE

    # 1. Hourly rate: e.g. "₹80/hr", "80 per hour", "100 rupaye ghanta", "100 रुपये प्रति घंटा"
    rate_match = re.search(
        r"(?i)(?:₹|rs\.?|inr)?\s*(\d+(?:\.\d+)?)\s*(?:\/|\s*per\s*|\s*रुपये?\s*प्रति\s*|\s*rupees?\s*per\s*|\s*rupaye?\s*(?:per\s*)?)(?:hr|hour|ghante|ghanta|घंटा|घंटे)",
        clean,
    )
    if rate_match:
        try:
            hourly_rate = float(rate_match.group(1))
        except ValueError:
            pass

    # 2. Labor hours / days.
    # Use (?!\.[0-9]|\d) as a non-backtracking boundary instead of (?!\w) on a quantified group,
    # which eliminates the polynomial ReDoS path CodeQL flags on repeated-digit inputs.
    # Days conversion: 1 day = 8 working hours
    days_match = re.search(
        r"(?i)(?<!\d)([0-9]+(?:\.[0-9]+)?)(?!\.[0-9]|[0-9])\s*(?:days?|दिन)(?![a-zA-Z])",
        clean,
    )
    if days_match:
        try:
            labor_hours = float(days_match.group(1)) * 8.0
        except ValueError:
            pass
    else:
        hours_match = re.search(
            r"(?i)(?<!\d)([0-9]+(?:\.[0-9]+)?)(?!\.[0-9]|[0-9])\s*(?:hours?|hrs?|ghante|ghanta|घंटे|घण्टे|घंटा)(?![a-zA-Z])",
            clean,
        )
        if hours_match:
            try:
                labor_hours = float(hours_match.group(1))
            except ValueError:
                pass

    # Strip commas from thousands-separated numbers before materials matching to avoid
    # nested quantifiers (e.g. \d+(?:,\d+)*) that cause polynomial ReDoS on adversarial input.
    clean_no_commas = re.sub(r"(?<=\d),(?=\d)", "", clean)

    # 3. Materials / Base making cost
    # First look for explicit contextual cost phrasing.
    # Uses [0-9]+(?:\.[0-9]+)? (flat, no nested quantifier) after comma-stripping above.
    ctx_match = re.search(
        r"(?i)(?:total\s+)?(?:making\s*cost|cost\s*of\s*making|base\s*cost|raw\s*materials?(?:\s*cost)?|production\s*cost|manufacturing\s*cost|लागत|खर्च)\s*[:=-]?\s*(?:is|was|around|approx|roughly|लगभग)?\s*(?:₹|rs\.?|inr)?\s*([0-9]+(?:\.[0-9]+)?)",
        clean_no_commas,
    )
    if ctx_match:
        try:
            materials = float(ctx_match.group(1))
        except ValueError:
            pass
    else:
        # Currency symbol followed by digits (excluding if immediately followed by /hr)
        cur_match = re.search(r"(?i)(?:₹|rs\.?|inr)\s*([0-9]+(?:\.[0-9]+)?)(?!\s*(?:\/|per|प्रति))", clean_no_commas)
        if cur_match:
            try:
                materials = float(cur_match.group(1))
            except ValueError:
                pass
        else:
            # Digits followed by currency words: e.g. "400 rupees", "400 rs", "450.50 रुपये", "400 rupaye"
            word_match = re.search(
                r"(?i)(?<![0-9])([0-9]+(?:\.[0-9]+)?)\s*(?:rupees?|rs\.?|inr|rupaye?|रुपये|रुपया|रु)(?!\s*(?:\/|per|प्रति))",
                clean_no_commas,
            )
            if word_match:
                try:
                    materials = float(word_match.group(1))
                except ValueError:
                    pass

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
