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

# Base image may not expose $systemUser to every instruction; pin paths for reliable builds.
USER frappe
WORKDIR /home/frappe/bench

ARG GITHUB_PAT_TOKEN
# Private GitHub clones: send PAT via git http.extraHeader (works for classic + fine-grained tokens; URL-embedded PAT often fails in CI).
ARG CUSTOM_ERPNEXT_BRANCH=prod
ARG CUSTOM_ERPNEXT_GITHUB_PATH=AchuDexQBit/erpnext
# Private app (bench get-app). Empty on template branches; set per client branch.
ARG CUSTOM_WHITELIST_GITHUB_PATH=AchuDexQBit/erpnext_app_dqb_distributors
ARG CUSTOM_WHITELIST_BRANCH=dqb_distributors-prod

RUN echo "-> Builder cleanup" \
    && if [ -z "${GITHUB_PAT_TOKEN}" ]; then echo "ERROR: build-arg GITHUB_PAT_TOKEN is empty (set GitHub secret CUSTOMISATION_TOKEN for CI)"; exit 1; fi \
    && rm -rf /home/frappe/bench/sites/site1.local \
    && _cf=/home/frappe/bench/apps/frappe/frappe/utils/connections.py \
    && if [ -f "${_cf}" ]; then sed -i 's/socket\.AF_INET, socket\.SOCK_STREAM/socket.AF_INET6, socket.SOCK_STREAM/g' "${_cf}"; fi \
    && bench remove-app erpnext --no-backup || true \
    && bench remove-app payments --no-backup || true \
    && bench remove-app hrms --no-backup || true \
    && rm -rf /home/frappe/bench/apps/erpnext /home/frappe/bench/apps/payments /home/frappe/bench/apps/hrms

RUN echo "-> get-app erpnext" \
    && git config --global http.https://github.com/.extraHeader "AUTHORIZATION: token ${GITHUB_PAT_TOKEN}" \
    && if bench get-app --branch ${CUSTOM_ERPNEXT_BRANCH} https://github.com/${CUSTOM_ERPNEXT_GITHUB_PATH}.git; then \
         git config --global --unset http.https://github.com/.extraHeader; \
       else \
         _e=$?; git config --global --unset http.https://github.com/.extraHeader 2>/dev/null || true; exit $_e; \
       fi

RUN echo "-> get-app payments + hrms" \
    && bench get-app --branch version-15 https://github.com/frappe/payments \
    && bench get-app --branch version-15 https://github.com/frappe/hrms

RUN echo "-> get-app whitelist" \
    && if [ -n "${CUSTOM_WHITELIST_GITHUB_PATH}" ]; then \
         git config --global http.https://github.com/.extraHeader "AUTHORIZATION: token ${GITHUB_PAT_TOKEN}"; \
         if bench get-app --branch ${CUSTOM_WHITELIST_BRANCH} https://github.com/${CUSTOM_WHITELIST_GITHUB_PATH}.git; then \
           git config --global --unset http.https://github.com/.extraHeader; \
         else \
           _e=$?; git config --global --unset http.https://github.com/.extraHeader 2>/dev/null || true; exit $_e; \
         fi; \
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
# Space-separated names for `bench install-app` on first boot (must exist under bench/apps). ERPNext is installed by new-site.
# Per client branch; server env_file overrides ENV if set.
ARG BENCH_EXTRA_APPS="payments hrms erpnext_app_dqb_distributors"
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
