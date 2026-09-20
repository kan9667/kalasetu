# KalaSetu / Karigar Setu — Detailed Phases & Future Scope

Last roadmap update: 20 September 2026.

## 1. How to use this roadmap

This document expands the project phases in [AGENTS.md](../AGENTS.md).
[architecture.md](architecture.md) describes the implementation and its known gaps.
A roadmap item is a requirement or proposal, not proof that it has shipped.

The previous version used “core demo”, “AI features”, and “hackathon polish”
as Phase 1–3. Those labels are superseded by the trust-first phases below.
All original product ideas are retained in Section 8, with their new placement.
Existing screens should be audited and improved rather than rebuilt unnecessarily.

Status vocabulary:

- **Implemented / locally tested:** evidence exists from automated local tests.
- **Open:** a reproduced defect or required deliverable remains.
- **Planned:** work has not been accepted as complete.
- **Simulated:** uses demo, mocked, or local-only behavior.
- **Externally verified:** separately demonstrated with an actual provider,
  physical device, or marketplace environment; record which one.

### Phase overview

| Phase | Outcome | Scope boundary |
| --- | --- | --- |
| 0 — Prototype stabilization | A reproducible, honestly labelled demo | No claim of live marketplace or production operation |
| 1 — Trust and data integrity | Safe ownership, approval, pricing, authentication and offline replay | Local prototype verification; close known integrity defects |
| 2 — Production foundation and controlled pilot | Durable services, bounded AI jobs, operational readiness and device validation | No marketplace availability claim without integration evidence |
| 3 — Marketplace and operations integration | Approved listings reach real channels; orders and operations become authoritative | Channel-by-channel rollout, not an all-at-once launch |
| Future scope — Optional expansion | More languages, immersive discovery and partner-led services | Requires separate prioritization and approval |

### Current checkpoint — Phase 1 verification closed, physical pilot pending

The latest comprehensive local verification on the Phase 1 branch reported
**150 backend tests passed, 1 skipped; 227 Flutter tests passed; clean Flutter
analysis (0 issues) and git diff whitespace checks (0 issues)**. The skipped real
image-model test is opt-in through `RUN_REMBG_TESTS=1`.

The three previously open queue-identity regressions are now resolved and verified
with deterministic regression tests:

1. **Originating artisan binding**: Synchronous identity capture at the repository
   boundary (`RequestSessionContext.capture()`) and execution zone inheritance prevent
   a request started by artisan A from ever being queued or dispatched as artisan B
   after an account switch or online failure (`ownership_lifecycle_test.dart`,
   `queued_dispatch_test.dart`).
2. **Ownerless outbox quarantine**: Outbox records without an owner strictly fail closed
   (“missing owner is not authorization”). Recoverable records are restored from payload
   snapshots; unrecoverable records transition to `statusUserActionRequired` quarantine
   rather than replaying under the active artisan (`ownership_lifecycle_test.dart`).
3. **Backend scope enforcement**: Operations persist originating `backend` origin at
   enqueue time. `AuthInterceptor` validates both outgoing request URI origin
   (`options.uri`) and active client configuration (`ApiConfig.baseUrl`) against
   the operation's captured backend origin both before and after token retrieval,
   blocking cross-backend replay (`queued_dispatch_test.dart`).
4. **Pre-interceptor race protection**: Pausing between repository session validation
   and `AuthInterceptor` dispatch during an account switch proves 0 transport requests
   reach the wire, preserving queued work and idempotency keys with `retryCount == 0`.

**Operational boundaries and verification separation**:
- **Automated verification**: Confirms correctness of data structures, cryptographic
  hashes, cost-floor enforcement, session boundary transitions, and HTTP contracts in
  isolated SQLite/mock/loopback environments.
- **Physical-device testing**: Camera hardware sensors, microphone background interruptions,
  WorkManager OS scheduling, low-memory pressure, and battery restrictions are separate
  verification boundaries requiring execution on physical mobile hardware (see Section 4.7).
- **Carrier SMS delivery**: Live cellular delivery via 2Factor remains disabled
  (`ENABLE_REAL_SMS=false`) to protect API credits and budget; carrier delivery is a
  separately authorized pilot step.
