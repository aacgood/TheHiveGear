#! /bin/bash

export DEBIAN_FRONTEND=noninteractive
THEHIVE_URL="http://127.0.0.1:9000"
CORTEX_URL="http://127.0.0.1:9001"
LOG_FILE=$(mktemp)

check() {
    expected=$1
    shift
    status_code=$(curl -v "$@" -s -o /dev/stderr -w '%{http_code}' 2>>${LOG_FILE}) || true
    if [ "${status_code}" = "${expected}" ]
    then
      ok
    else
      ko
      echo "got ${status_code}, expected ${expected}" >&2
      echo "see more detail in $LOG_FILE" >&2
      exit 1
    fi
}

ok() {
    echo "OK" >&2
}

ko() {
    echo "KO" >&2
}



system_update(){
    echo "[$(date +%H:%M:%S)]: Running apt-get update..."
    apt-get update -y -qq   
    
    echo "[$(date +%H:%M:%S)]: Running apt-get upgrade..."
    apt-get upgrade -y -qq

    echo "[$(date +%H:%M:%S)]: Download Pre-requsites..."
    apt-get install zip unzip -y -qq
    apt-get install python3-pip -y -qq
}

install_openjdk(){
    echo "[$(date +%H:%M:%S)]: Installing OpenJDK"
    add-apt-repository ppa:openjdk-r/ppa -y
    apt-get install openjdk-8-jre-headless -y -qq
}

install_elastic(){
    echo "[$(date +%H:%M:%S)]: Installing Elasticsearch 6.x"
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key D88E42B4 >/dev/null
    bash -c 'echo deb https://artifacts.elastic.co/packages/6.x/apt stable main > /etc/apt/sources.list.d/elastic-6.x.list'
    apt-get install apt-transport-https -y
    apt-get update && apt-get install elasticsearch -y
}

configure_elastic(){
    echo "[$(date +%H:%M:%S)]: Updating elasticsearch.yml file"    
    sed -i 's/#network.host: 192.168.0.1/network.host: 127.0.0.1/g' /etc/elasticsearch/elasticsearch.yml
    sed -i 's/#cluster.name: my-application/cluster.name: hive/g' /etc/elasticsearch/elasticsearch.yml
    bash -c 'echo thread_pool.index.queue_size: 100000 >> /etc/elasticsearch/elasticsearch.yml'
    bash -c 'echo thread_pool.search.queue_size: 100000 >> /etc/elasticsearch/elasticsearch.yml'
    bash -c 'echo thread_pool.bulk.queue_size: 100000 >> /etc/elasticsearch/elasticsearch.yml'   
    bash -c 'echo path.repo: [\"/opt/backup\"] >>/etc/elasticsearch/elasticsearch.yml'
    mkdir /opt/backup
    chown -R elasticsearch:elasticsearch /opt/backup
    echo "[$(date +%H:%M:%S)]: Creating elasticsearch service"    
    systemctl enable elasticsearch.service
    systemctl restart elasticsearch.service
}

install_docker(){
    echo "[$(date +%H:%M:%S)]: Installing Docker"
    wget -O- https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - >/dev/null 2>&1
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
    apt-get install docker-ce -y -qq
}

install_cortex(){
    echo "[$(date +%H:%M:%S)]: Downloading Cortex v3.0.1-1"
    cd /opt 
    wget https://dl.bintray.com/thehive-project/binary/cortex-3.0.1-1.zip >/dev/null 2>&1
    wget http://dl.bintray.com/thehive-project/binary/cortex-3.0.1-1.zip.asc  >/dev/null 2>&1
    gpg --verify cortex-3.0.1-1.zip.asc cortex-3.0.1-1.zip
    # Need logic to confirm its ok.....
    unzip -q cortex-3.0.1-1.zip
    ln -s cortex-3.0.1-1 cortex
}

install_thehive(){
    echo "[$(date +%H:%M:%S)]: Downloading TheHive v3.4.0-1"   
    cd /opt 
    wget https://dl.bintray.com/thehive-project/binary/thehive-3.4.0-1.zip >/dev/null 2>&1
    wget http://dl.bintray.com/thehive-project/binary/thehive-3.4.0-1.zip.asc  >/dev/null 2>&1
    wget https://raw.githubusercontent.com/TheHive-Project/TheHive/master/PGP-PUBLIC-KEY >/dev/null 2>&1
    gpg --import PGP-PUBLIC-KEY
    gpg --verify thehive-3.4.0-1.zip.asc thehive-3.4.0-1.zip
    # Need logic to confirm its ok.....
    unzip -q thehive-3.4.0-1.zip
    ln -s thehive-3.4.0-1 thehive
}

