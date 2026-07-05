# Scenario Apps — Boilerplate + FRS Design

**Date:** 2026-07-03
**Status:** For review (approve → Phase 0/1 coding)

## 1. Vision & boundary

Each vertical (FRS, ANPR, …) is a **separate, single-tenant app** with its own custom
UI (client-to-client UI varies). Apps run inference **locally** (low latency, self-
contained) using models developed/exported by the CVOps platform (`ai_project`). The
platform stores NO scenario domain data — apps own everything (persons, cameras,
events). A shared **boilerplate** provides the common core so each new scenario is fast.

- **`ai_project`** = model factory (annotate → train → eval → export ONNX/OpenVINO + manifest).
- **`scenarios/boilerplate/`** = reusable core (runtime, stream, pipeline, vectordb, db, auth, events).
- **`scenarios/frs/`** = FRS app on the boilerplate (first instance).
- **`scenarios/anpr/`** = later, same boilerplate.

## 2. Tech stack

- **Backend:** Python 3.11 · FastAPI · async SQLAlchemy · **Postgres + TimescaleDB** (events timeseries) · **Qdrant** (embedding similarity).
- **Inference runtime:** **ONNX Runtime + OpenVINO** (CPU + Intel GPU + NVIDIA GPU). Pluggable backends; **DeepStream = Phase 2** (multi-cam GPU scale).
- **Models:** **SCRFD** (face detect, 5 landmarks) + **AdaFace** (recognition, 512-d) — both pluggable via manifest (adaface|arcface, scrfd|yolov8-face). Quality-adaptive AdaFace chosen for low-quality CCTV faces.
- **Frontend:** **Next.js 14 (DashCode template)** + Tailwind + **TanStack Query** + JS. Single-tenant. Deployable to Vercel/Node.
- **Media server:** **MediaMTX** — single hub that pulls each camera ONCE and republishes to all
  consumers (inference, browser live wall via WebRTC, recorder). Required at scale (clients buy 30+
  cameras). Configurable `VE_MEDIA_SERVER=mediamtx|none`.
- **Ingest/decode:** **FFmpeg-per-stream** (not OpenCV) → numpy frames; reads from MediaMTX (not the
  camera directly); frame-skip/backpressure from day 1.

## 3. Folder structure

```
scenarios/
  boilerplate/
    vizor_edge/
      runtime/    base.py · onnx_backend.py · openvino_backend.py · tensorrt_backend.py(stub) · registry.py · manifest.py
      models/     face_detect.py(SCRFD pre/post) · face_embed.py(AdaFace align→512d) · detector.py(YOLO) · ocr.py(later)
      stream/     mediamtx.py(camera path register/republish/record via HTTP API) · rtsp.py(FFmpeg decode from MediaMTX) · annotate.py · backpressure.py
      pipeline/   loop.py(frame-loop) · tracker.py(IOU tracker→appearance) · deepstream/(Phase-2)
      vectordb/   qdrant.py(upsert/search/filter by watchlist+model_id)
      db/         base.py(async SQLAlchemy) · timeseries.py(Timescale hypertable helpers)
      events/     appearance.py(lifecycle start/update/end + meaningful-delta gate) · alerts.py
      core/       config.py · auth.py(JWT + API key, single-tenant users) · api.py(FastAPI factory) · health.py
      hooks.py    # BusinessHook interface (scenario logic)
    pyproject.toml

  frs/
    backend/app/
      domain/     poi.py · poi_face.py · watchlist.py · poi_watchlist.py · camera.py · appearance.py · person.py(Phase2)
      enroll.py       # image → SCRFD → align → AdaFace → Qdrant upsert + poi_face
      recognizer.py   # BusinessHook: frame faces → embed → Qdrant(watchlist-scoped top-k) → appearance events
      gallery.py      # Qdrant collection mgmt (dim 512, model_id payload)
      api/        pois · watchlists · cameras · events(feed+alerts) · investigate(1:N + appearance search) · users
      main.py
    backend/migrations/   # alembic + create_hypertable(recognition_events)
    backend/models/       # scrfd.onnx + adaface.onnx (+ openvino IR) + manifest.json
    frontend/             # DashCode Next.js: Cameras · Live wall · POIs/Watchlists · Events/Alerts · Investigation · Users
    infra/docker-compose.yml   # postgres(timescale) · qdrant · backend · frontend (GPU opt-in)

  anpr/                   # later
```