- **Future architectural phases**: PostgreSQL/Supabase with RLS, cloud object storage,
  durable worker queues, and GeM/ONDC marketplace integration remain deferred to Phase 2 and 3.


## 2. Rules that apply to every phase

1. **Approve exact content:** Publication requires explicit artisan approval of
   the same revision, bilingual text, tags, selected image and price that go live.
   Edits invalidate approval. A chatbot, worker, exporter or retry cannot bypass it.
2. **Never undercut the cost floor:** Enforce integer-paise calculations on the
   server using materials + labor hours × hourly rate + transport + overhead.
   Reject missing/invalid inputs and non-finite or negative values as appropriate;
   never accept a client-calculated floor as authority.
3. **Preserve offline work:** Capture media and draft state durably before reporting
   success. Retry, logout, migration and corruption recovery must not silently erase it.
4. **Isolate tenants and backends:** Bind private data, cached media and operations
   to their originating artisan and backend. Unknown provenance is a recovery case,
   not permission to adopt the currently logged-in account.
5. **Expose degraded results:** Raw-image fallback, unavailable models, uncertain
   transcription and missing comparable-price data must be visible in API and UI.
6. **Keep demonstrations truthful:** Sample orders, revenue, NGO access, marketplace
   badges and model mocks must never look like verified real activity.
7. **Protect budgets and secrets:** Keep keys server-side and out of source/logs.
   No real SMS, paid model run, public export or production migration is authorized
   merely by inclusion in this roadmap.

## 3. Phase 0 — Prototype stabilization

### Goal and entry condition

Make the existing Flutter/FastAPI demo reproducible and understandable before
adding operational complexity. This is the baseline phase, not a reason to
rebuild features already implemented.

### 0.1 Reproducible development environment

- Document supported Python, Flutter/Dart and platform tooling with exact commands.
- Separate deterministic API tests from optional heavy image/STT model execution.
- Maintain safe placeholders in `.env.example`; do not commit real databases,
  recordings, uploaded media, vector indexes or credentials.
- Provide explicit development/demo configuration and documented startup checks.
- Explain where SQLite, Hive and Drift are used and which stores are authoritative.
- Record migrations already present; Alembic is existing work, not a future invention.

### 0.2 Honest, coherent demonstration flow

- Support capture → voice/manual description → pricing → review → catalogue.
- Preserve a visible offline draft and a clear “waiting to sync” state.
- Label demo OTP, coordinator simulation, sample orders, analytics and QR/profile
  visuals. Never imply a mock login grants artisan API authorization.
- Show useful empty, loading, denied-permission and failed-service states.
- Keep recoverable failures on screen with retry/manual-entry options.

### 0.3 Accessibility and demo polish

- Retain voice-first onboarding: “Photo lo → Bolkar batao → Sahi daam pao”.
- Add or refine Step 2 spoken/visual cues for materials, labor time and technique:
  “सामग्री”, “बनाने में लगा समय”, and “विशेष तकनीक”.
- Preserve Hindi/English labels, readable prices, large touch targets and explicit
  microphone/camera permission explanations.
- Treat prompt chips as a usability hypothesis to evaluate, not a guaranteed
  improvement in ASR or cost extraction.
- Use a documented demo script and sample data clearly separated from live data.

### Deliverables and exit criteria

- Reproducible setup guide, safe demo configuration and a known-limitations list.
- A clean-machine demo completes the basic flow without unexplained crashes.
- Missing AI connectivity produces a labelled fallback rather than fabricated success.
- No missing baseline functionality is hidden by mock data or presentation polish.

### Out of scope

Production cloud services, live marketplace certification, real financial claims
and broad visual redesign.

## 4. Phase 1 — Trust and data integrity

### Goal and entry condition

Make one listing safe to own, generate, review, price, publish and replay after
interruption. Build on the existing prototype; completion is evidence-based.

### 1.1 Authentication, session lifecycle and SMS safeguards

- Enforce server-verified artisan identity and ownership on every private route.
- Preserve the cryptographic OTP lifecycle: expiry, attempt limits, single use,
  resend cooldowns and per-phone/IP limits.
- Keep a durable, concurrency-safe SMS budget ledger. Rejected contenders must
  not destroy the delivered challenge. Uncertain delivery remains counted.
