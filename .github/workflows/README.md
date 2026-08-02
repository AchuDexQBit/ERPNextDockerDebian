# Client image build (repository_dispatch)

Build and push a client ERPNext image to GHCR from a `repository_dispatch` event. Stage also deploys to AWS EC2; prod only builds and pushes.

## Prerequisites

- A GitHub PAT with **`repo`** scope (to call the dispatches API).
- Repository secret **`CUSTOMISATION_TOKEN`** — PAT that can clone private app repos (`bench get-app`).
- For stage deploy: secrets **`AWS_EC2_HOST`**, **`AWS_EC2_USER`**, **`AWS_EC2_SSH_KEY`**.
- GitHub Environments named `{client}-stage` and `{client}-prod` as needed (e.g. `sparebox-stage`).

## Event types

| `event_type` | Build + push GHCR | Deploy on AWS EC2 |
| --- | --- | --- |
| `client-stage-deploy` | Yes | Yes |
| `client-prod-deploy` | Yes | No |

`TARGET_ENV` (and thus `CUSTOM_WHITELIST_BRANCH`) is **`prod`** for `client-prod-deploy`, otherwise **`stage`**.

Image tag: `ghcr.io/dexqbit/erpnext-{branch}:latest`

## Required `client_payload` fields

| Field | Purpose |
| --- | --- |
| `client` | GitHub Environment prefix (`{client}-stage` / `{client}-prod`) |
| `branch` | Checkout ref + image tag suffix |
| `whitelist_github_path` | Private app `owner/repo` (e.g. `DexQBit/MLBR-Sparebox-BE`) |
| `bench_install_apps` | Space-separated apps to bake/install (e.g. `sparebox_be`) |
| `site` | Bench site name (migrate / clear-cache) |
| `env_file` | Compose `--env-file` path on the EC2 host |
| `compose_project` | Docker Compose project name (`-p`) |

## Stage (build + deploy)

```bash
curl -i -X POST \
  -H "Authorization: token PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/DexQBit/ERPNextDockerDebian/dispatches \
  -d '{
    "event_type": "client-stage-deploy",
    "client_payload": {
      "client": "sparebox",
      "branch": "sparebox-stage",
      "site": "sparebox-stage.local",
      "env_file": "secrets/sparebox_stage.env",
      "compose_project": "sparebox_stage",
      "whitelist_github_path": "DexQBit/MLBR-Sparebox-BE",
      "bench_install_apps": "sparebox_be"
    }
  }'
```

## Prod (build only)

```bash
curl -i -X POST \
  -H "Authorization: token PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/DexQBit/ERPNextDockerDebian/dispatches \
  -d '{
    "event_type": "client-prod-deploy",
    "client_payload": {
      "client": "sparebox",
      "branch": "sparebox-prod",
      "site": "sparebox-prod.local",
      "env_file": "secrets/sparebox_prod.env",
      "compose_project": "sparebox_prod",
      "whitelist_github_path": "DexQBit/MLBR-Sparebox-BE",
      "bench_install_apps": "sparebox_be"
    }
  }'
```

Replace `PAT` with your token. Swap payload values for other clients (different `client`, `branch`, app path, bench apps, site, env file, and compose project).
