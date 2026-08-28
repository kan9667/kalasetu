"""
Storage Service.

Handles saving and retrieving uploaded images and audio files.
"""

import os
import uuid
import aiofiles
from pathlib import Path
from fastapi import UploadFile

from ..config import get_settings, ensure_upload_dir

settings = get_settings()


class StorageService:
    """Manages file storage in backend/uploads directory."""

    def __init__(self):
        self.upload_dir = ensure_upload_dir()

    async def save_upload(self, file: UploadFile, subfolder: str = "images") -> str:
        """
        Save an uploaded file and return its accessible relative path / URL.

        Args:
            file: FastAPI UploadFile object
            subfolder: Subfolder within uploads (images, audio, etc.)

        Returns:
            Relative URL (e.g. /uploads/images/xyz.jpg)
        """
        target_dir = self.upload_dir / subfolder
        target_dir.mkdir(parents=True, exist_ok=True)

        ext = Path(file.filename or "file.jpg").suffix.lower()
        if not ext:
            ext = ".jpg"

        filename = f"{uuid.uuid4().hex}{ext}"
        file_path = target_dir / filename

        async with aiofiles.open(file_path, "wb") as out_file:
            content = await file.read()
            await out_file.write(content)

        # Return static mount relative URL
        return f"{settings.static_url_prefix}/{subfolder}/{filename}"

    def get_local_path_from_url(self, url: str) -> Path | None:
        """
        Convert a relative URL (e.g. /uploads/images/abc.jpg) to a local Path.
        """
        if not url:
            return None

        clean_url = url.replace("\\", "/")
        if clean_url.startswith(settings.static_url_prefix):
            rel_path = clean_url[len(settings.static_url_prefix):].lstrip("/")
            local_path = self.upload_dir / rel_path
            if local_path.exists():
                return local_path

        # Check if direct local path exists
        direct_path = Path(url)
        if direct_path.exists():
            return direct_path

        return None
