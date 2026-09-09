<div align="center">

<img width="180" height="279" alt="KalaSetu logo" src="https://github.com/user-attachments/assets/f1a4c9de-6260-4b11-9b0b-9082505c8232" />

# KalaSetu
### कलासेतु — "Causeway of Craft"

**Bridging looms to livelihoods: an offline-first emissary that speaks an artisan's own tongue and safeguards the worth of their hands.**

Built for Smart India Hackathon 2026 · Problem Statement PS-90

[![Flutter](https://img.shields.io/badge/Client-Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Groq](https://img.shields.io/badge/Primary%20LLM-Groq%20Cloud-F55036)](https://groq.com)
[![Gemini](https://img.shields.io/badge/Fallback%20LLM-Google%20Gemini-4285F4)](https://ai.google.dev)
[![Offline First](https://img.shields.io/badge/Design-Offline--First-orange)]()
[![SIH 2026](https://img.shields.io/badge/SIH%202026-PS--90-brightgreen)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[Architecture Specification](docs/architecture.md) · [Submission Guide](SUBMISSION_GUIDE.md) · [Presentation](submission/PRESENTATION.md) · [Demo Video](submission/DEMO.md)

</div>

---

## 1. Project Information

- **Project Title:** KalaSetu (कलासेतु) — Offline-First Multimodal AI Co-Pilot for Indian Artisans
- **PS ID:** PS-90
- **PS Title:** Digital Storefront & Fair-Value Market Access Enablement for Rural Craft Producers
- **Category:** Software
- **Theme:** Heritage & Culture / Smart Automation / Inclusive Technology

---

## 2. Problem Statement

India's traditional handicraft sector sustains over 7 million rural artisans, yet most struggle to bridge the divide into year-round e-commerce:
1. **Seasonal Market Isolation:** Government exhibitions (Shilp Samagam, Surajkund Mela, Dilli Haat) provide brief seasonal visibility that vanishes once fairs conclude.
2. **Literacy & Technical Friction:** Commercial e-commerce catalogs demand professional studio photography, fluent English SEO copy, and typing-heavy admin portals that exclude non-literate artisans.
3. **Exploitative Pricing & Middlemen:** Lacking real-time market awareness, artisans frequently undervalue their craft or sell below cost to predatory intermediaries.
4. **Intermittent Connectivity:** Rural craft clusters suffer from unstable networks where cloud-dependent applications fail entirely.

---

## 3. Proposed Solution

KalaSetu compresses the entire digitization and e-commerce pipeline into **one photograph and one spoken sentence**:
- **Point & Shoot Studio:** An artisan takes a raw photo on any smartphone; a 10-stage computer vision pipeline strips cluttered backgrounds, corrects lighting, and outputs a square 1080×1080 studio asset.
- **Speak in Any Tongue:** The artisan narrates naturally in their regional language; domain-biased Whisper transcribes the voice note and generates a structured bilingual (English + Hindi) listing.
- **Inviolable Fair Price Floor:** The pricing engine calculates a strict non-negotiable cost floor (`Materials + Labor Hours × Fair Wage + Transport + Overhead`) combined with ChromaDB RAG market comparables, mathematically preventing algorithms from undercutting the artisan.
- **Offline-First Resilience:** Local Drift (SQLite) and Hive databases store all photos, audio notes, and drafts on the device, draining to the server automatically the moment connectivity returns.
- **Human in the Loop:** Every output (image, description, pricing) is read aloud via on-device bilingual TTS and requires the artisan's manual approval before going live.

---

## 4. Key Features

- **AI Image Studio:** 10-stage computer vision pipeline (rembg U²-Net, CLAHE illumination correction, auto-crop) turns phone snaps into e-commerce-ready assets.
- **Multilingual Voice Auto-Cataloger:** Artisans describe items in regional dialects; produces high-converting bilingual English + Hindi titles, descriptions, and SEO tags while strictly quarantining confidential cost numbers.
- **Dynamic Fair Pricing Engine:** Dual-layer pricing combining a mathematical cost floor with ChromaDB RAG retrieval over indexed market benchmarks (Amazon Karigar, FabIndia, Etsy, Okhai).
- **Offline-First Sync Engine:** Local Drift + Hive queue drains automatically when network connectivity resumes with exponential backoff.
- **KalaMitra Conversational Assistant:** Groq-powered multi-lingual assistant capable of executing voice actions (inventory filters, order lookups, scheme advisories).
- **Social Media Launchpad:** One-tap generated marketing copy with customized prompt templates for WhatsApp, Instagram, and Facebook.
- **Orders & Packaging Advisory:** Packaging guidance and downloadable PDF shipping labels with ONDC-compatible profile QR codes.
- **Bilingual On-Device TTS:** Complete voice accessibility for non-literate artisans across every screen.

---

## 5. Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| **Mobile Client** | Flutter 3.x, Dart | Cross-platform offline-first mobile app |
| **State Management** | Riverpod 2.x | Reactive, decoupled state propagation |
| **Local Database & Sync** | Drift (SQLite), Hive, WorkManager | Offline queue, persistent storage, background sync |
| **Backend API** | FastAPI, SQLAlchemy 2.0, Pydantic v2 | High-performance asynchronous REST API |
| **Computer Vision** | rembg (U²-Net), OpenCV, Pillow | 10-stage studio background removal & enhancement |
| **Speech-to-Text** | Whisper Large v3 (Groq API) | Regional dialect audio transcription with craft glossary |
| **Large Language Models** | Groq Cloud (primary), Google Gemini (fallback) | Bilingual listing generation, KalaMitra chat, social copy |
| **Vector Store & RAG** | ChromaDB, Google Gemini Embeddings | Market benchmark similarity search for pricing intelligence |
| **Deployment** | Docker, Uvicorn | Production-ready containerized microservices |

---

## 6. Architecture

See [docs/architecture.md](docs/architecture.md) for architecture documentation and [docs/ARCHITECTURE.md](docs/architecture.md) for the 76KB in-depth technical specification.

```text
       Artisan (Smartphone Camera & Microphone)
                         │
                         ▼
        ┌──────────────────────────────────┐
        │     Flutter Client (Frontend)    │
        │  - Offline Cache (Hive & Drift)  │
        │  - Background Queue (WorkManager)│
        │  - Text-To-Speech (Bilingual TTS)│
        └─────────────────┬────────────────┘
                          │ HTTPS REST / Multipart
                          ▼
        ┌──────────────────────────────────┐
        │       FastAPI Gateway (Backend)  │
        │  - Auth & Product Catalog Routes │
        │  - Speech & Vision Orchestration │
        │  - Database (SQLite / Postgres)  │
        └───────┬───────────────┬──────────┘
                │               │
        ┌───────▼───────┐ ┌─────▼─────────────────────────┐
        │  AI Services  │ │  Machine Learning Pipelines   │
        │ - Groq Cloud  │ │ - Computer Vision (U²-Net)    │
        │   (Llama/Gemma│ │ - Speech Pipeline (Whisper v3)│
        │ - Gemini API  │ │ - Pricing Engine (ChromaDB    │
        │   (Fallback)  │ │   RAG + Cost Floor Formula)   │
        └───────────────┘ └───────────────────────────────┘
                          │
                          ▼
                Authoritative Output
       (Studio Photo, Bilingual Listing, Fair Price)
                          │
                          ▼
                 Artisan Approval
```

---

## 7. Repository Structure

```text
KalaSetu/
├── README.md                  # Standardized SIH 15-section project overview
├── SUBMISSION_GUIDE.md        # Evaluator checklist & submission instructions
├── requirements.txt           # Unified backend & ML python dependencies
├── LICENSE                    # MIT Open Source License
├── submission/                # Final presentation & demo video links
│   ├── PRESENTATION.md        # PPT/PPTX link / Google Drive viewer link
│   └── DEMO.md                # Video walkthrough & demonstration agenda
├── docs/                      # Technical documentation & architecture specs
│   ├── architecture.md        # High-level architecture specification
│   ├── Ideas.md               # Product ideation notes
│   └── kalasetu-redesign-v3.html # Interactive UI design mockup
├── assets/                    # Project visuals & branding
│   └── screenshots/           # Prototype walkthrough screenshots
│       └── README.md
├── backend/                   # FastAPI backend service
│   ├── routers/               # REST endpoints (/api/v1/auth, catalog, pricing, chat)
│   ├── services/              # Core business logic & AI orchestration
│   ├── models/                # SQLAlchemy models & Pydantic schemas
│   ├── utils/                 # Shared cost extraction & helper utilities
│   └── tests/                 # Comprehensive pytest integration suites
├── ML/                        # Standalone AI/ML pipelines
│   ├── image_pipeline/        # 10-stage background removal & image enhancement
│   ├── voice_pipeline/        # Whisper transcription & domain glossary
│   └── pricing/               # Cost floor formula & ChromaDB RAG benchmarks
└── frontend/                  # Flutter mobile client
    ├── lib/
    │   ├── core/              # Config, routing, offline sync engine, theme
    │   ├── data/              # Repositories, models, network services
    │   └── features/          # Feature screens (auth, catalog, pricing, chatbot)
    └── assets/                # App logos, craft icons, localizations
```

### What goes where?

| Item | Location |
|---|---|
| Mobile client source code | [`frontend/`](frontend/) |
| Backend API & business logic | [`backend/`](backend/) |
| Machine Learning pipelines | [`ML/`](ML/) |
| Architecture & technical specifications | [`docs/architecture.md`](docs/architecture.md) |
| Submission presentation (PPT/PPTX) | [`submission/PRESENTATION.md`](submission/PRESENTATION.md) |
| Prototype demo video link | [`submission/DEMO.md`](submission/DEMO.md) |
| App screenshots & visual walkthrough | [`assets/screenshots/`](assets/screenshots/) |
| Evaluator compliance checklist | [`SUBMISSION_GUIDE.md`](SUBMISSION_GUIDE.md) |
| Unified Python dependencies | [`requirements.txt`](requirements.txt) |

---

## 8. Final Presentation

Keep your final SIH presentation in the repository whenever file size permits:
- **Presentation Details:** [`submission/PRESENTATION.md`](submission/PRESENTATION.md)
- **Local PPTX:** [`submission/KalaSetu_SIH2026_Presentation.pptx`](submission/)
- **Shareable Viewer Link:** Included in `submission/PRESENTATION.md` if file exceeds GitHub limits.

---

## 9. Demo Video

A video walkthrough demonstrating the working prototype across voice cataloging, studio image processing, fair price calculation, and offline sync:
- **Demo Video Documentation:** [`submission/DEMO.md`](submission/DEMO.md)

---

## 10. Screenshots / Prototype Photos

Visual demonstration of the mobile app workflows:
- **Screenshots Directory:** [`assets/screenshots/`](assets/screenshots/)


---

## 11. Installation

### Prerequisites
- Python 3.11+
- Flutter 3.x / Dart 3.12+ ([Flutter install guide](https://docs.flutter.dev/get-started/install))
- A [Groq Cloud](https://console.groq.com) API Key and [Google Gemini](https://ai.google.dev) API Key
- Android Studio / Xcode or a physical Android/iOS device

### 1. Clone the Repository
```bash
git clone https://github.com/kan9667/kalasetu.git
cd kalasetu
```

### 2. Backend Setup
```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate

# Install unified dependencies from root
pip install -r requirements.txt

# Configure environment variables
cp .env.example .env
# Edit .env and enter your GROQ_API_KEY and GEMINI_API_KEY
```

### 3. Frontend Setup
```bash
cd frontend
flutter pub get
```

---

## 12. Run

### Start Backend API Server
From the project root:
```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```
- Swagger Interactive Documentation: `http://localhost:8000/docs`
- Health Check: `curl http://localhost:8000/api/v1/health`

### Run Mobile Application
```bash
cd frontend
flutter run
```
*Tip: To run with mock AI responses (no active backend required):*
```bash
flutter run --dart-define=MOCK_AI_BACKEND=true
```

### Run Tests
```bash
# Run backend integration and rule suites (from root)
pytest backend/tests/ -v

# Run Flutter client unit tests
cd frontend
flutter test
```

---

## 13. Team Details

KalaSetu is built by a 6-person multidisciplinary engineering team for **Smart India Hackathon 2026 (PS-90)**:

| Member Name | Role & Core Responsibilities | GitHub Profile |
|---|---|---|
| **Kanishka Pandey** | System Integration, FastAPI Backend, API Architecture | [@kan9667](https://github.com/kan9667) |
| **Aadi Jain** | Pricing Pipeline, Cost Floor Engine & Backend Services | [@DeltaData0](https://github.com/DeltaData0) |
| **Aanya Varshney** | Flutter Frontend UI & Artisan Experience Design | [@aanyavarshneyav](https://github.com/aanyavarshneyav) |
| **Rudraksh Saini** | Offline Sync Engine (Drift/Hive/WorkManager) | [@Rudrakssh](https://github.com/Rudrakssh) |
| **Dhruv Makkar** | Computer Vision & 10-Stage Studio Image Pipeline | [@dhruvsded1](https://github.com/dhruvsded1) |
| **Triman Singh Chadha** | Speech-to-Text Pipeline & Regional Craft Glossary | [@Triman01](https://github.com/Triman01) |

---

## 14. Future Scope

1. **ONDC Direct Protocol Integration:** Native Beckn protocol adapters allowing artisans to broadcast catalog inventory directly to ONDC buyer apps without platform commissions.
2. **Bhashini Regional Dialect Expansion:** Fine-tuned speech-to-text integration for niche tribal dialects (Santhali, Gondi, Warli).
3. **Web3 Provenance & Craft Authenticity Certificate:** Non-invasive cryptographic NFC/QR craft origin verification tags to protect artisans from industrial counterfeits.
4. **Buyer-Side Web AR Visualization:** WebXR interactive 3D view enabling global buyers to visualize handcrafted home decor directly in their rooms.

---



---

<div align="center">
<sub>Licensed under the <a href="LICENSE">MIT License</a>. Digitizing what the government already helped artisans build — without taking a cut of their livelihood to do it.</sub>
</div>
