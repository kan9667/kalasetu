"""
Seed Data Generator.

Generates realistic benchmark product data as a fallback when live scraping
fails or is blocked. This ensures the pipeline always has data to work with
for embedding and pricing.

Uses curated artisan product data spanning the major handicraft categories
found across Indian e-commerce platforms.
"""

from __future__ import annotations

import logging
import random
from datetime import datetime, timedelta

from ..models import BenchmarkProduct, SourcePlatform
from .base_scraper import generate_product_id

logger = logging.getLogger(__name__)


# ── Curated Seed Catalog ────────────────────────────────────────────────────
# Each entry: (title, description, category, price_low, price_high, image_keyword)

SEED_CATALOG: list[tuple[str, str, str, float, float, str]] = [
    # ── Pottery ──────────────────────────────────────────────────────────
    (
        "Khurja Blue Pottery Vase – Hand-Painted Floral Design",
        "Traditional Khurja blue pottery vase with hand-painted floral motifs. Made from quartz stone powder, not clay. Lead-free glaze, food-safe.",
        "pottery", 450, 1200, "blue_pottery_vase",
    ),
    (
        "Terracotta Table Lamp – Warli Art",
        "Handcrafted terracotta lamp with Warli tribal art painted by artisans from Maharashtra. Uses natural earth pigments.",
        "pottery", 600, 1500, "terracotta_lamp",
    ),
    (
        "Black Pottery Serving Bowl – Nizamabad Craft",
        "Traditional Nizamabad black pottery bowl with silver inlay work. Perfect for serving dry snacks or as a decorative piece.",
        "pottery", 350, 900, "black_pottery_bowl",
    ),
    (
        "Jaipur Blue Pottery Wall Plate – Peacock Motif",
        "Decorative blue pottery wall plate featuring traditional peacock design. Hand-glazed with Turkish blue and white patterns.",
        "pottery", 500, 1800, "blue_pottery_plate",
    ),
    (
        "Terracotta Planter Set – Hand-Painted Madhubani",
        "Set of 3 terracotta planters with hand-painted Madhubani art from Bihar. Weather-resistant finish.",
        "pottery", 800, 2200, "terracotta_planter",
    ),
    (
        "Longpi Black Stone Pottery Cooking Pot",
        "Traditional Longpi pottery from Manipur made from serpentinite stone and special clay. Chemical-free cooking, retains heat.",
        "pottery", 900, 2500, "longpi_pot",
    ),

    # ── Textiles ─────────────────────────────────────────────────────────
    (
        "Banarasi Silk Saree – Handwoven Zari Work",
        "Pure Banarasi silk saree with intricate gold zari weaving. Traditional kadwa technique by master weavers of Varanasi.",
        "textiles", 8000, 35000, "banarasi_saree",
    ),
    (
        "Kalamkari Cotton Dupatta – Hand Block Printed",
        "Organic cotton dupatta with traditional Kalamkari hand-painted motifs from Srikalahasti, Andhra Pradesh. Natural vegetable dyes.",
        "textiles", 600, 2000, "kalamkari_dupatta",
    ),
    (
        "Pashmina Shawl – Hand Embroidered Kashmir",
        "Pure pashmina shawl with hand embroidered sozni work from Kashmir. Ultra-soft, lightweight, and warm.",
        "textiles", 5000, 25000, "pashmina_shawl",
    ),
    (
        "Ikat Cotton Fabric – Pochampally Weave",
        "Handwoven Pochampally Ikat cotton fabric in geometric patterns. Double-ikat technique from Telangana.",
        "textiles", 400, 1200, "ikat_fabric",
    ),
    (
        "Chikankari Kurti – Lucknowi Hand Embroidery",
        "Pure cotton kurti with delicate Chikankari embroidery from Lucknow. Shadow work and phanda stitch detailing.",
        "textiles", 1200, 4500, "chikankari_kurti",
    ),
    (
        "Ajrakh Block Print Stole – Kutch Gujarat",
        "Natural dyed Ajrakh print stole from Kutch. Traditional resist-printing technique using indigo and alizarin on cotton.",
        "textiles", 500, 1800, "ajrakh_stole",
    ),
    (
        "Chanderi Silk Cotton Saree – Handloom",
        "Handloom Chanderi silk-cotton saree from Madhya Pradesh. Sheer texture with zari border and traditional motifs.",
        "textiles", 3500, 12000, "chanderi_saree",
    ),
    (
        "Khadi Cotton Handwoven Scarf – Gandhi Ashram",
        "Hand-spun and handwoven khadi cotton scarf. Naturally breathable and eco-friendly fabric.",
        "textiles", 300, 900, "khadi_scarf",
    ),
    (
        "Patola Double Ikat Saree – Patan Gujarat",
        "Authentic Patola silk saree from Patan with double ikat weaving. Each saree takes 4-6 months to weave.",
        "textiles", 15000, 80000, "patola_saree",
    ),
    (
        "Kantha Embroidered Bedcover – Bengal",
        "Hand-stitched Kantha embroidered bedcover from West Bengal. Running stitch on recycled cotton layers.",
        "textiles", 2000, 6000, "kantha_bedcover",
    ),

    # ── Jewelry ──────────────────────────────────────────────────────────
    (
        "Kundan Necklace Set – Rajasthani Handcrafted",
        "Traditional Kundan necklace with earrings set. Handcrafted in Jaipur using refined gold polishing and glass stone setting.",
        "jewelry", 2500, 8000, "kundan_necklace",
    ),
    (
        "Silver Filigree Earrings – Cuttack Odisha",
        "Pure silver filigree (tarakasi) earrings handcrafted in Cuttack. Delicate wire-work jhumka design.",
        "jewelry", 800, 3500, "filigree_earrings",
    ),
    (
        "Dokra Brass Necklace – Tribal Bastar Design",
        "Lost-wax cast (Dokra) brass necklace from Bastar, Chhattisgarh. Ancient tribal metalwork technique.",
        "jewelry", 600, 2500, "dokra_necklace",
    ),
    (
        "Temple Jewelry Set – South Indian Gold Plated",
        "Gold-plated temple jewelry set with traditional Lakshmi motif. Handcrafted in Nagercoil, Tamil Nadu.",
        "jewelry", 3000, 10000, "temple_jewelry",
    ),
    (
        "Lac Bangles Set – Rajasthani Handmade",
        "Set of 6 lac bangles with mirror work and stone inlay. Handmade by artisans in Jaipur.",
        "jewelry", 200, 800, "lac_bangles",
    ),
    (
        "Bidri Silver Inlay Cufflinks – Bidar Karnataka",
        "Bidri ware cufflinks with pure silver inlay on zinc-copper alloy. Traditional Bidar craft dating to 14th century.",
        "jewelry", 1200, 4000, "bidri_cufflinks",
    ),

    # ── Woodwork ─────────────────────────────────────────────────────────
    (
        "Sandalwood Carved Elephant – Mysore Craft",
        "Hand-carved sandalwood elephant figurine from Mysore. Intricate detailing with natural sandalwood fragrance.",
        "woodwork", 2000, 8000, "sandalwood_elephant",
    ),
    (
        "Sheesham Wood Jewelry Box – Saharanpur Carved",
        "Hand-carved sheesham wood jewelry box from Saharanpur, UP. Jali (lattice) work with brass inlay.",
        "woodwork", 800, 3000, "sheesham_box",
    ),
    (
        "Walnut Wood Trinket Box – Kashmiri Carving",
        "Hand-carved walnut wood trinket box from Kashmir. Traditional chinar leaf motif with fine detailing.",
        "woodwork", 1200, 5000, "walnut_box",
    ),
    (
        "Channapatna Lacquerware Toy Set",
        "Set of 5 traditional Channapatna turned-wood toys. Non-toxic vegetable dyes, GI-tagged craft from Karnataka.",
        "woodwork", 400, 1200, "channapatna_toys",
    ),
    (
        "Rosewood Inlay Serving Tray – Mysore",
        "Rosewood serving tray with ivory-wood and sandalwood inlay work. Handcrafted by artisans near Mysore.",
        "woodwork", 1500, 5000, "rosewood_tray",
    ),

    # ── Handloom Saree ───────────────────────────────────────────────────
    (
        "Kanchipuram Silk Saree – Temple Border",
        "Pure mulberry silk Kanchipuram saree with gold zari temple border. Handwoven in Kanchipuram, Tamil Nadu.",
        "handloom saree", 8000, 40000, "kanchipuram_saree",
    ),
    (
        "Jamdani Muslin Saree – Bengal Handloom",
        "Fine muslin Jamdani saree with supplementary weft technique. UNESCO-recognized intangible heritage craft from Bangladesh/Bengal.",
        "handloom saree", 4000, 15000, "jamdani_saree",
    ),
    (
        "Sambalpuri Ikat Saree – Odisha Handloom",
        "Traditional Sambalpuri silk ikat saree from Odisha. Tie-dye technique on warp and weft threads before weaving.",
        "handloom saree", 3000, 12000, "sambalpuri_saree",
    ),
    (
        "Tant Cotton Saree – Bengal Handloom",
        "Lightweight tant cotton saree from Shantipur, West Bengal. Perfect for daily wear with traditional border design.",
        "handloom saree", 800, 3000, "tant_saree",
    ),

    # ── Block Print ──────────────────────────────────────────────────────
    (
        "Sanganeri Block Print Cotton Bedsheet",
        "Hand block printed cotton bedsheet from Sanganer, Jaipur. Traditional floral jaal print with natural dyes.",
        "block print", 600, 2500, "sanganeri_bedsheet",
    ),
    (
        "Bagru Print Table Runner – Natural Dye",
        "Hand block printed table runner using traditional Bagru technique. Dabu mud-resist printing with natural dyes.",
        "block print", 400, 1200, "bagru_runner",
    ),
    (
        "Bagh Print Silk Dupatta – MP Handcraft",
        "Bagh print silk dupatta from Dhar district, MP. Geometric patterns using vegetable dyes and hand-carved teak blocks.",
        "block print", 800, 3000, "bagh_dupatta",
    ),

    # ── Brass Handicraft ─────────────────────────────────────────────────
    (
        "Dhokra Brass Horse – Tribal Lost-Wax Casting",
        "Dhokra (lost-wax) cast brass horse figurine. Traditional tribal craft from Bastar, Chhattisgarh.",
        "brass handicraft", 800, 3500, "dhokra_horse",
    ),
    (
        "Moradabad Brass Flower Vase – Etched Design",
        "Hand-etched brass flower vase from Moradabad, UP. Traditional Mughal-inspired floral engraving.",
        "brass handicraft", 600, 2500, "moradabad_vase",
    ),
    (
        "Thanjavur Art Plate – Gold Plated Brass",
        "Traditional Thanjavur art plate with repousse work. Gold and silver plated brass with raised motifs.",
        "brass handicraft", 1500, 6000, "thanjavur_plate",
    ),

    # ── Jute Craft ───────────────────────────────────────────────────────
    (
        "Jute Macrame Wall Hanging – Handknotted",
        "Handknotted jute macrame wall hanging with bohemian design. Made by women artisans in West Bengal.",
        "jute craft", 400, 1500, "jute_macrame",
    ),
    (
        "Jute Shopping Bag – Block Printed",
        "Eco-friendly jute shopping bag with Madhubani-style block print. Reinforced cotton handles.",
        "jute craft", 150, 500, "jute_bag",
    ),
    (
        "Sabai Grass Basket – Odisha Tribal Craft",
        "Handwoven sabai grass basket from Odisha tribal artisans. Natural golden color with geometric patterns.",
        "jute craft", 300, 1200, "sabai_basket",
    ),

    # ── Leather Craft ────────────────────────────────────────────────────
    (
        "Shantiniketan Leather Bag – Batik Design",
        "Vegetable-tanned leather bag with hand-painted batik design from Shantiniketan, West Bengal.",
        "leather craft", 1200, 4000, "shantiniketan_bag",
    ),
    (
        "Jodhpuri Mojari – Hand Embroidered Leather",
        "Traditional Jodhpuri mojari shoes with hand embroidery on camel leather. Artisan-made in Rajasthan.",
        "leather craft", 600, 2500, "mojari_shoes",
    ),
    (
        "Kolhapuri Chappal – Genuine Leather Handmade",
        "Authentic Kolhapuri leather chappal handcrafted in Maharashtra. Vegetable-tanned with traditional design.",
        "leather craft", 500, 2000, "kolhapuri_chappal",
    ),

    # ── Bamboo Craft ─────────────────────────────────────────────────────
    (
        "Bamboo Pendant Lamp – Northeast India",
        "Handwoven bamboo pendant lamp from Assam. Traditional cane and bamboo weaving technique.",
        "bamboo craft", 800, 3000, "bamboo_lamp",
    ),
    (
        "Bamboo Tea Tray Set – Tripura Craft",
        "Bamboo tea serving tray with 4 coasters. Handcrafted by tribal artisans of Tripura.",
        "bamboo craft", 400, 1200, "bamboo_tray",
    ),
    (
        "Cane Storage Basket – Meghalaya Handwoven",
        "Handwoven cane storage basket from Meghalaya. Traditional Khasi tribal design, sturdy and eco-friendly.",
        "bamboo craft", 500, 1800, "cane_basket",
    ),
]

