#!/bin/sh
set -e

echo "-> Check if site exists"
if [ ! -f "/home/frappe/bench/sites/${RFP_DOMAIN_NAME}/site_config.json" ]; then
    echo "-> Site not found, running setup..."
    bash /home/frappe/bench/setup.sh
fi

# Frappe v15 + HRMS: UserType needs user_type_doctype_limit in conf (not legacy "user_types"). Merge on every boot so existing volumes pick this up after an image update.
_common_cfg="/home/frappe/bench/sites/common_site_config.json"
if [ -f "${_common_cfg}" ]; then
    echo "-> Ensure user_type_doctype_limit for HRMS (common_site_config.json)"
    python3 <<'PY'
import json, os
path = "/home/frappe/bench/sites/common_site_config.json"
lim = int(os.environ.get("RFP_ESS_USER_TYPE_DOCTYPE_LIMIT", "500"))
with open(path) as f:
    d = json.load(f)
ut = d.get("user_type_doctype_limit")
if not isinstance(ut, dict):
    ut = {}
changed = False
if ut.get("employee_self_service") is None:
    ut["employee_self_service"] = lim
    d["user_type_doctype_limit"] = ut
    changed = True
if d.pop("user_types", None) is not None:
    changed = True
if changed:
    with open(path, "w") as f:
        json.dump(d, f, indent=2)
PY
    chown frappe:frappe "${_common_cfg}"
fi

echo "-> Clearing cache"
su frappe -c "cd /home/frappe/bench && bench --site ${RFP_DOMAIN_NAME} clear-cache" || true

echo "-> Bursting env into config"
envsubst '${RFP_DOMAIN_NAME}' < /home/frappe/temp_nginx.conf > /etc/nginx/conf.d/default.conf
envsubst '${PATH} ${HOME} ${NVM_DIR} ${NODE_VERSION}' < /home/frappe/temp_supervisor.conf > /home/frappe/supervisor.conf

echo "-> Starting nginx"
nginx

echo "-> Starting supervisor"
/usr/bin/supervisord -c /home/frappe/supervisor.conf
