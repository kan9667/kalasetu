web: PYTHONPATH=. alembic -c backend/alembic.ini upgrade head && python -m uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-8000}
