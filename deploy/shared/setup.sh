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
d["socketio_port"] = 9000
# Frappe v15 UserType.validate_document_type_limit reads frappe.conf["user_type_doctype_limit"][frappe.scrub(name)] — not "user_types".
# Required for HRMS after_install (Employee Self Service). Scrubbed name: employee_self_service
d["user_type_doctype_limit"] = {"employee_self_service": 500}
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

_remove_incomplete_site_dir() {
    _d="/home/frappe/bench/sites/${RFP_DOMAIN_NAME}"
    if [ -d "${_d}" ] && [ ! -f "${_d}/site_config.json" ]; then
        echo "-> Removing incomplete site directory (no site_config.json): ${_d}"
        rm -rf "${_d}"
        return 0
    fi
    return 1
}

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

_orphan_drop_mariadb() {
    su frappe -s /bin/bash <<'EOSU'
set -e
cd /home/frappe/bench
exec ./env/bin/python3 <<'PY'
import hashlib
import os
import re

import pymysql

site = os.environ["RFP_DOMAIN_NAME"]
root_pw = os.environ["RFP_DB_ROOT_PASSWORD"]
host = os.environ.get("RFP_DB_HOST", "127.0.0.1")
port = int(os.environ.get("RFP_DB_PORT", "3306"))
explicit = (os.environ.get("RFP_DB_NAME") or "").strip()

if explicit:
    db_name = explicit
else:
    site_path = os.path.realpath(os.path.join("/home/frappe/bench/sites", site))
    db_name = "_" + hashlib.sha1(site_path.encode(), usedforsecurity=False).hexdigest()[:16]

if not re.match(r"^[_0-9a-zA-Z]+$", db_name):
    raise SystemExit(f"refusing unsafe RFP_DB_NAME / derived id: {db_name!r}")

conn = pymysql.connect(host=host, port=port, user="root", password=root_pw)
conn.autocommit(True)
cur = conn.cursor()
cur.execute(f"DROP DATABASE IF EXISTS `{db_name}`")
for h in ("%", "localhost"):
    cur.execute(f"DROP USER IF EXISTS '{db_name}'@'{h}'")
conn.close()
print(f"-> Dropped MariaDB database + user {db_name} (orphan recovery)")
PY
EOSU
}

_new_site_rc=1
for _attempt in 1 2; do
    _remove_incomplete_site_dir || true
    set +e
    _new_site_log=$(_bench_new_site 2>&1)
    _new_site_rc=$?
    set -e
    printf '%s\n' "${_new_site_log}"
    if [ "${_new_site_rc}" -eq 0 ]; then
        break
    fi
    if [ "${_attempt}" -eq 1 ] && printf '%s' "${_new_site_log}" | grep -qi 'already exists' && _remove_incomplete_site_dir; then
        echo "-> Retrying bench new-site after removing stale site folder"
        continue
    fi
    break
done

if [ "${_new_site_rc}" -ne 0 ]; then
    if printf '%s' "${_new_site_log}" | grep -qi 'already exists'; then
        echo "-> new-site still failing after stale-folder cleanup (often orphan MariaDB from old boots)."
        if [ "${RFP_RECOVER_ORPHAN_SITE:-}" = "true" ]; then
            echo "-> RFP_RECOVER_ORPHAN_SITE=true: remove orphan DB then retry new-site"
            _site_cfg="/home/frappe/bench/sites/${RFP_DOMAIN_NAME}/site_config.json"
            if [ -f "${_site_cfg}" ]; then
                su frappe -c "cd /home/frappe/bench && bench drop-site ${RFP_DOMAIN_NAME} --force --no-backup --db-root-password ${RFP_DB_ROOT_PASSWORD}" || _orphan_drop_mariadb
            else
                echo "-> No site folder (bench drop-site cannot run); dropping DB as Frappe v15 would name it"
                _orphan_drop_mariadb
            fi
            set +e
            _retry_log=$(_bench_new_site 2>&1)
            _retry_rc=$?
            set -e
            printf '%s\n' "${_retry_log}"
            if [ "${_retry_rc}" -ne 0 ]; then
                echo "ERROR: new-site failed after orphan recovery (rc=${_retry_rc})."
                exit "${_retry_rc}"
            fi
        else
            echo "-> new-site failed: site or database already exists but site files are missing (common if sites/ was not on a volume)."
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

echo "-> Migrate site (patches, schema, fixtures / role sync for installed apps)"
su frappe -c "cd /home/frappe/bench && bench --site ${RFP_DOMAIN_NAME} migrate"

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