- Maintain dedicated 2Factor integration with redaction of credentials, recipient
  data and OTPs across application and transport logging.
- Keep simulation distinct from real authentication. Store real tokens securely;
  verify migration before removing legacy copies.
- Validate account, backend and session generation across async token retrieval,
  request preparation, response application and streaming.
- Retain offline work on session expiry. Do not trigger repeated OTP requests on
  every screen navigation, transient connection failure or app resume.
- Keep real delivery disabled during automated testing. Carrier verification is
  a separately authorized Phase 2 pilot prerequisite.

### 1.2 Server-owned approval and publication

- Keep creation draft-only and maintain server-owned revision/state transitions.
- Preserve canonical content hashes and immutable approved revision records.
- Require matching revision/hash, verified owned ready media and valid price at
  the atomic approve-and-publish boundary.
- Editing image, bilingual content, tags or price must require fresh review.
- Route relisting and chatbot publish requests through explicit review.
- Preserve truthful pending-approval/pending-unpublish UI until server confirmation.
- Keep soft-deletion tombstones and audit history without leaving deleted items public.
- Test direct API calls, stale approvals, concurrent edits, batch sync and retries.

### 1.3 Durable offline operations — immediate open work

- Capture originating artisan ID, backend scope and operation identity before
  asynchronous mutation work begins, including online attempts that later fail.
- Persist immutable payloads, media checksums, idempotency keys, dependencies,
  result metadata and retry/lease state.
- Preserve the same identity across CREATE → MEDIA_UPLOAD → ATTACH_MEDIA →
  APPROVE_PUBLISH, as well as update, delete and unpublish operations.
- Validate identity before dispatch and before applying success or error responses.
  A session switch cannot transfer queued work to the replacement account.
- Safely migrate ownerless/backend-less legacy records. Recover provenance only
  from trustworthy evidence; otherwise preserve them in an actionable recovery state.
- Bind operations to their original backend. Define an explicit migration procedure
  for legitimate backend changes; URL changes alone do not authorize data movement.
- Reclaim expired leases and replay lost responses without duplicating publication.
- Preserve completed upstream results until their dependents have safely finished.
- Surface 409 conflicts for review; do not silently overwrite or invent a merge.
- Fail closed on corrupt Hive/Drift records without generic box deletion.

### 1.4 Exact-media review and private media lifecycle

- Validate image/audio type, bounded streamed size and checksums server-side.
- Keep originals and enhanced derivatives linked by media lineage.
- Render the selected asset from verified bytes and carry the reviewed checksum
  through durable approval intent, upload and attachment.
- Stage an immutable upload snapshot and compare the server checksum before approval.
- Reject missing, tampered or mismatched media without silent publication retries.
- Cancel stale downloads and clean only request-owned staging files on session changes.
- Keep cache origin/account isolation, authenticated access and bounded disk usage.
- Test photo replacement, process death, upload response loss and account switching.

### 1.5 AI identity, partial failure and recovery

- Persist each AI operation's original input fingerprint, owner, backend, draft,
  generation, request snapshot and idempotency key before dispatch.
- On restart, resume only matching operations; verify saved image bytes before replay.
- Prevent late image, voice, listing or pricing results from overwriting newer input.
- Keep UI timeouts separate from durable operation outcomes.
- Validate generated JSON against schemas and expose component-specific failure states.
- Permit manual correction when STT, translation, enhancement or pricing is unavailable.
- Generated cost estimates remain suggestions requiring confirmation of cost inputs.

### 1.6 Fair-price enforcement and review UX

- Enforce the full cost floor at create, update, batch sync and publish.
- Keep money in integer paise; document unit conversion and rounding rules.
- Recompute dependent suggestions when cost, image, transcript or listing inputs change.
- Explain cost breakdown and degraded/missing market evidence in Hindi and English.
- Provide TTS read-back of the selected listing and price; audio playback is not approval.
- Require an explicit confirmation action and keep it unavailable for unverified media.

### Deliverables

- Tested ownership/authentication, approval, price-floor and media contracts.
- Durable operation identity with migration and recovery behavior documented.
- Regression fixtures for every reproduced defect, including the three current blockers.
- Updated architecture/API documentation and a bounded local-prototype verification report.

