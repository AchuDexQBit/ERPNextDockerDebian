FROM frappe/bench:v5.29.0

ARG adminPass=12345
ARG mysqlPass=12345
ARG pythonVersion=python3
ARG appBranch=version-16
ARG CUSTOMISATION_TOKEN

ENV \
    systemUser=frappe \
    mariadbVersion=11.8 \
    benchPath=bench-repo \
    benchFolderName=bench \
    benchRepo="https://github.com/frappe/bench" \
    benchBranch=v5.x \
    frappeRepo="https://github.com/frappe/frappe" \
    erpnextRepo="https://github.com/frappe/erpnext" \
    siteName=dqb_demo_distributors.dexqbit.com

COPY ./mariadb.cnf /home/$systemUser/mariadb.cnf
COPY --chown=1000:1000 ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sudo chmod +x /usr/local/bin/entrypoint.sh

RUN sudo apt-get update \
    && sudo apt-get install -y -q apt-utils \
    && echo "debconf debconf/frontend select Noninteractive" | sudo debconf-set-selections \
    && sudo apt-get install -y -q apt-transport-https curl \
    && sudo mkdir -p /etc/apt/keyrings \
    && sudo curl -o /etc/apt/keyrings/mariadb-keyring.pgp "https://mariadb.org/mariadb_release_signing_key.pgp" \
    && echo "deb [signed-by=/etc/apt/keyrings/mariadb-keyring.pgp] https://mirror.kku.ac.th/mariadb/repo/${mariadbVersion}/debian bookworm main" | sudo tee /etc/apt/sources.list.d/mariadb.list \
    && sudo apt-get update \
    && sudo apt-get install -y -q \
    mariadb-server mariadb-client mariadb-common libmariadb3 python3-mysqldb \
    redis-server supervisor nginx \
    && sudo apt-get autoremove --purge -y \
    && sudo apt-get clean -y \
    && sudo cp /home/$systemUser/mariadb.cnf /etc/mysql/mariadb.cnf \
    && sudo service mariadb start \
    && sudo mariadb --user="root" --password="${mysqlPass}" --execute="ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysqlPass}';" \
    && sudo redis-server --port 11000 --daemonize yes \
    && bench init $benchFolderName --frappe-path $frappeRepo --frappe-branch $appBranch --python $pythonVersion \
    && cd $benchFolderName \
    && bench get-app erpnext $erpnextRepo --branch $appBranch \
    && bench get-app erpnext_app_dqb_distributors https://x-access-token:${CUSTOMISATION_TOKEN}@github.com/AchuDexQBit/erpnext_app_dqb_distributors --branch prod \
    && sudo rm -rf /tmp/* \
    && bench new-site $siteName \
    --mariadb-root-password $mysqlPass \
    --admin-password $adminPass \
    && bench --site $siteName install-app erpnext \
    && bench --site $siteName install-app erpnext_app_dqb_distributors \
    && bench use $siteName \
    && $pythonVersion -m compileall -q /home/$systemUser/$benchFolderName/apps/frappe/frappe \
    && $pythonVersion -m compileall -q /home/$systemUser/$benchFolderName/apps/erpnext/erpnext \
    && $pythonVersion -m compileall -q /home/$systemUser/$benchFolderName/apps/erpnext_app_dqb_distributors

WORKDIR /home/$systemUser/$benchFolderName
CMD ["/usr/local/bin/entrypoint.sh"]
EXPOSE 8000 9000 3306