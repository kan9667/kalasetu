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

## Verification Sign-Off

| Role | Name / Identifier | Signature / Date | Status |
| --- | --- | --- | --- |
| **QA / Field Lead** | *Unassigned* | *Pending* | Not Executed |
| **Engineering Lead** | *Unassigned* | *Pending* | Not Executed |