# Placeholder image URLs (using placeholder services for seed data)
PLACEHOLDER_IMAGE_BASE = "https://placehold.co/600x600/e8d5b7/8b6914?text="


class SeedDataGenerator:
    """
    Generates realistic benchmark product data from a curated catalog
    of Indian handicraft products.

    Used as a fallback when live scraping fails or is blocked, ensuring
    the pipeline always has data for embedding and price comparison.
    """

    def __init__(self, categories: list[str] | None = None):
        self.categories = categories

    def generate(self, max_products: int = 500) -> list[BenchmarkProduct]:
        """
        Generate benchmark products from the seed catalog.

        Each seed entry is expanded into multiple variants with randomized
        prices within the specified range to simulate market diversity.
        """
        products: list[BenchmarkProduct] = []
        seen_ids: set[str] = set()

        # Filter catalog by requested categories if specified
        catalog = SEED_CATALOG
        if self.categories:
            catalog = [
                entry
                for entry in SEED_CATALOG
                if entry[2] in self.categories
            ]

        logger.info(
            "Generating seed data: %d templates, max %d products",
            len(catalog),
            max_products,
        )

        # Generate multiple price variants per template
        variants_per_item = max(1, max_products // max(len(catalog), 1))

        for title, description, category, price_low, price_high, img_keyword in catalog:
            if len(products) >= max_products:
                break

            for variant_idx in range(variants_per_item):
                if len(products) >= max_products:
                    break

                # Randomize price within range
                price = round(random.uniform(price_low, price_high), 0)

                # Create variant title
                variant_title = title
                if variant_idx > 0:
                    suffixes = [
                        "– Premium Quality",
                        "– Artisan Collection",
                        "– Limited Edition",
                        "– Traditional Design",
                        "– Festival Special",
                        "– Heritage Craft",
                        "– Master Artisan Series",
                        "– Classic",
                        "– Contemporary Design",
                        "– Handpicked",
                    ]
                    variant_title = (
                        f"{title.split('–')[0].strip()} "
                        f"{random.choice(suffixes)}"
                    )

                image_url = f"{PLACEHOLDER_IMAGE_BASE}{img_keyword}"
                product_id = generate_product_id(image_url, variant_title)

                if product_id in seen_ids:
                    continue
                seen_ids.add(product_id)

                # Randomize scraped_at to simulate data collected over time
                days_ago = random.randint(0, 30)
                scraped_time = datetime.now() - timedelta(days=days_ago)

                # Assign to a random source platform for realism
                platform = random.choice([
                    SourcePlatform.AMAZON_KARIGAR,
                    SourcePlatform.FABINDIA,
                    SourcePlatform.ETSY_INDIA,
                    SourcePlatform.OKHAI,
                ])

                products.append(
                    BenchmarkProduct(
                        id=product_id,
                        image_url=image_url,
                        title=variant_title,
                        description=description,
                        category=category,
                        selling_price=price,
                        source_platform=platform,
                        product_url=f"https://example.com/product/{product_id}",
                        scraped_at=scraped_time,
                    )
                )

        logger.info("Seed data generator produced %d products", len(products))
        return products
