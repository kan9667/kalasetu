# KalaSetu — System Architecture & Technical Specification

> **AI-Driven Market Linkage & Smart Cataloging Platform for Marginalized Artisans**  
> *Built for Smart India Hackathon 2026 · Problem Statement PS-90*

---

## 1. Executive Summary & Core Mission

**KalaSetu (कलासेतु)** is an offline-first, multilingual, AI-powered "virtual business manager" built to bridge the digital, economic, and linguistic divide for India's traditional artisans, weavers, and rural craft clusters.

Government initiatives (e.g., *Shilp Samagam*, *Surajkund Mela*, *Dilli Haat*) provide temporary, seasonal market exposure, but when exhibitions end, artisan revenues collapse. Traditional craftspeople face four structural barriers when trying to sell online:
1. **Studio Quality Barrier:** Lack of photography equipment, lighting, and knowledge to create clean e-commerce product photos.
2. **Linguistic & Digital Literacy Barrier:** Inability to write SEO-optimized product descriptions in English or navigate complex multi-step e-commerce seller portals.
3. **Information Asymmetry & Exploitative Pricing:** Inability to assess fair market benchmarks, leaving artisans vulnerable to predatory middlemen who capture 300% to 500% retail markups.
4. **Connectivity Barrier:** Unreliable or absent cellular data in rural craft clusters and remote artisan villages.

KalaSetu solves these challenges through a unified mobile-first ecosystem: the artisan captures a photo and speaks naturally in their regional mother tongue. The platform automatically enhances the photo to studio grade, transcribes the dialect with domain craft vocabulary biasing, generates structured bilingual (Hindi & English) listings, calculates a mathematically guaranteed fair price floor with market comparables, and enables instant 1-tap multi-platform social sharing and order fulfillment — fully functional even when completely offline.

---

## 2. High-Level System Architecture

KalaSetu is designed as a modular, 4-tier distributed architecture spanning client-side presentation, local offline persistence, an asynchronous API gateway, and specialized machine learning pipelines.

```mermaid
flowchart TD
    classDef client fill:#EBF3FA,stroke:#02569B,stroke-width:2px,color:#02569B;
    classDef gateway fill:#E0F2F1,stroke:#00796B,stroke-width:2px,color:#00796B;
    classDef ai fill:#F3E5F5,stroke:#6A1B9A,stroke-width:2px,color:#6A1B9A;
    classDef external fill:#FFF3E0,stroke:#E65100,stroke-width:2px,color:#E65100;

    subgraph Tier1 ["1. Client Layer — Cross-Platform Flutter App (Android / iOS / Web)"]
        UI["Mobile Presentation & User Workflows\n• 5-Step Cataloging Wizard  • KalaMitra AI Chatbot & Agent\n• Orders & Packaging Advice  • Performance Analytics  • Social Launchpad"]
        State["Reactive State Management (Riverpod 2.x)\n• AsyncNotifiers  • Draft State  • Live Connectivity Listener"]
        UI <--> State
    end

    subgraph Tier2 ["2. Local Offline Engine (On-Device Storage)"]
        HiveStore[("Hive Document Store\n• Products Box (Fast Cache)\n• Pending Sync Box\n• User Profiles & Auth")]
        DriftQueue[("Drift SQLite Database\n• Media Upload Queue\n• Retry Policy & Backoff\n• Background Sync")]
        State <--> HiveStore
        State <--> DriftQueue
    end

    subgraph Tier3 ["3. API Gateway & Backend Services (FastAPI + SQLite)"]
        Gateway["FastAPI Gateway (main.py)\n• Dynamic IP Discovery  • CORS  • Threadpool Dispatch"]
        DB[("Relational Database (SQLAlchemy)\n• Artisans  • Products  • Social Drafts")]
        Services["Core Application Services\n• CatalogService  • ChatService  • PricingService  • SocialService"]
        Gateway <--> Services
        Services <--> DB
    end

    subgraph Tier4 ["4. AI & Machine Learning Subsystems"]
        CV["Image Studio Pipeline (ML/image_pipeline)\nrembg (U²-Net) + CLAHE + Auto-Crop + 1080x1080 Canvas"]
        ASR["Voice Pipeline (ML/voice_pipeline)\nWhisper Large v3 + Craft Glossary Biasing + Silence Filter"]
        Pricing["Dynamic Pricing Engine (ML/pricing)\nCost Floor Enforcer + Gemini Embeddings + ChromaDB RAG"]
        KalaMitra["KalaMitra Conversational Agent\nGroq Cloud LLM + Craft Context + Tool Actions"]
    end

    subgraph Tier5 ["5. External Public DPI & Native Social Sinks"]
        ONDC["India DPI: ONDC / GeM\n(Artisan Profile & QR Codes)"]
        Social["Social Platforms\n(WhatsApp, Instagram, Facebook)"]
        Models["Foundation AI APIs\n(Groq Cloud, Google Gemini, OpenAI Whisper)"]
    end

    State <==>|"REST / Multipart HTTP\n(Online or Reconnect)"| Gateway
    Services --> CV
    Services --> ASR
    Services --> Pricing
    Services --> KalaMitra
    KalaMitra <--> Models
    Pricing <--> Models
    State -.->|"Direct Native Intents"| Social
    Services -.->|"Profile Verification"| ONDC

    class UI,State client;
    class HiveStore,DriftQueue,Gateway,DB,Services gateway;
    class CV,ASR,Pricing,KalaMitra ai;
    class ONDC,Social,Models external;
```