### Exit criteria (Automated Verification)

- [x] The three queue-identity failures are fixed and independently reproduced as passing (`ownership_lifecycle_test.dart`, `queued_dispatch_test.dart`).
- [x] Unauthorized/cross-account/cross-backend replay is rejected without data loss (verified in unit and integration suites).
- [x] No public revision bypasses exact-content approval or the cost floor (server-enforced at mutation and publish boundaries).
- [x] Restart, duplicate retry, response loss, stale input, and storage corruption tests pass.
- [x] Both full suites (150 backend, 227 Flutter) and Flutter analysis pass; skipped model test (`test_stage1_standalone_image_pipeline`) explained.
- [x] Documented simulations (demo OTP, coordinator mode, mock SMS, mock ASR) remain clearly labelled.
- [x] Sign-off names the tested revision and operational boundaries rather than asserting universal safety.

### 4.7 Physical-Device Smoke-Test Checklist (Pending Field Execution)

> [!IMPORTANT]
> **Verification Status: PENDING EXECUTION ON PHYSICAL HARDWARE.**
> The following checklist defines the required physical smoke test sequence for Phase 2 pilot onboarding. These steps are verified in automated/mocked environments but have **NOT** yet been executed on physical hardware; do not claim them as passed without running them on target physical Android/iOS devices.

**Environment Prerequisites**:
- **Isolated Non-Production Backend**: Configured strictly with `ENVIRONMENT=development` (or `test`), `SMS_PROVIDER=mock`, `ENABLE_REAL_SMS=false`, and `ALLOW_DEMO_OTP=true`.
- **OTP Acquisition**: Fixed OTP `123456` applies **ONLY** to primary demo number `9876543210`. For Account B (e.g. `9876543211`), backend generates a random 6-digit cryptographic OTP; obtain its generated `demo_otp` from the authorized isolated non-production login challenge response (`response["demo_otp"]`). `MockSmsProvider` records messages in memory; it does not log OTPs. Do not add OTP logging, weaken authentication, or introduce another fixed OTP.
- **Package Verification**: Verify installed package identifier via `adb shell pm list packages | grep kalasetu` (configured as `applicationId = "com.kalasetu.kalasetu"` in `frontend/android/app/build.gradle.kts`) rather than assuming it.

