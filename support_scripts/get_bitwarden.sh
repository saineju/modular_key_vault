#!/bin/bash

set -e

function install_bitwarden() {
    ver=$1
    if [[ "${ver}" == "" || "${ver}" == "latest" ]]; then
        ver=$(curl -s https://api.github.com/repos/bitwarden/cli/releases/latest|jq -r .tag_name)
    fi
    echo "Attempting to install Bitwarden cli version ${ver}"
    DOWNLOAD_URL="https://github.com/bitwarden/cli/releases/download/${ver}"
    FILE="bw-linux-${ver:1}.zip"
    SHASUMS="bw-linux-sha256-${ver:1}.txt"
    wget -O /tmp/${FILE} ${DOWNLOAD_URL}/${FILE}
    wget -O /tmp/${SHASUMS} ${DOWNLOAD_URL}/${SHASUMS}
    cd /tmp
    dos2unix ${SHASUMS}
    if [ -f /etc/alpine-release ]; then
        echo "$(cat ${SHASUMS}|tr '[:upper:]' '[:lower:]')  ${FILE}"|sha256sum -c
        ret=$?
    else
        echo "$(cat ${SHASUMS}) ${FILE}"|sha256sum -c
        ret=$?
    fi
    if [ ${ret} != 0 ]; then
        echo "Checksums did not match, downloaded file is corrupted, exiting"
        exit 1
    fi
    unzip /tmp/${FILE} -d /usr/local/sbin
    rm -f /tmp/${FILE}
    rm -f /tmp/${SHASUMS}
}

install_bitwarden latest
