# Vizor scenario tooling

`scenarios/` is the **platform + tooling source of truth**: it holds the shared
`platform/` (edge backend + web UI), the `template/` skeleton, and these tools.
Each scenario is generated as its **own standalone repo** with `platform/` vendored in.

## Create a new scenario repo
```bash
tools/create-scenario "PPE Detection"          # -> ../ppe/  (own git repo)
tools/create-scenario "Crowd Analytics" --slug crowd --out ~/work
```
Auto-assigns unique host ports (registry: `tools/ports-registry.json`). Then:
```bash
cd ../ppe && docker compose up -d --build
```

## Update a scenario's vendored platform
```bash
tools/sync-platform ../ppe        # or, inside the repo: ./sync-platform.sh
```

Ports: index N (from registry) → backend 8000+N, frontend 3000+N, postgres 5432+N,
redis 6379+N, qdrant 6333+N, rustfs 9000+2N/9001+2N, maildev 1025+N/1080+N,
mediamtx 8554+N/8889+N/8888+N/9997+N. (frs=0, suspect=1.)
