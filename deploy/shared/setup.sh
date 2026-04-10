#!/bin/bash
set -e

echo "-> Create empty common site config"
echo "{}" > /home/frappe/bench/sites/common_site_config.json
chown frappe:frappe /home/frappe/bench/sites/common_site_config.json

echo "-> Create new site with ERPNext"
su frappe -c "cd /home/frappe/bench && bench new-site ${RFP_DOMAIN_NAME} \
    --admin-password ${RFP_SITE_ADMIN_PASSWORD} \
    --no-mariadb-socket \
    --db-root-password ${RFP_DB_ROOT_PASSWORD} \
    --install-app erpnext"

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
