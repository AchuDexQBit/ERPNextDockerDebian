#!/bin/sh
set -e

echo "-> Check if site exists"
if [ ! -f "/home/frappe/bench/sites/${RFP_DOMAIN_NAME}/site_config.json" ]; then
    echo "-> Site not found, running setup..."
    bash /home/frappe/bench/railway-setup.sh
fi

echo "-> Clearing cache"
su frappe -c "bench --site ${RFP_DOMAIN_NAME} clear-cache" || true

echo "-> Bursting env into config"
envsubst '${RFP_DOMAIN_NAME}' < /home/${systemUser}/temp_nginx.conf > /etc/nginx/conf.d/default.conf
envsubst '${PATH} ${HOME} ${NVM_DIR} ${NODE_VERSION}' < /home/${systemUser}/temp_supervisor.conf > /home/${systemUser}/supervisor.conf

echo "-> Starting nginx"
nginx

echo "-> Starting supervisor"
/usr/bin/supervisord -c /home/${systemUser}/supervisor.conf