#! /bin/bash

export DEBIAN_FRONTEND=noninteractive

system_update(){
    echo "[$(date +%H:%M:%S)]: Running apt-get update..."
    apt-get update    
    
    echo "[$(date +%H:%M:%S)]: Running apt-get upgrade..."
    apt-get upgrade -y

    echo "[$(date +%H:%M:%S)]: Download Pre-requsites..."
    apt-get install zip unzip python3-pip
}

install_openjdk(){
    echo "[$(date +%H:%M:%S)]: Installing OpenJDK"
    add-apt-repository ppa:openjdk-r/ppa -y
    apt-get install openjdk-8-jre-headless -y
}

install_elastic(){
    echo "[$(date +%H:%M:%S)]: Installing Elasticsearch 5.x"    
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key D88E42B4 >/dev/null
    bash -c 'echo deb https://artifacts.elastic.co/packages/5.x/apt stable main > /etc/apt/sources.list.d/elastic-5.x.list'
    apt-get install apt-transport-https -y
    apt-get update && apt-get install elasticsearch -y
}

configure_elastic(){
    echo "[$(date +%H:%M:%S)]: Updating elasticsearch.yml file"    
    sed -i 's/#network.host: 192.168.0.1/network.host: 127.0.0.1/g' /etc/elasticsearch/elasticsearch.yml
    sed -i 's/#cluster.name: my-application/cluster.name: hive/g' /etc/elasticsearch/elasticsearch.yml
    bash -c 'echo script.inline: true >> /etc/elasticsearch/elasticsearch.yml'
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

install_thehive(){
    echo "[$(date +%H:%M:%S)]: Downloading TheHive v3.4.0-1"   
    cd /opt 
    wget https://dl.bintray.com/thehive-project/binary/thehive-3.4.0-1.zip >/dev/null 2>&1
    wget http://dl.bintray.com/thehive-project/binary/thehive-3.4.0-1.zip.asc  >/dev/null 2>&1
    wget https://raw.githubusercontent.com/TheHive-Project/TheHive/master/PGP-PUBLIC-KEY >/dev/null 2>&1
    gpg --import PGP-PUBLIC-KEY
    gpg --verify thehive-3.4.0-1.zip.asc thehive-3.4.0-1.zip
    # Need logic to confirm its ok.....
    unzip thehive-3.4.0-1.zip
    ln -s thehive-3.4.0-1 thehive
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

install_cortex(){
    echo "[$(date +%H:%M:%S)]: Downloading Cortex v3.0.0-1"
    cd /opt 
    wget https://dl.bintray.com/thehive-project/binary/cortex-3.0.0-1.zip >/dev/null 2>&1
    wget http://dl.bintray.com/thehive-project/binary/cortex-3.0.0-1.zip.asc  >/dev/null 2>&1
    gpg --verify thehive-3.4.0-1.zip.asc thehive-3.4.0-1.zip
    # Need logic to confirm its ok.....
    unzip cortex-3.0.0-1.zip
    ln -s cortex-3.0.0-1 cortex
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
    sed -i 's/\/etc\/cortex\//\/opt\/cortex\/conf\//g' /opt/cortex/package/cortex.service

    mkdir /var/log/cortex
    addgroup cortex
    adduser --system cortex
    cp /opt/cortex/package/cortex.service /usr/lib/systemd/system
    chown -R cortex:cortex /opt/cortex
    chown -R cortex:cortex /opt/cortex-3.0.0-1
    chown -R cortex:cortex /var/log/cortex
    chgrp cortex /opt/cortex/conf/application.conf
    chmod 640 /opt/cortex/conf/application.conf
    systemctl enable cortex
    service cortex start
}


add_analyzers(){
    echo "[$(date +%H:%M:%S)]: Installing Docker"
    wget -O- https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - >/dev/null 2>&1
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
    apt-get install docker-ce -y
    usermod -a -G docker cortex

    echo "[$(date +%H:%M:%S)]: Configuring Cortex Analyzers and Responders"
    (cat << _EOF_

job {
    runner = [docker]
}
_EOF_
) | sudo tee -a /opt/cortex/conf/application.conf >/dev/null 2>&1

    sed -i '0,/urls = \[\]/s//urls = \[\"https:\/\/dl.bintray.com\/thehive-project\/cortexneurons\/analyzers.json"\]/' /opt/cortex/conf/application.conf
    sed -i '0,/urls = \[\]/s//urls = \[\"https:\/\/dl.bintray.com\/thehive-project\/cortexneurons\/responders.json"\]/' /opt/cortex/conf/application.conf

}

restore_db(){
    echo "[$(date +%H:%M:%S)]: Restoring TheHive DB"
    cp /vagrant/thehivedb.zip /opt/backup
    cd /opt/backup
    unzip thehivedb.zip
    chown -R elasticsearch:elasticsearch /opt/backup

    echo "[$(date +%H:%M:%S)]: Registering snapshot with Elasticsearch"
    curl -s -XPUT 'http://localhost:9200/_snapshot/the_hive_backup' -d '{
        "type": "fs",
        "settings": {
            "location": "/opt/backup",
            "compress": true
        }
    }' 

    echo "[$(date +%H:%M:%S)]: Performing restore of TheHive and Cortex DB's"
    curl -XPOST 'http://localhost:9200/_snapshot/the_hive_backup/backup/_restore' -d '{
        "indices": [ "the_hive_15", "cortex_4"]
    }' 
    sleep 30
    curl -s 'http://localhost:9200/_cat/indices?v'
}

integrate_thehive_cortex(){
    echo "[$(date +%H:%M:%S)]: Enabling TheHive/Cortex integration"
    sed -i 's/#play.modules.enabled += connectors.cortex.CortexConnector/play.modules.enabled += connectors.cortex.CortexConnector/g' /opt/thehive/conf/application.conf
    sed -i 's/^cortex {.*/cortex {\n  "CORTEX" {\n    url = "http:\/\/127.0.0.1:9001"\n    key = "xYMjaioc7CCsTPkk2n\/Wt7msmZ36RFz8"\n    ws {}\n  }\n}/g' /opt/thehive/conf/application.conf
    sed -i '/#"CORTEX-SERVER-ID" {/,+6 d' /opt/thehive/conf/application.conf
    
}

install_apiutils(){
    # pip3 list --format=columns | grep thehive4py 
    echo "[$(date +%H:%M:%S)]: Installaing thehive4py/cortex4py"
    pip3 install cortexutils
    pip3 install thehive4py
    pip3 install cortex4py
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

system_cleanup(){
    echo "[$(date +%H:%M:%S)]: Performing clean up"
    cd /opt
    mkdir packages
    chmod thehive:thehive packages
    mv *.zip* packages
    mv PGP-PUBLIC-KEY packages
}

reboot_system(){
    echo "[$(date +%H:%M:%S)]: Script Complete - Rebooting"
    reboot now
}

main() {
    system_update
    install_openjdk
    install_elastic
    configure_elastic
    install_thehive
    configure_thehive
    install_cortex
    configure_cortex
    add_analyzers
    restore_db
    integrate_thehive_cortex
    install_apiutils
    configure_pre_logon
    system_cleanup
    reboot_system
}

main
exit 0
