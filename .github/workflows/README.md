# Client image build (repository_dispatch)

Build and push a client ERPNext image to GHCR from a `repository_dispatch` event. Deploy is manual.

CI always checks out this repo’s **`prod`** branch. Clients are distinguished by `client` in the payload and the event type (`stage` / `prod`).

## Prerequisites

- A GitHub PAT with **`repo`** scope (to call the dispatches API).
- Repository secret **`CUSTOMISATION_TOKEN`** — PAT that can clone private app repos (`bench get-app`).

## Event types

| `event_type` | Effect |
| --- | --- |
| `client-stage-deploy` | Build + push; `CUSTOM_WHITELIST_BRANCH=stage` |
| `client-prod-deploy` | Build + push; `CUSTOM_WHITELIST_BRANCH=prod` |

Image tag: `ghcr.io/dexqbit/erpnext-{client}-{stage|prod}:latest`

## Required `client_payload` fields

| Field | Purpose |
| --- | --- |
| `client` | Client slug used in the image tag (e.g. `sparebox`) |
| `whitelist_github_path` | Private app `owner/repo` (e.g. `DexQBit/MLBR-Sparebox-BE`) |
| `bench_install_apps` | Space-separated apps to bake/install. Include `erpnext` when the client needs it (e.g. `erpnext erpnext_app_dexi`). Sparebox-style Frappe-only: `sparebox_be` |

## Stage

```bash
curl -i -X POST \
  -H "Authorization: token PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/DexQBit/ERPNextDockerDebian/dispatches \
  -d '{
    "event_type": "client-stage-deploy",
    "client_payload": {
      "client": "sparebox",
      "whitelist_github_path": "DexQBit/MLBR-Sparebox-BE",
      "bench_install_apps": "sparebox_be"
    }
  }'
```

Produces: `ghcr.io/dexqbit/erpnext-sparebox-stage:latest`

## Prod

```bash
curl -i -X POST \
  -H "Authorization: token PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/DexQBit/ERPNextDockerDebian/dispatches \
  -d '{
    "event_type": "client-prod-deploy",
    "client_payload": {
      "client": "sparebox",
      "whitelist_github_path": "DexQBit/MLBR-Sparebox-BE",
      "bench_install_apps": "sparebox_be"
    }
  }'
```

Produces: `ghcr.io/dexqbit/erpnext-sparebox-prod:latest`

### Dexi (needs ERPNext)

```bash
curl -i -X POST \
  -H "Authorization: token PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/DexQBit/ERPNextDockerDebian/dispatches \
  -d '{
    "event_type": "client-stage-deploy",
    "client_payload": {
      "client": "dexi",
      "whitelist_github_path": "DexQBit/erpnext_app_dexi",
      "bench_install_apps": "erpnext erpnext_app_dexi"
    }
  }'
```

`erpnext` is cloned from `DexQBit/erpnext@prod` (Dockerfile defaults). The whitelist app uses branch `stage` or `prod` from the event type.

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