install_python_utils(){
    # pip3 list --format=columns | grep thehive4py 
    echo "[$(date +%H:%M:%S)]: Installaing thehive4py/cortex4py"
    pip3 install cortexutils
    pip3 install thehive4py
    pip3 install cortex4py
}

configure_cortex(){
    echo "[$(date +%H:%M:%S)]: Adding play.secret to Cortex application.conf file"
    cp /opt/cortex/conf/reference.conf /opt/cortex/conf/application.conf  

    sed -i '0,/host = \["127.0.0.1:9300"\]/s//uri = "http:\/\/127.0.0.1:9200"/' /opt/cortex/conf/application.conf
    
    (cat << _EOF_
# Secret key
# ~~~~~
# The secret key is used to secure cryptographics functions.
# If you deploy your application to several instances be sure to use the same key!
play.http.secret.key="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)"
_EOF_
) | sudo tee -a /opt/cortex/conf/application.conf >/dev/null 2>&1

    echo "[$(date +%H:%M:%S)]: Configuring Cortex service"
    sed -i 's/#play.modules.enabled += connectors.cortex.CortexConnector/play.modules.enabled += connectors.cortex.CortexConnector/g' /opt/thehive/conf/application.conf
    sed -i 's/auth.method.basic = false/auth.method.basic = true/g' /opt/cortex/conf/application.conf
    sed -i 's/\/etc\/cortex\//\/opt\/cortex\/conf\//g' /opt/cortex/package/cortex.service
    
    mkdir /var/log/cortex
    addgroup cortex
    adduser --system cortex
    cp /opt/cortex/package/cortex.service /usr/lib/systemd/system
    chown -R cortex:cortex /opt/cortex
    chown -R cortex:cortex /opt/cortex-3.0.1-1
    chown -R cortex:cortex /var/log/cortex
    chgrp cortex /opt/cortex/conf/application.conf
    chmod 640 /opt/cortex/conf/application.conf
    usermod -a -G docker cortex
    systemctl enable cortex
    service cortex start
}

configure_thehive(){
    echo "[$(date +%H:%M:%S)]: Adding play.secret to TheHive application.conf file"
    (cat << _EOF_
# Secret key
# ~~~~~
# The secret key is used to secure cryptographics functions.
# If you deploy your application to several instances be sure to use the same key!
play.http.secret.key="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)"
_EOF_
) | sudo tee -a /opt/thehive/conf/application.conf >/dev/null 2>&1
    
    echo "[$(date +%H:%M:%S)]: Configuring TheHive service"
    sed -i 's/\/etc\/thehive\//\/opt\/thehive\/conf\//g' /opt/thehive/package/thehive.service
    sed -i 's/auth.method.basic = false/auth.method.basic = true/g' /opt/thehive/conf/application.conf

    mkdir /var/log/thehive
    addgroup thehive
    adduser --system thehive
    cp /opt/thehive/package/thehive.service /usr/lib/systemd/system
    chown -R thehive:thehive /opt/thehive
    chown -R thehive:thehive /opt/thehive-3.4.0-1
    chown -R thehive:thehive /var/log/thehive
    chgrp thehive /opt/thehive/conf/application.conf
    chmod 640 /opt/thehive/conf/application.conf
    systemctl enable thehive
    service thehive start
}

