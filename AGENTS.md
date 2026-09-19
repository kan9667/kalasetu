# AGENTS.md — KalaSetu / Karigar Setu

## Purpose

KalaSetu is an offline-first Flutter + FastAPI prototype for helping Indian
artisans turn a product photo and voice note into a bilingual (English/Hindi)
listing with image enhancement and fair-price guidance.

This file is the operating context for agents working in this repository.
Read it before changing architecture, sync, publishing, pricing, authentication,
or AI-pipeline code.

## Repository map

| Path | Responsibility |
| --- | --- |
| `frontend/` | Flutter client: capture, voice recording, add-product review flow, Hive cache, Drift media queue, UI and TTS. |
| `backend/` | FastAPI API, SQLAlchemy data models, product routes, catalog/voice/pricing/social/chat services. |
| `ML/image_pipeline/` | rembg + OpenCV + Pillow product-photo enhancement. |
| `ML/voice_pipeline/` | Whisper-compatible transcription plus craft glossary biasing. |
| `ML/pricing/` | Cost-floor calculation, embeddings, ChromaDB comparable lookup, LLM price reasoning. |
| `docs/architecture.md` | Detailed architecture and known prototype gaps; update it when behavior changes. |
| `frontend/test/`, `backend/tests/`, `ML/*/tests/` | Automated tests. Add tests for every change to a safety-critical invariant. |

## Intended end-to-end flow

```text
Capture photo + voice note while offline
  -> persist durable local draft and media
  -> upload/sync when connectivity returns
  -> enhance image, transcribe voice, generate bilingual listing, suggest price
  -> artisan reviews each generated result
  -> artisan explicitly approves one immutable listing revision
  -> server publishes approved revision only
  -> future: export to GeM / ONDC
```

## Non-negotiable product invariants

1. **Explicit human approval:** No AI image, listing text, tags, or suggested
   price may become public without the artisan explicitly approving the exact
   revision being published.
2. **Never price below cost floor:** A listing price must be greater than or
   equal to `materials + labor_hours * hourly_rate + transport + overhead`.
   Enforce this on the server at every mutation and publish boundary; UI checks
   are supplementary only.
3. **Offline work is durable:** A capture must survive connectivity loss, app
   process death, restart, and retry. Never delete local queued/draft data as a
   generic error-recovery technique.
4. **Tenant isolation:** An artisan can access and mutate only their own
   profile, drafts, products, media, and social content.
5. **Degraded AI is transparent:** A timeout, mock value, raw-image fallback,
   failed transcription, or missing market data must be visibly marked as
   degraded; it must not masquerade as a successful AI result.

## Current implementation reality

This is a prototype transitioning through Phase 1. The following describes
current capabilities and remaining gaps:

- Authoritative database: Local SQLite with strict foreign keys enabled
  (`PRAGMA foreign_keys = ON`), managed with Alembic migrations
  (`backend/alembic/`). Supabase/PostgreSQL and remote RLS remain future work.
- Authentication: Cryptographic OTP challenge lifecycle (`OtpChallengeDB`,
  salted SHA-256 hashes, 5-minute expiry, max 3 attempts, single-use,
  per-phone and per-IP rate limiting, pluggable `SmsProvider`) with pinned
  HS256 JWT tokens. Demo OTP is restricted to `ALLOW_DEMO_OTP=true` in
  non-production environments. Tenant isolation is enforced across all private
  routes.
- Listing Lifecycle: Server-owned states (`draft`, `awaiting_approval`, `approved`,
  `published`, `superseded`, `rejected`, `legacy_unverified`). Creation defaults
  to `draft`. Updates bump revision and invalidate approvals. Direct publication
  is blocked; publication requires explicit `POST /api/v1/products/{id}/approve-and-publish`
  with matching revision, SHA-256 content hash, server-recalculated integer paise
  floor check, and a validated `ready` media asset.
- Currency / Floor: Stored and computed in integer paise (`price_paise`,
  `cost_floor_paise`, etc.) with legacy float compatibility. Prices below floor
  are strictly rejected at create, update, sync, and publish.
- Media Validation: Magic-byte inspection (JPEG, PNG, WebP), 15MB streaming
  limit, SHA-256 hash, private storage, and `media_assets` state machine.
- Offline Operations: Flutter append-only `OfflineOperation` outbox keyed by
  unique operation ID (`op.id`), never `productId`. Multi-step dependency execution
  (`CREATE -> MEDIA_UPLOAD -> ATTACH_MEDIA -> APPROVE_PUBLISH`), immutable payload snapshots,
  retention of completed upstream operations until all dependents finish, preservation of
  idempotency keys across retries, and `pendingApprovalSync` local state with null approval metadata.
