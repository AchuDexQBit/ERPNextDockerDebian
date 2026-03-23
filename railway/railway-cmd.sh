#!/bin/sh
set -e

# Railway sets PORT for inbound HTTP; default keeps local/docker-compose behavior on 80.
export PORT="${PORT:-80}"

echo "-> Clearing cache"
su frappe -c "bench execute frappe.cache_manager.clear_global_cache"

echo "-> Bursting env into config"
envsubst '$RFP_DOMAIN_NAME,$PORT' < /home/$systemUser/temp_nginx.conf > /etc/nginx/conf.d/default.conf
envsubst '$PATH,$HOME,$NVM_DIR,$NODE_VERSION' < /home/$systemUser/temp_supervisor.conf > /home/$systemUser/supervisor.conf

echo "-> Starting nginx"
nginx

echo "-> Starting supervisor"
/usr/bin/supervisord -c /home/$systemUser/supervisor.conf
