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

echo "-> Install custom app"
su frappe -c "cd /home/frappe/bench && bench --site ${RFP_DOMAIN_NAME} install-app erpnext_wl_dqb_demo"

echo "-> Set default site"
su frappe -c "cd /home/frappe/bench && bench use ${RFP_DOMAIN_NAME}"

echo "-> Enable scheduler"
su frappe -c "cd /home/frappe/bench && bench enable-scheduler"

echo "-> Setup complete!"