# Single source of truth for the production ERPNext image (Railway, Hetzner, AWS, etc.).
# Build from the repository root:
#   docker build -f deploy/shared/Dockerfile -t erpnext:prod .
#
# Client-specific values: copy deploy/client.env.example -> deploy/client.env and pass build-args
# (see hetzner/docker-compose.yml and aws/docker-compose.yml).

# ------------------------------------------
# - Stage: 01 - builder
# ------------------------------------------
FROM pipech/erpnext-docker-debian:version-15-latest AS builder

USER $systemUser
WORKDIR /home/$systemUser/$benchFolderName

ARG GITHUB_PAT_TOKEN
ARG CUSTOM_ERPNEXT_BRANCH=prod
ARG CUSTOM_ERPNEXT_GITHUB_PATH=AchuDexQBit/erpnext
ARG CUSTOM_WHITELIST_GITHUB_PATH=
ARG CUSTOM_WHITELIST_BRANCH=prod

RUN echo "-> Start builder" \
    && rm -rf /home/$systemUser/$benchFolderName/sites/site1.local \
    && sed -i 's/socket\.AF_INET, socket\.SOCK_STREAM/socket.AF_INET6, socket.SOCK_STREAM/g' /home/frappe/bench/apps/frappe/frappe/utils/connections.py \
    && bench remove-app erpnext --no-backup || true \
    && bench remove-app payments --no-backup || true \
    && rm -rf /home/$systemUser/$benchFolderName/apps/erpnext \
    && rm -rf /home/$systemUser/$benchFolderName/apps/payments \
    && bench get-app --branch version-15 https://github.com/frappe/payments \
    && bench get-app --branch ${CUSTOM_ERPNEXT_BRANCH} https://${GITHUB_PAT_TOKEN}@github.com/${CUSTOM_ERPNEXT_GITHUB_PATH} \
    && if [ -n "${CUSTOM_WHITELIST_GITHUB_PATH}" ]; then \
         bench get-app --branch ${CUSTOM_WHITELIST_BRANCH} https://${GITHUB_PAT_TOKEN}@github.com/${CUSTOM_WHITELIST_GITHUB_PATH}; \
       fi \
    && echo "-> Builder done!"

# ------------------------------------------
# - Stage: 02 - production
# ------------------------------------------
FROM frappe/bench:v5.22.9

ENV systemUser=frappe
ENV benchFolderName=bench

COPY --from=builder --chown=$systemUser /home/$systemUser/$benchFolderName /home/$systemUser/$benchFolderName

COPY deploy/shared/temp_nginx.conf /home/$systemUser/temp_nginx.conf
COPY deploy/shared/temp_supervisor.conf /home/$systemUser/temp_supervisor.conf

USER root
WORKDIR /home/$systemUser/$benchFolderName

ARG DEBIAN_FRONTEND=noninteractive
ARG DEPLOY_TARGET=generic
# Space-separated app names for `bench install-app` on first boot (must exist under bench/apps from the builder). Empty = ERPNext only.
# Set per client branch or pass build-arg / env_file. Server env_file overrides ENV when set.
ARG BENCH_EXTRA_APPS=""
ENV BENCH_EXTRA_APPS="${BENCH_EXTRA_APPS}"

LABEL org.opencontainers.image.source="https://github.com/frappe/erpnext"
LABEL deploy.target="${DEPLOY_TARGET}"

RUN echo "-> Install nginx & supervisor" \
    && apt-get update \
    && apt-get install -y nginx supervisor \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm /etc/nginx/sites-enabled/default \
    && su $systemUser -c "bench build" \
    && su $systemUser -c "cp -r /home/$systemUser/$benchFolderName/sites /home/$systemUser/$benchFolderName/built_sites"

COPY --chown=$systemUser --chmod=0755 deploy/shared/setup.sh /home/$systemUser/$benchFolderName/setup.sh
COPY --chown=$systemUser --chmod=0755 deploy/shared/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=$systemUser --chmod=0755 deploy/shared/cmd.sh /usr/local/bin/cmd.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/cmd.sh"]

EXPOSE 80
