#!/bin/sh
set -e

echo "-> Set ownership of sites folder"
chown frappe:frappe /home/frappe/bench/sites

echo "-> Linking assets"
su frappe -c "ln -sf /home/frappe/bench/built_sites/assets /home/frappe/bench/sites/assets"
su frappe -c "ln -sf /home/frappe/bench/built_sites/apps.json /home/frappe/bench/sites/apps.json"
su frappe -c "ln -sf /home/frappe/bench/built_sites/apps.txt /home/frappe/bench/sites/apps.txt"

# Do not mkdir sites/<RFP_DOMAIN_NAME>/ here — an empty folder makes bench new-site fail with
# "Site … already exists" while site_config.json is still missing (see setup.sh cleanup).

exec "$@"
