#!/bin/bash

script_dir=$(dirname $0)
source "${script_dir}/support_scripts/fancy_select.sh"
configuration_path="${HOME}/.key_vault"
configuration_file="configuration"
configuration="${configuration_path}/${configuration_file}"
backend_path="${script_dir}/backends"
error=0
red='\033[0;31m'
yellow='\033[0;33m'
nc='\033[0m'

function help() {
    echo "Usage: $0 <list|generate|get_key|get_public_key> [-k key_name] [-t ttl] [-e encryption_type]"
    echo -e "\tlist\t\tList keys in vault"
    echo -e "\tsearch\t\tSearch for key name, useful if there are more than one matches"
    echo -e "\tgenerate\tGenerate new key to vault"
    echo -e "\tget_key\t\tGet private key to ssh-agent"
    echo -e "\tget_public_key\tget public key for the specified key"
    echo -e "\tconfigure\tedit the configuration file"
    echo -e "\t-k|--key-name\tName for key, required for generating key or getting the key"
    echo -e "\t-i|--id\t\tUse key ID to fetch the key"
    echo -e "\t-n|--no-prefix\tDo not add key prefix"
    echo -e "\t-t|--ttl\tHow long private key should exist in agent, uses ssh-agent ttl syntax"
    echo -e "\t-e|--key-enc\tKey type, accepts rsa or ed25519"
    echo -e "\t-b|--backend\tBackend to use instead of the default one"
    echo -e "\tAll required parameters will be asked unless specified with switch"
}

function ask(){
    while : ; do
        echo -n "$1 "
        read a
        [ "$a" = "" ] && a="$2"
        a=$(echo $a | tr A-Z a-z)
        [ "$a" = "y" -o "$a" = "n" ] && break
        echo
            echo "Illegal input!"
            echo
    done
}

