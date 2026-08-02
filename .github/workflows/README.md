# Client image build (repository_dispatch)

Build and push a client ERPNext image to GHCR from a `repository_dispatch` event. Deploy is manual.

## Prerequisites

- A GitHub PAT with **`repo`** scope (to call the dispatches API).
- Repository secret **`CUSTOMISATION_TOKEN`** — PAT that can clone private app repos (`bench get-app`).

## Event types

| `event_type` | Effect |
| --- | --- |
| `client-stage-deploy` | Build + push; `CUSTOM_WHITELIST_BRANCH=stage` |
| `client-prod-deploy` | Build + push; `CUSTOM_WHITELIST_BRANCH=prod` |

Image tag: `ghcr.io/dexqbit/erpnext-{branch}:latest`

## Required `client_payload` fields

| Field | Purpose |
| --- | --- |
| `branch` | Checkout ref + image tag suffix |
| `whitelist_github_path` | Private app `owner/repo` (e.g. `DexQBit/MLBR-Sparebox-BE`) |
| `bench_install_apps` | Space-separated apps to bake/install (e.g. `sparebox_be`) |

## Stage

```bash
curl -i -X POST \
  -H "Authorization: token PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/DexQBit/ERPNextDockerDebian/dispatches \
  -d '{
    "event_type": "client-stage-deploy",
    "client_payload": {
      "branch": "sparebox-stage",
      "whitelist_github_path": "DexQBit/MLBR-Sparebox-BE",
      "bench_install_apps": "sparebox_be"
    }
  }'
```

## Prod

```bash
curl -i -X POST \
  -H "Authorization: token PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/DexQBit/ERPNextDockerDebian/dispatches \
  -d '{
    "event_type": "client-prod-deploy",
    "client_payload": {
      "branch": "sparebox-prod",
      "whitelist_github_path": "DexQBit/MLBR-Sparebox-BE",
      "bench_install_apps": "sparebox_be"
    }
  }'
```

Replace `PAT` with your token. Swap payload values for other clients.

## Manual deploy (on the host)

After the image is in GHCR, SSH to the deploy host and run from the deploy directory (e.g. `/home/ubuntu/deploy`). Replace `COMPOSE_PROJECT`, `ENV_FILE`, and `SITE` for your client/env.

Example (Sparebox stage): `COMPOSE_PROJECT=sparebox_stage`, `ENV_FILE=secrets/sparebox_stage.env`, `SITE=sparebox-stage.local`.

```bash
docker image prune -a -f
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE down
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE pull
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE up -d
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE exec --user frappe erpnext bash -c "bench --site SITE migrate"
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE exec --user frappe erpnext bash -c "bench build"
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE exec --user frappe erpnext bash -c "bench --site SITE clear-cache"
```
