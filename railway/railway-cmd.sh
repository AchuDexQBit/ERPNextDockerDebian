#!/bin/sh
set -e

echo "-> Check if site exists"
if [ ! -f "/home/frappe/bench/sites/${RFP_DOMAIN_NAME}/site_config.json" ]; then
    echo "-> Site not found, running setup..."
    bash /home/frappe/bench/railway-setup.sh
fi

# remove this section for prod release
echo "-> Enabling developer mode"
su frappe -c "cd /home/frappe/bench && bench --site ${RFP_DOMAIN_NAME} set-config developer_mode 1" || true
# 

echo "-> Clearing cache"
su frappe -c "cd /home/frappe/bench && bench --site ${RFP_DOMAIN_NAME} clear-cache" || true

echo "-> Bursting env into config"
envsubst '${RFP_DOMAIN_NAME}' < /home/frappe/temp_nginx.conf > /etc/nginx/conf.d/default.conf
envsubst '${PATH} ${HOME} ${NVM_DIR} ${NODE_VERSION}' < /home/frappe/temp_supervisor.conf > /home/frappe/supervisor.conf

echo "-> Starting nginx"
nginx

echo "-> Starting supervisor"
/usr/bin/supervisord -c /home/frappe/supervisor.conf