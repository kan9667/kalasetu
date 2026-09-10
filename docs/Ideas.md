
# KalaSetu — Implementation Phases & Future Scope

---

## Phase 1: High-Impact & Core Demo Features (Top Priority)

* **Spoken Cues on Voice Description Screen (`Step 2`)**:
  - Add visual & audio prompt chips guiding the artisan on **what to say**:
    - *"सामग्री (Materials used: clay, silk, brass)"*
    - *"बनाने में लगा समय (Hours of labor spent)"*
    - *"विशेष तकनीक (Special technique/heritage)"*
  - This directly improves Whisper transcription accuracy and Gemini cost-extraction precision.

* **Universal Text-to-Speech (TTS) Read-Back**:
  - Add a floating or header **"सुनें" (Listen)** audio button on every screen (Catalogue, Product Details, Pricing Step) so non-literate artisans can hear descriptions and pricing explanations read aloud in Hindi.

* **"My Orders" & Packaging Advisory Screen**:
  - An **Orders Tab/Screen** displaying received orders, buyer location, status (*New, Packed, Shipped*).
  - **AI Packaging Suggestions**: Tailored advice based on craft category (e.g., for *Terracotta/Pottery*: double-wall corrugated box, straw/shredded paper cushioning; for *Chanderi Silk*: moisture-proof wrapping).

* **Artisan Performance & Revenue Analytics**:
  - A dashboard widget in Profile or Home showing:
    - Total sales (₹)
    - Most popular crafts & views
    - Fair wage premium earned vs middleman rate.

---

## Phase 2: AI & ML Pipeline Features

* **Artisan Help Chatbot ("LLM as an Agent" / KalaMitra)**:
  - A conversational voice/text assistant where artisans can ask questions in Hindi:
    - *"मेरी कुल्हड़ की बिक्री कैसे बढ़ाऊं?"* (How do I increase sales?)
    - *"मिट्टी के बर्तन को सुरक्षित पैक कैसे करें?"* (How to safely pack pottery?)

* **Printable Artisan Story & Packaging Label**:
  - A 1-click generator for a printable package label with:
    - Artisan name & village
    - Bilingual craft story & wash-care instructions
    - ONDC / QR code linking to the artisan's profile.

* **Image Pipeline Latency Optimization**:
  - Optimize the background removal and lighting correction pipeline in `ML/image_pipeline/` and add an interactive Before/After preview slider in Step 1.

---

## Phase 3: Polish & Hackathon Readiness

* **Voice-First Onboarding**:
  - 3-slide welcome walk-through with automatic voice guidance explaining: *Photo lo $\to$ Bolkar batao $\to$ Sahi daam pao*.

* **UI Sequencing & State Transition Polish**:
  - Smooth hero animations and micro-interactions when moving between draft steps and catalogue cards.

* **Edge-Case & Offline Graceful Handling**:
  - Visual sync indicators, robust retry handling for degraded 2G/poor cellular networks, and local offline draft recovery.

---

## Future Scope

1. **Live ONDC (Open Network for Digital Commerce) Integration**:
   - Implement full Beckn protocol BAP/BPP gateway connections for direct live marketplace cataloging, buyer-seller discovery, and automated order intake.
   - Plug into automated logistics and shipping aggregators (Shiprocket, Delhivery, India Post).

2. **Pan-India Multilingual & Dialect Expansion**:
   - Expand voice cataloging, LLM generation, and TTS beyond Hindi and English into 12+ Indic languages (Tamil, Telugu, Kannada, Bengali, Odia, Gujarati, Marathi, Assamese).
   - Fine-tune ASR biasing for regional craft dialects and localized heritage terminology (e.g., *Ikat*, *Kalamkari*, *Dhokra*, *Bidriware*).

3. **Augmented Reality (AR) Product Visualizer**:
   - WebAR and mobile AR support allowing prospective domestic and international buyers to view 3D scale models of pottery, handicrafts, and brassware in their physical living space.

4. **Micro-Credit & Working Capital Integration (FinTech Linkage)**:
   - Use verified artisan catalog volume and sales velocity to generate alternative credit scores for collateral-free micro-loans through OCEN and government initiatives (PM SVANidhi, Mudra Yojana).

5. **Production Cloud Hardening & Push Services**:
   - Transition media storage from local filesystem to S3 / Cloudflare R2 with CDN acceleration.
   - Integrate Firebase Cloud Messaging (FCM) for push notifications and establish Alembic database schema migrations.


