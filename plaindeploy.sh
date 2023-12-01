#!/bin/bash

function configuredocker() {
  sysctl -w vm.max_map_count=262144
  SYSCTL_STATUS=$(grep vm.max_map_count /etc/sysctl.conf)
  if [ "$SYSCTL_STATUS" == "vm.max_map_count=262144" ]; then
    echo "SYSCTL already configured"
  else
    echo "vm.max_map_count=262144" >>/etc/sysctl.conf
  fi
}


function deploylme() {

  docker volume create --name kafka_data > /dev/null
  docker volume create --name esdata > /dev/null
  docker volume create --name zoo_data > /dev/null
  docker volume create --name zoo_log > /dev/null

  docker compose up -d
}

# check if created > curl -X GET http://localhost:8083/connectors
function configsink() {

  echo -e "\e[32m[X]\e[0m Waiting for connector to be ready"
  while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://localhost:8083)" != "200" ]]; do
    sleep 1
  done

  curl -X POST http://localhost:8083/connectors -H 'Content-Type: application/json' -d \
'{
  "name": "elasticsearch-sink",
  "config": {
    "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
    "tasks.max": "1",
    "topics": "example-topic",
    "key.ignore": "true",
    "schema.ignore": "true",
    "connection.url": "http://elasticsearch:9200",
    "type.name": "_doc",
    "name": "elasticsearch-sink",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false"
  }
}'

}

function install() {
  echo -e "Compose config"
  read -e -p "Proceed ([y]es/[n]o):" -i "y" check

  if [ "$check" == "n" ]; then
    return 1
  fi

  apt install apt-transport-https curl software-properties-common net-tools -y
  adduser hyphy
  groupadd docker
  usermod -aG sudo hyphy
  usermod -aG docker hyphy
  ufw allow OpenSSH

  #install docker
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  #move configs
  echo -e "\e[31m[!]\e[0m Duplicationg config."
  cp docker-compose-plain.yml docker-compose.yml

  configuredocker
  deploylme
  configsink
}

function uninstall() {
  echo -e "Clear all?"
  read -e -p "Proceed ([y]es/[n]o):" -i "n" check
  if [ "$check" == "n" ]; then
    return
  elif [ "$check" == "y" ];then
    docker compose down
    docker volume prune -a -f
    cd .. && rm -r EKK 
    echo -e "\e[33m[!]\e[0m - Done"
    return
  else
    echo -e "\e[33m[!]\e[0m ONLY PROVIDE y or n"
  fi
}

############
#START HERE#
############

if [ "$(id -u)" -ne 0 ]; then
  echo -e "\e[31m[!]\e[0m This script must be run with root privileges"
  exit 1
fi

if [ "$1" == "install" ]; then
  install
elif [ "$1" == "uninstall" ]; then
  uninstall
fi