function get_key_name(){
    if [ -n "${key_id}" ]; then
        key_name="${key_id}"
    elif [ -z "${key_name}" ]; then
        echo -n "Enter searched key name: "
        read key_name
      fi

      if [ -z "${no_prefix}" ]; then
          key_name=${key_name#"$key_prefix"}
          key_name="${key_prefix}${key_name}"
      fi
}

function configure() {
    key_prefix="key_vault/"
    ttl="1h"
    echo "What backend would you like to use?"
    declare -a backends
    for b in $(ls ${backend_path}); do
        backends+=("$b")
    done
    select_option ${backends[@]}
    choice=$?
    backend=${backends[$choice]}

    ## General configuration
    ask "Do you want to change default prefix (default: ${key_prefix}) [y/N]" "n"
    if [[ "$a" == "y" ]]; then
        echo -n "Enter prefix: "
        read key_prefix
    fi

    ask "Do you want to change default key time to live (default ${ttl}) [y/N]" "n"
    if [[ "$a" == "y" ]]; then
        ttl_ok=1
        while [ ${ttl_ok} != 0 ]; do
            echo -n "Enter ttl: "
            read ttl
            if [[ $(echo "${ttl}"|egrep "^[[:digit:]]+[sSwWdDhHmM]?$") ]]; then
                ttl_ok=0
            else
                echo "Invalid ttl format, ssh-add formats supported"
            fi
        done
    fi

    echo "Settings:"
    echo "backend: ${backend}"
    echo "prefix:  ${key_prefix}"
    echo "ttl:     ${ttl}"
    echo -e "backend=${backend}\nttl=${ttl}\nkey_prefix=${key_prefix}" > ${configuration}

    ## Backend related configuration
    if [ "${backend}" == "vault" ]; then
        curl_parameteters="-s"
        keyvault="kv"
        ask "Do you want to change vault URL (default: ${VAULT_URL:-https://localhost:8200} [y/N]" "n"
        if [[ "${a}" == "y" ]]; then
            echo -n "Enter vault url: "
            read VAULT_URL
        fi

        ask "Do you want to add curl parameters (default: ${curl_parameters} [y/N]" "n"
        if [[ "${a}" == "y" ]]; then
            echo -n "Enter additional curl parameters: "
            read additional_curl_parameters
            curl_parameters="${curl_parameters} ${additional_curl_parameters}"
        fi
        ask "Do you want to change key vault path (default: ${keyvault}) [y/N]" "n"
        if [[ "${a}" == "y" ]]; then
            echo -n "Enter key vault path: "
            read keyvault
        fi
        echo -e "\ncurl_params=${curl_parameters}\nvault_address=${VAULT_URL}\nkeyvault=${keyvault}" >> ${configuration}
    fi
}

function generate_key() {
    tempdir=$(mktemp -d)
    mkfifo ${tempdir}/key

    if [ -z "${key_type}" ]; then
        declare -a key_types
        key_types=("rsa" "ed25519")
        echo "Select key type:"
        select_option ${key_types[@]}
        choice=$?
        key_type=${key_types[$choice]}
    fi

    if [ "${key_type}" == "rsa" ]; then
        ssh-keygen -t rsa -b 4096 -f ${tempdir}/key -N ''>/dev/null 2>&1 <<< y > /dev/null&
    else
        ssh-keygen -t ed25519 -f ${tempdir}/key -N ''>/dev/null 2>&1 <<< y > /dev/null&
    fi
    private_key=''
    while read line; do
        if [ "$line" ]; then
            private_key+="$line\n"
        else
            break
        fi
    done < ${tempdir}/key
    public_key=$(cat ${tempdir}/key.pub)
    get_key_name

    rm -f ${tempdir}/key
    rm -f ${tempdir}/key.pub
    rmdir ${tempdir}
    vault_add_secret
    if [[ "$?" != 0 ]]; then
        echo "Something went wrong when adding key"
        exit 1
    fi
    echo "${public_key}"
}

function generate_selection(){
    OIFS=$IFS
    IFS=$'\n'
    declare -a options
    echo "Multiple matches found, please select correct one with arrow keys"
    for i in ${secrets};do
        if [[ "$i" != "Multiple matches found." ]]; then
            options+=("$i")
        fi
    done
    IFS=${OIFS}
    select_option "${options[@]}"
    choice=$?
    key_name=$(echo ${options[$choice]}|egrep -o "id: [[:alnum:]]+"|cut -d ' ' -f 2)
}

function get_item() {
    get_key_name
    vault_get_secret
    if [[ "$?" != 0 ]]; then
        key_name=${key_name#"$key_prefix"}
        vault_search_secret
        if [[ "$?" != 0 ]]; then
            echo "Unable to find key with name ${key_name}"
            exit 1
        fi
        if [ -n "${secrets}" ]; then
            generate_selection
        fi
        vault_get_secret
        if [[ "$?" != 0 ]]; then
            echo "Unable to get ${secret_type}-key for ${key_name}"
            exit 1
        fi
    fi
    if [[ -n "${secrets}" ]]; then
        generate_selection
        vault_get_secret
    fi
}

function search(){
    get_key_name
    vault_search_secret
    if [[ "$?" != 0 ]]; then
        echo "Key with name ${key_name} not found."
    elif [[ -n "${secrets}" ]]; then
        echo "${secrets}"
    else
        echo "${secret}"
    fi
}

if [[ ! -f "${configuration}" || "${configure}" == "true" ]]; then
    mkdir -p ${HOME}/.key_vault
    configure
    help
    exit 0
fi

if [ $# -eq 0 ]; then
    help
    exit 1
fi

source ${configuration}

while [[ $# -gt 0 ]]
    do
        opt="$1"
        case $opt in
            -k|--key-name)
                key_name="$2"
                shift
                shift
            ;;
            -i|-id)
                key_id="$2"
                no_prefix=true
                shift
                shift
            ;;
            -n|--no-prefix)
                no_prefix=true
                shift
            ;;
            -t|--ttl)
                ttl="$2"
                shift
                shift
            ;;
            -e|--key-enc)
                key_type="$2"
                shift
                shift
            ;;
            -h|--help)
                help
                exit 0
            ;;
            -b|--backend)
                backend="$2"
                shift
                shift
            ;;
            get_public_key)
                secret_type=public
                shift
            ;;
            get_key)
                secret_type=private
                shift
            ;;
            list)
                list=true
                shift
            ;;
            generate)
                generate=true
                secret_type='ssh-key'
                shift
            ;;
            search)
                search=true
                shift
            ;;
            configure)
                configure
                shift
            ;;
            *)
                echo "Unrecognized param: $1"
                shift
            ;;
    esac
done

## Allow backend to be inputted with just the backend name without prefix and suffix
backend=${backend#"backend_"}
backend=${backend%".sh"}
backend="backend_${backend}.sh"

source "${backend_path}/${backend}"

vault_check_dependencies
if [ "${error}" == 1 ]; then
    echo "Please fix errors above, aborting"
    exit 1
fi

vault_login
vault_sync

if [ "${generate}" == "true" ]; then
    generate_key
elif [ "${list}" == "true" ]; then
    vault_list_secrets
    echo "${secrets}"
elif [ "${secret_type}" == "private" ]; then
    get_item
    echo "${secret}"|ssh-add -t ${ttl} -
elif [ "${secret_type}" == "public" ]; then
    get_item
    echo ${secret}
elif [ "${search}" == "true" ]; then
    search
fi
