#!/bin/bash

set -e
set -o pipefail

install_utilities() {
	sudo apt -y install git moreutils
}

install_postgrest() {
  local postgrest_v=$1

  sudo apt-get install -y wget curl jq xz-utils

  local postgrest_url
  postgrest_url="$(curl "https://api.github.com/repos/PostgREST/postgrest/releases/$postgrest_v" | jq -r '.assets[] | select (.name | contains("linux-static-x64")) | .browser_download_url')"
  local postgrest_archive="postgrest-linux-static-x64.tar.xz"
  wget "$postgrest_url" -O "$postgrest_archive"

  sudo tar xvf "$postgrest_archive" -C '/usr/local/bin'
  rm "$postgrest_archive"
}

install_python() {
  DEBIAN_FRONTEND=noninteractive sudo apt-get -y install python3 python3-pip python3-venv

  python3 -m venv .tests
  # shellcheck source=/dev/null
  source .tests/bin/activate
  pip install psycopg2-binary
  deactivate
}

install_jmeter() {
  local jmeter_v=$1

  sudo apt-get install -y unzip openjdk-8-jdk wget

  wget "https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${jmeter_v}.zip"

  jmeter_src="apache-jmeter-${jmeter_v}"
  sudo unzip "${jmeter_src}.zip" -d '/opt'
  rm "${jmeter_src}.zip"

  jmeter="jmeter-${jmeter_v}"
  cat <<EOF > "$jmeter"
#!/usr/bin/env bash

cd "/opt/apache-jmeter-${jmeter_v}/bin"
./jmeter \$@
EOF
  sudo chmod +x "$jmeter"
  sudo mv "$jmeter" "/usr/local/bin/${jmeter}"
  sudo ln -sf "/usr/local/bin/${jmeter}" "/usr/local/bin/jmeter"

  sudo chmod 777 "/opt/apache-jmeter-$jmeter_v/bin"
}

print_help () {
cat <<EOF 
  Usage: $0 [OPTION[=VALUE]]...

  Installs dependencies
  OPTIONS:
    --install-all       Install all dependencies
    --install-utilities Install utilities
    --install-postgrest Install PostgREST
    --install-python    Install Python
    --install-jmeter    Install Jmeter
EOF
}

postgrest_v="latest"
jmeter_v="5.4.3"

while [ $# -gt 0 ]; do
  case "$1" in
    --install-all)
        sudo apt-get update
        install_utilities
        install_postgrest $postgrest_v
        install_python
        install_jmeter $jmeter_v
        ;;
    --install-utilities)
        sudo apt-get update
        install_utilities
        ;;
    --install-postgrest)
        sudo apt-get update
        install_postgrest $postgrest_v
        ;;
    --install-python)
        sudo apt-get update
        install_python
        ;;
    --install-jmeter)
        sudo apt-get update
        install_jmeter $jmeter_v
        ;;
    --help|-h|-\?)
        print_help
        exit 0
        ;;
    -*)
        echo "ERROR: '$1' is not a valid option"
        echo
        print_help
        exit 1
        ;;
    *)
        echo "ERROR: '$1' is not a valid argument"
        echo
        print_help
        exit 2
        ;;
    esac
    shift
done
