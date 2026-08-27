"""
Vector Store — ChromaDB wrapper for benchmark product embeddings.

Provides add/query operations over the benchmark product collection
using cosine similarity search.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

import chromadb
from chromadb.config import Settings as ChromaSettings

from ..config import get_settings
from ..models import BenchmarkProduct, SimilarProduct

logger = logging.getLogger(__name__)


class VectorStore:
    """
    ChromaDB-backed vector store for benchmark product embeddings.

    Uses persistent local storage so the index survives restarts.
    Cosine similarity is the default distance metric.
    """

    def __init__(self):
        settings = get_settings()
        db_path = settings.chromadb_path

        # Ensure the directory exists
        Path(db_path).mkdir(parents=True, exist_ok=True)

        self.client = chromadb.PersistentClient(
            path=db_path,
            settings=ChromaSettings(anonymized_telemetry=False),
        )
        self.collection = self.client.get_or_create_collection(
            name=settings.chromadb_collection,
            metadata={"hnsw:space": "cosine"},  # Cosine similarity
        )

        logger.info(
            "VectorStore initialized: %s (%d items)",
            db_path,
            self.collection.count(),
        )

    def add_products(
        self,
        products: list[BenchmarkProduct],
        vectors: list[list[float]],
    ) -> int:
        """
        Upsert benchmark products with their embedding vectors.

        Args:
            products: List of benchmark products to index.
            vectors: Corresponding embedding vectors (same order).

        Returns:
            Number of products successfully indexed.
        """
        if len(products) != len(vectors):
            raise ValueError(
                f"Products ({len(products)}) and vectors ({len(vectors)}) "
                f"count mismatch"
            )

        if not products:
            return 0

        # Prepare batch data for ChromaDB
        ids = [p.id for p in products]
        documents = [p.embedding_text() for p in products]
        metadatas = [
            {
                "title": p.title,
                "description": p.description[:500] if p.description else "",
                "category": p.category,
                "selling_price": p.selling_price,
                "source_platform": p.source_platform.value,
                "product_url": p.product_url or "",
                "image_url": p.image_url,
            }
            for p in products
        ]

        # ChromaDB has a batch size limit; process in chunks
        batch_size = 100
        total_added = 0

        for i in range(0, len(ids), batch_size):
            batch_end = min(i + batch_size, len(ids))
            try:
                self.collection.upsert(
                    ids=ids[i:batch_end],
                    embeddings=vectors[i:batch_end],
                    documents=documents[i:batch_end],
                    metadatas=metadatas[i:batch_end],
                )
                total_added += batch_end - i
                logger.info(
                    "Indexed batch %d–%d (%d items)",
                    i,
                    batch_end - 1,
                    batch_end - i,
                )
            except Exception as e:
                logger.error("Failed to index batch %d–%d: %s", i, batch_end - 1, e)

        logger.info(
            "VectorStore now contains %d items (added %d)",
            self.collection.count(),
            total_added,
        )
        return total_added

    def query_similar(
        self,
        query_vector: list[float],
        top_k: int = 5,
        category_filter: Optional[str] = None,
    ) -> list[SimilarProduct]:
        """
        Find the most similar benchmark products using cosine similarity.

        Args:
            query_vector: The query embedding vector (from artisan's product).
            top_k: Number of results to return.
            category_filter: Optional category to restrict search to.

        Returns:
            List of SimilarProduct instances sorted by similarity (highest first).
        """
        where_filter = None
        if category_filter:
            where_filter = {"category": category_filter}

        try:
            results = self.collection.query(
                query_embeddings=[query_vector],
                n_results=top_k,
                where=where_filter,
                include=["metadatas", "distances", "documents"],
            )
        except Exception as e:
            logger.error("Vector query failed: %s", e)
            return []

        # Parse results
        similar_products: list[SimilarProduct] = []

        if not results["ids"] or not results["ids"][0]:
            logger.info("No similar products found")
            return []

        for i, product_id in enumerate(results["ids"][0]):
            metadata = results["metadatas"][0][i]
            # ChromaDB returns distances; for cosine, distance = 1 - similarity
            distance = results["distances"][0][i]
            similarity = 1.0 - distance

            similar_products.append(
                SimilarProduct(
                    id=product_id,
                    title=metadata.get("title", ""),
                    description=metadata.get("description", ""),
                    category=metadata.get("category", ""),
                    selling_price=float(metadata.get("selling_price", 0)),
                    source_platform=metadata.get("source_platform", ""),
                    similarity_score=round(max(0.0, similarity), 4),
                    product_url=metadata.get("product_url"),
                )
            )

        logger.info(
            "Found %d similar products (top similarity: %.4f)",
            len(similar_products),
            similar_products[0].similarity_score if similar_products else 0,
        )
        return similar_products

    def get_count(self) -> int:
        """Return the number of items in the collection."""
        return self.collection.count()

    def clear(self) -> None:
        """Delete all items from the collection."""
        settings = get_settings()
        self.client.delete_collection(settings.chromadb_collection)
        self.collection = self.client.get_or_create_collection(
            name=settings.chromadb_collection,
            metadata={"hnsw:space": "cosine"},
        )
        logger.info("VectorStore cleared")