| Step | Action | Expected Invariant & Verification | Field Result |
| --- | --- | --- | --- |
| **1. Test-Mode Login (Account A)** | Enter primary demo phone (`9876543210`), request OTP under `ALLOW_DEMO_OTP=true`, enter fixed `123456`. | Receives JWT bearer token, transitions to authenticated artisan mode, persists credentials in `flutter_secure_storage`. Invalid OTP shows typed failure and creates no fake profile. | Pending Physical Run |
| **2. Offline Capture** | Enable Airplane mode (cellular + Wi-Fi off). Tap "+" to create new listing. Take photo via device camera, record voice note or enter description, input labor hours and materials cost. | Camera frame decodes properly into byte slice. Draft snapshot serialized in `draft_box`. Step 1–4 inputs preserved. Queue badge shows pending items. No crash on lost connection. | Pending Physical Run |
| **3a. Task-Switcher Dismissal** | While offline with active draft, swipe away app from Android overview / iOS app switcher, then reopen. | Activity resumes; draft controllers, inputs, and unenhanced photo remain intact without state destruction. | Pending Physical Run |
| **3b. Hard Force-Stop Recovery** | While offline with active draft, verify package ID and execute `adb shell am force-stop com.kalasetu.kalasetu`. Relaunch app. | `active_draft_snapshot` restored intact from disk on startup; Step 5 review screen displays saved inputs; Drift SQLite queue retains outbox operations across process death without truncation. | Pending Physical Run |
| **4a. Reconnect Sync (Unapproved Draft)** | Create draft offline without tapping "Approve & Publish". Re-enable connectivity and trigger sync. | Draft and media sync to backend (`status='draft'`, `is_live=False`). Product remains strictly unpublished and unlisted in public catalog; no public revision is created. | Pending Physical Run |
| **4b. Reconnect Sync (Approved Operation)** | Complete Step 5 review offline, verify preview, tap "Approve & Publish", enqueueing outbox chain. Re-enable connectivity. | Outbox drains in dependency order (`CREATE -> MEDIA_UPLOAD -> ATTACH_MEDIA -> APPROVE_PUBLISH`). Submits `revision` and `content_hash`. Server verifies revision, content hash, ready media asset, and recalculates integer paise cost floor from stored parameters (`materials_paise + labor_hours * hourly_rate_paise + transport_paise + overhead_paise`), verifying `price_paise >= cost_floor_paise`. Product publishes only on server confirmation. | Pending Physical Run |
| **5. Account Switch with Pending Work** | Queue work as Account A offline. Log out while offline. Temporarily connect network for login screen only; authenticate Account B (`9876543211`, obtaining `demo_otp` from the authorized isolated non-production login challenge response). Trigger sync under Account B. Log out and reconnect Account A. | While authenticated as Account B, Account A's pending outbox operations do **NOT** drain or dispatch under Account B's token. Cache partitions isolate Account A (`acc_<hash_A>`). Logging back into Account A resumes drain under Account A. | Pending Physical Run |
| **6. Exact-Media Review** | In Step 5 review screen, inspect displayed preview image against selected asset. Retake photo. | Preview renders byte-verified image matching selected asset. Photo retake invalidates previous enhancement, clears verified media ID, and disables publishing until fresh preview is verified. | Pending Physical Run |
| **7. Explicit Publication Boundary** | On Step 5 review screen, tap "Publish" / "Approve & Publish". | Submits `POST /api/v1/products/{id}/approve-and-publish` containing `revision` and canonical `content_hash`. Server validates stored listing price against recalculated integer paise floor, ready media asset, and content hash parity. Catalog marks item `published` only on server confirmation. | Pending Physical Run |
| **8. Unpublish** | From catalog or product details, select "Unpublish" on a published product. | UI marks status as `pendingUnpublishSync` until server confirms. Server receives `POST /api/v1/products/{id}/unpublish` with `expected_revision` and `content_hash`, transitions item to `draft`, and removes from public view. | Pending Physical Run |

### Out of scope (Deferred to Phase 2 & 3)

PostgreSQL/Supabase deployment with RLS, cloud object storage (S3/GCS), registered OS background
workers (WorkManager), live GeM/ONDC integration, and authoritative commerce operations.
These remain deferred to their respective phases and must not be used to bypass Phase 1 integrity checks.

## 5. Phase 2 — Production foundation and controlled pilot

### Goal and entry condition

Replace single-node prototype dependencies with operable services while preserving
Phase 1 invariants. Start rollout only after Phase 1 blockers are closed.

### 2.1 Database migration and isolation

- Select the managed PostgreSQL/Supabase deployment and document access paths.
- Port and test Alembic migrations, constraints, revision records, idempotency
  leases and SMS ledger behavior under the target database's concurrency semantics.
- Replace SQLite-specific rowid assumptions with database-appropriate admission logic.
- Enforce RLS where database APIs expose tenant data; retain backend ownership checks.
- Keep privileged service credentials off devices and separate public/private views.
- Add indexes for owner-scoped listings, queue/job lookups and active reservations.
- Rehearse backup, restore, cutover and rollback with record-count/integrity checks.
- Preserve owner/backend provenance during migration; do not rewrite approvals silently.

### 2.2 Private object storage

- Choose a storage provider through a documented cost/security decision.
- Use private objects and bounded, scoped upload/download authorization.
- Preserve checksum validation, immutable asset IDs, media lineage and approval binding.
- Handle expired access links without losing queued work or substituting another asset.
- Define orphan cleanup, retention and deletion policies without deleting referenced media.
- Test multipart/interrupted upload, duplicate completion and cross-tenant object access.
- Keep a local development adapter; a CDN must not accidentally make private media public.

### 2.3 Durable AI worker jobs

- Move expensive image/STT/translation/LLM work into a bounded durable worker queue.
- Return job identity/status instead of requiring a long-lived mobile request.
- Define queued, running, succeeded, failed, degraded and cancelled states.
- Add retry policy, timeouts, lease recovery, deduplication and dead-letter handling.
- Limit worker concurrency and model memory; measure cold-start and queue latency.
- Join pipeline outputs using exact draft revision/input fingerprints, not arrival order.
- Keep workers unable to approve or publish on the artisan's behalf.
- Preserve intermediate successful outputs when another pipeline component fails.

