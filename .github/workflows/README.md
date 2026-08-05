# Client image build (repository_dispatch)

Build and push a client ERPNext image to GHCR from a `repository_dispatch` event. Deploy is manual.

CI always checks out this repo’s `**prod**` branch. Clients are distinguished by `client` in the payload and the event type (`stage` / `prod`).

## Prerequisites

- A GitHub PAT with `**repo**` scope (to call the dispatches API).
- Repository secret `**CUSTOMISATION_TOKEN**` — PAT that can clone private app repos (`bench get-app`).

## Event types

| `event_type`          | Effect                                        |
| --------------------- | --------------------------------------------- |
| `client-stage-deploy` | Build + push; `CUSTOM_WHITELIST_BRANCH=stage` |
| `client-prod-deploy`  | Build + push; `CUSTOM_WHITELIST_BRANCH=prod`  |

Image tag: `ghcr.io/dexqbit/{client}-{stage|prod}:latest`

## Required `client_payload` fields

| Field                   | Purpose                                                                                               |
| ----------------------- | ----------------------------------------------------------------------------------------------------- |
| `client`                | Client slug used in the image tag (e.g. `sparebox`)                                                   |
| `whitelist_github_path` | Private app `owner/repo` (e.g. `DexQBit/MLBR-Sparebox-BE`)                                            |
| `bench_install_apps`    | Space-separated apps to bake/install (`erpnext`, `payments`, `hrms`, `crm`, plus custom folder names) |

## Optional version fields (defaults keep v15 behaviour)

| Field                | Default             | Purpose                                                               |
| -------------------- | ------------------- | --------------------------------------------------------------------- |
| `pipech_image_tag`   | `version-15-latest`   | Builder base: `pipech/erpnext-docker-debian:{tag}`                    |
| `frappe_bench_image` | `frappe/bench:v5.22.9` | Production stage base (must match Python: v15→v5.22.9, v16→v5.29.0) |
| `frappe_apps_branch` | `version-15`          | Branch for official `frappe/payments` and `frappe/hrms`               |
| `crm_branch`         | `main`                | Branch for official `frappe/crm` (no `version-N`; use `main`)         |
| `erpnext_branch`     | `prod`                | Branch on `DexQBit/erpnext` when `erpnext` is in `bench_install_apps` |

## Stage (Sparebox / v15 defaults)

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

Produces: `ghcr.io/dexqbit/sparebox-stage:latest`

## Prod (Sparebox)

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

Produces: `ghcr.io/dexqbit/sparebox-prod:latest`

## Dexi (v16 + HRMS + CRM)

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
      "bench_install_apps": "erpnext hrms crm erpnext_app_dexi",
      "pipech_image_tag": "version-16-latest",
      "frappe_bench_image": "frappe/bench:v5.29.0",
      "frappe_apps_branch": "version-16",
      "crm_branch": "main",
      "erpnext_branch": "version-16"
    }
  }'
```

- Base image: `pipech/erpnext-docker-debian:version-16-latest`
- Production base: `frappe/bench:v5.29.0` (Python 3.14 for v16; `v5.22.9` lacks that Python → `bench build` FileNotFoundError)
- ERPNext: `DexQBit/erpnext@version-16`
- HRMS: official `frappe/hrms@version-16`
- CRM: official `frappe/crm@main` (CRM has no `version-16` branch)
- Whitelist app: `DexQBit/erpnext_app_dexi` at `stage` or `prod` from the event type

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

### List apps in the image / installed on the site

```bash
# Apps present under bench/apps (baked into the image)
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE exec --user frappe erpnext bash -c "ls apps"

# Apps installed on the site
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE exec --user frappe erpnext bash -c "bench --site SITE list-apps"
```

### Install an extra app on an existing site

The app must already be in the image (`ls apps`). First-boot installs use `BENCH_INSTALL_APPS` in the env file; for an existing site, install manually then migrate:

```bash
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE exec --user frappe erpnext bash -c "bench --site SITE install-app hrms"
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE exec --user frappe erpnext bash -c "bench --site SITE install-app crm"
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE exec --user frappe erpnext bash -c "bench --site SITE migrate"
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE exec --user frappe erpnext bash -c "bench build"
docker compose -p COMPOSE_PROJECT -f compose.yml --env-file ENV_FILE exec --user frappe erpnext bash -c "bench --site SITE clear-cache"
```

Replace `hrms` / `crm` with any other app folder name under `bench/apps`.