## 4. Data model (Corsight-informed)

**Postgres**
- `poi`: poi_id(immutable), display_name, display_img, consent(state+time), notes, created_at
- `poi_face`: face_id, poi_id→, img_crop, face_score, yaw, pitch, width, model_id, forced_reason, qdrant_point_id
- `watchlist`: watchlist_id, name, **type(blacklist=alert-on-match | whitelist=alert-on-absence)**, color, severity, **threshold_delta**, repeated_alert
- `poi_watchlist`: (poi_id, watchlist_id)
- `camera`: camera_id, rtsp(creds **encrypted**), **base_threshold**, watchlists[], analysis_quality(frame-sample), status
- `appearance`: appearance_id, tracker_id, camera_id, poi_id, best_face_crop, best_confidence, started_at, ended_at, match_data(JSONB), face_attributes(certainty cols)
- `user`: single-tenant users + roles(admin/operator/viewer)

**Qdrant** `faceprints`: 512-d vectors, payload `{poi_id, face_id, watchlist_ids[], model_id, face_score}`. Search **filtered by watchlist_ids** (scoping) → top-k above threshold.

**Timescale** `recognition_events` hypertable: ts, appearance_id, camera_id, poi_id, confidence, trigger, in/out → feeds/reports/attendance.

## 5. Pipeline (recognition)

```
RTSP(FFmpeg) → frame → SCRFD detect+landmarks → quality-gate(score/yaw/pitch/width)
→ align(112×112) → AdaFace embed(512-d) → Qdrant search(watchlist-scoped top-k)
→ IOU tracker collapse → appearance event (start → update(s) → end)
   [meaningful-delta gate: push only when confidence materially improves / WL or POI changes]
→ effective threshold = camera.base + watchlist.threshold_delta
→ alert: blacklist-hit OR whitelist-miss  → WS/SSE feed + notification + annotate overlay
```

**Key patterns (from Corsight):**
- **Appearance = tracker-collapsed sighting** (one person, one camera). Keep best face + best confidence.
- **Event lifecycle + meaningful-delta gate** — kills alert spam (only push on material improvement).
- **Two-layer attributes**: raw `{result, score}` + Certainty (determined/inconclusive/not_determined).
- **Quality gate** on enroll AND match + `forced_reason` on override.
- **Versioned faceprint** (`model_id` in Qdrant payload) → model migration without wipe.
- **MATCH_PRIORITY** — reconcile multi-watchlist verdicts into one headline outcome.
- Consent + `labeled_outcome` (review→retrain) + `retain` flag.

**Avoid (Corsight complexity):** deep Pydantic metaclass web (Postgres gives schema), inline faceprint blob (use Qdrant), opaque HTTP matcher (Qdrant native top-k+filter).

## 6. Frontend (DashCode Next.js) — screens

**v1 MUST:** Cameras (RTSP CRUD + health) · **Live wall** (multi-cam grid via RTSP→WS/MJPEG) · **POIs/Watchlists** (enroll: name+faces+watchlist) · **Events feed + Alerts feed** (+ notification center) · **Investigation** (upload face → 1:N identify + search-across-appearances, threshold+time filter) · Users/auth/roles.
**Phase 2:** Generative Insights (loitering/crowd/journey/proximity) · privacy masking · retention/audit · person-clustering · bulk import · saved cases.

Reuse DashCode's shell/components; add TanStack Query for API; build FRS screens.

## 7. ai_project ↔ app contract

Model exported as **`{weights (onnx/openvino IR) + manifest.json}`**. Manifest:
`{family(scrfd|yolov8-face|adaface|arcface), task(detect|embed), input_size, embed_dim?, preprocess, postprocess}`. Boilerplate `runtime/registry` reads manifest → loads correct backend/adapter. **Phase 1:** FRS bundles SCRFD+AdaFace weights. **Phase 3:** pull from ai_project export.

## 8. Phased plan