init_cortex(){
    echo "[$(date +%H:%M:%S)]: Checking Cortex is available"
    sleep 30
    check 200 "$CORTEX_URL/index.html"

    echo "[$(date +%H:%M:%S)]: Creating the index"
    check 204 -XPOST "$CORTEX_URL/api/maintenance/migrate"

    echo "[$(date +%H:%M:%S)]: Creating the Cortex SuperAdmin account"
    check 201 "$CORTEX_URL/api/user" -H 'Content-Type: application/json' -d '
            {
              "login" : "admin",
              "name" : "admin",
              "roles" : [
                  "superadmin"
               ],
              "preferences" : "{}",
              "password" : "thehive1234",
              "organization": "cortex"
            }'

    echo "[$(date +%H:%M:%S)]: Creating the Cortex 'YourOrg' Organization"
    check 201 -u admin:thehive1234 "$CORTEX_URL/api/organization" -H 'Content-Type: application/json' -d '
        {
          "name": "YourOrg",
          "description": "Your organization"
        }'


    echo "[$(date +%H:%M:%S)]: Creating the Cortex 'YourOrg' OrgAdmin"
    check 201 -u admin:thehive1234 "$CORTEX_URL/api/user" -H 'Content-Type: application/json'  -d '
        {
          "login" : "thehive",
          "name" : "thehive",
          "roles" : [
              "read",
              "analyze",
              "orgadmin"
           ],
          "password" : "thehive1234",
          "organization": "YourOrg"
        }'

    echo "[$(date +%H:%M:%S)]: Creating api key for OrgAdmin"
    # API key that contains a '/' causes issues, so keep trying until we get one without a '/'
    key="///" 

    while true; do
        sleep 1
        if [[ "$key" == */* ]];
        
        then
            key=$(curl -s -u admin:thehive1234 "$CORTEX_URL/api/user/thehive/key/renew" -d '')
        else
            break
        fi
    done

    check 200 "$CORTEX_URL/api/user/thehive" -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $key"

    
    echo "[$(date +%H:%M:%S)]: Enabling TheHive / Cortex Integration Key"
    sed -i 's/^cortex {.*/cortex {\n  "CORTEX" {\n    url = "http:\/\/127.0.0.1:9001"\n    key = "'$key'"\n    ws {}\n  }\n}/g' /opt/thehive/conf/application.conf
    sed -i '/#"CORTEX-SERVER-ID" {/,+6 d' /opt/thehive/conf/application.conf

    echo "[$(date +%H:%M:%S)]: Disabling basic auth for Cortex"
    sed -i 's/auth.method.basic = true/auth.method.basic = false/g' /opt/cortex/conf/application.conf

    echo "[$(date +%H:%M:%S)]: Configuring Docker Analyzers/Responders for Cortex"
    sed -i '0,/urls = \[\]/s//urls = \[\"https:\/\/dl.bintray.com\/thehive-project\/cortexneurons\/analyzers.json"\]/' /opt/cortex/conf/application.conf
    sed -i '0,/urls = \[\]/s//urls = \[\"https:\/\/dl.bintray.com\/thehive-project\/cortexneurons\/responders.json"\]/' /opt/cortex/conf/application.conf

    echo "[$(date +%H:%M:%S)]: Restarting TheHive and Cortex"
    service thehive restart
    service cortex restart
    sleep 30
    check 200 "$CORTEX_URL/index.html"    
}

activate_analyzer() {

    echo "[$(date +%H:%M:%S)]: Activating Analyzer $1"
    if [ "$2" ]
    then
      data="$2"
    else  
      data='{
              "configuration": {
                  "check_tlp": false,
                  "max_tlp": 2
              },
              "name": '\"$1\"'
          }'
    fi

    status_code=$(curl -s -H "Authorization: Bearer ${key}" "$CORTEX_URL/api/organization/analyzer/${1}" \
        -H 'Content-Type: application/json' -d "$data" -o /dev/stderr -w '%{http_code}')

    if [ "${status_code}" = "201" ]
    
    then
        ok
    else
        ko
    fi

}

configure_pre_logon(){
    echo "[$(date +%H:%M:%S)]: Configuring /etc/issue file"
    (cat << _EOF_

---

IP Address: \4{eth0}

---

TheHive -> http://\4{eth0}:9000
Cortex  -> http://\4{eth0}:9001


---


_EOF_
) | sudo tee -a /etc/issue >/dev/null 2>&1

}

reboot_system(){
    echo "[$(date +%H:%M:%S)]: Script Complete - Rebooting"
    sleep 30
    reboot now
}


# Script starts here

main() {
    system_update
    install_openjdk
    install_elastic
    configure_elastic
    install_docker
    install_cortex
    install_thehive
    install_python_utils
    configure_cortex
    configure_thehive
    init_cortex
    activate_analyzer Abuse_Finder_2_0
    activate_analyzer DShield_lookup_1_0
    activate_analyzer FileInfo_7_0 '{ 
    "name": "FileInfo_7_0",
    "configuration": {
        "manalyze_enable": false,
        "manalyze_enable_docker": false,
        "manalyze_enable_binary": false,
        "auto_extract_artifacts": true,
        "check_tlp": false,
        "max_tlp": 2,
        "check_pap": false,
        "max_pap": 2
    },
    "jobCache": 0
    }'
    activate_analyzer EmlParser_1_2
    activate_analyzer MaxMind_GeoIP_3_0
    activate_analyzer UnshortenLink_1_2
    activate_analyzer Fortiguard_URLCategory_2_1
    activate_analyzer CyberCrime-Tracker_1_0
    activate_analyzer TalosReputation_1_0
    activate_analyzer URLhaus_2_0
    activate_analyzer Urlscan_io_Search_0_1_0
    configure_pre_logon
    reboot_system

}

main
exit 0
