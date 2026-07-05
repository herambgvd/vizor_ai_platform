# Vizor AI Platform + Scenario Tooling

Source of truth for the shared **edge** backend + **web** UI and the scenario generator.
Each scenario is generated as its **own standalone repo** with `platform/` vendored in.

## Contents
- `platform/` — edge backend (`edge` pip pkg) + shared web UI (`@/web`)
- `template/` — tokenized standalone scenario skeleton
- `tools/create-scenario` — generate a new scenario repo
- `tools/sync-platform` — push platform updates into a scenario repo
- `tools/ports-registry.json` — scenario → host-port index

## Create a scenario
```bash
tools/create-scenario "PPE Detection"     # -> ../ppe/  (own git repo)
cd ../ppe && docker compose up -d --build
```