### 2.4 AI quality, latency and comparable-price evidence

- Build a consented evaluation set spanning craft categories, lighting and Hindi/English speech.
- Measure transcription errors, bilingual consistency, structured-output validity,
  enhancement failures and price-floor violations.
- Optimize image latency using measured bottlenecks; provide a before/after slider
  that accurately identifies the asset selected for publication.
- Define Chroma/vector index ownership, embedding versions, provenance, refresh and rebuild.
- Exclude private/unapproved data from public comparable lookup.
- Show confidence and evidence freshness; do not present model estimates as market facts.
- Keep optional live-model evaluation separate from deterministic CI tests.

### 2.5 Flutter background sync and field reliability

- Register supported background execution and preserve foreground/manual sync fallback.
- Reclaim stale leases after termination; never promise guaranteed background execution.
- Test on physical target devices: low storage, process kill, reboot, battery restrictions,
  microphone interruption, camera permissions and secure-storage failures.
- Test Wi-Fi/cellular changes, intermittent 2G-like conditions and large queues.
- Expose per-item progress, retry eligibility, conflicts and recoverable error actions.
- Add a reviewable multi-device conflict flow; do not introduce silent last-writer-wins.

### 2.6 Accessibility and artisan experience

- Extend “सुनें” read-back to catalogue, product details, pricing and error guidance.
- Provide stop/replay controls, sensible audio focus and offline TTS capability messaging.
- Test voice-first onboarding and Step 2 guidance with actual artisans.
- Improve review readability, bilingual editing, before/after media selection and recovery UX.
- Retain useful draft-step transitions and catalogue animations, with reduced-motion support.
- Prefer clear state feedback over animation when network or storage work is pending.

### 2.7 Deployment, observability and authorized SMS verification

- Separate development, staging and production configuration and secrets.
- Set bounded request limits, worker limits, redacted structured logs and health checks.
- Monitor queue age, failure rates, rejected approvals, model latency and SMS spend.
- Establish release rollback, incident response, backup drills and retention controls.
- After separate authorization, verify one real OTP flow using an approved configured
  template and an explicitly authorized recipient; never use a sample phone number.
- Confirm backend challenge verification, quota accounting and credential redaction.
- Account for registration already triggering OTP in the app; avoid an extra manual send.
- Restart after cached configuration changes and restore disabled SMS after the test.
- Define pilot throughput, latency, recovery and cost targets before testing them.

### Deliverables and exit criteria

- [ ] Rehearsed database migration and restore with tenant-isolation tests.
- [ ] Private storage and durable workers verified in staging under interruption.
- [ ] No Phase 1 safety regressions under multi-worker load.
- [ ] Physical-device test matrix completed for the supported pilot devices.
- [ ] Approved real-provider tests recorded separately from mocks; unresolved dependencies disclosed.
- [ ] Artisan usability pilot, support path, monitoring and rollback procedure are ready.
- [ ] Measured operating costs and agreed service targets support the intended pilot size.

### Out of scope

Claiming live marketplace acceptance, real sales analytics from sample orders,
automated lending decisions, or expansion into many languages before EN/HI quality is validated.

## 6. Phase 3 — Marketplace and operations integration

### Goal and entry condition

Turn approved listings into traceable external commerce, using the Phase 2
foundation. Integrate one channel at a time with explicit external prerequisites.

### 3.1 Marketplace discovery and contract design

- Verify current GeM/ONDC participation, onboarding and sandbox requirements with
  the relevant channel/partner before selecting an adapter approach.
- Decide whether ONDC participation is through a partner or a direct network role.
  Do not assume building both buyer- and seller-side components is required.
- Map supported craft categories, required attributes, units, pricing and media rules.
- Record unavailable channel capabilities; do not fabricate export-success states.
- Keep this roadmap a work plan, not a statement of current protocol eligibility.

### 3.2 Approved-revision export adapters

