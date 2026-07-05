# Vizor Shared Infra

One set of backing services shared by **all** scenario stacks on a client host.
Instead of every scenario running its own Postgres + Redis + Qdrant + RustFS +
MediaMTX (N× waste when a client buys multiple scenarios), you run this **once**
and point each scenario at it.

```
vizor-infra (this)              scenario stacks (app-only)
┌───────────────────────┐       ┌──────────────────────────────┐
│ vizor-postgres  :5432 │◀──────│ frs   backend/worker/beat/ui  │  :8000 / :3000
│ vizor-redis     :6379 │◀──────│ suspect …                     │  :8001 / :3001
│ vizor-qdrant    :6333 │◀──────│ ppe …                         │  :8002 / :3002
│ vizor-rustfs    :9000 │◀──────│ anpr / fire / people-analytics│  …
│ vizor-mediamtx  :9997 │       └──────────────────────────────┘
│ vizor-maildev   :1080 │        all joined on network: vizor_shared
└───────────────────────┘
```

## Isolation (no cross-talk despite sharing)

| Service   | Shared how                                            |
|-----------|-------------------------------------------------------|
| Postgres  | one server, **one database per scenario** (`frs`, `suspect`, …) |
| Redis     | one server, **one logical DB-number per scenario** (`/0`, `/1`, … from the port-index; max 16) |
| Qdrant    | one server, **app-specific collection names** per scenario |
| RustFS/S3 | one server, **one bucket per scenario** (`vizor-<slug>`, auto-created) |
| MediaMTX  | one media server, camera **paths namespaced** at runtime |

## Run

```bash
cp .env.example .env          # edit creds for anything beyond local dev
docker compose up -d
```

Then start each scenario in **shared mode** (from its own repo):

```bash
cd ../vizor_ai_frs
cp .env.shared.example .env.shared     # already points at vizor-* hosts
docker compose -f docker-compose.shared.yml --env-file .env.shared up -d --build
```

Each scenario backend creates its own database on first boot (`scripts/ensure_db.py`)
and its own S3 bucket on first write — no manual provisioning.

## Standalone vs shared — pick one per host

- **Standalone** (`docker-compose.yml` in each scenario): fully self-contained,
  own infra. Best for dev / single-scenario / distribution demos.
- **Shared** (`docker-compose.shared.yml` + this): one infra, many scenarios.
  Best for a client running multiple scenarios on one box.

Don't mix modes on the same host — the standalone infra host-ports (5432/6379/…)
collide with this. Use shared infra for multi-scenario clients.

## Scaling out

For production, replace these containers with managed services (RDS Postgres,
managed Redis, Qdrant Cloud, S3). Only the `VE_*` values in each `.env.shared`
change — no code and no compose changes in the scenarios.
