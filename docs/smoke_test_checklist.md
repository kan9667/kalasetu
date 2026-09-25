# Physical-Device Smoke-Test Checklist

> [!IMPORTANT]
> **Status: PENDING FIELD EXECUTION.**
> The following checklist specifies the exact test protocol required for target physical Android and iOS devices prior to pilot deployment. These tests have been verified in automated test harnesses and mock/loopback environments, but **MUST NOT** be claimed as passed until physically executed on hardware devices.

---

## Environment Prerequisites

1. **Isolated Non-Production Backend**:
   - Backend configured strictly with:
     ```env
     ENVIRONMENT=development  # (or test, never production)
     SMS_PROVIDER=mock
     ENABLE_REAL_SMS=false
     ALLOW_DEMO_OTP=true
     ```
2. **Designated Test Accounts & OTP Acquisition**:
   - **Account A (Primary Demo Phone)**: `9876543210`. The fixed OTP `123456` applies **ONLY** to this designated number in non-production environments with `ALLOW_DEMO_OTP=true`.
   - **Account B (Secondary Test Phone)**: Any valid 10-digit Indian test number (e.g. `9876543211`). Backend generates a random 6-digit cryptographic OTP (`secrets.randbelow(900000) + 100000`). In this non-production test mode, obtain Account B's generated `demo_otp` from the authorized isolated non-production login challenge response (`response["demo_otp"]`). `MockSmsProvider` records messages in memory; it does not log OTPs. Do not add OTP logging, weaken authentication, or introduce another fixed OTP.
3. **Application Package Verification**:
   - Do not assume an unverified package name. On connected Android devices, verify the installed package identifier using:
     ```bash
     adb shell pm list packages | grep kalasetu
     ```
     (Configured as `applicationId = "com.kalasetu.kalasetu"` in `frontend/android/app/build.gradle.kts`).
4. **App Build**: Fresh debug or staging APK/IPA installed via `flutter run` or `flutter install`.

---

## Test Execution Matrix

### 1. Test-Mode Login (Account A)
- **Preconditions**: Fresh app launch; unauthenticated state; backend running.
- **Action**:
  1. Navigate to Phone Login screen.
  2. Enter primary demo phone number (`9876543210`).
  3. Tap "Send OTP".
  4. On OTP screen, enter demo code `123456`.
- **Expected Invariant**:
  - Receives authoritative JWT bearer token from backend.
  - Transitions to `ActiveSessionMode.artisan` and persists token in platform `flutter_secure_storage`.
  - Navigates to HomeScreen.
  - *Negative Check*: Entering an invalid code (e.g. `999999`) shows typed failure; no fake user profile or bypass occurs.
- **Field Result**: `[ ] Pending Physical Run`

---

### 2. Offline Capture
- **Preconditions**: Artisan logged in; app on HomeScreen.
- **Action**:
  1. Toggle device into **Airplane Mode** (disable Wi-Fi and Cellular data).
  2. Tap "+" Floating Action Button to start "Add Product".
  3. Step 1: Capture product photo using physical device camera.
  4. Step 2: Record a brief voice description or enter manual Hindi/English text.
  5. Step 3: Enter materials cost (`₹250`) and labor hours (`3 hours` @ `₹100/hr`).
  6. Step 4: Review calculated cost floor (`₹550`).
- **Expected Invariant**:
  - Device camera decodes image into immutable byte slice without OOM.
  - Draft snapshot persisted atomically to `draft_box` (`active_draft_snapshot`).
  - Inputs from Steps 1–4 are fully intact.
  - Outbox reflects pending operations; queue badge indicator increments.
  - No crash, unhandled exception, or blank screen on lost connection.
- **Field Result**: `[ ] Pending Physical Run`

---

### 3. Process Lifecycle Recovery: Task-Switcher Dismissal vs. Force-Stop
- **Preconditions**: Offline draft with captured media from Step 2 exists; app on Step 4 or Step 5.
- **Action 3a (Task-Switcher Dismissal / Background Pause)**:
  1. Leave device in Airplane Mode.
  2. Swipe away app from Android overview / iOS app switcher.
  3. Tap app icon to resume.
  - **Expected Invariant 3a**: UI resumes active draft flow; controllers and form fields remain intact; non-destruction of active draft state.
- **Action 3b (Hard Force-Stop)**:
  1. Leave device in Airplane Mode.
  2. Identify package ID (`adb shell pm list packages | grep kalasetu`).
  3. Execute explicit force-stop via ADB:
     ```bash
     adb shell am force-stop com.kalasetu.kalasetu
     ```
  4. Relaunch app from launcher icon.
  - **Expected Invariant 3b**: `active_draft_snapshot` is hydrated from Hive disk storage on startup without corruption; Step 5 review displays captured photo and inputs; Drift SQLite database preserves all queued outbox records across process death without truncation or data loss.
