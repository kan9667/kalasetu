"""
Database Configuration and Session Management.

Uses SQLite with SQLAlchemy 2.0. Initializes tables and seeds default products.
"""

import json
from datetime import datetime
from typing import Generator
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker, Session

from .config import get_settings

settings = get_settings()

# Connect SQLite engine
engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False} if "sqlite" in settings.database_url else {},
    echo=settings.debug,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db() -> Generator[Session, None, None]:
    """FastAPI Dependency for database sessions."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """Create all tables and insert initial demo products if empty."""
    from .models.db_models import ProductDB

    Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    try:
        count = db.query(ProductDB).count()
        if count == 0:
            demo_products = [
                ProductDB(
                    id="prod_1",
                    title="Handcrafted Terracotta Chai Kulhad (Set of 6)",
                    title_hi="हस्तनिर्मित मिट्टी के चाय कुल्हड़ (6 का सेट)",
                    description="Pure natural clay tea cups made on traditional potter's wheel, wood-fired for authentic earthy aroma. 100% biodegradable and chemical-free.",
                    description_hi="पारंपरिक चाक पर शुद्ध प्राकृतिक मिट्टी से बने चाय के कुल्हड़, लकड़ी की भट्टी में पके हुए। पूर्णतः जैविक व रसायन मुक्त।",
                    price=450.0,
                    image_url="https://images.unsplash.com/photo-1578749556568-bc2c40e68b61?auto=format&fit=crop&w=600&q=80",
                    category="Pottery",
                    tags=json.dumps(["terracotta", "eco-friendly", "pottery", "kitchenware"]),
                    status="live",
                    created_at=datetime.now(),
                ),
                ProductDB(
                    id="prod_2",
                    title="Hand-woven Chanderi Silk Cotton Dupatta",
                    title_hi="हाथ से बुना चंदेरी सिल्क कॉटन दुपट्टा",
                    description="Lightweight handloom dupatta with traditional zari border, crafted by master weavers using natural vegetable dyes.",
                    description_hi="पारंपरिक ज़री बॉर्डर और प्राकृतिक वनस्पति रंगों से तैयार हल्का हथकरघा दुपट्टा।",
                    price=1850.0,
                    image_url="https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=600&q=80",
                    category="Textiles",
                    tags=json.dumps(["handloom", "chanderi", "silk", "traditional"]),
                    status="live",
                    created_at=datetime.now(),
                ),
                ProductDB(
                    id="prod_3",
                    title="Carved Sheesham Wood Elephant Figurine with Brass Inlay",
                    title_hi="पीतल की नक्काशी के साथ शीशम की लकड़ी की हस्तनिर्मित हाथी की मूर्ति",
                    description="Intricately hand-carved decorative elephant crafted from seasoned Indian rosewood (Sheesham), detailed with fine hand-embedded floral brass inlays.",
                    description_hi="अनुभवी शीशम की लकड़ी से तराशी गई सुंदर हाथी की सजावटी मूर्ति, जिसमें बारीक पीतल की नक्काशी का काम किया गया है।",
                    price=1250.0,
                    image_url="https://images.unsplash.com/photo-1601924994987-69e26d50dc26?auto=format&fit=crop&w=600&q=80",
                    category="Woodwork",
                    tags=json.dumps(["woodwork", "sheesham", "brass-inlay", "handcarved", "home-decor"]),
                    status="live",
                    created_at=datetime.now(),
                ),
            ]
            db.add_all(demo_products)
            db.commit()
    finally:
        db.close()


# Database tables are initialized explicitly in lifespan (main.py)
