"""
Craft Vocabulary Glossary.

Curated Indian handicraft terminology injected into transcription prompts.

General speech models learn from news and broadcast audio, where these words
barely appear, so they get substituted with the nearest common word — "Dhokra"
becomes "doctor", "Chikankari" becomes "chicken curry". Since these terms are
often the product name itself, that failure is expensive.

Passing the vocabulary as a prompt hint measurably reduces the substitution.
"""

from __future__ import annotations


# ── Craft Categories ─────────────────────────────────────────────────────────

CATEGORIES: list[str] = [
    "Pottery",
    "Textiles",
    "Woodwork",
    "Jewelry",
    "Paintings",
    "Bamboo Craft",
    "Brass",
    "Leather",
    "Stone Carving",
    "Metalwork",
]


# ── Craft Terms by Domain ────────────────────────────────────────────────────

TEXTILE_TERMS: list[str] = [
    "Bandhani", "Ajrakh", "Chikankari", "Kalamkari", "Ikat", "Patola",
    "Banarasi", "Chanderi", "Kanjeevaram", "Phulkari", "Kantha", "Sujani",
    "Block print", "Batik", "Zari", "Zardozi", "Pashmina", "Khadi",
    "Handloom", "Tussar", "Muga", "Eri silk",
]

POTTERY_TERMS: list[str] = [
    "Terracotta", "Blue pottery", "Khurja pottery", "Black pottery",
    "Chaak", "Kulhad", "Surahi", "Matka", "Diya", "Glazed earthenware",
]

METAL_TERMS: list[str] = [
    "Dhokra", "Bidriware", "Bell metal", "Brassware", "Thewa",
    "Meenakari", "Filigree", "Kansa", "Repousse",
]

PAINTING_TERMS: list[str] = [
    "Madhubani", "Mithila", "Pattachitra", "Warli", "Gond", "Kalighat",
    "Phad", "Kerala mural", "Tanjore", "Miniature painting", "Cheriyal",
]

WOOD_BAMBOO_TERMS: list[str] = [
    "Channapatna", "Sandalwood carving", "Rosewood inlay", "Sheesham",
    "Bamboo weave", "Cane craft", "Sikki grass", "Screwpine", "Jute craft",
]

MATERIAL_TERMS: list[str] = [
    "Natural dye", "Vegetable dye", "Indigo", "Lac", "Clay", "Riverbed clay",
    "Handspun", "Hand-block printed", "Hand-carved", "Wheel-thrown",
]


# ── Devanagari Terms ─────────────────────────────────────────────────────────

# A Hindi transcript comes back in Devanagari, so Latin-script hints cannot
# match it. These are the same craft vocabulary written the way the recogniser
# will actually output it — without them, "चाक" (potter's wheel) is transcribed
# as "चात".

DEVANAGARI_TERMS: list[str] = [
    # Materials
    "मिट्टी", "टेराकोटा", "पीतल", "कांसा", "चांदी", "लकड़ी", "बांस",
    "जूट", "चमड़ा", "रेशम", "सूती", "ऊन", "पत्थर", "संगमरमर",
    # Techniques
    "चाक", "हस्तनिर्मित", "कढ़ाई", "बुनाई", "नक्काशी", "छपाई",
    "रंगाई", "ढलाई", "जड़ाई", "हथकरघा",
    # Craft names
    "बंधनी", "अजरख", "चिकनकारी", "कलमकारी", "मधुबनी", "वारली",
    "पट्टचित्र", "फुलकारी", "कांथा", "ढोकरा", "मीनाकारी", "जरदोजी",
    # Objects
    "फूलदान", "बर्तन", "सुराही", "कुल्हड़", "दीया", "मूर्ति",
    "साड़ी", "दुपट्टा", "शॉल", "चादर", "थाली",
]


# ── Aggregate ────────────────────────────────────────────────────────────────

ALL_TERMS: list[str] = (
    TEXTILE_TERMS
    + POTTERY_TERMS
    + METAL_TERMS
    + PAINTING_TERMS
    + WOOD_BAMBOO_TERMS
    + MATERIAL_TERMS
)

# Languages whose transcripts come back in Devanagari script
DEVANAGARI_LANGUAGES: frozenset[str] = frozenset({"hi", "mr"})


def get_glossary_terms(
    category: str | None = None,
    limit: int = 40,
    language_code: str | None = None,
) -> list[str]:
    """
    Return craft terms to inject into a transcription prompt.

    Args:
        category: Optional category hint. When supplied, terms from the matching
                  domain are returned first so the most relevant vocabulary
                  survives the limit.
        limit: Maximum number of terms to return.
        language_code: Source language. For languages written in Devanagari the
                       script-matched terms are placed first, since Latin-script
                       hints cannot match a Devanagari transcript.

    Returns:
        List of craft terms, most relevant first.
    """
    domain_map = {
        "textiles": TEXTILE_TERMS,
        "pottery": POTTERY_TERMS,
        "brass": METAL_TERMS,
        "metalwork": METAL_TERMS,
        "jewelry": METAL_TERMS,
        "paintings": PAINTING_TERMS,
        "woodwork": WOOD_BAMBOO_TERMS,
        "bamboo craft": WOOD_BAMBOO_TERMS,
    }

    if category:
        preferred = domain_map.get(category.strip().lower(), [])
        remaining = [t for t in ALL_TERMS if t not in preferred]
        ordered = preferred + MATERIAL_TERMS + remaining
    else:
        ordered = list(ALL_TERMS)

    # The recogniser writes Hindi in Devanagari, so those terms lead for
    # Devanagari-script languages — a Latin hint cannot match a Devanagari word.
    if language_code and language_code in DEVANAGARI_LANGUAGES:
        ordered = DEVANAGARI_TERMS + ordered

    # Preserve order while removing duplicates
    seen: set[str] = set()
    unique = [t for t in ordered if not (t in seen or seen.add(t))]
    return unique[:limit]


def build_prompt_hint(
    category: str | None = None,
    limit: int = 40,
    language_code: str | None = None,
) -> str:
    """
    Format the glossary for a transcription prompt.

    Whisper treats the prompt as *context* — text resembling what it is about
    to hear — not as an instruction. A plain list of expected words biases
    recognition; an English sentence wrapped around them dilutes it. Measured
    on a Hindi sample, the bare list recovered "चाक" where the wrapped version
    did not.
    """
    terms = get_glossary_terms(
        category=category, limit=limit, language_code=language_code
    )
    return ", ".join(terms)