- **Field Result**: `[ ] Pending Physical Run`

---

### 4. Reconnect Sync: Unapproved Draft vs. Approved Publication
- **Preconditions**: Outbox operations exist in Drift queue; device in Airplane Mode.
- **Scenario 4a (Unapproved Draft Sync)**:
  1. Artisan created listing offline but stopped before Step 5 review (or saved as draft without tapping "Approve & Publish").
  2. Disable Airplane Mode (restore connectivity).
  3. Trigger queue drain.
  - **Expected Invariant 4a**: Draft item and media asset sync to backend. Server commits item with `status='draft'` (`is_live=False`). **Crucial check**: Product remains strictly unpublished and unlisted in the public catalog; no public revision is created without explicit approval.
- **Scenario 4b (Explicitly Reviewed & Approved Offline Operation)**:
  1. Artisan completed Step 5 review offline, verified preview render, and explicitly tapped "Approve & Publish", enqueueing `APPROVE_PUBLISH` in outbox dependency chain (`CREATE -> MEDIA_UPLOAD -> ATTACH_MEDIA -> APPROVE_PUBLISH`).
  2. Disable Airplane Mode (restore connectivity).
  3. Trigger queue drain.
  - **Expected Invariant 4b**: Outbox executes in dependency order. Client submits `POST /api/v1/products/{id}/approve-and-publish` with `revision` and `content_hash`. Server verifies revision freshness, content hash parity, ready media asset, and independently recalculates integer paise cost floor from stored parameters (`materials_paise + labor_hours * hourly_rate_paise + transport_paise + overhead_paise`), verifying `price_paise >= cost_floor_paise`. Listing transitions to `published` ONLY upon authoritative server validation and HTTP 200.
- **Field Result**: `[ ] Pending Physical Run`

---

### 5. Account Switch with Pending Work (Controlled Network Timing)
- **Preconditions**: Artisan A has pending offline operations in Drift outbox; device is offline.
- **Action**:
  1. With Account A's items pending in outbox, open Profile -> Logout while offline. Account A's items remain durably queued in Drift with `owner == 'artisan_A'`.
  2. Fresh login requires network connectivity to verify credentials against the backend. Temporarily restore connectivity (disable Airplane Mode).
  3. On Login screen, enter Account B's phone (`9876543211`). Tap "Send OTP".
  4. Obtain Account B's generated `demo_otp` from the authorized isolated non-production login challenge response. Enter the OTP; do not look for or add OTP logs.
  5. Account B logs in and receives token.
  6. Trigger queue drain or observe automatic sync while authenticated as Account B.
  7. Log out of Account B, reconnect as Account A (`9876543210`, OTP `123456`), and trigger sync.
- **Expected Invariant**:
  - While authenticated as Account B, Account A's pending queue operations **DO NOT** dispatch or drain under Account B's token.
  - Private media cache directories isolate Account A's files (`acc_<hash_A>`) from Account B (`acc_<hash_B>`).
  - Account A's operations remain intact in queue with `statusPending` and `retryCount == 0`.
  - Upon logging back into Account A, Account A's queued operations resume and dispatch under Account A's credentials.
- **Field Result**: `[ ] Pending Physical Run`

---

### 6. Exact-Media Review
- **Preconditions**: App on Step 5 ("Review & Confirm") screen.
- **Action**:
  1. Inspect displayed preview image.
  2. Tap "Enhance Image" (if online) or observe raw photo fallback.
  3. Note displayed asset.
  4. Tap "Retake Photo" and capture a completely different object.
- **Expected Invariant**:
  - The rendered preview matches the exact selected asset (raw photo or enhanced derivative).
  - Retaking photo immediately invalidates previous enhancement, clears verified media ID, and forces generation bump.
  - The "Publish" button is disabled until the newly captured image renders and is byte-verified against `reviewedMediaChecksum`.
- **Field Result**: `[ ] Pending Physical Run`

---

### 7. Explicit Publication Boundary
- **Preconditions**: Step 5 review verified; listing price set at or above cost floor.
- **Action**:
  1. Ensure price field is at or above integer paise floor (e.g. `₹600` >= `₹550`).
  2. Tap "Approve & Publish".
- **Expected Invariant**:
  - Client sends `POST /api/v1/products/{id}/approve-and-publish` containing `revision` and canonical `content_hash`.
  - Server recalculates integer paise floor from stored parameters (`materials_paise + labor_hours * hourly_rate_paise + transport_paise + overhead_paise`) and validates `db_item.price_paise >= authoritative_floor_paise`.
  - Server checks revision freshness, verified ready media asset, and content hash parity before creating immutable `ProductRevisionDB` snapshot.
  - Product does NOT appear as `published` in public catalog until server confirms with HTTP 200.
