# Demo Video — KalaSetu

The demo video is **optional**, but strongly recommended for demonstrating the working prototype to the Smart India Hackathon evaluators.

---

## Demo Video Link

> [!IMPORTANT]
> Paste your public or unlisted YouTube / Google Drive video URL below. Ensure permissions are set to **"Anyone with the link can view"**.

- **Video URL:** `<PASTE_YOUTUBE_OR_GOOGLE_DRIVE_VIDEO_LINK_HERE>`

---

## Video Demonstration Flow

The demo video walks evaluators through the core artisan user journey:

1. **Problem Context (0:00 - 0:45)**
   - Overview of rural Indian artisans losing digital market access post-fairs due to literacy, cataloging, and photography hurdles.

2. **AI Photo Studio (0:45 - 1:30)**
   - Uploading a raw, cluttered phone camera photo of an authentic handicraft (e.g. wood carving / blue pottery).
   - Automated rembg background excision, shadow synthesis, CLAHE contrast balance, and square 1080×1080 output.

3. **Regional Voice-to-Listing (1:30 - 2:30)**
   - Recording a voice note in Hindi or regional dialect describing the craft, materials, and effort.
   - Whisper transcription with craft-domain vocabulary biasing.
   - LLM generation of SEO-optimized English title & description paired with culturally resonant Devanagari Hindi copy.
   - Automated quarantine of raw production costs from customer-facing text.

4. **Fair Wage Cost Floor & Dynamic Pricing (2:30 - 3:30)**
   - Visual breakdown of the non-negotiable cost floor (`Materials + Labor Hours × Fair Wage + Transport + Overhead`).
   - Comparison with ChromaDB RAG vector benchmarks across Indian artisan marketplaces (FabIndia, Okhai, Etsy).
   - Demonstrating that the system prevents algorithms from undercutting the artisan's floor.

5. **KalaMitra AI Assistant & Voice Actions (3:30 - 4:15)**
   - Natural language voice chat managing inventory, filtering catalogs, and checking government artisan schemes.

6. **Offline-First Synchronization (4:15 - 5:00)**
   - Airplane mode test: drafting a product offline into local Drift database and auto-syncing when internet connectivity resumes.
