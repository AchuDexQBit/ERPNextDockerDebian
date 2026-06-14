# Deploy a custom Frappe app on Render

This guide covers deploying a **client-specific Frappe / ERPNext backend** on [Render](https://render.com) using the image CI publishes to **GHCR**. It mirrors [`deploy/compose.ghcr.yml`](../deploy/compose.ghcr.yml) (MariaDB + Redis + ERPNext) as separate Render services.

> **Render does not run Docker Compose.** You cannot point Render at `deploy/compose.ghcr.yml`. Use the steps below instead.

---

## Free plan (Hobby workspace)

This section applies if you are on Render’s **Free** instance types. Read it before deploying.

### What Render gives you for free

| Service type | Free tier? | Notes |
| ------------ | ---------- | ----- |
| **Web Service** (ERPNext) | Yes | 512 MB RAM; spins down after **15 min** idle (~1 min cold start) |
| **Key Value** (Redis) | Yes | **25 MB** RAM; **no persistence** — data lost on restart |
| **Private Service** (MariaDB) | **No** | Must use a **paid** instance (Starter+) |
| **Persistent disk** | **No** on Free web | Site uploads / `sites/` are **lost** on redeploy, restart, or spin-down |

Other Free limits: **750 instance-hours/month** per workspace; **one** Free Key Value instance; no shell/SSH on Free web services. See [Render Free docs](https://render.com/docs/free).

### Can ERPNext run on Free?

**Only as a demo / smoke test — not for real use.**

- ERPNext + Frappe usually needs **more than 512 MB RAM**; the Free web service may OOM or fail during `bench new-site` / `bench build`.
- Without a **paid disk** on the web service, `/home/frappe/bench/sites` is ephemeral — you can lose the site on every spin-down or redeploy.
- **MariaDB cannot be Free on Render** — you still need at least a **paid Private Service** for the database (with a disk), or an **external MariaDB** host.
- Free Redis is fine for trying cache/queue, but queues are wiped when Redis restarts.

### Minimum cost on Render (realistic)

| Component | Suggested plan |
| --------- | -------------- |
| ERPNext web | **Starter** ($7/mo) or **Standard** — attach disk at `/home/frappe/bench/sites` |
| MariaDB | **Starter** Private Service + disk at `/var/lib/mysql` |
| Redis | **Free** (demo) or **Starter** Key Value (persistence) |

**Cheapest Render path that can actually hold data:** paid MariaDB pserv + Free web (still no site disk — fragile) → upgrade web to Starter + disk as soon as you care about the site.

### Free-plan deploy summary

1. **CI** — same as below (build GHCR image).
2. **MariaDB** — paid Private Service **or** external MariaDB; set `RFP_DB_HOST` to that hostname.
3. **Redis** — Free Key Value; set `RFP_REDIS_URL` from the internal connection string.
4. **ERPNext** — Free Web Service, **Existing Image** from GHCR, `PORT=80`, runtime env vars below. **Do not expect a disk option** on Free.
5. Accept spin-down, cold starts, and possible data loss — or upgrade to paid.

The steps in **Part 2** below call out **Free** vs **paid** where it matters.

---

## How it fits together

| Layer | Where it happens |
| ----- | ---------------- |
| Custom app **code** cloned into the image | GitHub Actions → `bench get-app` in [`deploy/shared/Dockerfile`](../deploy/shared/Dockerfile) |
| Image published | `ghcr.io/dexqbit/erpnext-<branch>:latest` via [`.github/workflows/build.yml`](../.github/workflows/build.yml) |
| Runtime (site, DB, Redis) | Render services + environment variables |
| Site files persistence | Render disk on the web service at `/home/frappe/bench/sites` |

**Recommended:** build in CI, pull the GHCR image on Render (faster deploys, same flow as Hetzner).

**Alternative:** build on Render from `render/Dockerfile` using [`render.yaml`](../render.yaml) (Blueprint). Slower; use only if you skip GHCR.

---

## Prerequisites

1. A **client branch** named `<client_name>-<env>` (e.g. `acme-prod`). See [`deploy/README.md`](../deploy/README.md).
2. On that branch, [`deploy/shared/Dockerfile`](../deploy/shared/Dockerfile) clones your forks:
   - `CUSTOM_ERPNEXT_GITHUB_PATH` / `CUSTOM_ERPNEXT_BRANCH` — customised ERPNext repo
   - `CUSTOM_WHITELIST_GITHUB_PATH` / `CUSTOM_WHITELIST_BRANCH` — optional private Frappe app
   - Extra public apps: add `bench get-app` lines in the builder stage
3. GitHub Actions secret **`CUSTOMISATION_TOKEN`** — PAT with access to private app repos.
4. A Render account.

---

## Part 1 — Build the custom app image (CI)

### 1. Configure the branch

On your client branch, set build args in **either**:

- [`deploy/shared/Dockerfile`](../deploy/shared/Dockerfile) `ARG` defaults, **or**
- [`.github/workflows/build.yml`](../.github/workflows/build.yml) `build-args` (as in the whitelist example).

Example build-args in CI:

```yaml
build-args: |
  GITHUB_PAT_TOKEN=${{ secrets.CUSTOMISATION_TOKEN }}
  DEPLOY_TARGET=ci
  CUSTOM_ERPNEXT_GITHUB_PATH=YourOrg/your-erpnext-fork
  CUSTOM_ERPNEXT_BRANCH=main
  CUSTOM_WHITELIST_GITHUB_PATH=YourOrg/your-private-app
  CUSTOM_WHITELIST_BRANCH=main
```

If the app must be **installed on the site** at first boot (not only cloned), set `BENCH_EXTRA_APPS` in the Dockerfile `ENV` or on Render (space-separated app folder names, e.g. `payments my_custom_app`).

### 2. Push to trigger a build

```sh
git push origin <client_name>-<env>
```

CI publishes:

```text
ghcr.io/dexqbit/erpnext-<client_name>-<env>:latest
```

Confirm under **GitHub → Packages** before deploying.

### 3. Create a new build after app code changes

1. Push changes to your **custom app repo(s)**.
2. Push the **client branch** in this repo (or re-run the **Build and Push Client Image** workflow).
3. **Redeploy on Render** (image-backed services do not auto-pull `:latest` — see [Part 4](#part-4--redeploy-after-a-new-build)).

---

## Part 2 — Deploy on Render (GHCR image)

### Step 1 — GHCR registry credential (private packages)

Skip if the package is **public**.

1. Render Dashboard → **Workspace Settings** → **Registry Credentials**
2. Add **GitHub Container Registry**
   - Username: your GitHub user
   - Password: PAT with **`read:packages`**
3. Name it e.g. `ghcr-dexqbit`

### Step 2 — MariaDB (private service)

Equivalent to the `db` service in compose.

> **Free plan:** Private Services **do not** offer a Free instance type. Use the **Starter** plan (or higher) and attach a disk. Alternatively, host MariaDB elsewhere (VPS, RDS, etc.) and set `RFP_DB_HOST` to that hostname.

1. **New** → **Private Service** → **Existing Image**
2. Image: `docker.io/library/mariadb:10.11`
3. Name: e.g. `erpnext-db`
4. **Instance type:** **Starter** (minimum for a persistent DB on Render)
5. Environment:

   | Key | Value |
   | --- | ----- |
   | `MARIADB_ROOT_PASSWORD` | strong password (save it) |
   | `MARIADB_CHARACTER_SET_SERVER` | `utf8mb4` |
   | `MARIADB_COLLATE_SERVER` | `utf8mb4_unicode_ci` |

6. **Disk:** `/var/lib/mysql`, e.g. 10 GB (**required** — paid plans only)
7. Create and note the internal hostname (e.g. `erpnext-db`)

### Step 3 — Redis (Key Value)

Equivalent to the `redis` service in compose.

1. **New** → **Key Value**
2. Name: e.g. `erpnext-redis`
3. **Instance type:** **Free** (demo; no persistence) or **Starter** (recommended if you keep queues/cache across restarts)
4. Create; copy the internal **`redis://…`** connection string from the service page

### Step 4 — ERPNext web service (GHCR image)

Equivalent to the `erpnext` service in compose.

1. **New** → **Web Service** → **Existing Image**
2. Image: `ghcr.io/dexqbit/erpnext-<client_name>-<env>:latest`
3. Registry credential: select from Step 1 (if private)
4. **Instance type:**
   - **Free** — demo only (512 MB RAM, spin-down, no disk, site data not durable)
   - **Starter** or **Standard** — use for anything you want to keep; attach a disk (next step)
5. **Disk (paid web only):** `/home/frappe/bench/sites`, e.g. 10 GB — **required** for durable site files. **Not available on Free.**
6. **Health check path:** `/`

### Step 5 — Environment variables (web service)

These replace [`deploy/client.env`](../deploy/client.env.example) for Render. Set them under **Environment** on the ERPNext web service.

| Variable | Example / notes |
| -------- | --------------- |
| `PORT` | `80` (nginx listens on 80 in this image) |
| `RFP_DOMAIN_NAME` | `site1.local` (works with bundled nginx) |
| `RFP_PUBLIC_URL` | `https://your-service.onrender.com` or custom domain |
| `RFP_SITE_ADMIN_PASSWORD` | Frappe Administrator password |
| `RFP_DB_HOST` | MariaDB internal hostname from Step 2 |
| `RFP_DB_PORT` | `3306` |
| `RFP_DB_ROOT_PASSWORD` | Same as `MARIADB_ROOT_PASSWORD` on the DB service |
| `RFP_REDIS_URL` | Internal Redis URL from Step 3 |
| `RFP_MARIADB_USER_HOST_LOGIN_SCOPE` | `%` |
| `RFP_RECOVER_ORPHAN_SITE` | `false` (set `true` once only if recovering an orphaned DB — see [`deploy/README.md`](../deploy/README.md)) |
| `BENCH_EXTRA_APPS` | Optional; e.g. `payments my_custom_app` (apps must exist in the image) |

**Not needed on Render** when using a prebuilt GHCR image: `GHCR_IMAGE`, `GITHUB_PAT_TOKEN`, `CUSTOM_*` (those are CI/build-time only).

### Step 6 — First deploy

1. Deploy the web service.
2. Watch **Logs** — first boot runs `bench new-site` and can take **5–15+ minutes** (often longer on **Free** due to RAM limits).
3. Open the Render URL and log in with `RFP_SITE_ADMIN_PASSWORD`.
4. **Free plan:** after **15 minutes** without traffic, the service spins down. The next visit triggers a ~1 minute cold start. Any site files not on a paid disk may be gone after spin-down or redeploy.

### Step 7 — Custom domain (optional)

1. Web service → **Settings** → **Custom Domains**
2. Point DNS as Render instructs
3. Update `RFP_PUBLIC_URL` to `https://your.domain.com` and redeploy

---

## Part 3 — Blueprint deploy (build on Render)

Use this if you **do not** pull from GHCR and want Render to build from Git instead.

> **Free plan:** [`render.yaml`](../render.yaml) uses **paid** plans (`starter` / `standard`) and disks. It is not a Free-tier Blueprint. On Free, follow **Part 2** manually and pick **Free** only for the web service and Key Value.

1. Connect the **client branch** to this repo on Render.
2. **New** → **Blueprint** → select [`render.yaml`](../render.yaml) at the repo root.
3. When prompted, set **`sync: false`** secrets:
   - `MARIADB_ROOT_PASSWORD` (DB service)
   - `GITHUB_PAT_TOKEN`, `CUSTOM_ERPNEXT_GITHUB_PATH`
   - `RFP_DOMAIN_NAME`, `RFP_PUBLIC_URL`, `RFP_SITE_ADMIN_PASSWORD`
4. Blueprint creates MariaDB (pserv), Redis (Key Value), and ERPNext (web, `render/Dockerfile`).

For production clients, prefer **Part 2 (GHCR)** after CI is working. For Free-tier experiments, use **Part 2** with manual service creation, not the Blueprint.

---

## Part 4 — Redeploy after a new build

Image-backed Render services **do not** auto-update when GHCR `:latest` changes.

After CI pushes a new image:

1. Render Dashboard → ERPNext web service → **Manual Deploy** → **Deploy latest reference**

Optional — trigger from CI (add to `.github/workflows/build.yml` after the push step):

```yaml
- name: Trigger Render deploy
  if: github.ref == 'refs/heads/<client_name>-<env>'
  run: |
    curl -f -X POST \
      "https://api.render.com/v1/services/${{ secrets.RENDER_SERVICE_ID }}/deploys" \
      -H "Authorization: Bearer ${{ secrets.RENDER_API_KEY }}" \
      -H "Content-Type: application/json" \
      -d '{"clearCache": "do_not_clear"}'
```

Store **`RENDER_API_KEY`** and **`RENDER_SERVICE_ID`** in GitHub Actions secrets.

---

## Compose ↔ Render mapping

| [`deploy/compose.ghcr.yml`](../deploy/compose.ghcr.yml) | Render |
| -------------------------------------------------------- | ------ |
| `db` | Private Service, `mariadb:10.11` + disk |
| `redis` | Key Value (Redis) |
| `erpnext` (`${GHCR_IMAGE}`) | Web Service, **Existing Image** from GHCR |
| `deploy/client.env` | Environment variables on web service |
| `frappe_sites` volume | Disk on web service |
| `mariadb_data` volume | Disk on DB service |

---

## Custom app checklist

| Task | Action |
| ---- | ------ |
| Clone private app at build | `bench get-app` in Dockerfile + `CUSTOMISATION_TOKEN` in CI |
| Install app on new site | `BENCH_EXTRA_APPS=app_folder_name` on Render |
| Change app code | Push app repo → push client branch → CI rebuild → Render redeploy |
| Change runtime only (passwords, URL) | Update Render env vars → redeploy |
| Site already exists, new app in image | `bench install-app` via shell on running service, or new site |

---

## Troubleshooting

| Symptom | Likely fix |
| ------- | ---------- |
| Deploy fails pulling image | Check GHCR credential; confirm tag exists for your branch |
| OOM / exit 137 / slow `bench new-site` on Free | Free web has **512 MB RAM** — upgrade web to **Starter** or **Standard** |
| Site gone after idle or redeploy (Free) | Free web has **no persistent disk** — upgrade web to Starter+ and mount `/home/frappe/bench/sites` |
| Service suspended mid-month | Used **750 Free instance-hours** — wait for reset or upgrade to paid |
| Cold start / loading page ~1 min | Normal on Free after 15 min idle — send traffic or upgrade to paid (no spin-down) |
| Restart loop / “Site already exists” | On paid web: ensure disk at `/home/frappe/bench/sites`; see [`deploy/README.md`](../deploy/README.md) §4 |
| DB connection refused | Confirm `RFP_DB_HOST` is the **private** hostname, not a public URL |
| Redis errors | Use the **internal** `redis://…` URL from the Key Value service |
| Health check fails on first deploy | Wait for `bench new-site` to finish; check logs |
| App missing after deploy | App must be in the **image** (CI build) and listed in `BENCH_EXTRA_APPS` for first-site install |

---

## Related files

| Path | Role |
| ---- | ---- |
| [`render.yaml`](../render.yaml) | Render Blueprint (build-on-Render path) |
| [`render/Dockerfile`](Dockerfile) | Symlink to [`deploy/shared/Dockerfile`](../deploy/shared/Dockerfile) |
| [`render/docker-compose.yml`](docker-compose.yml) | Optional local / VPS build (`DEPLOY_TARGET=render`) |
| [`deploy/README.md`](../deploy/README.md) | Full multi-client deployment guide |
| [`.github/workflows/build.yml`](../.github/workflows/build.yml) | CI build → GHCR |