- **Field Result**: `[ ] Pending Physical Run`

---

---

### 8. Unpublish
- **Preconditions**: A published product exists in the artisan's catalog.
- **Action**:
  1. Open product details or catalog screen.
  2. Tap "Unpublish" on the published item.
- **Expected Invariant**:
  - Item status immediately transitions to `ProductStatus.pendingUnpublishSync`.
  - Server receives `POST /api/v1/products/{id}/unpublish` with `expected_revision` and 64-character hex `content_hash`.
  - Upon server confirmation, item transitions to `draft` and is removed from public view.
  - Existing approved revision history is preserved in `product_revisions` audit trail.
- **Field Result**: `[ ] Pending Physical Run`

---

## Voice Transcription & Bilingual Listing Smoke-Test Suite

> [!NOTE]
> **Verification Boundary Notice:**
> The state transitions, audio cryptographic fingerprint validation, single-flight deduplication, and account-isolation barriers below have been proved via automated test harnesses using mocked transport and loopback servers. These tests verify protocol correctness and that the tested race scenarios pass, but **DO NOT** constitute physical-device hardware microphone validation, real-world acoustic/noise testing, or live third-party speech/LLM provider verification. Physical execution on target devices is required.

### 9. Meaningful Hindi/English Recording → Transcript → Bilingual Listing & Tags
- **Preconditions**: Device online; artisan logged in; Add Product flow on Step 2 ("Describe").
- **Action**:
  1. Tap the microphone icon to record audio on the physical device.
  2. Speak a clear descriptive sentence in Hindi (e.g., *"यह हाथ से बना हुआ मिट्टी का पानी का घड़ा है, जिस पर पारंपरिक चित्रकारी की गई है"*) or English (*"Handmade terracotta water jug with traditional floral hand painting"*).
  3. Stop recording and listen back via playback control.
  4. Submit for transcription and listing generation.
- **Expected Invariant**:
  - Audio file recorded with valid container format (M4A/WAV/MP3).
  - Waveform and audio playback function without distortion or crashes.
  - Speech service transcribes audio into accurate text matching the spoken language.
  - Catalog listing generation returns a structured bilingual listing containing:
    - English Title & Hindi Title (`title_en`, `title_hi`).
    - English Description & Hindi Description (`description_en`, `description_hi`).
    - Craft category matching the product (e.g. *Pottery & Ceramics*).
    - Relevant craft tags (e.g. *terracotta*, *hand-painted*, *eco-friendly*).
  - Review screen displays generated titles and descriptions clearly.
- **Field Result**: `[ ] Pending Physical Run`

---

### 10. Greeting-Only Recording → Clarification Prompt
- **Preconditions**: Add Product flow on Step 2.
- **Action**:
  1. Record an audio clip containing only a conversational greeting or non-descriptive filler (e.g., *"नमस्ते भाई साहब"*, *"Hello sir"*, *"Good morning"*).
  2. Submit recording for transcription and listing generation.
- **Expected Invariant**:
  - Voice service transcribes the greeting faithfully.
  - Catalog/LLM service identifies the input as lacking craft details and returns a clarification status or prompting response.
  - UI displays an actionable clarification cue requesting essential craft attributes (e.g., *"Please mention the craft material, technique, or product type"*).
  - UI **DOES NOT** hallucinate a generic product listing or fabricate imaginary dimensions, materials, or prices.
- **Field Result**: `[ ] Pending Physical Run`

---

### 11. Slow / Unavailable Listing Provider → Truthful Pending / Failure / Fallback State
- **Preconditions**: Add Product flow on Step 2; physical network simulator active or simulated provider delay/failure.
- **Action**:
  1. Record and submit a voice description.
  2. While request is in-flight, introduce artificial latency (>15s) or drop Wi-Fi/Cellular connectivity to simulate timeout or HTTP 503/504 gateway error.
- **Expected Invariant**:
  - UI displays an honest, non-blocking pending indicator (no indefinite freeze or unhandled red screen).
  - Upon network timeout or failure, UI presents a truthful failure banner: *"Listing generation delayed / network unavailable"*.
  - An explicit "Retry" button is provided.
  - Manual text fields for title and description remain fully accessible and editable as an immediate fallback.
  - The recorded audio note and completed transcript are safely preserved—neither is erased on listing failure.
  - UI **NEVER** displays synthetic or mock listings masquerading as a successful AI result.
- **Field Result**: `[ ] Pending Physical Run`

---