- GeM and ONDC exports are not yet implemented. ONDC-related QR/profile visuals
  are prototype-only; legacy listings (`legacy_unverified`) require re-approval
  before any future marketplace export.
- Orders, analytics, NGO authentication, notifications, and some AI fallbacks
  contain mocked/local-only behavior; see `docs/architecture.md` section 26.

## Current high-risk areas

Treat these as active risks when modifying adjacent code:

- WorkManager code exists but is not registered from app startup.
- Local filesystem media and local ChromaDB are development/pilot storage, not
  horizontally scalable production infrastructure.
- Multi-device concurrent editing: Optimistic locking handles stale revision
  conflicts (returning 409), but full 3-way merge/reconciliation is not
  implemented.
- Uploads and media storage need private authenticated download URLs or signed
  tokens for production deployment.
- `pytest -q` collection under Python 3.14: Isolated from heavy ML imports, but
  optional ML dependencies should remain separated from API test suites.

## Audit findings tracker

Status of review findings after Phase 1 Trust & Data Integrity implementation:

### Resolved in Phase 1

- [RESOLVED] Authentication: Pinned HS256 JWT bearer authentication,
  cryptographic OTP challenges with rate limiting and Indian phone validation, and
  server-side tenant isolation across all private routes.
- [RESOLVED] Approval and Revision Lifecycle: Server-owned revision tracking,
  canonical SHA-256 content hashing, immutable approved revisions in `product_revisions`,
  draft-only creation, revision-bumping edits, and atomic `/approve-and-publish` endpoint.
- [RESOLVED] Client Image URL Rejection: `image_url` strictly prohibited on mutations
  with HTTP 422; published listings and approved revisions remain untouched.
  Legitimate image replacement requires verified owned `media_id`, unpublishing
  the item and requiring explicit re-approval.
- [RESOLVED] Server-Returned Attachment Chaining: Offline replay saves authoritative
  server-returned `revision` and `content_hash` from `ATTACH_MEDIA` and submits
  them in `APPROVE_PUBLISH`.
- [RESOLVED] Mandatory Idempotency Keys: Required `Idempotency-Key` header on create,
  update, delete, upload, approve-and-publish, and sync with lease expiration reclamation
  and request tampering detection (returning HTTP 409).
- [RESOLVED] Cost Floor Enforcement: Integer paise storage and server-authoritative
  recalculation. Below-floor prices rejected with 422 Unprocessable Entity.
- [RESOLVED] Deliberate Soft-Delete Tombstone Policy: Deletion marks `is_deleted=True, status='deleted'`
  and unlists the item while strictly preserving `product_revisions` rows for auditability.
- [RESOLVED] Legacy Data Migration: Alembic migration `0001` migrated existing
  `live` rows to `legacy_unverified` with approval metadata strictly NULL. Migration
  `0002` safely handles baseline schemas, revisions, idempotency, and media quarantine.
- [RESOLVED] Media Validation & Cleanup: Magic-byte inspection, SHA-256 checksums,
  15MB limit, private storage, atomic staged moves from `uploads/staging/` to `uploads/private/`,
  and single-transaction commits for media records and idempotency records with failure cleanup.
- [RESOLVED] Batch Sync Optimistic Locking: `ProductSyncBatch` accepts `expected_revision` on
  items, rejecting stale revisions with HTTP 409 and rolling back all mutations atomically.
- [RESOLVED] Append-Only Offline Outbox & Durability: Hive records keyed strictly by `op.id`,
  immutable payload snapshots, explicit dependency chaining (`CREATE -> MEDIA_UPLOAD -> ATTACH_MEDIA -> APPROVE_PUBLISH`),
  retention of completed upstream operations until all dependents finish, `pendingApprovalSync`
- [RESOLVED] Non-Destructive Fail-Closed Hive Startup: Strict elimination of `deleteBoxFromDisk`
  on safety-critical boxes (`products_box`, `pending_sync_box`, `draft_box`, `user_profile_box`,
  `auth_box`), `crashRecovery: false` to prevent silent box truncations, timestamped quarantine
  with restrictive file permissions, and `HiveRecoveryApp` fallback screen.
