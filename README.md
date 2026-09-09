<div align="center">

<img width="180" height="279" alt="KalaSetu logo" src="https://github.com/user-attachments/assets/f1a4c9de-6260-4b11-9b0b-9082505c8232" />

# KalaSetu
### कलासेतु — "Bridge of Art"

**AI-driven market linkage & smart cataloging for marginalized Indian artisans**

*Offline-first virtual business manager · Built for Smart India Hackathon 2026 · Problem Statement PS-90*

[![Flutter](https://img.shields.io/badge/Client-Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Groq](https://img.shields.io/badge/Primary%20LLM-Groq%20Cloud-F55036)](https://groq.com)
[![Gemini](https://img.shields.io/badge/Fallback%20LLM-Google%20Gemini-4285F4)](https://ai.google.dev)
[![Offline First](https://img.shields.io/badge/Design-Offline--First-orange)]()
[![SIH 2026](https://img.shields.io/badge/SIH%202026-PS--90-brightgreen)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[Architecture Docs](docs/ARCHITECTURE.md) · [Report an Issue](https://github.com/kan9667/kalasetu/issues)

</div>

---

## What is KalaSetu?

KalaSetu turns a phone photo and a voice note into a professional, fairly-priced, bilingual product listing — no typing, no English, no middlemen. An artisan photographs their product and describes it out loud in their own language; the app removes the background and corrects the lighting, transcribes and translates the description into a structured English + Hindi listing, and suggests a fair price backed by a hard cost floor and live market comparables — reading everything back aloud before anything goes live.

It's built for artisans who already get seasonal exposure at government fairs (Shilp Samagam, Surajkund Mela, Dilli Haat) but have no way to keep selling once the fair ends, because year-round digital commerce demands things most artisans have never had access to: studio-quality photos, English SEO copywriting, and a sense of fair market pricing.

## Key Features

- **AI Image Studio** — a 10-stage computer vision pipeline (rembg background removal, CLAHE lighting correction, auto-crop) turns a cluttered phone photo into an e-commerce-ready 1080×1080 shot.
- **Multilingual Voice Auto-Cataloger** — the artisan speaks in their regional language; Whisper transcribes with craft-vocabulary biasing and an LLM produces a structured English + Hindi listing.
- **Dynamic Pricing Engine** — blends a non-negotiable cost floor (materials + labour + transport) with a ChromaDB RAG index of real handicraft market comparables (Amazon Karigar, FabIndia, Etsy, Okhai), so an AI-suggested price can never undercut the artisan.
- **Offline-First Sync** — Hive + Drift + WorkManager queue photos, voice notes, and product edits locally and drain the queue automatically the moment connectivity returns.
- **Product Catalogue & Inventory** — full CRUD product management with batch offline sync.
- **Social Media Launchpad** — one-tap caption generation for WhatsApp, Instagram, and Facebook, with per-channel prompt templates.
- **KalaMitra AI Chatbot** — a Groq-powered conversational agent that can navigate the app and execute in-app actions on the artisan's behalf.
- **Orders & Packaging Advisory** — AI packaging suggestions plus on-device PDF shipping labels with an ONDC profile QR code.
- **Performance Analytics** — revenue and fair-wage-premium tracking for artisans.
- **On-Device Bilingual TTS** — every screen can be read aloud in English or Hindi for non-literate users, backed by a guided onboarding tutorial.

Every AI decision — image, listing, or price — is reviewed and approved by the artisan before it ever goes live.

## Tech Stack

| Layer | Technology |
|---|---|
| **Mobile client** | Flutter/Dart, Riverpod, GoRouter, Drift (offline queue), Hive (cache/auth), WorkManager (background sync), Dio |
| **Backend API** | FastAPI, SQLAlchemy 2.0 + SQLite, Pydantic v2 |
| **Computer vision** | rembg (U²-Net), OpenCV, Pillow |
| **Speech-to-text** | Whisper Large v3 (via Groq / OpenAI-compatible endpoint) |
| **LLM** | Groq Cloud (primary — KalaMitra chat, cataloging, social captions), Google Gemini (fallback for cataloging/captions; sole engine for pricing reasoning + ChromaDB embeddings) |
| **Vector store** | ChromaDB (pricing RAG over handicraft market benchmarks) |

For the full 5-tier system diagram, per-feature data models, and API contracts, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the project's living technical specification.

## Project Structure

```
kalasetu/
├── backend/          # FastAPI service — auth, catalog, voice, pricing, products, social, chat
│   ├── routers/        # REST endpoints (/api/v1/...)
│   ├── services/       # Business logic (CatalogService, PricingService, ChatService, ...)
│   ├── models/          # SQLAlchemy ORM + Pydantic schemas
│   └── tests/            # pytest integration suites
├── ML/               # Standalone AI/ML pipelines
│   ├── image_pipeline/   # Background removal + enhancement
│   ├── voice_pipeline/   # Transcription + craft-term glossary
│   └── pricing/           # Cost floor + embeddings + ChromaDB RAG
├── frontend/         # Flutter mobile client
│   └── lib/
│       ├── core/           # Config, offline sync engine, router, theme, TTS
│       ├── data/            # Models, repositories, API services
│       └── features/      # Screens by feature (auth, add_product, catalogue, chatbot, orders, ...)
└── docs/             # Architecture spec & product notes
```

## Getting Started

### Prerequisites

- Python 3.11+
- Flutter 3.x / Dart 3.12+ ([install guide](https://docs.flutter.dev/get-started/install))
- A [Groq Cloud](https://console.groq.com) API key and a [Google Gemini](https://ai.google.dev) API key
- Android Studio / Xcode (or a physical device) to run the Flutter client

### 1. Clone the repo

```bash
git clone https://github.com/kan9667/kalasetu.git
cd kalasetu
```

### 2. Backend setup

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate

pip install -r backend/requirements.txt

cp .env.example .env             # then fill in GEMINI_API_KEY and GROQ_API_KEY

uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

The API is now live — interactive Swagger docs at `http://localhost:8000/docs`, health check at:

```bash
curl http://localhost:8000/api/v1/health
```

### 3. Frontend setup

```bash
cd frontend
flutter pub get
flutter run
```

By default the app auto-discovers the backend on your LAN. To point at a specific host, or to run the UI with no backend at all, use:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.X:8000
flutter run --dart-define=MOCK_AI_BACKEND=true   # fakes AI responses, no backend needed
```

## Configuration

Required environment variables (set in `.env`, copied from [`.env.example`](.env.example)):

| Variable | Purpose |
|---|---|
| `GROQ_API_KEY` | Primary LLM for KalaMitra chat, cataloging, and social captions |
| `GEMINI_API_KEY` | Fallback for cataloging/captions if Groq fails; sole engine for pricing (embeddings + price reasoning) |
| `WHISPER_API_KEY` | Speech-to-text (can reuse `GROQ_API_KEY` if using Groq's Whisper endpoint) |

At least one of `GROQ_API_KEY` / `WHISPER_API_KEY` must be set. See [§24 of the architecture doc](docs/ARCHITECTURE.md#24-environment-variables--configuration) for the full list, including optional overrides and Flutter build flags.

## Running Tests

```bash
# Backend (from repo root)
pip install pytest
pytest backend/tests/

# Frontend
cd frontend
flutter test
```

## Roadmap

The core capture → catalog → price → list loop works end-to-end. Known gaps, tracked in [§26 of the architecture doc](docs/ARCHITECTURE.md#26-known-gaps-mocked-components--future-roadmap):

- Orders are currently in-memory mock data — no backend table or endpoint yet
- NGO coordinator sign-in has no server-side credential verification
- No Alembic migrations yet — schema changes need manual SQL
- Media is stored on the local filesystem, not object storage
- SMS OTP is a hardcoded demo value (no SMS gateway integrated)

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — full system architecture, per-feature specs, data models, and API contracts
- Interactive API reference — `/docs` (Swagger) and `/redoc` on a running backend instance

## Getting Help

Run into an issue or have a question? [Open a GitHub issue](https://github.com/kan9667/kalasetu/issues) describing what you were doing and what you expected to happen. For "why does X work this way" questions, check [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) first — most design decisions are documented there.

## Team & Contributing

KalaSetu is built by a 6-person team for Smart India Hackathon 2026, Problem Statement PS-90:

- [**Aanya Varshney**](https://github.com/aanyavarshneyav) — frontend UI
- [**Rudraksh Saini**](https://github.com/Rudrakssh) — offline pipeline
- [**Dhruv Makkar**](https://github.com/dhruvsded1) — image enhancement ML pipeline
- [**Triman Singh Chadha**](https://github.com/Triman01) — voice pipeline
- [**Aadi Jain**](https://github.com/DeltaData0) — pricing pipeline & backend
- [**Kanishka Pandey**](https://github.com/kan9667)— integration & backend

Contributions happen via feature branches and pull requests into `main` — for a change of any size, please open an issue first to discuss the approach.

## License

Licensed under the [MIT License](LICENSE).

---

<div align="center">
<sub>Digitizing what the government already helped artisans build — without taking a cut of their livelihood to do it.</sub>
</div>