- Export only the immutable approved published revision with its verified media.
- Snapshot export payloads and preserve channel-specific idempotency and audit records.
- Block export of drafts, rejected, deleted, superseded and legacy-unverified content.
- Revalidate eligibility immediately before dispatch; edits require renewed approval.
- Track pending, submitted, accepted, rejected, retrying and withdrawn channel states.
- Handle delayed acknowledgements, retries, duplicate callbacks and reconciliation.
- Propagate unpublish/delete requests and display pending external removal truthfully.
- Test sandbox behavior before separately authorized public listing publication.

### 3.3 Orders, inventory and fulfilment

- Create authoritative order APIs/storage and replace in-memory orders as the source of truth.
- Authenticate incoming events and handle duplicate or out-of-order notifications.
- Add stock reservation/release and oversell prevention across channels.
- Distinguish order, payment, packing, shipment, cancellation, return and refund states.
- Give artisans a practical “My Orders” view with buyer-location privacy and actionable status.
- Integrate logistics partners only after capability, pricing and operational review.
- Separate payment/settlement confirmation from an order merely being placed.

### 3.4 Packaging, story cards and labels

- Preserve category-specific packaging guidance for pottery, textiles and metal crafts.
- Clearly label advisory output and allow artisan edits; do not invent shipment guarantees.
- Generate printable bilingual story/care cards with consented artisan identity/location.
- Create shipping labels only from authoritative order and logistics data.
- QR codes must resolve to a valid authorized/public destination; do not imply an ONDC
  affiliation or certification merely because a profile QR exists.
- Verify Hindi font rendering, print sizes and absence of private buyer data in public QR links.

### 3.5 Notifications and real analytics

- Build a durable notification event stream and in-app history before relying on push.
- Add platform push delivery with user preferences, deduplication and minimal sensitive content.
- Reconcile notification actions against current server state, including expired orders.
- Replace sample revenue charts with authoritative order/payment/refund calculations.
- Define gross sales, net earnings, cancelled orders and reporting periods explicitly.
- Instrument views/popularity with deduplication and privacy controls.
- Show “fair wage premium versus middleman rate” only with a defensible baseline;
  otherwise label it as an estimate or omit it.

### 3.6 KalaMitra, social sharing and assisted NGO workflows

- Retain Hindi voice/text advice on selling, packaging and listing improvement.
- Ground order/account answers in authorized data, not fabricated model responses.
- Keep chatbot actions typed, permission-checked and review-first for publication.
- Require explicit review before public social posts using newly generated content.
- Replace coordinator simulation with verified roles, scoped artisan assignments,
  consent, revocation and auditable actions.
- Define assisted review so NGO support does not silently replace artisan approval.
- Keep demo NGO access isolated from production credentials and permissions.

### Deliverables and exit criteria

- [ ] Channel contracts/onboarding dependencies and sandbox evidence recorded.
- [ ] At least the chosen launch channel works end-to-end with approved revisions only.
- [ ] Exports, withdrawals, callbacks and retries reconcile without duplicates.
- [ ] Authoritative orders, inventory, fulfilment and analytics replace sample data for launch.
- [ ] NGO and chatbot actions preserve authorization and artisan sign-off.
- [ ] Channel-specific pilot, support/incident procedure and rollback plan are accepted.
- [ ] Public launch is separately authorized; pending channels remain labelled unavailable.

## 7. After Phase 3 — Launch, measure and maintain

Completion of the numbered phases begins operation, not the end of engineering.

- Run a limited artisan cohort before expanding geography or catalogue size.
- Monitor draft recovery, successful reviewed publications, export acceptance,
  order completion, support incidents and actual cost per completed listing.
- Gather consented feedback on Hindi copy, TTS, price explanations and trust.
- Review security, restore backups, update dependencies and rerun regression suites regularly.
- Track model/prompt changes as versioned releases with quality and safety comparisons.
- Prioritize improvements from measured failure rates and artisan needs.
- Keep separate launch checklists for local demo, device pilot and external marketplace release.
- Avoid fixed completion dates until dependencies, team capacity and acceptance gates are known.

## 8. Original ideas — preserved and assigned