- [RESOLVED] Media Asset Lineage and Degradation Tracking: Alembic migration `0003` adding
  `source_media_id`, `is_degraded`, and `degraded_reason` to `media_assets`. Private image
  enhancement endpoint returning authoritative `media_id`, preserving original, tracking degradation,
  and propagating through Drift queue and `AddProductDraft` to Step 5 confirmation review.
- [RESOLVED] AI & Media Endpoints Security & Streaming: Bearer JWT authentication, required
  `Idempotency-Key` headers across catalog, voice, pricing, chat, media, and products routes,
  with single-pass chunked streaming ingestion and magic-byte inspection (JPEG, PNG, WebP, MP3, WAV,
  M4A, OGG, FLAC) to eliminate memory exhaustion.
- [RESOLVED] Secure Token Storage & Authenticated HTTP Client: `SecureTokenStorage` utilizing
  `flutter_secure_storage` with seamless migration from legacy unencrypted `auth_box` and
  in-memory test fallback; unified `AuthenticatedHttpClient` injecting Bearer auth headers and
  idempotency keys.
- [RESOLVED] Server-Enforced Unpublish & Client Status Integrity: Client-side direct live/published
  mutations eliminated; `POST /api/v1/products/{id}/unpublish` implemented on server requiring
  `expected_revision` and `content_hash` pinned to lowercase 64-character hex regex `^[a-f0-9]{64}$`
  with 409 Conflict rejection on mismatch; truthfulness preserved via `ProductStatus.pendingUnpublishSync`
  without erasing approval metadata until authoritative server confirmation; safe coalescing of pending unsubmitted
  approvals while preserving in-flight/response-lost approvals with authoritative replay.
- [RESOLVED] AI Idempotency Fingerprints: Canonical sorted JSON dictionary fingerprints across all 11 AI endpoints
  (/catalog/generate-listing, /catalog/voice-to-listing, /catalog/voice-to-product, /catalog/transcribe,
  /catalog/enhance-image, /voice/transcribe, /voice/process-note, /pricing/suggest, /pricing/suggest-upload,
  /pricing/suggest-from-voice, /chat/message), with lineage-aware deduplication and request-scoped cleanup.
- [RESOLVED] Client Key Ownership & Durable Media Cache: AuthInterceptor generation eliminated; caller-owned
  persisted idempotency keys; retryable SecureTokenStorage migration with legacy fallback; PrivateMediaCache
  bounded to 15MB with atomic rename, staging cleanup, and zero token leakage; POSIX 0600 quarantine enforcement.
- [RESOLVED] Private Media Access Security: Origin verification (`isConfiguredApiOrigin`) enforcing scheme, host,
  and port matching against `ApiConfig.baseUrl` preventing bearer leakage to third-party endpoints; strict regex
  `^[a-zA-Z0-9_-]+$` preventing directory traversal; backend (`srv_<hash>`) and account (`acc_<hash>`) directory
  namespacing; in-flight request cancellation and directory isolation on `deactivateAccount()`; bounded direct
  image download in `ImageEnhancerService` utilizing `PrivateMediaCache` streaming with 15MB ceiling and atomic rename.
- [RESOLVED] Durable Token Storage Migration: Fail-closed readback verification in `SecureTokenStorage`; legacy token
  in `auth_box` retained and never deleted on readback mismatch or platform errors (`MissingPluginException`);
  explicit storage double injection support; single-flight synchronization preventing concurrent duplicate migrations.
- [RESOLVED] Persistent AI Operation Identity & Complete Pre-Dispatch Storage: Replaced non-deterministic
  `DateTime.now()` keys with deterministic, SHA-256 fingerprinted `AiOperationRecord` entries durably persisted
  to `ai_operations_box` before any HTTP dispatch; payload fingerprints calculate cryptographic hashes of raw
  photo bytes (`sha256(File(originalImagePath).readAsBytesSync())`), voice transcripts, audio paths, and cost
  inputs; distinct operation types (`image_enhancement`, `voice_to_listing`, `fair_pricing`) prevent key collisions;
  monotonic input generations (`imageInputGeneration`, `voiceInputGeneration`, `pricingInputGeneration`) ensure
  stale in-flight operations are superseded and never overwrite newer user inputs.
- [RESOLVED] Background Future Decoupling & Late Result Reconciliation: Detached UI timeout mechanisms from
  underlying network futures; in-flight futures run to completion in the background, persisting completed results
  to durable `AiOperationRecord` storage with exact status and timestamps; on screen re-entry or app resume,
  completed records are reconciled against the active draft if and only if input generations match, preventing
  redundant network calls and lost computations while preserving unique operation IDs across Drift outbox transfers.
