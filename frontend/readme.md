# KalaSetu Mobile Client — Flutter Application

The mobile client of **KalaSetu (कलासेतु)** — an offline-first, multimodal AI business co-pilot tailored for rural and marginalized Indian artisans. Built with Flutter, it bridges low-literacy craftspeople to national and global e-marketplaces through voice-driven cataloging, on-device studio photo enhancement, automated bilingual copywriting, non-negotiable fair pricing floors, and conversational AI assistance.

---

## Key Capabilities

* **Offline-First Architecture:** Complete on-device resilience using local relational storage (Drift SQLite), fast key-value cache (Hive), and OS-level background synchronization workers (WorkManager). Product drafts, voice notes, and captured images are stored locally and automatically drained to the backend when network connectivity resumes.
* **Multilingual Voice-to-Listing:** Artisans narrate product details in their regional language; voice notes are streamed to the Whisper Large v3 speech engine and synthesized into structured bilingual (English + Devanagari Hindi) listings with SEO tags.
* **AI Photo Studio Integration:** Captures raw, cluttered workshop photos on budget smartphones and connects directly to the containerized rembg (U²-Net) + OpenCV CLAHE vision pipeline to produce square 1080×1080 e-commerce assets.
* **Dual-Layer Fair Pricing Assistant:** Real-time calculation displaying an inviolable mathematical cost floor (`Materials + Labor Hours × Fair Wage + Transport + Overhead`) alongside indexed handicraft market comps from ChromaDB RAG.
* **KalaMitra AI Conversational Co-Pilot:** In-app voice and chat assistant powered by Groq LPUs that executes direct app actions (filtering inventory, updating product status, triggering sync) and provides tailored advice on government schemes (PM Vishwakarma, Pehchan ID, Mudra loans) and craft defect troubleshooting.
* **Orders & Packaging Advisory:** Order lifecycle management with craft-specific transit packaging guidelines and downloadable, printable shipping labels embedding ONDC-compliant artisan profile QR codes.
* **Social Media Launchpad:** One-tap marketing copy generation with custom templates formatted for direct dispatch across WhatsApp, Instagram, and Facebook.
* **Bilingual On-Device TTS:** Complete voice feedback across all screens using `flutter_tts`, enabling low-literacy artisans to listen to previews, prices, and guidance.

---

## Technology Stack

| Component | Technology | Version | Purpose |
|---|---|---|---|
| **Framework** | Flutter (Dart SDK) | `^3.12.0` (Flutter 3.44+) | High-performance multi-platform UI compiled to native ARM machine code |
| **State Management** | `flutter_riverpod` | `^2.5.1` | Reactive, testable, compile-safe application state |
| **Routing** | `go_router` | `^14.6.2` | Declarative deep-linking and state-driven navigation |
| **Relational Offline DB** | `drift` / `sqlite3_flutter_libs` | `^2.21.0` / `^0.5.24` | ACID-compliant local database for offline draft items and media queues |
| **Key-Value Cache** | `hive` / `hive_flutter` | `^2.2.3` / `^1.1.0` | Ultra-fast local persistence for auth sessions, cached profiles, and settings |
| **Background OS Worker** | `workmanager` | `^0.6.0` | Android background job execution with exponential backoff for queue draining |
| **Networking & HTTP** | `dio` | `^5.7.0` | High-throughput asynchronous HTTP client with multipart file upload support |
| **Connectivity** | `connectivity_plus` | `^6.0.5` | Real-time network interface monitoring |
| **Camera & Media** | `camera`, `image_picker` | `^0.11.0+2`, `^1.1.2` | Hardware camera stream and gallery asset selection |
| **Audio I/O** | `record`, `just_audio` | `^7.1.1`, `^0.9.40` | Low-latency audio capture and waveform playback |
| **Voice Accessibility** | `flutter_tts` | `^4.1.0` | On-device text-to-speech reading in Hindi and English |
| **Localization** | `easy_localization` | `^3.0.7` | Dynamic runtime locale switching (English, Hindi, Tamil, Bengali) |
| **Typography & Icons** | `google_fonts`, `phosphor_flutter` | `^6.2.1`, `^2.1.0` | Craft-inspired typography (Zilla Slab & Nunito Sans) and accessible iconography |

---

## Directory Structure

