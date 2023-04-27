#!/bin/bash

set -e
set -o pipefail

install_postgrest() {
  sudo apt-get update -y
  sudo apt-get install wget -y

  postgrest=postgrest-v$postgrest_v-linux-static-x64.tar.xz
  wget https://github.com/PostgREST/postgrest/releases/download/v$postgrest_v/$postgrest

  sudo tar xvf $postgrest -C '/usr/local/bin'
  rm $postgrest
}

install_plpython() {
  sudo apt-get update -y
  sudo apt-get -y install python3 postgresql-plpython3-14
}

install_jmeter() {
  sudo apt-get update -y
  sudo apt-get install openjdk-8-jdk -y

  wget "https://downloads.apache.org//jmeter/binaries/apache-jmeter-${jmeter_v}.zip"

  jmeter_src="apache-jmeter-${jmeter_v}"
  sudo unzip "${jmeter_src}.zip" -d '/usr/local/src'
  rm "${jmeter_src}.zip"

  jmeter="jmeter-${jmeter_v}"
  touch $jmeter
  echo '#!/usr/bin/env bash' >> $jmeter
  echo '' >> $jmeter
  echo "cd '/usr/local/src/apache-jmeter-${jmeter_v}/bin'" >> $jmeter
  echo './jmeter $@' >> $jmeter
  sudo chmod +x $jmeter
  sudo mv $jmeter "/usr/local/bin/${jmeter}"

  sudo chmod 777 /usr/local/src/apache-jmeter-$jmeter_v/bin
}

postgrest_v=9.0.0
jmeter_v=5.5


  install_postgrest
  install_plpython
  install_jmeter