- [RESOLVED] Exact-Media Review Runtime Enforcement: Eliminated debug-only assertions in favor of strict runtime
  checks in `Step5ConfirmWidget`; enforces preview verification against the exact bound asset (`boundMediaGeneration ==
  imageInputGeneration`); photo retakes immediately invalidate previous enhancement results and require fresh
  preview generation; unenhanced raw photos require verified local disk existence (`File.existsSync()`); publication
  is strictly blocked if preview generation fails, the local file is missing, or media generation mismatches,
  guaranteeing an artisan never approves an unseen or misattributed asset.
- [RESOLVED] Repository Initialization Barrier & Fail-Closed Deserialization: Single-flight `ProductRepository.initialize()`
  gates all mutating and read methods (`getProducts`, `addProduct`, `updateProduct`, `approveAndPublishProduct`,
  `deleteProduct`, `unpublishProduct`, `syncPendingQueue`), awaiting database hydration, schema migrations, and
  expired lease reclamation before handling requests; `OfflineOperation.fromPendingString` safely distinguishes
  legacy action strings from modern JSON payloads, throwing structured `FormatException` on truncated or malformed
  JSON rather than executing corrupt actions; wired directly into `main.dart` root `ProviderContainer` prior to
  rendering `KalaSetuApp`.
- [RESOLVED] Session-Bound Private Media Cache & Atomic Deduplication: `PrivateMediaCache` isolates files by
  authenticated account (`acc_<hash>`) and normalized backend origin (`scheme://host:port` with lowercased host
  and default port handling); captures session generation and account identity at download invocation entry;
  concurrent requests for the same media asset are atomically deduplicated via synchronous Completer registration;
  account logouts, token revocations, or origin changes immediately abort in-flight transfers and reject promotion
  of staging `.tmp` files via `SessionChangedException`; `AppImage` validates active session generation before
  rendering cached files on disk.
- [RESOLVED] Production Wiring & Drift Outbox Hydration: Replaced manual test injection with automatic Drift
  outbox watching via `watchPendingOperations()`; outbox updates trigger real-time badge count updates and queue
  state synchronization; verified outbox dependency chaining (`CREATE -> MEDIA_UPLOAD -> ATTACH_MEDIA -> APPROVE_PUBLISH`)
  and local outbox ID preservation (`explicitLocalId`) through end-to-end integration tests.
- [RESOLVED] Error Classification & Transparent AI Degradation: HTTP 401/403 session expiration handled via
  `expireSession()` preserving offline drafts and outbox; HTTP 409/413/422 treated as non-retryable validation errors
  instead of offline fallbacks; component-level degradation tracking (`isImageDegraded`, `isVoiceDegraded`,
  `isListingDegraded`, `isPricingDegraded` with reasons); Step 5 confirmation screen displays cached/downloaded
  `mediaId` asset and prominent degradation banners.
- [RESOLVED] Chatbot Review Navigation: Registered `/review-product/:id` route in `app_router.dart`; preserved target
  `productId` in `executeAction`; widget and navigation tests verifying chat review action button deep-links directly
  to `ReviewExistingProductScreen` without auto-publishing.
- [RESOLVED] Verifiable Lifecycle Initialization & Media Reconciliation: Removed unawaited async constructor
  side-effects from `ProductRepository`, replacing with explicit `Future<void> initialize({DateTime? now})`; added
  `sha256_checksum` and `sha256Checksum` in `RealUploadApi.resultPayload`; Drift queue SQLite disk persistence tested
  with real mock HTTP adapter verifying checksum propagation and media reconciliation without manual payload injection;
  verified expired in-flight approval lease reclamation across simulated app restart.
- [RESOLVED] Test Coverage & Verification: 121 backend tests passing under Python 3.14 (covering AI idempotency
  fingerprints, auth security, SQLite FKs, tenant isolation, approval workflow, migrations, concurrency, media
  privacy, streaming ingest, cost extraction, and e2e integration); 3 migration tests passing; 162 Flutter tests
  passing (covering unpublish truthfulness, coalescing scenarios a-d, upstream dependency resolution, hash validation,
  409 conflict refresh, review existing product screen, secure token migration fallback, private media cache
  bounded abort, drift queue durability, offline media lineage, degradation banners, chatbot review navigation,
  exact-media review verification, repository initialization barrier, cache session binding, and live HTTP wire test)
  with 0 `flutter analyze` issues.
  *Note on test execution environment*: All automated verification was executed on local macOS developer workstation
  test harnesses (SQLite with foreign keys enabled, Drift native SQLite, in-memory/mock HTTP adapters, and live
  FastAPI server wire test on loopback). Physical Android/iOS hardware field trials remain planned for Phase 2.

