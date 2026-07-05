# create-scenario CLI + platform-as-tooling repo — Design

**Date:** 2026-07-05
**Goal:** A generator that, given a scenario name, produces a **complete standalone
scenario repo** (edge-backed FastAPI backend + clean DashCode Next.js frontend) with
the shared `platform/` **vendored** in — so every scenario lives in its **own git
repo** (per-repo team access, per-scenario customization, easy distribution). User
has 13 scenarios to build; a monorepo won't scale for their access/management needs.

## Decisions (approved)
- **Platform sharing:** vendored copy + `sync-platform` script (NOT submodule / packages).
  Each generated repo is fully self-contained: `git clone` → `docker compose up` works.
- **Home:** repurpose `scenarios/` as the **platform + tooling source-of-truth** — keep
  `platform/`, add `template/` + `tools/`. `frs/` + `suspect/` stay for now (working);
  extract later if desired.
- **Ports:** auto-assigned from `tools/ports-registry.json` (slug → index N). Seeded
  frs=0, suspect=1; next = max+1.
- **Output location:** sibling of `scenarios/` by default (`../<slug>/`), `--out` override.

## Repo layout (scenarios/ = canonical)
```
scenarios/
├── platform/                 # edge backend + web frontend (shared, unchanged)
├── template/                 # scenario skeleton (standalone-repo layout, tokenized)
│   ├── docker-compose.yml     # repo-root; name __SLUG__; standalone build contexts
│   ├── .env.example  .gitignore  README.md  sync-platform.sh
│   ├── backend/  (Dockerfile, alembic.ini, pyproject, mediamtx.yml, app/, migrations/)
│   └── frontend/ (clean Next scaffold, views/Home.jsx, menu.js, configs)
├── tools/
│   ├── create-scenario        # Python (stdlib) generator
│   ├── sync-platform          # re-vendor platform into a scenario repo
│   └── ports-registry.json    # {"frs":0,"suspect":1}
├── frs/  suspect/            # existing apps (unchanged)
└── docs/superpowers/specs/
```

## Generated standalone repo layout
```
<slug>/                        # its own git repo
├── platform/                  # VENDORED copy of scenarios/platform
├── backend/                   # FastAPI on edge (own DB, port)
├── frontend/                  # clean Next scaffold, own views/ + menu.js
├── docker-compose.yml         # name: <slug>; binds ./platform, ./backend, ./frontend
├── .env  .env.example  .gitignore  README.md  sync-platform.sh
```
Standalone build contexts (differ from monorepo): backend build context `.` (repo
root) so `COPY platform /edge` + `COPY backend/...`; volumes `./platform:/edge` +
`./backend:/app`; frontend context `frontend`, volumes `./frontend:/app` +
`./platform/web:/app/web`.

## `create-scenario` flow
`python tools/create-scenario "PPE Detection" [--slug ppe] [--out ../]`
1. Name → `slug` (slugify, lowercase, `_`→`-`... identifiers use `[a-z0-9]`),
   `name` (display), `db`=slug-with-underscores, perm-prefix=slug.
2. Allocate port index N from `ports-registry.json` (reuse if slug present, else max+1);
   derive host ports: backend 8000+N, frontend 3000+N, postgres 5432+N, redis 6379+N,
   qdrant 6333+N, rustfs 9000+N/9010+N, maildev 1025+N/1080+N, mediamtx 8554+N/8889+N/
   8888+N/9997+N. Persist the registry.
3. Create `<out>/<slug>/` (refuse if exists).
4. Copy `template/` → output; **token-substitute** file contents (`__SLUG__`, `__NAME__`,
   `__DB__`, `__PORT_*__`).
5. Vendor: copy `scenarios/platform/` → `<slug>/platform/` (exclude `.venv`, `__pycache__`,
   `web/node_modules`, `.next`).
6. Write `.env` from `.env.example`.
7. `git init` + initial commit.
8. Print next steps.

## `sync-platform`
Dropped into every generated repo (`sync-platform.sh`) + `tools/sync-platform`. Copies
the latest `platform/` from a configurable source (default: the scenarios path or its
git URL) into the repo's `platform/`. Explicit, on-demand platform updates per repo.

## Tokens
`__SLUG__` (identifiers/compose project/db/perm-prefix) · `__NAME__` (display/title) ·
`__DB__` (postgres db) · `__PORT_BACKEND__ __PORT_FRONTEND__ __PORT_POSTGRES__
__PORT_REDIS__ __PORT_QDRANT__ __PORT_RUSTFS1__ __PORT_RUSTFS2__ __PORT_MAILDEV_SMTP__
__PORT_MAILDEV_UI__ __PORT_MEDIAMTX_RTSP__ __PORT_MEDIAMTX_WEBRTC__ __PORT_MEDIAMTX_HLS__
__PORT_MEDIAMTX_API__`.

## Template contents (skeleton = clean base, no scenario features)
- **backend:** edge base app (main/registry/api[routers=[]] /domain[models empty;
  perms `__SLUG__.read` / `__SLUG__.manage`]); migrations = platform base
  (0001_baseline metadata.create_all + 0002 + 0003); Dockerfile/compose for standalone.
- **frontend:** clean Next scaffold (post DashCode-cleanup: no components/constant/
  hooks/store/configs); `views/Home.jsx` placeholder; `menu.js` = Dashboard + feature
  placeholder + Audit + Settings(common admin); tailwind content incl. `./views`+`./menu.js`
  + colour safelist; binds `platform/web` via `@/web/*`.

## Verification (build-time smoke test)
Generate a throwaway `_smoke` scenario → assert `docker compose config` valid, backend
`py_compile` clean, expected files present, ports don't collide → delete it.

## Non-goals
- Migrating frs/suspect out of the monorepo now.
- Publishing platform as pip/npm packages.
- Auto-updating vendored platform (explicit `sync-platform` only).
