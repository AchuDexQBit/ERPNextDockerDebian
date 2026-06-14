# AWS deploy with auto-deploy (GitHub Actions → SSH)

Deploy a **Frappe backend** (custom app only or ERPNext + apps) on **AWS EC2** using the **GHCR** image from CI, and **automatically redeploy** the app container after each successful build.

**Flow:**

```text
push client branch → build.yml builds image → push GHCR :latest → SSH to EC2 → compose pull erpnext → compose up -d erpnext
```

MariaDB and Redis stay running; only the **`erpnext`** compose service is updated (historical name — it runs the Frappe bench image). Site and DB data live in Docker volumes.

See also [`deploy/README.md`](../deploy/README.md) for branch naming and shared concepts.

---

## Deployment modes

| Mode                                    | Image build (CI)                                                               | First-site install (EC2 env)                                         |
| --------------------------------------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| **ERPNext client**                      | `CUSTOM_ERPNEXT_GITHUB_PATH=YourOrg/erpnext-fork`                              | `BENCH_INSTALL_APPS=erpnext` (default) + optional `BENCH_EXTRA_APPS` |
| **Frappe-only backend** (e.g. Sparebox) | `CUSTOM_ERPNEXT_GITHUB_PATH=` (empty) + `CUSTOM_WHITELIST_*` for your app repo | `BENCH_INSTALL_APPS=<app_folder_name>`                               |

You always need **Frappe + MariaDB + Redis**. ERPNext is optional — only install it if your app depends on it.

---

## Sparebox example (Frappe-only, `sparebox-stage`)

This repo’s [`build.yml`](../.github/workflows/build.yml) is configured for branch **`sparebox-stage`**:

**CI build-args:**

```yaml
CUSTOM_ERPNEXT_GITHUB_PATH=          # empty — no ERPNext in the image
CUSTOM_WHITELIST_GITHUB_PATH=DexQBit/MLBR-Sparebox-BE
CUSTOM_WHITELIST_BRANCH=stage
BENCH_INSTALL_APPS=mlbr_sparebox_be    # folder under bench/apps/ (verify in your repo)
```

**GHCR tag:** `ghcr.io/dexqbit/erpnext-sparebox-stage:latest`

**EC2 env:** copy [`deploy/client.env.frappe-backend.example`](../deploy/client.env.frappe-backend.example) → `~/deploy/secrets/sparebox_stage.env` and fill in passwords / URLs.

**Auto-deploy job** (already in `build.yml`):

```yaml
deploy-aws:
  needs: build-and-push
  if: github.ref == 'refs/heads/sparebox-stage'
  environment: sparebox-stage
  # … SSH → compose pull/up erpnext …
```

**Verify app folder name** (must match `BENCH_INSTALL_APPS`):

```sh
# after a local or CI build, or inside the running container:
ls /home/frappe/bench/apps/
```

If the folder is not `mlbr_sparebox_be`, update `build.yml`, EC2 env, and [`deploy/client.env.frappe-backend.example`](../deploy/client.env.frappe-backend.example).

---

## Prerequisites

1. **Client branch** `<client_name>-<env>` (e.g. `sparebox-stage`) with CI publishing  
   `ghcr.io/dexqbit/erpnext-<branch>:latest`.