- **Phase 0 — boilerplate skeleton:** runtime (onnx+openvino, manifest) · FFmpeg RTSP + backpressure · Qdrant wrapper · Timescale db base · auth/api/config · **appearance event-lifecycle engine** · hooks · MJPEG overlay.
- **Phase 1 — FRS end-to-end (CPU-first, WORKING):** domain + migrations(+hypertable) · SCRFD+AdaFace (onnx) · enroll · recognizer hook (Qdrant match + watchlist + appearance events + alerts) · Cameras/POIs/Watchlists/Events/Alerts APIs · **Investigation (1:N + appearance search)** · DashCode UI · docker-compose (postgres+timescale, qdrant).
- **Phase 2 — GPU + scale:** TensorRT backend (ONNX→engine on target GPU) · **DeepStream pipeline** (NVDEC+PGIE SCRFD+SGIE AdaFace+nvtracker→hook) · person-clustering · insights.
- **Phase 3 — ai_project integration:** artifact+manifest export → FRS pulls instead of bundling.

## 9. Matching is scenario-specific (Qdrant = optional plugin, not core)

Different scenarios match differently — the boilerplate must not force a vector DB
on all of them.

| Scenario | Match by | Backend | Qdrant? |
|----------|----------|---------|---------|
| FRS | face embedding → similarity | Qdrant | ✅ |
| Suspect | body/ReID embedding → similarity | Qdrant | ✅ |
| ANPR | plate text (exact/fuzzy) | Postgres | ❌ (but may ALSO add vehicle-embedding search → Qdrant, optional) |
| PPE | rule (no gallery) | — | ❌ |
| Crowd | counting | — | ❌ |

So a **`matching/`** abstraction: `Matcher.match(query) -> [Match]`. Implementations:
`vector.py` (QdrantMatcher, FRS/Suspect), `text.py` (PlateMatcher, ANPR). PPE/Crowd
use no matcher — the hook rules/counts directly. Qdrant stays an **optional module**:
scenarios that don't need it never run the container.

## 10. Camera modes + dynamic per-camera config

Every camera has a **mode**:
- `detection` — SCRFD (+ optional age/gender) only. No embedding, no Qdrant. Cheap.
- `recognition` — full detect→align→embed→match→appearance→alert pipeline.

The pipeline reads `camera.mode` and branches, so detection-only cameras skip all
vector work. **All tuning is per-camera, DB-stored, frontend-editable (never hardcoded):**
`mode`, `detection_confidence`, `base_threshold` (effective = base + watchlist.delta),
`roi_enabled` + `roi_polygon` (process only inside ROI), `min_face_size`,
`age_gender_enabled`, `frame_skip`/analysis-fps. Stream re-reads config on change.

## 11. Age & gender (ops-level, no training)

Use InsightFace's ready `genderage.onnx` (ships with buffalo_l): aligned face →
(gender, age). Optional, gated by `camera.age_gender_enabled` and the license
`age_gender` feature. Attached as event/appearance attributes (two-layer pattern).

## 12. Feature modules + licensing (monetization)

**Feature modules** — FRS is a host; Attendance, Transit (rule: Camera A→B within X min),
Investigations, and future features are self-contained plugin packages under
`frs/backend/app/modules/<id>/` (own router + service + tables). A central
`ModuleRegistry` (boilerplate `core/modules.py`) holds all; the **license** decides which
mount. New feature = new folder + `register(ModuleSpec)` — no core edits. Frontend reads
`/api/features` to render only enabled modules.

**License** — single-tenant, one signed token per deployment (offline, tamper-proof):
Ed25519-signed JWT. Vendor signs with a private key (`tools/gen_license.py`); the app
bundles only the public key and verifies signature + expiry (`core/license.py`). Claims:
```json
{ "client":"HCL", "exp":..., "modules":["attendance","transit","investigations"],
  "limits":{"cameras":10,"recognition_cameras":6,"storage_gb":500},
  "features":{"age_gender":true,"export":true} }
```
Enforcement: camera-add checks `limits.cameras` (409 over cap); module routers mount only
if granted; a storage guard rotates/stops recording past `storage_gb`; expiry checked at
startup + runtime. One codebase, sold in tiers by issuing different licenses. Dev mode
(env=dev, no token) falls back to an unlimited license so the app runs out-of-the-box.

## 12b. Media server & scale (MediaMTX — 30+ cameras)