---

## 3. Core Feature 1: AI Image Enhancer & Studio (CV Pipeline)

### 3.1 Problem & Architectural Seam
Artisans typically photograph their products on workshop floors, dusty mats, or poorly-lit indoor spaces using entry-level smartphones. Poor image quality directly causes buyer distrust and product rejection on major e-commerce platforms.

The **AI Image Studio** (`ML/image_pipeline` and `frontend/lib/features/add_product/widgets/step1_capture_widget.dart`) executes a deterministic, 10-stage computer vision workflow that cleans, corrects, centers, and renders the handicraft onto a studio-grade white e-commerce canvas.

### 3.2 10-Stage Computer Vision Pipeline

```mermaid
flowchart LR
    A["1. Raw Capture\n(Validation & EXIF)"] --> B["2. rembg (U²-Net)\nAlpha Matting"]
    B --> C["3. Auto-Crop\nContour Bounding"]
    C --> D["4. Lighting Fix\nCLAHE on Luminance"]
    D --> E["5. White Balance\nGray-World Algorithm"]
    E --> F["6. Sharpening\nUnsharp Masking"]
    F --> G["7. Background\nAlpha Composite on White"]
    G --> H["8. E-Com Canvas\n1080x1080 Square Fit"]
    H --> I["9. Optimization\nJPEG/WebP Quality 85"]
```

#### Detailed Stage Breakdown:
1. **Input Validation & Normalization:** Checks byte integrity, handles EXIF orientation rotation flags, and converts palette/RGBA images into standard formats.
2. **Background Removal (`rembg`):** Uses the U²-Net Salient Object Detection deep learning model to separate foreground craft from cluttered workshop backgrounds, outputting a precise alpha transparency mask.
3. **Product Detection & Auto-Crop:** Identifies the minimum bounding rectangle of non-zero alpha pixels and crops with a balanced 8% margin padding.
4. **Luminance Correction (CLAHE + Gamma):** Converts the image to CIELAB color space and applies Contrast Limited Adaptive Histogram Equalization (CLAHE) with adaptive gamma correction strictly on the **L (Luminance)** channel.  
   *Design Decision:* This step is performed *before* placing the object on a white canvas; applying CLAHE after adding a white background would distort the histogram due to the high concentration of white pixels.
5. **White Balance Correction:** Applies the gray-world assumption to automatically cancel yellowish incandescent or bluish CFL lighting casts typical of village workshops.
6. **Unsharp Masking:** Applies mild edge-enhancement convolution to highlight intricate handcrafted details (wood grain, embroidery threads, pottery textures).
7. **Clean Background Compositing:** Alpha-blends the isolated craft onto a clean pure white (`#FFFFFF`) or soft neutral canvas.
8. **E-Commerce Canvas Standard:** Centers and scales the craft to fit a standard square 1080x1080 e-commerce canvas without distortion.
9. **Final Output Compression:** Compresses output into WebP/JPEG format targeting ~200–400 KB for rapid mobile rendering over 2G/3G networks.

### 3.3 UI Implementation & Interactive Before/After Comparison
In `step1_capture_widget.dart`, artisans are presented with an interactive, gesture-driven **Before/After split slider**. Artisans can drag the dividing line left and right to inspect the background removal and lighting enhancements before accepting or retaking the shot.

---

## 4. Core Feature 2: Multilingual Voice Auto-Cataloger (ASR & LLM)