2. **EC2** (Ubuntu 22.04+) with Docker Engine and Compose v2.
3. **Security group:** SSH (22) for setup; for CI SSH, see [Security](#security).
4. **GHCR login on EC2** (once):

   ```sh
   echo <PAT_with_read:packages> | docker login ghcr.io -u <github_user> --password-stdin
   ```

5. **First manual deploy** on EC2 (creates volumes + site) before relying on auto-deploy:

   ```sh
   cd /home/ubuntu/deploy
   docker compose -p sparebox_stage -f compose.yml --env-file secrets/sparebox_stage.env up -d
   ```

---

## EC2 layout

```text
/home/ubuntu/deploy/
  compose.yml              # copy of deploy/compose.ghcr.yml
  secrets/
    sparebox_stage.env     # runtime secrets (gitignored on your laptop)
```

**Frappe-only env** (`secrets/sparebox_stage.env`):

```env
CLIENT_ENV_FILE=secrets/sparebox_stage.env
GHCR_IMAGE=ghcr.io/dexqbit/erpnext-sparebox-stage:latest
ERPNext_HTTP_PORT=80
RFP_DOMAIN_NAME=site1.local
RFP_PUBLIC_URL=https://api.yourdomain.com
RFP_SITE_ADMIN_PASSWORD=…
RFP_DB_HOST=db
RFP_DB_PORT=3306
RFP_DB_ROOT_PASSWORD=…
RFP_REDIS_URL=redis://redis:6379
BENCH_INSTALL_APPS=mlbr_sparebox_be
BENCH_EXTRA_APPS=
```

**ERPNext client env:** use [`deploy/client.env.example`](../deploy/client.env.example) instead; omit `BENCH_INSTALL_APPS` or set `erpnext`.

Compose project name (isolates stacks on one host):

```sh
docker compose -p sparebox_stage …
```

---

## CI: build the image

Push the client branch → [`.github/workflows/build.yml`](../.github/workflows/build.yml).

### Frappe-only (no ERPNext)

In `build-args` for that branch:

```yaml
build-args: |
  GITHUB_PAT_TOKEN=${{ secrets.CUSTOMISATION_TOKEN }}
  DEPLOY_TARGET=ci
  CUSTOM_ERPNEXT_GITHUB_PATH=
  CUSTOM_WHITELIST_GITHUB_PATH=DexQBit/Your-App-Repo
  CUSTOM_WHITELIST_BRANCH=stage
  BENCH_INSTALL_APPS=your_app_folder
```

### ERPNext client

```yaml
build-args: |
  GITHUB_PAT_TOKEN=${{ secrets.CUSTOMISATION_TOKEN }}
  DEPLOY_TARGET=ci
  CUSTOM_ERPNEXT_GITHUB_PATH=YourOrg/your-erpnext-fork
  CUSTOM_ERPNEXT_BRANCH=prod
  CUSTOM_WHITELIST_GITHUB_PATH=YourOrg/extra-app   # optional
  CUSTOM_WHITELIST_BRANCH=main
  BENCH_INSTALL_APPS=erpnext
```

`BENCH_INSTALL_APPS` is baked into the image `ENV` and should match the EC2 env file.

---

## GitHub secrets

**Settings → Secrets and variables → Actions** (or per-branch **Environment**, e.g. `sparebox-stage`):

| Secret                | Description                                                            |
| --------------------- | ---------------------------------------------------------------------- |
| `AWS_EC2_HOST`        | EC2 public IP or DNS                                                   |
| `AWS_EC2_USER`        | e.g. `ubuntu`                                                          |
| `AWS_EC2_SSH_KEY`     | Private key (PEM) for the instance                                     |
| `CUSTOMISATION_TOKEN` | PAT for private `bench get-app` in CI (repo scope + org SSO if needed) |

---

## Auto-deploy in CI

The **`deploy-aws`** job runs after **`build-and-push`** when the branch matches `if:`.

Current Sparebox config:

```yaml
deploy-aws:
  needs: build-and-push
  if: github.ref == 'refs/heads/sparebox-stage'
  runs-on: ubuntu-latest
  environment: sparebox-stage
  steps:
    - name: Deploy Frappe backend on AWS EC2
      uses: appleboy/ssh-action@v1.2.0
      with:
        host: ${{ secrets.AWS_EC2_HOST }}
        username: ${{ secrets.AWS_EC2_USER }}
        key: ${{ secrets.AWS_EC2_SSH_KEY }}
        script_stop: true
        script: |
          set -e
          cd /home/ubuntu/deploy
          docker compose -p sparebox_stage -f compose.yml --env-file secrets/sparebox_stage.env pull erpnext
          docker compose -p sparebox_stage -f compose.yml --env-file secrets/sparebox_stage.env up -d erpnext
```

Add another client: duplicate the job with a different `if:`, `-p` project name, and env file path.

---

## What happens on each push

1. **build-and-push** — clones your app(s) in the Dockerfile builder, pushes GHCR `:latest`.
2. **deploy-aws** — SSH: `pull erpnext` → `up -d erpnext`.

**Not restarted:** `db`, `redis`.  
**Preserved:** `frappe_sites`, `mariadb_data` volumes.

**Do not** run `docker compose down -v` for routine updates (wipes DB and sites).

If the site was first created **with ERPNext** and you switch to **Frappe-only**, reset volumes once or use a new `RFP_DOMAIN_NAME` — the old site DB will not match.

---

## Security

- Use a **dedicated SSH key** for CI (`AWS_EC2_SSH_KEY`), not your personal key.
- **Security group:** GitHub-hosted runners use [dynamic IPs](https://api.github.com/meta). Prefer a self-hosted runner, VPN, or SSM over wide-open SSH.
- Deploy script only updates one compose project and the `erpnext` service.

---

## Verify auto-deploy

1. Push to `sparebox-stage` (or your branch).
2. GitHub Actions: **build-and-push** → **deploy-aws** both green.
3. On EC2:

   ```sh
   docker compose -p sparebox_stage -f ~/deploy/compose.yml ps
   docker compose -p sparebox_stage -f ~/deploy/compose.yml logs -f --tail=100 erpnext
   ```

4. Hit `RFP_PUBLIC_URL` or EC2:80; log in with `RFP_SITE_ADMIN_PASSWORD`.

---

## App code updates

| Change                             | Action                                                                                                                                            |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Python/JS in custom app            | Push app repo → push deploy branch → CI rebuild → auto-deploy                                                                                     |
| New app in image (`bench get-app`) | Update Dockerfile / CI build-args; set `BENCH_INSTALL_APPS` before **first** site only                                                            |
| DB schema                          | After deploy: `docker compose -p sparebox_stage … exec --user frappe erpnext bash -c "cd /home/frappe/bench && bench --site site1.local migrate"` |
| Env only (`RFP_*`, `BENCH_*`)      | Edit env on EC2 → `up -d erpnext` (no CI)                                                                                                         |

---

## Troubleshooting

| Symptom                             | Likely fix                                                                          |
| ----------------------------------- | ----------------------------------------------------------------------------------- |
| CI `git clone` fails on private app | `CUSTOMISATION_TOKEN` access + org SSO; correct branch in `CUSTOM_WHITELIST_BRANCH` |
| `install-app` / new-site fails      | Wrong `BENCH_INSTALL_APPS` — check `ls apps/` in the image                          |
| `deploy-aws` skipped                | `if: github.ref` must match branch exactly                                          |
| SSH fails                           | Security group, `AWS_EC2_HOST`, key pair                                            |
| `pull` fails on EC2                 | `docker login ghcr.io` on EC2                                                       |
| Site loop / “already exists”        | `frappe_sites` volume; see [`deploy/README.md`](../deploy/README.md)                |
| ERPNext UI but wanted Frappe-only   | Rebuild with empty `CUSTOM_ERPNEXT_GITHUB_PATH`; reset site/volumes                 |
| Old code after deploy               | Confirm new GHCR image; manual `pull erpnext` on EC2                                |

---

## Related files

| Path                                                                                      | Role                                                           |
| ----------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| [`deploy/compose.ghcr.yml`](../deploy/compose.ghcr.yml)                                   | MariaDB + Redis + app container → copy to EC2 as `compose.yml` |
| [`deploy/client.env.frappe-backend.example`](../deploy/client.env.frappe-backend.example) | Frappe-only env template (Sparebox)                            |
| [`deploy/client.env.example`](../deploy/client.env.example)                               | ERPNext client env template                                    |
| [`deploy/shared/Dockerfile`](../deploy/shared/Dockerfile)                                 | Image build (`CUSTOM_ERPNEXT_*`, `CUSTOM_WHITELIST_*`)         |
| [`deploy/shared/setup.sh`](../deploy/shared/setup.sh)                                     | First boot: `bench new-site` + `BENCH_INSTALL_APPS`            |
| [`.github/workflows/build.yml`](../.github/workflows/build.yml)                           | Build, push GHCR, deploy-aws                                   |
| [`aws/docker-compose.yml`](docker-compose.yml)                                            | Optional on-EC2 **build** path; production uses GHCR compose   |
