#!/bin/bash
set -e

echo "-> Write common site config (Redis URLs if set)"
python3 <<'PY'
import json, os

path = "/home/frappe/bench/sites/common_site_config.json"
url = (os.environ.get("RFP_REDIS_URL") or "").strip()
cache = (os.environ.get("RFP_REDIS_CACHE_URL") or "").strip() or url
queue = (os.environ.get("RFP_REDIS_QUEUE_URL") or "").strip() or url
socketio = (os.environ.get("RFP_REDIS_SOCKETIO_URL") or "").strip() or url
d = {}
if cache:
    d["redis_cache"] = cache
if queue:
    d["redis_queue"] = queue
if socketio:
    d["redis_socketio"] = socketio
with open(path, "w") as f:
    json.dump(d, f)
PY
chown frappe:frappe /home/frappe/bench/sites/common_site_config.json

_RFP_DB_HOST="${RFP_DB_HOST:-127.0.0.1}"
_RFP_DB_PORT="${RFP_DB_PORT:-3306}"
_RFP_MARIADB_SCOPE="${RFP_MARIADB_USER_HOST_LOGIN_SCOPE:-%}"

_NEW_SITE_DB_ARGS=""
if [ -n "${RFP_DB_NAME:-}" ]; then
    _NEW_SITE_DB_ARGS="${_NEW_SITE_DB_ARGS} --db-name ${RFP_DB_NAME}"
fi
if [ -n "${RFP_DB_PASSWORD:-}" ]; then
    _NEW_SITE_DB_ARGS="${_NEW_SITE_DB_ARGS} --db-password ${RFP_DB_PASSWORD}"
fi

echo "-> Create new site with ERPNext (DB ${_RFP_DB_HOST}:${_RFP_DB_PORT})"

_bench_new_site() {
    su frappe -c "cd /home/frappe/bench && bench new-site ${RFP_DOMAIN_NAME} \
        --admin-password ${RFP_SITE_ADMIN_PASSWORD} \
        --db-host ${_RFP_DB_HOST} \
        --db-port ${_RFP_DB_PORT} \
        --mariadb-user-host-login-scope ${_RFP_MARIADB_SCOPE} \
        --db-root-password ${RFP_DB_ROOT_PASSWORD} \
        ${_NEW_SITE_DB_ARGS} \
        --install-app erpnext"
}

set +e
_new_site_log=$(_bench_new_site 2>&1)
_new_site_rc=$?
set -e
printf '%s\n' "${_new_site_log}"

if [ "${_new_site_rc}" -ne 0 ]; then
    if printf '%s' "${_new_site_log}" | grep -qi 'already exists'; then
        echo "-> new-site failed: site or database already exists but site files are missing (common if sites/ was not on a volume)."
        if [ "${RFP_RECOVER_ORPHAN_SITE:-}" = "true" ]; then
            echo "-> RFP_RECOVER_ORPHAN_SITE=true: bench drop-site (DB + folder) then retry new-site"
            su frappe -c "cd /home/frappe/bench && bench drop-site ${RFP_DOMAIN_NAME} --force --no-backup --db-root-password ${RFP_DB_ROOT_PASSWORD}" || true
            _bench_new_site
        else
            echo "ERROR: Fix once: set RFP_RECOVER_ORPHAN_SITE=true in env and recreate the container, or run bench drop-site with --db-root-password, then remove that var. See deploy/README.md."
            exit 1
        fi
    else
        exit "${_new_site_rc}"
    fi
fi

if [ -n "${BENCH_EXTRA_APPS:-}" ]; then
    echo "-> Installing extra bench apps: ${BENCH_EXTRA_APPS}"
    for app in ${BENCH_EXTRA_APPS}; do
        su frappe -c "cd /home/frappe/bench && bench --site ${RFP_DOMAIN_NAME} install-app ${app}"
    done
fi

if [ -n "${RFP_PUBLIC_URL:-}" ]; then
    _pub_host="${RFP_PUBLIC_URL#*://}"
    _pub_host="${_pub_host%%/*}"
    _pub_host="${_pub_host%%:*}"
    echo "-> Public URL ${RFP_PUBLIC_URL} (host ${_pub_host})"
    if [ "${_pub_host}" != "${RFP_DOMAIN_NAME}" ]; then
        su frappe -c "cd /home/frappe/bench && bench --site ${RFP_DOMAIN_NAME} setup add-domain ${_pub_host}"
    fi
    su frappe -c "cd /home/frappe/bench && bench --site ${RFP_DOMAIN_NAME} set-config host_name \"${RFP_PUBLIC_URL}\""
fi

echo "-> Set default site"
su frappe -c "cd /home/frappe/bench && bench use ${RFP_DOMAIN_NAME}"

echo "-> Enable scheduler"
su frappe -c "cd /home/frappe/bench && bench enable-scheduler"

echo "-> Setup complete!"