```text
frontend/
├── android/                    # Android native project and Gradle configuration
├── ios/                        # iOS native project
├── assets/                     # Packaged static assets
│   ├── fonts/                  # Custom offline font binaries
│   ├── icons/                  # Scalable craft and UI icons
│   ├── images/                 # App logos, background motifs, and placeholders
│   ├── sounds/                 # UI feedback audio files
│   └── translations/           # JSON translation bundles (en.json, hi.json, ta.json, bn.json)
├── lib/
│   ├── main.dart               # App entrypoint, dependency initialization & service pre-warming
│   ├── app.dart                # EasyLocalization wrapper & MaterialApp router binding
│   ├── core/                   # Shared infrastructure and utilities
│   │   ├── config/             # Dynamic API endpoint resolution (api_config.dart)
│   │   ├── offline_sync/       # Drift SQLite media database, sync queue & WorkManager runner
│   │   ├── providers/          # Global application state providers
│   │   ├── router/             # GoRouter routes and transition handlers
│   │   ├── services/           # Platform utilities (audio, social sharing, storage)
│   │   ├── theme/              # Earthy artisan design system (terracotta, indigo, turmeric)
│   │   ├── utils/              # Formatters, validators, and currency helpers
│   │   └── widgets/            # Reusable responsive components and feedback banners
│   ├── data/                   # Data and networking layer
│   │   ├── models/             # Strongly typed data models and serializers
│   │   ├── repositories/       # Abstraction layer between network and local databases
│   │   └── services/           # Backend API clients (Dio REST endpoints)
│   │       ├── api_service.dart            # Base HTTP client with auto-headers & error handling
│   │       ├── chat_service.dart           # KalaMitra LLM conversation & intent parsing
│   │       ├── image_enhancer_service.dart # U²-Net studio background excision endpoint
│   │       ├── pricing_service.dart        # Dual-layer pricing & cost floor calculation
│   │       ├── social_media_service.dart   # Marketing caption generator for social platforms
│   │       ├── speech_service.dart         # Whisper STT transcription & voice cataloging
│   │       └── sync_service.dart           # Local queue dispatcher to backend
│   └── features/               # Domain feature modules
│       ├── add_product/        # 5-step smart cataloging flow (photo, voice, review, price, publish)
│       ├── auth/               # Artisan onboarding, Pehchan ID KYC & OTP verification
│       ├── catalogue/          # Searchable, filterable product grid with sync state badges
│       ├── chatbot/            # KalaMitra voice assistant with direct in-app action dispatch
│       ├── home/               # Navigation shell with real-time connectivity indicators
│       ├── notifications/      # Order alerts, scheme updates, and sync logs
│       ├── orders/             # Order fulfillment, packaging advisory & printable shipping labels
│       ├── profile/            # Master artisan credentials, language switcher & performance stats
│       ├── social_media/       # Social media launchpad (WhatsApp/Instagram/Facebook)
│       └── tutorial/           # First-run onboarding walkthrough for new artisans
└── test/                       # Comprehensive unit and widget testing suites
```

---

## Configuration & Environment Flags

The app connects by default to the production cloud backend hosted on Railway, with dynamic fallback resolution for local LAN physical testing. Configuration is managed at build or runtime using Dart environment flags:

### Available `--dart-define` Flags

| Flag | Default Value | Description |
|---|---|---|
| `API_BASE_URL` | Dynamic auto-discovery | Base URL of the backend API (e.g., `https://kalasetu-production.up.railway.app`) |
| `MOCK_AI_BACKEND` | `false` | When set to `true`, uses local heuristic mock responses for AI pipelines (offline testing without cloud API keys) |
| `DEBUG` | `false` | Enables verbose HTTP network and sync queue diagnostic logging in the console |

---

## Getting Started

### Prerequisites
* **Flutter SDK**: `3.22.0` or newer (stable channel)
* **Dart SDK**: `3.12.0` or newer
* **Android Studio / Android SDK**: API level 21 (Android 5.0 Lollipop) or higher
* **Java**: OpenJDK 17 or higher

### 1. Install Dependencies
From the `frontend/` directory:
```bash
flutter pub get
```

### 2. Run the Application

#### Connect to Cloud Backend (Production Railway API):
```bash
flutter run --dart-define=API_BASE_URL=https://kalasetu-production.up.railway.app
```

#### Run with Standalone Mock Mode (No Backend Required):
```bash
flutter run --dart-define=MOCK_AI_BACKEND=true
```

#### Run Locally with Localhost Backend:
If running `uvicorn backend.main:app` locally on machine port 8000:
* On Android Emulator (points to host loopback):
  ```bash
  flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
  ```
* On Physical Android Device (replace with your machine's LAN IP):
  ```bash
  flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
  ```

---

## Building for Production

### Build Release APK (Universal Android)
Compile an optimized, standalone release APK pointed to the live production cloud backend:
```bash
flutter build apk --release --no-tree-shake-icons --dart-define=API_BASE_URL=https://kalasetu-production.up.railway.app
```
The compiled release binary will be generated at:
```text
build/app/outputs/flutter-apk/app-release.apk
```

### Build App Bundle (Google Play Store)
```bash
flutter build appbundle --release --dart-define=API_BASE_URL=https://kalasetu-production.up.railway.app
```

---

## Testing

The frontend includes extensive unit and widget test suites covering authentication, smart cataloging, offline sync, and conversational bot actions:

```bash
# Run all unit and widget tests
flutter test

# Run a specific test suite
flutter test test/add_product_bilingual_test.dart
flutter test test/chatbot_direct_actions_test.dart
flutter test test/offline_sync_placeholder_test.dart
```

---

## Offline-First Architecture Breakdown

```text
                      Artisan Action (New Listing / Edit / Photo)
                                        │
                                        ▼
                      ┌──────────────────────────────────┐
                      │    Drift (Local SQLite DB)       │
                      │  - Stores raw image & audio path │
                      │  - Marks status: "pending_sync"  │
                      └─────────────────┬────────────────┘
                                        │
                         Connectivity Available?
                                ├── YES ──► Immediate HTTP Multipart Upload via Dio
                                │
                                └── NO ───► Enqueue in WorkManager Background Queue
                                                  │
                                                  ▼
                                    OS Network State Restored
                                                  │
                                                  ▼
                                    WorkManager wakes background worker
                                    Drains queue with exponential backoff
                                    Updates local status to "synced"
```

---

## Architecture & Code Quality Highlights

1. **Strict Cost Floor Enforcement:** The UI visually bounds pricing input sliders so that an artisan cannot accidentally publish an item below its calculated material, labor, and transport costs.
2. **Accessible Regional UX:** Form inputs accept voice notes alongside typing; text sizes, tap targets (minimum 48×48dp), and contrast ratios comply with WCAG 2.1 AA accessibility standards for low-literacy users.
3. **Failover Resilience:** The networking layer handles transient cloud network errors gracefully, preserving the artisan's captured draft on device without data loss.
