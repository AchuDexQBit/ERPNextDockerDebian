# Single source of truth for the production ERPNext image (Railway, Hetzner, AWS, etc.).
# Build from the repository root:
#   docker build -f deploy/shared/Dockerfile -t erpnext:prod .
#
# Client-specific values: copy deploy/client.env.example -> deploy/client.env and pass build-args
# (see hetzner/docker-compose.yml and aws/docker-compose.yml).

# ------------------------------------------
# - Stage: 01 - builder
# ------------------------------------------
ARG PIPECH_IMAGE_TAG=version-15-latest
FROM pipech/erpnext-docker-debian:${PIPECH_IMAGE_TAG} AS builder

USER $systemUser
WORKDIR /home/$systemUser/$benchFolderName

ARG GITHUB_PAT_TOKEN
ARG CUSTOM_ERPNEXT_BRANCH=prod
ARG CUSTOM_ERPNEXT_GITHUB_PATH=DexQBit/erpnext
ARG CUSTOM_WHITELIST_GITHUB_PATH=
ARG CUSTOM_WHITELIST_BRANCH=prod
# Official frappe/payments + frappe/hrms: e.g. version-15 / version-16
ARG FRAPPE_APPS_BRANCH=version-15
# frappe/crm has no version-N branches; use main (or develop)
ARG CRM_BRANCH=main
# Space-separated: erpnext / payments / hrms / crm / custom app folder names.
ARG BENCH_INSTALL_APPS=erpnext

RUN echo "-> Start builder (BENCH_INSTALL_APPS=${BENCH_INSTALL_APPS} FRAPPE_APPS_BRANCH=${FRAPPE_APPS_BRANCH})" \
    && rm -rf /home/$systemUser/$benchFolderName/sites/site1.local \
    && bench remove-app erpnext --no-backup || true \
    && bench remove-app payments --no-backup || true \
    && rm -rf /home/$systemUser/$benchFolderName/apps/erpnext \
    && rm -rf /home/$systemUser/$benchFolderName/apps/payments \
    && case " ${BENCH_INSTALL_APPS} " in \
         *" payments "*) \
           echo "-> get-app payments@${FRAPPE_APPS_BRANCH}" \
           && bench get-app --branch ${FRAPPE_APPS_BRANCH} https://github.com/frappe/payments ;; \
       esac \
    && case " ${BENCH_INSTALL_APPS} " in \
         *" erpnext "*) \
           echo "-> get-app erpnext from ${CUSTOM_ERPNEXT_GITHUB_PATH}@${CUSTOM_ERPNEXT_BRANCH}" \
           && bench get-app --branch ${CUSTOM_ERPNEXT_BRANCH} https://${GITHUB_PAT_TOKEN}@github.com/${CUSTOM_ERPNEXT_GITHUB_PATH} ;; \
       esac \
    && case " ${BENCH_INSTALL_APPS} " in \
         *" hrms "*) \
           echo "-> get-app hrms@${FRAPPE_APPS_BRANCH}" \
           && bench get-app --branch ${FRAPPE_APPS_BRANCH} https://github.com/frappe/hrms ;; \
       esac \
    && case " ${BENCH_INSTALL_APPS} " in \
         *" crm "*) \
           echo "-> get-app crm@${CRM_BRANCH}" \
           && bench get-app --branch ${CRM_BRANCH} https://github.com/frappe/crm ;; \
       esac \
    && if [ -n "${CUSTOM_WHITELIST_GITHUB_PATH}" ]; then \
         echo "-> get-app whitelist ${CUSTOM_WHITELIST_GITHUB_PATH}@${CUSTOM_WHITELIST_BRANCH}" \
         && bench get-app --branch ${CUSTOM_WHITELIST_BRANCH} https://${GITHUB_PAT_TOKEN}@github.com/${CUSTOM_WHITELIST_GITHUB_PATH}; \
       fi \
    && echo "-> Builder done!"

# ------------------------------------------
# - Stage: 02 - production
# ------------------------------------------
# v15: frappe/bench:v5.22.9 (Python ~3.11). v16: frappe/bench:v5.29.0+ (Python 3.14).
ARG FRAPPE_BENCH_IMAGE=frappe/bench:v5.22.9
FROM ${FRAPPE_BENCH_IMAGE}

ENV systemUser=frappe
ENV benchFolderName=bench

COPY --from=builder --chown=$systemUser /home/$systemUser/$benchFolderName /home/$systemUser/$benchFolderName

COPY deploy/shared/temp_nginx.conf /home/$systemUser/temp_nginx.conf
COPY deploy/shared/temp_supervisor.conf /home/$systemUser/temp_supervisor.conf

USER root
WORKDIR /home/$systemUser/$benchFolderName

ARG DEBIAN_FRONTEND=noninteractive
ARG DEPLOY_TARGET=generic
# Same list as builder; used by setup.sh on first boot. Env file can override at runtime.
ARG BENCH_INSTALL_APPS=erpnext
ENV BENCH_INSTALL_APPS="${BENCH_INSTALL_APPS}"

LABEL org.opencontainers.image.source="https://github.com/DexQBit/erpnext"
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
