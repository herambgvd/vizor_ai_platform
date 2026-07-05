# __NAME__

Standalone Vizor scenario app — FastAPI backend on the shared **edge** boilerplate +
a DashCode Next.js frontend. The shared platform is **vendored** at `./platform`
(update it with `./sync-platform.sh`).

## Run (dev)
```bash
cp .env.example .env
docker compose up -d --build
```
- Frontend: http://localhost:__PORT_FRONTEND__
- Backend API: http://localhost:__PORT_BACKEND__/api/v1
- Login: support@geniusvision.in / Gvd@6001 (dev bootstrap admin)

## Layout
```
platform/    vendored edge backend (/edge) + shared web UI (@/web)
backend/     this scenario's FastAPI app (app/, migrations/)  — build features under app/
frontend/    this scenario's Next.js app — scenario UI in views/, nav in menu.js
```
- Scenario UI lives in `frontend/views/` (NOT `platform/web`); nav in `frontend/menu.js`.
- Common admin UI (users/roles/branding/…) comes from `@/web/*` (the vendored platform).

## Update the shared platform
```bash
PLATFORM_SRC=/path/to/scenarios/platform ./sync-platform.sh
```
