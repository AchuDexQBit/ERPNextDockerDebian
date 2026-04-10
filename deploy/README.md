# Multi-client deployment (branch per client and environment)

This repository builds a **single production image** from [`deploy/shared/Dockerfile`](./shared/Dockerfile). Each **client** and **environment** is represented by a **Git branch** (see naming below). **Secrets and private repo URLs** stay out of Git (local `deploy/client.env` or GitHub Environment secrets).

### Branch naming convention

Use:

`<client_name>-<env>`

- **`client_name`**: short, stable identifier (e.g. `acme`, `globex`). Use lowercase and hyphens if the name has multiple words (e.g. `acme-corp`).
- **`env`**: exactly one of **`prod`**, **`stage`**, or **`dev`**.

Examples: `acme-prod`, `acme-stage`, `acme-dev`.

The same client usually has **three branches** if you run all tiers; each branch can carry slightly different config (or identical Dockerfiles with different `deploy/client.env` on each server). The CI image tag includes the **full branch name**, so `acme-prod` and `acme-stage` produce different tags.

---

## Simple steps (new branch → deploy)

1. **Create the branch** from `main` (or your template branch):

   ```sh
   git checkout main && git pull
   git checkout -b <client_name>-<env>
   ```

   Use `env` = `prod`, `stage`, or `dev` (e.g. `acme-prod`).

2. **Adjust the image only if this client needs it** — On that branch, edit [`deploy/shared/Dockerfile`](./shared/Dockerfile) only if you must add extra private apps (`bench get-app`) or change fork paths. Otherwise skip.

3. **Push the branch**

   ```sh
   git push -u origin <client_name>-<env>
   ```

   That triggers [`.github/workflows/build.yml`](../.github/workflows/build.yml) and publishes an image tagged like `ghcr.io/<your-org>/erpnext-<client_name>-<env>:latest` (matching your workflow settings).

4. **Prepare secrets (never commit)**

   **`cp deploy/client.env.example deploy/client.env`** copies the tracked template to **`deploy/client.env`**, which Git ignores. You run it in a shell at the **repository root** (the folder that contains `deploy/`, `hetzner/`, etc.)—typically **on the server** where you run `docker compose`, or on your laptop if you build from there (then ensure `deploy/client.env` exists at that path before Compose).

   ```sh
   cd /path/to/ERPNextDockerDebian   # repo root
   cp deploy/client.env.example deploy/client.env
   ```

   Edit `deploy/client.env` and replace placeholders (domains, passwords, token, repo paths, optional `BENCH_EXTRA_APPS`). Reference: [`deploy/client.env.example`](./client.env.example).

5. **Deploy**

   - **Hetzner or AWS (build on the server):** on a checkout of **that branch**, from the **repository root**, with `deploy/client.env` present:

     ```sh
     docker compose -f hetzner/docker-compose.yml --env-file deploy/client.env up -d --build
     ```

     Use `aws/docker-compose.yml` instead of `hetzner` if you are on AWS.

   - **Or:** pull the CI-built image on the server and run it with the same **runtime** variables as in `deploy/client.env` (exact command depends on your host; Compose above is the path documented in this repo).

   - **Railway:** connect the service to this branch and set the same variables as in `deploy/client.env` (build arguments and runtime environment).

**One-line summary:** branch `<client_name>-<env>` → optional Dockerfile edits → push → fill `deploy/client.env` → `docker compose … up -d --build` (or Railway / pre-built image with those envs).

---

## Concepts

| What | Where it lives |
|------|----------------|
| Shared image definition | `deploy/shared/Dockerfile` (+ scripts and nginx/supervisor templates in `deploy/shared/`) |
| Client + env **code/config** in Git | Branch `<client_name>-<env>` (optional edits to Dockerfile, compose files, defaults) |
| Client-specific **secrets** | `deploy/client.env` on the server (gitignored), or GitHub Actions secrets / Environments |
| Apps **cloned into the image** | `bench get-app` in the Dockerfile **builder** stage (`GITHUB_PAT_TOKEN`, `CUSTOM_ERPNEXT_*`, `CUSTOM_WHITELIST_*`) |
| Apps **installed on the site** at first boot | Runtime env `BENCH_EXTRA_APPS` (space-separated **app names** that already exist under `bench/apps` from the build) |