| Original idea | Placement and delivery requirement |
| --- | --- |
| Spoken cues on Step 2 | Phase 0 baseline; Phase 2 artisan usability and ASR-quality evaluation |
| Universal “सुनें” TTS | Phase 1 review read-back; Phase 2 broader accessible guidance |
| My Orders screen | Demo-labelled baseline; Phase 3 authoritative order integration |
| AI packaging advice | Labelled advice can exist in demo; Phase 3 order-aware guidance |
| Artisan revenue/performance dashboard | Demo-labelled baseline; Phase 3 real metrics and documented definitions |
| KalaMitra voice/text assistant | Existing UI can remain; Phase 1 safe actions, Phase 2 reliability, Phase 3 authorized commerce assistance |
| Printable artisan story/care label and QR | Phase 3 authoritative print workflow; no false marketplace affiliation |
| Image latency optimization and before/after slider | Phase 2 measured performance; Phase 1 exact-media selection remains mandatory |
| Voice-first onboarding | Phase 0 baseline; Phase 2 physical-device and artisan testing |
| Hero animations and micro-interactions | Phase 2 polish after integrity/accessibility needs |
| Offline indicators, retries and recovery | Phase 1 correctness; Phase 2 OS/background and field validation |
| Live ONDC/GeM and logistics | Phase 3, dependent on verified external access and contracts |
| Cloud storage/CDN and push | Phase 2 private storage; Phase 3 authoritative event notifications |
| Alembic migrations | Already part of Phase 1; Phase 2 extends them to the hosted database |

### Optional future initiatives — not current release blockers

#### Multilingual and dialect expansion

- Expand beyond EN/HI incrementally; candidate languages include Tamil, Telugu,
  Kannada, Bengali, Odia, Gujarati, Marathi and Assamese.
- Build consented craft glossaries for terms such as Ikat, Kalamkari, Dhokra and Bidriware.
- Evaluate each language's ASR, translation, TTS and review UX before enabling it.
- Add native-speaker review, fallback behavior and language-specific quality gates.
- “12+ languages” is an ambition, not a currently supported capability.

#### AR product visualization

- Investigate WebAR/mobile AR only where buyer research indicates useful demand.
- Define 3D capture/asset creation, dimensional accuracy, storage and rendering costs.
- Do not imply a single phone photo guarantees an accurate 3D model.
- Provide lightweight non-AR views for unsupported devices and slow networks.

#### Working-capital and micro-credit partnerships

- Treat OCEN, PM SVANidhi, Mudra and other programs as research leads from the
  original ideas list, not confirmed integrations or eligibility promises.
- Obtain qualified partner/compliance review before designing any financial workflow.
- Require explicit consent and limited, auditable data sharing.
- Do not turn model-estimated prices or unverified catalogue volume into automatic
  credit decisions. Provide correction and appeal mechanisms for any partner assessment.
- Keep financial product development outside the core listing application's commitments.

## 9. Developer handoff and completion evidence

For each work package, record:

- Responsible developer, scope and prerequisite.
- Frontend/backend/schema/API/documentation changes required.
- Data migration, rollback and failure/recovery behavior.
- Success-path and adversarial regression tests with exact commands and results.
- Whether evidence is unit, local integration, device, real-provider or channel-sandbox testing.
- Remaining risks, external approvals and whether the phase gate is actually satisfied.

Suggested execution order:

1. Close Phase 1 operation-identity blockers and preserve their regression tests.
2. Produce a bounded Phase 1 sign-off and freeze a reproducible demo.
3. Design Phase 2 infrastructure interfaces and migrate in tested, reversible increments.
4. Validate a physical-device pilot and separately authorized provider delivery.
5. Integrate one Phase 3 commerce channel with authoritative order handling.
6. Expand only after operational evidence supports it.

### Reusable Antigravity handoff prompt

> Read AGENTS.md, docs/Ideas.md and the relevant architecture sections. Work only
> on the explicitly assigned phase/work package. Inspect existing implementation
> before adding or replacing features. Preserve unrelated changes and all offline
> data. Add success and failure-path tests, including identity changes and lost
> responses where relevant. Do not use real credentials, paid delivery or public
> publishing without separate authorization. Report exact implementation/test
> evidence, migration implications and unresolved risks. Do not declare a phase
> complete from a green test count alone.