### 4.1 Problem & Domain Phonetic Substitution
Marginalized artisans possess deep generational knowledge of their craft but often cannot read or write English, and many are not literate in formal Hindi. When speaking about their products, standard ASR models (trained on news broadcasts) consistently misclassify regional craft terminology:
* *"Dhokra"* (ancient lost-wax brass casting) becomes *"doctor"*.
* *"Chikankari"* (delicate Lucknow embroidery) becomes *"chicken curry"*.
* *"चाक"* (chaak - potter's wheel) is misheard as *"चात"* (chaat).

### 4.2 Voice-to-Bilingual Cataloging Architecture

```mermaid
flowchart TD
    Audio["Artisan Spoken Voice Note (.m4a / .wav)"] --> SilenceCheck{"Audio Energy Check\nffmpeg volumedetect"}
    SilenceCheck -- "Max Vol < -40dB" --> Reject["Reject: Prompt Artisan to Speak Louder"]
    SilenceCheck -- "Audible" --> Glossary["Inject Craft Glossary Biasing\n(100+ Terms: Latin + Devanagari)"]
    
    Glossary --> Whisper["Whisper Large v3 STT\nOpenAI-Compatible Inference"]
    Whisper --> HallucinationGuard{"Silence Hallucination?\n(e.g. 'Thanks for watching')"}
    HallucinationGuard -- "Yes" --> Reject
    HallucinationGuard -- "No" --> CleanTranscript["Clean Native Transcript\n(Hindi / Regional Language)"]

    CleanTranscript --> CategoryDetect["Dynamic Category & Keyword Detection\n(Textiles, Pottery, Brass, Woodwork, etc.)"]
    CategoryDetect --> LLMPrompt["Bilingual LLM Structuring Engine (Groq / Gemini)"]
    LLMPrompt --> Output["Structured Bilingual Listing (JSON)\n• Title (EN + HI)  • Storytelling Description (EN + HI)\n• Accurate Category  • 5-8 SEO Tags"]
```

### 4.3 Key Components:
1. **Audio Silence Detection:** `CatalogService._is_audio_silent()` runs `ffmpeg -af volumedetect` on the uploaded recording. If the peak volume is below `-40 dB`, the system flags it as empty noise and prompts the user to re-record before invoking inference.
2. **Craft Vocabulary Glossary Biasing (`craft_terms.py`):** Injects curated Indian craft terminology into Whisper's initial prompt context across categories:
   * *Textiles:* Bandhani, Ajrakh, Chikankari, Kalamkari, Ikat, Patola, Banarasi, Chanderi, Kanjeevaram, Phulkari, Zari, Zardozi, Tussar silk.
   * *Pottery:* Terracotta, Khurja, Blue pottery, Chaak, Kulhad, Surahi, Matka, Diya.
   * *Metalwork:* Dhokra, Bidriware, Bell metal, Thewa, Meenakari, Filigree, Kansa.
   * *Devanagari Set:* Full dual-script glossary ensures phonetic alignment in native Devanagari output.
3. **Silence Hallucination Filtering:** Traps common Whisper failure modes when processing silent or ambient audio (e.g., *"Thank you for watching"*, *"Please subscribe"*, *"धन्यवाद"* looping).
4. **Spoken Cue Guidance (UI Step 2):** Visual chips and audio prompts instruct the artisan on what to include:
   * *"सामग्री"* (Materials used)
   * *"बनाने में लगा समय"* (Hours of manual labor)
   * *"विशेष तकनीक"* (Special craft technique or heritage method)
5. **Cost Cue Extractor:** An LLM routine parses the transcript to extract mentioned raw material expenditures and hours of labor to automatically seed the Pricing Assistant in Step 4.

---

## 5. Core Feature 3: Dynamic Pricing Assistant (RAG & Cost Floor Engine)

### 5.1 The Economic Challenge: Eliminating Middleman Exploitation
Because rural artisans lack access to real-time e-commerce price indices, urban middlemen routinely purchase authentic handicrafts at prices below the artisan's cost of sustenance. KalaSetu prevents this by computing an **unbreachable mathematical cost floor** combined with **Retrieval-Augmented Generation (RAG)** over market benchmarks.

### 5.2 Dynamic Pricing Pipeline

```mermaid
flowchart TD
    subgraph CostInputs ["Artisan Cost Breakdown"]
        Mat["Raw Material Cost (₹)"]
        Labor["Labor Hours Invested × Hourly Wage Floor (₹50–₹120/hr)"]
        Freight["Transport & Packaging (₹)"]
        Overhead["Workshop Overhead (₹)"]
    end

    subgraph MathematicalFloor ["Strict Mathematical Floor"]
        CalcFloor["Cost Floor = Materials + (Labor × Wage) + Freight + Overhead"]
    end

    subgraph MarketRAG ["Market Benchmark Retrieval (RAG)"]
        ProductData["Craft Description + Enhanced Photo"]
        GeminiEmbed["Gemini Multimodal Embedding (3072 Dimensions)"]
        ChromaDB[("ChromaDB Vector Store\nReal Listing Benchmarks from\nAmazon Karigar, FabIndia, Etsy, Okhai")]
        TopMatches["Retrieve Top 3-5 Comparable Products\n(Cosine Similarity Score)"]
        ProductData --> GeminiEmbed --> ChromaDB --> TopMatches
    end

    subgraph PricingInference ["LLM Pricing Analyst (pricer.py)"]
        Prompt["Prompt Context:\n• Cost Floor Threshold\n• Market Benchmark Listings\n• Craft Heritage Value"]
        LLM["Groq / Gemini Structured Inference"]
        Prompt --> LLM
    end

    subgraph OutputDecision ["Output & Invariant Enforcement"]
        InvariantCheck{"Suggested Price >= Cost Floor?"}
        Enforce["Clamp Suggested Price to Cost Floor + Margin"]
        FinalResult["Price Suggestion Result\n• Suggested Price (₹)  • Min / Max Price Range\n• Confidence Score  • Market Position (Budget / Mid / Premium)\n• English Reasoning  • Hindi Reasoning (for TTS Audio Readback)"]
    end

    CostInputs --> CalcFloor --> Prompt
    TopMatches --> Prompt
    LLM --> InvariantCheck
    InvariantCheck -- Yes --> FinalResult
    InvariantCheck -- No --> Enforce --> FinalResult
```

### 5.3 Mathematical Formulation & Hard Invariants
The platform strictly enforces that no suggested price may undercut the artisan:

$$\text{Cost Floor} = C_{\text{materials}} + (T_{\text{labor}} \times W_{\text{hourly}}) + C_{\text{transport}} + C_{\text{overhead}}$$

$$\text{Suggested Price} \ge \text{Cost Floor}$$

If an LLM hallucinates a price below this threshold, server-side post-processing clamps `suggested_price` to the cost floor plus category baseline margins. The response includes a conversational Hindi reasoning string read aloud via on-device Text-to-Speech (TTS) so non-literate artisans understand exactly why the price was recommended.

---

## 6. Core Feature 4: Dual Offline-First Storage & Sync Engine

### 6.1 Architectural Necessity
Rural artisan clusters often have intermittent or absent cellular connectivity. An application requiring a continuous cloud connection is unusable in these regions. KalaSetu implements a **Dual Offline Engine**:

```mermaid
flowchart TD
    UserAction["Artisan Creates / Updates Product"] --> NetworkCheck{"Is Internet Reachable?\n(connectivity_plus + /health probe)"}

    subgraph OfflineMode ["Offline State"]
        HiveWrite["1. Write to Hive products_box (status: pendingSync)\nInstant UI Update (0ms latency)"]
        PendingMark["2. Record operation in pending_sync_box"]
        DriftQueue["3. Enqueue heavy media files in Drift SQLite queue\n(status: pending, retryCount: 0)"]
    end

    subgraph ReconnectDrain ["Auto-Reconnect Drain"]
        NetReturn["Connectivity Restored & Health Check Passes"]
        MediaUpload["4. Background Worker Uploads Queued Media\n(POST /uploads) -> Receives Remote URLs"]
        BatchSync["5. Send Batch Sync (POST /api/v1/products/sync)"]
        ServerPersist["6. Server Persists Batch in ProductDB"]
        LocalUpdate["7. Promote Hive status to 'live' & Clear Pending Box"]
    end

    NetworkCheck -- "Offline" --> OfflineMode
    NetworkCheck -- "Online" --> DirectAPI["Direct FastAPI Call"]
    OfflineMode -.-> NetReturn --> ReconnectDrain
```

### 6.2 Dual Engine Breakdown:
* **Drift SQLite Database (`offline_sync.sqlite`):** Handles background media upload queueing. The `QueueItems` table tracks media type, file paths, retry counts (up to 3 with exponential backoff), job status (`pending`, `uploading`, `processing`, `completed`, `failed`), and error messages.
* **Hive NoSQL Store:** Handles instant synchronous key-value storage for products (`products_box`), authentication (`auth_box`), draft state (`draft_box`), and pending mutation queues (`pending_sync_box`).
* **Dynamic Network Discovery (`ApiConfig`):** When running locally or on physical Android devices over Wi-Fi, the app automatically probes candidate IPs (`LAN IP`, `10.0.2.2`, `localhost`) against `/api/v1/health` and binds to the first responsive host without manual configuration.

---

## 7. Core Feature 5: KalaMitra AI Chatbot & Navigation Agent

### 7.1 Agent Purpose & Scope
**KalaMitra (कला-मित्र)** is an in-app AI assistant, craft mentor, and autonomous navigation agent designed for artisans. Rather than acting as a generic chatbot, KalaMitra understands the artisan's registered trade and can autonomously trigger actions inside the Flutter application.

### 7.2 Agent Loop & Tool Calling Architecture

```mermaid
flowchart TD
    ArtisanMsg["Artisan Speaks or Types Query\n(Hindi, English, or Regional Dialect)"] --> WhisperCheck{"Is Voice Audio?"}
    WhisperCheck -- Yes --> Transcribe["Whisper STT Transcription"] --> PromptBuild
    WhisperCheck -- No --> PromptBuild["Build Dynamic System Prompt"]

    subgraph PromptEngine ["KalaMitra Context Injection (chat_service.py)"]
        ArtisanProfile["Artisan Profile Context:\nRegistered Craft (e.g. 'Terracotta Pottery')\nCluster Location & Language"]
        DomainKnowledge["Curated Domain Guidelines:\n• PM Vishwakarma, Pehchan Card, Mudra Loans\n• Defect Prevention (Cracking, Dye-bleeding)\n• Safe Packaging & Pricing Principles"]
        FormattingRules["Strict Accessibility Rules:\n• Clean Plain Text Only (Zero Asterisks Allowed)\n• Language Matching & Language-Switch Suggestions"]
        ArtisanProfile & DomainKnowledge & FormattingRules --> PromptBuild
    end

    PromptBuild --> LLM["Groq Cloud LLM (openai/gpt-oss-120b)"]
    LLM --> ParseAction{"Contains Structured Action?"}

    subgraph ClientExecution ["Flutter Client Tool Execution"]
        ActionNav["type: 'navigate'\nSwitches Bottom Tab or GoRouter Route"]
        ActionStatus["type: 'update_product_status'\nDirectly Marks Item 'sold' / 'relisted' in Hive\n(With 1-Tap Undo Action)"]
        ActionFilter["type: 'filter_catalogue'\nApplies Category / Search Query Filters"]
        ActionSync["type: 'sync_pending'\nImmediately Drains Offline Media Queue"]
    end

    ParseAction -- "Yes" --> ClientExecution
    ParseAction -- "No" --> PlainTextReply["Render Clean Conversational Response in UI"]
    ClientExecution --> PlainTextReply
```

### 7.3 Direct Action Execution Matrix:
* `update_product_status`: Automatically updates product status in Hive (e.g., *"चंदेरी साड़ी बिक गई"* $\to$ marks *Chanderi Saree* as `sold` with an instant undo button in chat).
* `filter_catalogue`: Immediately navigates to the catalogue and filters for queried materials or crafts (e.g., *"Show my brass items"*).
* `sync_pending`: Manually triggers background sync if the artisan wants to force an upload.
* `navigate`: Routes directly to relevant screens (`/add-product`, `/my-stats`, `/language-settings`, `/my-orders`).
* **Zero Asterisks Rule:** To prevent confusing markdown artifacts on simple mobile text views, all responses are stripped of asterisks (`*` and `**`).

---

## 8. Core Feature 6: Orders Management, AI Packaging & PDF Labels

### 8.1 Fulfillment Lifecycle & Breakage Prevention
Handicrafts are fragile and often suffer transit damage when shipped across state borders. The Orders module provides end-to-end status tracking paired with **Category-Tailored Packaging Advisory** and a **Printable Artisan Story Label Maker**.

```mermaid
flowchart LR
    subgraph OrderPipeline ["Order Lifecycle"]
        O1["New Order\n(Buyer Location & Items)"] --> O2["Packed\n(Advisory Applied)"]
        O2 --> O3["Shipped\n(Tracking ID Added)"]
        O3 --> O4["Delivered\n(Fulfillment Complete)"]
    end

    subgraph PackagingAdvisory ["AI Packaging Suggestions"]
        Cat{"Craft Category"}
        Cat -- Pottery --> P1["Double-wall corrugated box\nShredded straw / paper cushioning\nFragile stickers on 4 sides"]
        Cat -- Textiles --> P2["Moisture-proof inner polywrap\nAcid-free tissue layering\nPadded courier bag"]
        Cat -- Metal/Wood --> P3["Bubble wrap buffers\nAnti-tarnish cloth wrap\nRigid wooden / cardboard box"]
    end

    subgraph LabelMaker ["Printable Label Generator (LabelMakerService)"]
        PDF["Generate High-Res PDF (pdf & printing)"]
        PDF --> Elements["• Consignee & Order Barcode\n• Bilingual Craft Story\n• Wash & Handling Instructions\n• Verified ONDC / Profile QR Code"]
    end

    O1 --> Cat
    O1 --> PDF
```

### 8.2 Printable Artisan Story & Packaging Label (`LabelMakerService`):
Generates a printable PDF shipping label using Flutter's `pdf` and `printing` packages:
* **Bilingual Craft Narrative:** Incorporates the story of the craft (e.g., *"Handcrafted using riverbed clay on the potter's wheel..."* in English and Hindi).
* **Wash & Care Guidelines:** Tailored handling instructions (e.g., *"Gentle hand wash with mild soap; avoid direct thermal shock"*).
* **ONDC Profile QR Code:** Links buyers directly to the artisan's verified government digital identity.

---

## 9. Core Feature 7: Artisan Performance & Revenue Analytics

### 9.1 Measuring Direct Economic Empowerment
The **Artisan Analytics Dashboard** (`features/profile/screens/my_stats_screen.dart`) provides clear, visual financial reporting designed for users who may struggle with complex accounting spreadsheets.

```mermaid
flowchart TD
    SalesData[("Hive products_box & Orders Data")] --> MetricEngine["Analytics Calculation Engine"]
    
    subgraph Metrics ["Core Tracked Indicators"]
        M1["Total Revenue Earned (₹)"]
        M2["Total Units Sold & Live Listings"]
        M3["Top Performing Craft Categories"]
        M4["Customer Reach Across States"]
    end

    subgraph FairWageFormula ["Fair Wage Premium Metric"]
        Premium["Fair Wage Premium = Total KalaSetu Revenue - (Units Sold × Estimated Middleman Baseline Rate)"]
    end

    MetricEngine --> Metrics
    MetricEngine --> FairWageFormula
    Metrics & FairWageFormula --> UICharts["Visual Dashboards:\n• Revenue Growth Trendlines\n• Fair Wage Comparison Cards\n• Category Distribution Charts"]
```

### 9.2 Fair Wage Premium Calculation:
The dashboard explicitly calculates the **Fair Wage Premium** earned by selling directly through KalaSetu compared to historical middleman rates:

$$\text{Fair Wage Premium} = \sum (\text{Direct Selling Price} - \text{Middleman Trader Baseline})$$

This demonstrates tangible economic improvement, giving artisans confidence in their digital business.

---

## 10. Core Feature 8: Social Media Helper & Sharing Launchpad

### 10.1 Promoting Listings Across Indian Social Sinks
Artisans can promote their creations directly to social platforms from two entry points:
1. **From Catalogue:** Tapping the *"Promote"* action chip on any listing.
2. **From Stepper Step 5:** Immediately upon publishing a new craft listing.

```mermaid
flowchart TD
    Trigger["Artisan Taps 'Share / Promote'"] --> LoadDraft["Backend AI Caption Generator\n(POST /api/v1/listings/{id}/social-draft)"]
    LoadDraft --> Editor["Social Media Launchpad Screen\n• Multi-Image Selector  • Caption Editor  • Hashtag Chips"]
    
    Editor --> Destination{"Select Destination"}

    Destination -- "WhatsApp" --> WA["SocialSharingService.shareToWhatsApp()\nDirect Intent (com.whatsapp) with Image + Text"]
    
    Destination -- "Instagram / Facebook" --> MetaFlow["Meta Policy Compliance Flow:\n1. Copy full caption & tags to Clipboard\n2. Show Toast: 'Caption copied! Paste into post'\n3. Fire image-only intent to com.instagram.android"]
    
    Destination -- "System Share" --> Generic["OS System Share Chooser (share_plus)"]

    subgraph AndroidQueries ["Android 11+ Package Visibility (<queries>)"]
        Q1["com.whatsapp & com.whatsapp.w4b"]
        Q2["com.instagram.android"]
        Q3["com.facebook.katana"]
    end

    WA & MetaFlow -.-> AndroidQueries
```

### 10.2 Platform Constraints & Meta Anti-Spam Compliance:
* **Meta Platform Policy 2.3:** Instagram and Facebook explicitly block third-party applications from pre-filling user post captions via `Intent.EXTRA_TEXT`.
* **The Clipboard-First Strategy:** KalaSetu solves this by copying the formatted caption and hashtags to the system `Clipboard`, displaying a prominent bilingual instruction toast (*"Caption copied! Opening Instagram — paste into your post"*), and launching Instagram's photo composer directly with the resolved local image.
* **WhatsApp Direct Intent:** WhatsApp allows full pre-populated text and media, providing a 1-tap sharing experience.
* **Android `<queries>` Configuration:** Declares package names in `AndroidManifest.xml` so Android 11+ (API 30+) devices allow package discovery via `canLaunchUrl`.

---

## 11. Backend & Database Architecture (`backend/`)

The backend is an asynchronous **FastAPI** service running on Python 3.10+ backed by **SQLAlchemy 2.0** and SQLite (`backend/kalasetu.db`).

### 11.1 Entity-Relationship Model

```mermaid
erDiagram
    ARTISANS ||--o{ PRODUCTS : owns
    PRODUCTS ||--o{ SOCIAL_DRAFTS : has
    
    ARTISANS {
        string id PK
        string name
        string phone UK
        string craft_type
        string location_cluster
        string state
        string experience_years
        string pehchan_id
        string preferred_language
        datetime created_at
    }

    PRODUCTS {
        string id PK
        string artisan_id FK
        string title
        string title_hi
        text description
        text description_hi
        float price
        string image_url
        string category
        text tags
        string status
        datetime created_at
        datetime updated_at
    }

    SOCIAL_DRAFTS {
        string id PK
        string listing_id FK
        string draft_key
        string image_url
        text caption
        text hashtags
        string source
        boolean edited_by_user
        datetime created_at
        datetime updated_at
    }
```

### 11.2 Core Router Specification:
* `/api/v1/auth`: Phone-based registration, demo OTP validation, and artisan profile lookups.
* `/api/v1/products`: Product catalog listing, category filtering, updates, and idempotent batch offline synchronization (`/sync`).
* `/api/v1/catalog`: Computer vision enhancement (`/enhance-image`), Whisper transcription (`/transcribe`), bilingual listing generation (`/generate-listing`), and unified voice-to-product orchestration (`/voice-to-product`).
* `/api/v1/pricing`: RAG price recommendations (`/suggest`), multimodal image pricing (`/suggest-upload`), and voice pricing (`/suggest-from-voice`).
* `/api/v1/chat`: KalaMitra conversational assistant, navigation actions, starter topics, and voice chat.
* `/api/v1/social`: Social media caption generation and draft persistence.
* `/api/v1/health`: Liveness probe used by mobile connectivity listeners to confirm true internet reachability.

---

## 12. End-to-End System Workflows

### 12.1 Complete Voice-to-Product Stepper Flow

```mermaid
sequenceDiagram
    autonumber
    actor Artisan as Artisan (Mobile App)
    participant UI as Stepper UI
    participant Gateway as FastAPI Gateway
    participant CV as Image Studio
    participant Whisper as Whisper STT
    participant LLM as Cataloger LLM
    participant RAG as Pricing RAG
    participant DB as SQLite DB

    Artisan->>UI: Captures Photo (Step 1)
    UI->>Gateway: POST /api/v1/catalog/enhance-image
    Gateway->>CV: Run 10-stage CV pipeline
    CV-->>Gateway: Return enhanced image path
    Gateway-->>UI: Display Before/After Comparison Slider

    Artisan->>UI: Records Voice Note with Spoken Cues (Step 2)
    UI->>Gateway: POST /api/v1/voice/process
    Gateway->>Whisper: Transcribe with Craft Glossary Prompt
    Whisper-->>Gateway: Return Clean Transcript
    Gateway->>LLM: Generate Bilingual Titles, Descriptions, Tags
    LLM-->>Gateway: Return Bilingual Listing (EN + HI)
    Gateway->>RAG: Compute Cost Floor & Retrieve ChromaDB Benchmarks
    RAG-->>Gateway: Return Price Range & Comparables
    Gateway-->>UI: Populate AI Review (Step 3) & Pricing Assistant (Step 4)

    UI->>Artisan: Plays Hindi Audio Readback of Description & Price
    Artisan->>UI: Confirms & Taps "Publish" (Step 5)
    UI->>Gateway: POST /api/v1/products
    Gateway->>DB: Save Product (status: 'live')
    Gateway-->>UI: Listing Published! Show Social Sharing Launchpad
```

### 12.2 Offline Capture & Reconnection Synchronization

```mermaid
sequenceDiagram
    autonumber
    actor Artisan as Artisan (Offline)
    participant App as Mobile App
    participant Hive as Hive Document Store
    participant Drift as Drift SQLite Queue
    participant Net as Connectivity Monitor
    participant API as FastAPI Gateway
    participant DB as Server DB

    Note over Artisan,Drift: Artisan creates product while offline in cluster
    Artisan->>App: Submits listing
    App->>Hive: Put product (status: 'pendingSync')
    App->>Hive: Mark operation in 'pending_sync_box'
    App->>Drift: Enqueue photo & audio files (status: 'pending')
    App-->>Artisan: Saved locally! Shows "Sync Pending" banner

    Note over Net,API: Artisan reaches area with mobile connectivity
    Net->>App: Network change detected -> Ping /api/v1/health
    API-->>App: HTTP 200 OK (Connection verified)

    App->>Drift: Read pending media queue items
    loop For each queued file
        App->>API: Upload media file (POST /uploads)
        API-->>App: Return remote URL
        App->>Drift: Mark QueueItem completed
    end

    App->>Hive: Read all 'pendingSync' products
    App->>API: POST /api/v1/products/sync (Batch payload)
    API->>DB: Upsert into ProductDB (status: 'live')
    DB-->>API: Persisted
    API-->>App: ProductSyncResponse (synced_count: N)
    App->>Hive: Update local products to 'live' & clear pending box
    App-->>Artisan: Show Notification: "All items synced to cloud!"
```

---

## 13. Security, Privacy & Data Governance

* **Artisan Data Sovereignty:** Artisan mobile numbers and optional government Pehchan IDs are stored exclusively in the relational database and are never passed to external LLM completion prompts.
* **Scoped Media Uploads:** Uploaded media files are hashed with UUID prefixes (`uuid.uuid4().hex`) and segregated into dedicated directories (`/uploads/raw`, `/uploads/enhanced`, `/uploads/audio`, `/uploads/products`) to prevent directory traversal vulnerabilities.
* **API Abuse Prevention:**
  * Chat endpoint (`/api/v1/chat/message`): Capped at 20 requests per minute per client IP.
  * Social helper (`/api/v1/listings/{id}/social-draft`): In-memory sliding window allows a maximum of 5 regenerations per hour per listing.
* **Accessible Prompt Guardrails:** System prompts enforce clean plain-text formatting (no raw asterisks) and restrict responses strictly to craft guidance, government schemes, and marketplace assistance.

---

## 14. Technology Stack Summary

| Layer | Component | Technology | Architectural Role |
|---|---|---|---|
| **Mobile Client** | Core App | Flutter 3.x / Dart 3.x | Cross-platform UI for Android, iOS, and Web. |
| | State Management | Flutter Riverpod 2.x | Reactive dependency injection and state isolation. |
| | Media Sync Queue | Drift (SQLite) | Persistent background queue with exponential backoff retries. |
| | Document Store | Hive | High-speed, synchronous on-device NoSQL storage for catalog data. |
| | Navigation | GoRouter | Declarative routing with route-level authentication guards. |
| | Label Generation | Dart `pdf` & `printing` | On-device PDF rendering for shipping labels with ONDC QR codes. |
| **Backend API** | Web Framework | FastAPI (Python 3.10+) | Asynchronous API gateway with OpenAPI documentation. |
| | Database & ORM | SQLite 3 & SQLAlchemy 2.0 | Embedded relational persistence for profiles, products, and social drafts. |
| | Concurrency | `starlette.concurrency` | Threadpool dispatch for blocking OpenCV/rembg CPU tasks. |
| **AI & ML** | Computer Vision | `rembg` (U²-Net), OpenCV, Pillow | Background removal, CLAHE lighting fix, gray-world white balance, 1080x1080 canvas. |
| | Speech-to-Text | Whisper Large v3 | Regional audio transcription with craft glossary vocabulary prompting. |
| | Primary LLM | Groq Cloud (`gpt-oss-120b`) | Ultra-fast structured JSON cataloging and KalaMitra conversational agent. |
| | Multimodal LLM | Google Gemini (`gemini-3.6-flash`) | Multimodal vision analysis for social media generation. |
| | Vector Store | ChromaDB | Cosine similarity vector index over real Indian handicraft listings. |
| | Embeddings | Gemini `embedding-001` | 3072-dimensional multimodal unified vector embeddings. |
| | Audio Analysis | `ffmpeg` (volumedetect) | Native audio energy analysis to reject silent recordings before inference. |

---

## 15. Verification, Test Suites & Device Validation

| Test Suite | Path | Verification Focus |
|---|---|---|
| **Chat Tool Actions** | `backend/tests/test_chat_actions.py` | Validates that natural language queries trigger structured in-app actions (`update_product_status`, `filter_catalogue`, `sync_pending`). |
| **Chat API & Guardrails** | `backend/tests/test_chat_api.py` | Tests rate limiting (HTTP 429), language adaptation, and system prompt constraints. |
| **Backend Integration** | `backend/tests/test_api.py` | Tests authentication flows, product CRUD, and batch offline synchronization (`/sync`). |
| **Voice Integration** | `backend/tests/test_voice_integration.py` | Tests audio volume checks, craft glossary prompt injection, and end-to-end voice-to-product. |
| **Image Enhancement** | `backend/tests/test_image_pipeline_integration.py` | Tests threadpool background removal, CLAHE lighting, auto-crop, and canvas sizing. |
| **Frontend Direct Actions** | `frontend/test/chatbot_direct_actions_test.dart` | Tests Riverpod chat notifier mutating Hive product status with undo capability. |
| **Catalog Flow** | `frontend/test/add_product_flow_test.dart` | Tests multi-step draft progression, draft resumption, and validation. |
| **Artisan Analytics** | `frontend/test/artisan_analytics_test.dart` | Tests Fair Wage Premium calculations against middleman baselines. |
| **Packaging & Orders** | `frontend/test/my_orders_chip_test.dart` | Tests order fulfillment status transitions and craft packaging advisory logic. |
| **Physical Device Checks** | Live Hardware | Verified on Samsung Galaxy SM-M346B (Android 14 / API 34) ensuring `<queries>` package visibility and smooth hardware camera/mic access. |

---

*Document maintained under `docs/ARCHITECTURE.md` as the definitive technical architectural specification for KalaSetu.*