### 12. Artisan Edits Preserved When Late Results Arrive
- **Preconditions**: Add Product flow on Step 2 or 3; slow network connection.
- **Action**:
  1. Submit a voice note for listing generation.
  2. While the network flight is unresolved (or after an initial retry), artisan manually types a custom English title (e.g., *"My Masterpiece Terracotta Vase"*) and Hindi description in the form fields.
  3. The slow network response from the initial listing request arrives.
- **Expected Invariant**:
  - The artisan's manual edits are strictly preserved and **NOT** overwritten by late-arriving AI suggestions.
  - System verifies per-field edit generations (`titleEnEditGen`, `titleHiEditGen`, `descEnEditGen`, `descHiEditGen`); artisan edits are preserved because per-field edit generations advanced beyond the operation baseline (`baseline_edit_gens`). Note: title/description edits do not bump `listingInputGeneration`.
  - Degraded or late status indicators update truthfully without regressing form values.
- **Field Result**: `[ ] Pending Physical Run`

---

### 13. Recording Retake, App Termination / Restart, and Reconnect Recovery
- **Preconditions**: Draft with voice note exists; device in flight.
- **Action 13a (Recording Retake Invalidation)**:
  1. Record voice note and generate listing.
  2. Tap "Retake Audio" and record a different product description.
  - **Expected Invariant 13a**: Previous transcription and listing results are immediately invalidated. Cached operation IDs are cleared, and `voiceInputGeneration` is incremented. No stale suggestions from the old audio leak into the new draft.
- **Action 13b (App Termination & Restart Recovery)**:
  1. Record voice note and initiate listing generation.
  2. While operation is pending / in-flight, immediately force-kill app via task switcher or ADB (`am force-stop`).
  3. Relaunch app and navigate back to the active draft.
  - **Expected Invariant 13b**: The active draft hydrates from `draft_box` with recorded audio and immutable snapshot intact. `reconcileDraftOperations()` recovers the in-flight operation from `ai_operations_box`. If the network flight was interrupted or unpersisted locally, replay may resend the request using the exact same idempotency key and frozen payload; the server deduplicates via this key, avoiding duplicate server-side processing.
- **Action 13c (Reconnect Recovery)**:
  1. With app running and network restored, allow the recovered in-flight operation to complete.
  - **Expected Invariant 13c**: The listing result populates the draft form cleanly and persists atomically to `active_draft_snapshot`.
- **Field Result**: `[ ] Pending Physical Run`

---

### 14. Account Switch During Processing
- **Preconditions**: Dual physical accounts (Account A: `9876543210`, Account B: `9876543211`).
- **Action**:
  1. Log in as Account A.
  2. Initiate voice recording and submit listing generation.
  3. While listing generation is in-flight or cached locally, log out of Account A.
  4. Log in as Account B.
  5. Inspect the "Add Product" flow and draft state under Account B.
  6. Log out of Account B and log back in as Account A.
- **Expected Invariant**:
  - Account B's draft is clean and unpopulated; Account A's audio, transcript, and listing suggestions **DO NOT** appear under Account B.
  - Any late response arriving for Account A while Account B is active is safely discarded (due to owner/session generation mismatch) and never written to Account B's draft snapshot.
  - Upon logging back into Account A, Account A's draft state and cached operation records remain intact and recoverable.
- **Field Result**: `[ ] Pending Physical Run`

---

### 15. Explicit Human Approval Still Required Before Publication
- **Preconditions**: Step 3 (Review AI Listing) complete; bilingual titles, descriptions, and tags generated.
- **Action**:
  1. Attempt to navigate directly to catalog or publish boundary without reviewing Step 5.
  2. Proceed through Step 4 (Pricing & Cost Floor) and land on Step 5 ("Confirm & Publish").
  3. Verify preview of photo, bilingual text, tags, and price.
  4. Inspect database and backend catalog state prior to tapping "Approve & Publish".
  5. Tap "Approve & Publish".
- **Expected Invariant**:
  - No AI-generated text, tags, or suggested pricing can become public automatically without explicit human review.
  - Backend database confirms item remains strictly in `draft` or `awaiting_approval` state until Step 5 approval action is executed.
  - Tapping "Approve & Publish" sends explicit approval payload containing `revision` and SHA-256 `content_hash`.
  - Server confirms integer paise floor compliance (`price_paise >= cost_floor_paise`) and returns HTTP 200 before item transitions to `published`.
- **Field Result**: `[ ] Pending Physical Run`

---

## Verification Sign-Off

| Role | Name / Identifier | Signature / Date | Status |
| --- | --- | --- | --- |
| **QA / Field Lead** | *Unassigned* | *Pending* | Not Executed |
| **Engineering Lead** | *Unassigned* | *Pending* | Not Executed |