### Example: Payments + HRMS + one private (whitelist) app

Everything you want on the site must be **cloned during the image build** (`bench get-app` in [`deploy/shared/Dockerfile`](./shared/Dockerfile)), then **installed on the new site** at runtime via **`BENCH_EXTRA_APPS`** (`bench install-app` in [`deploy/shared/setup.sh`](./shared/setup.sh)).

1. **Payments** — Already cloned in the Dockerfile from `https://github.com/frappe/payments` (`version-15`). You only need to **install** it on the site:

   `BENCH_EXTRA_APPS=payments …`

2. **HRMS** — Not cloned by default. On the branch for that client, add a line in the **builder** stage of `deploy/shared/Dockerfile` next to the other `bench get-app` calls, for example:

   `bench get-app --branch version-15 https://github.com/frappe/hrms`

   (Use the branch that matches your ERPNext/Frappe version.) Rebuild the image. Then include the app **name** Frappe expects (the folder under `apps/`, usually `hrms`):

   `BENCH_EXTRA_APPS=payments hrms …`

3. **Private / whitelist app** — Set build args in `deploy/client.env` (passed through Compose as build args):

   - `CUSTOM_WHITELIST_GITHUB_PATH=YourOrg/your-private-app` (owner/repo only, same rules as `CUSTOM_ERPNEXT_GITHUB_PATH`)
   - `CUSTOM_WHITELIST_BRANCH=main` (or your release branch)
   - `GITHUB_PAT_TOKEN` must allow that repo

   The app’s **install name** is the Python package / app folder name in that repo (e.g. `my_company_app`). Add it to `BENCH_EXTRA_APPS`:

   `BENCH_EXTRA_APPS=payments hrms my_company_app`

Order in `BENCH_EXTRA_APPS` does not need to match install order for most apps; list every app you want installed besides ERPNext (ERPNext is already installed by `bench new-site --install-app erpnext`).

---

## When you onboard a new client or environment (checklist)

### 1. Create a branch

From your usual base branch (for example `main`):

```sh
git checkout main
git pull
git checkout -b <client_name>-<env>   # e.g. acme-prod, acme-stage, acme-dev
```

The name **must** follow `<client_name>-<env>` with `env` ∈ {`prod`, `stage`, `dev`}.

The GitHub workflow [`.github/workflows/build.yml`](../.github/workflows/build.yml) pushes:

`ghcr.io/<your-org>/erpnext-<branch-name>:latest`

So `acme-prod` becomes `erpnext-acme-prod:latest`, and `acme-stage` becomes `erpnext-acme-stage:latest`.

### 2. Point the build at that client’s forks (in Git, if defaults differ)

On this branch you can rely on **defaults** in [`deploy/shared/Dockerfile`](./shared/Dockerfile) or change **only** what that client needs:

- **`CUSTOM_ERPNEXT_GITHUB_PATH`** / **`CUSTOM_ERPNEXT_BRANCH`**: customised ERPNext repo (private clone uses PAT at build time).
- **`CUSTOM_WHITELIST_GITHUB_PATH`** / **`CUSTOM_WHITELIST_BRANCH`**: one extra private Frappe app repo (optional). Leave the path empty if unused.

If a client needs **more than one** extra private app cloned at build time, add another `bench get-app` line in the **builder** stage of `deploy/shared/Dockerfile` on **that client’s branch** (same pattern as the whitelist block).

Commit and push the branch.

### 3. Prepare secrets and runtime settings (never commit)

From the **repository root** on the host where Compose will run (or create the file there after editing elsewhere), copy the template to the real env file Git ignores:

```sh
cd /path/to/this-repo
cp deploy/client.env.example deploy/client.env
```

Edit `deploy/client.env` for that client **and** environment (e.g. different values for `acme-stage` vs `acme-prod`). Fill at least:

**Runtime (first boot / ongoing):**

- `RFP_DOMAIN_NAME` — Frappe site id / folder (often `site1.local` to match nginx here)
- `RFP_PUBLIC_URL` — optional full URL users use (e.g. `https://erp.client.com`); registers domain + `host_name` on first setup so emails/OAuth match the real host
- `RFP_SITE_ADMIN_PASSWORD`
- `RFP_DB_ROOT_PASSWORD` — MariaDB root password used when creating the site
- `BENCH_EXTRA_APPS` — optional; space-separated app names to `bench install-app` **after** ERPNext (each name must match an app already present in the image from the build)

**Build-time (used by Docker Compose when building):**

- `GITHUB_PAT_TOKEN` — PAT with access to the private repos used in `bench get-app`
- `CUSTOM_ERPNEXT_GITHUB_PATH`, `CUSTOM_ERPNEXT_BRANCH`
- `CUSTOM_WHITELIST_GITHUB_PATH`, `CUSTOM_WHITELIST_BRANCH` (if used)

`deploy/client.env` is listed in `.gitignore`. Use a **different** `deploy/client.env` on each server or keep a private copy per client outside the repo.

See also [`deploy/client.env.example`](./client.env.example) for keys and placeholder values.

### 4. Build and run (Hetzner or AWS compose)

Always run Compose from the **repository root**, and pass the env file:

**Hetzner (example):**

```sh
docker compose -f hetzner/docker-compose.yml --env-file deploy/client.env up -d --build
```

**AWS (example, e.g. EC2 with Docker):**

```sh
docker compose -f aws/docker-compose.yml --env-file deploy/client.env up -d --build
```

Adjust image name or port via variables documented in the compose files if needed.

### 5. Railway

- Connect the **client branch** to the Railway service.
- Dockerfile path can stay `railway/Dockerfile` (symlink to `deploy/shared/Dockerfile`).
- Set the **same** variables in Railway’s UI as you would put in `deploy/client.env` (build arguments and runtime environment).

### 6. GitHub Actions and secrets

Pushing the branch triggers [`.github/workflows/build.yml`](../.github/workflows/build.yml), which builds with `deploy/shared/Dockerfile` and tags the image with the **branch name**.

**Pat options:**

- **One secret for the whole repo:** keep using `CUSTOMISATION_TOKEN` as today (works well if each client uses a **separate repository or fork**, each with its own secret).
- **One monorepo, many branches:** use a GitHub **Environment** per branch (environment name **exactly** equals the branch name, e.g. `acme-prod`, `acme-stage`), store `CUSTOMISATION_TOKEN` (or a dedicated PAT secret) there, and add `environment: ${{ github.ref_name }}` to the build job so each branch only sees its own secrets. Create each environment in the repo settings before those builds succeed.

---

## Layout reference

| Path | Role |
|------|------|
| `deploy/shared/Dockerfile` | Canonical production image |
| `deploy/shared/*.sh`, `temp_*.conf` | Entrypoint, setup, nginx/supervisor templates |
| `deploy/client.env.example` | Template with placeholders; copy to `deploy/client.env` |
| `railway/Dockerfile`, `hetzner/Dockerfile`, `aws/Dockerfile` | Symlinks to `deploy/shared/Dockerfile` |
| `hetzner/docker-compose.yml`, `aws/docker-compose.yml` | Build context `..`, `dockerfile: deploy/shared/Dockerfile` |

---

## Quick reference

Use the section **Simple steps (new branch → deploy)** near the top of this file for the short path. For PAT options, GitHub Environments, and file layout, see **When you onboard a new client or environment** and **Layout reference** above.
