#!/bin/sh
set -e

# Railway sets PORT for inbound HTTP; default keeps local/docker behavior on 80.
export PORT="${PORT:-80}"
# Match the hostname users open in the browser (Railway sets this on deploy).
export RFP_DOMAIN_NAME="${RFP_DOMAIN_NAME:-${RAILWAY_PUBLIC_DOMAIN}}"

if [ -z "$RFP_DOMAIN_NAME" ]; then
  echo "ERROR: Set RFP_DOMAIN_NAME or rely on RAILWAY_PUBLIC_DOMAIN (empty). Frappe resolves sites by hostname."
  exit 1
fi

echo "-> Clearing cache (non-fatal if Redis is not reachable yet)"
su frappe -c "bench execute frappe.cache_manager.clear_global_cache" 2>/dev/null || echo "WARN: clear_global_cache skipped (Redis/bench not ready)"

echo "-> Bursting env into config"
envsubst '$RFP_DOMAIN_NAME,$PORT' < /home/$systemUser/temp_nginx.conf > /etc/nginx/conf.d/default.conf
envsubst '$PATH,$HOME,$NVM_DIR,$NODE_VERSION' < /home/$systemUser/temp_supervisor.conf > /home/$systemUser/supervisor.conf

echo "-> Testing nginx config"
nginx -t

echo "-> Starting supervisor (gunicorn, workers, socketio)"
/usr/bin/supervisord -c /home/$systemUser/supervisor.conf &
SUP_PID=$!

PY=python3
command -v "$PY" >/dev/null 2>&1 || PY=python

echo "-> Waiting for gunicorn on 127.0.0.1:8000 (up to 120s)"
i=0
while [ "$i" -lt 120 ]; do
  if "$PY" -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('127.0.0.1', 8000)); s.close()" 2>/dev/null; then
    echo "-> Gunicorn is accepting connections"
    break
  fi
  i=$((i + 1))
  sleep 1
done
if [ "$i" -eq 120 ]; then
  echo "ERROR: Nothing listening on 127.0.0.1:8000 — check supervisor / web.error.log"
  kill "$SUP_PID" 2>/dev/null || true
  exit 1
fi

echo "-> Starting nginx"
nginx

echo "-> Waiting on supervisor (PID $SUP_PID)"
wait "$SUP_PID"