Clients buy **30+ camera licenses**, so streaming must scale. Direct FFmpeg-per-camera fails:
cameras limit concurrent connections (~2-4) and browsers can't play RTSP. Solution — **MediaMTX**
as the single media hub (same pattern proven in ai_project's go2rtc→MediaMTX consolidation):

```
Camera RTSP ─► MediaMTX (ONE pull/camera, republish)
                 ├─► inference (FFmpeg decode → SCRFD/AdaFace)   local, reliable
                 ├─► live wall (WebRTC/HLS — browser native)      raw
                 ├─► recorder (MediaMTX built-in → storage/clips)
                 └◄─ annotated stream (optional push-back)
```

- **One camera pull**, many consumers → no camera overload; MediaMTX handles reconnect.
- **Live wall = raw WebRTC + detections over WebSocket** (client draws boxes on canvas). This avoids
  re-encoding 30 annotated streams — the scalable choice. Server-side annotated re-encode is optional
  (recording/clips only).
- **Decode still via FFmpeg** (MediaMTX doesn't yield numpy) but from the local MediaMTX URL, not the
  camera. `stream/mediamtx.py` registers camera paths + record config via MediaMTX's HTTP API.
- Recording → `core/storage.py` + investigation clips + retention cleanup (Celery-beat, license `storage_gb`).
- Config `VE_MEDIA_SERVER=mediamtx|none` (dev/1-cam direct, prod/30-cam via MediaMTX). Compose adds a
  `mediamtx` service.

## 13. Platform base capabilities (boilerplate — build FIRST, then scenarios)

Decision: finish the COMPLETE industry-grade base once; every scenario (FRS, ANPR)
reuses it → a new scenario is fast to build. Ordered, each package self-contained + tested:

1. **core/secrets.py** — Fernet encrypt/decrypt for DB-stored credentials (SMTP, FCM, S3).
2. **db/base.py + db/timeseries.py** — async SQLAlchemy engine/session/Base + `get_db` dep
   (no auto-commit — services `commit()` explicitly); Timescale hypertable helper.
3. **core/auth.py** — users, password hashing, JWT access/refresh, RBAC (admin/operator/viewer),
   API keys. Single-tenant users.
4. **core/storage.py** — object storage abstraction: local FS + S3-compatible (logos, report
   exports, face crops, snapshots, clips) + presigned URLs.
5. **core/audit.py** — audit log (actor, action, target, meta, ts) + `record()` + list endpoint.
6. **branding/** — white-label: logo (upload→storage), app name, theme colors. `GET /api/branding`
   (public, frontend renders) + `PUT` (admin).
7. **messaging/** — channels + dynamic **encrypted** config + Jinja2 **ready templates** + dispatcher:
   `config.py` (per-channel, encrypted), `templates.py` (ready templates + render),
   `email.py` (aiosmtplib, DB SMTP config), `push.py` (**FCM → our React Native app**),
   `inapp.py` (notifications table + feed), `webhook.py` (signed outbound), `dispatcher.py`
   (`notify(event)` → fan out to enabled channels). **WhatsApp = deferred pluggable slot** (costly).
8. **tasks/** — Celery app (Redis broker/backend) + task base + **Celery-beat** (scheduled):
   report generation, retention cleanup (license `storage_gb` cap), scheduled reports.
9. **reports/** — export framework: CSV/XLSX (openpyxl) / PDF (reportlab) builders, run as Celery
   tasks → storage → notify when ready.
10. **system/** — `resources.py` (CPU/RAM/storage via psutil, GPU via pynvml lazy) +
    `GET /api/system/resources` + WS live stream.
11. **core/realtime.py** — WebSocket/SSE hub (live wall, alerts feed, resource stream, notifications).

**Mobile app (separate, later):** a **React Native** app for real-time notifications + comms
(replaces WhatsApp). Backend supports it via device-token registration, **FCM push** (`push.py`),
WS realtime, and a mobile-facing API. Built after the base + FRS.

**New deps (pyproject extras):** messaging(aiosmtplib, jinja2, firebase-admin), tasks(celery, redis),
reports(openpyxl, reportlab), system(psutil; gpu→nvidia-ml-py), storage(aioboto3 for S3).
Secrets reuse cryptography (already present).

## 14. Non-goals (v1)
DeepStream (Phase 2), person-clustering (Phase 2), generative insights, privacy masking,
advanced audit/retention DASHBOARDS (backend audit-log IS in the base), WhatsApp (deferred —
mobile app instead), multi-tenant (apps are single-tenant), remote inference API (local inference).