### Remaining for Phase 2 / Phase 3

- [Phase 2] Migrate SQLite to Postgres/Supabase with migrations and RLS.
- [Phase 2] Move local filesystem media to private S3/GCS object storage with signed URLs.
- [Phase 2] Move image/STT/LLM pipeline jobs to durable asynchronous worker queues.
- [Phase 2] WorkManager background registration and stale upload lease recovery.
- [Phase 3] GeM and ONDC protocol adapters for approved published revisions.
- [Phase 3] Authoritative order ingestion, inventory reservations, and notifications.

## Development phases

### Phase 0 — Prototype stabilization (current)

Goal: preserve the demo while preventing silent loss or misleading claims.

- Keep the Flutter add-product flow usable online and offline.
- Clearly label mocks, fallbacks, and unavailable services.
- Fix test-environment reproducibility and document the supported Python and
  Flutter versions.
- Do not claim Supabase, GeM, ONDC, secure OTP, or production sync is live.

### Phase 1 — Trust and data integrity

Goal: make a listing safe to own, approve, price, and sync.

- Implement real phone authentication and bearer-token verification.
- Add server-side ownership checks to every protected route.
- Introduce listing revisions and server-enforced states:
  `draft -> awaiting_approval -> approved -> published`.
- Persist cost inputs, cost floor, approval metadata, and immutable approved
  revision/hash. Reject prices below the floor at create, update, sync, and
  publish boundaries.
- Replace split queues with a durable outbox/dependency model, idempotency keys,
  lease expiry, restart recovery, and conflict/version handling.
- Add adversarial tests for unauthorized access, approval bypass, below-floor
  publishing, duplicate submissions, response-lost uploads, and app-kill
  recovery.

### Phase 2 — Production foundation

Goal: replace single-node prototype state with durable managed services.

- Migrate to Postgres/Supabase with migrations and enforced RLS where used.
- Move media to private object storage with signed access URLs.
- Move image/STT/LLM jobs to a bounded worker queue with durable job status.
- Establish Chroma/vector index refresh, provenance, observability, backups,
  retention/deletion controls, and load testing.
- Make all AI fallback and confidence states explicit in API contracts and UI.

### Phase 3 — Marketplace and operations integration

Goal: connect verified, approved listings to external channels safely.

- Build GeM and ONDC adapters only for approved published revisions.
- Add export retries, idempotency, audit logs, reconciliation, and channel
  status in the artisan UI.
- Implement real order ingestion/webhooks, inventory reservation, notifications,
  and analytics sourced from authoritative order data.
- Add NGO/coordinator roles with scoped, auditable multi-artisan permissions.

## Working conventions

- Preserve unrelated user changes. Check `git status` before edits.
- Use `rg` for code search and `apply_patch` for file edits.
- Keep secrets only in `.env`; never commit real keys, tokens, databases,
  uploads, recordings, or generated Chroma indexes.
- Prefer explicit Pydantic/Dart types, bounded validation, UTC timestamps,
  UUIDs, and server-generated audit metadata.
- Avoid silently swallowing exceptions in safety-critical paths. Return a
  structured, actionable failure/degraded state instead.
- Do not use client-side status, timestamps, artisan IDs, or price floors as
  authorization or integrity proof.
- When changing API contracts, update Flutter callers, backend schemas, tests,
  and `docs/architecture.md` together.

## Required validation for sensitive changes

For changes involving sync, auth, approval, pricing, storage, or publication:

1. Add or update unit and integration tests first or alongside the change.
2. Test a successful path and failure paths: offline, duplicate retry, timeout
   after server success, app restart, concurrent edits, and unauthorized caller.
3. Verify no state can transition to `published` without a valid approval for
   the same content revision and a price at/above the persisted floor.
4. Run the relevant backend and Flutter test suites in their supported toolchain
   and report any environment limitations honestly.

## Environment variables

`.env.example` is the source of environment-variable names. Current AI-related
variables include `GROQ_API_KEY`, `GEMINI_API_KEY`, `WHISPER_API_KEY`,
`WHISPER_BASE_URL`, and `WHISPER_MODEL`. Future production work should add
database, object storage, authentication/OTP, queue, and export credentials
there without committing actual values.
