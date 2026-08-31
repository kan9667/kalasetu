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


# ── Aggregate ────────────────────────────────────────────────────────────────

ALL_TERMS: list[str] = (
    TEXTILE_TERMS
    + POTTERY_TERMS
    + METAL_TERMS
    + PAINTING_TERMS
    + WOOD_BAMBOO_TERMS
    + MATERIAL_TERMS
)


def get_glossary_terms(category: str | None = None, limit: int = 40) -> list[str]:
    """
    Return craft terms to inject into a transcription prompt.

    Args:
        category: Optional category hint. When supplied, terms from the matching
                  domain are returned first so the most relevant vocabulary
                  survives the limit.
        limit: Maximum number of terms to return.

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
        ordered = ALL_TERMS

    # Preserve order while removing duplicates
    seen: set[str] = set()
    unique = [t for t in ordered if not (t in seen or seen.add(t))]
    return unique[:limit]


def build_prompt_hint(category: str | None = None, limit: int = 40) -> str:
    """Format the glossary as a sentence suitable for a transcription prompt."""
    terms = get_glossary_terms(category=category, limit=limit)
    return (
        "The speaker may use Indian handicraft terminology. "
        "Transcribe these terms accurately if heard: " + ", ".join(terms) + "."
    )
