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
modes=("ssh-key","aws","password")

if [[ -f "${configuration}" ]]; then
    source ${configuration}
fi

function help() {
    echo "Usage: $0 <list|generate|get_key|get_public_key> [-k key_name] [-t ttl] [-e encryption_type]"
    echo -e "\tlist\t\tList keys in vault"
    echo -e "\tsearch\t\tSearch for key name, useful if there are more than one matches"
    echo -e "\tgenerate\tGenerate new key to vault"
    echo -e "\tget_key\t\tGet private key to ssh-agent"
    echo -e "\tget_public_key\tget public key for the specified key"
    echo -e "\tget_vault_token\tOutputs vault token, can be used for getting the token to env"
    echo -e "\tconfigure\tedit the configuration file"
    echo -e "\timport\t\timport existing data from either file or by being asked" 
    echo -e "\tunseal\t\tUnseal hashicorp vault"
    echo -e "\t-k|--key-name\tName for key, required for generating key or getting the key"
    echo -e "\t-i|--id\t\tUse key ID to fetch the key"
    echo -e "\t-n|--no-prefix\tDo not add key prefix"
    echo -e "\t-t|--ttl\tHow long private key should exist in agent, uses ssh-agent ttl syntax"
    echo -e "\t-e|--key-enc\tKey type, accepts rsa or ed25519"
    echo -e "\t-b|--backend\tBackend to use instead of the default one"
    echo -e "\t-m|--mode\twhat key mode should be used, selections: ssh-key,aws,password"
    echo -e "\t-f|--file\tFile to import"
    echo -e "\t-u|--url\tUse different url for key vault if applicable (default: ${vault_address})"
    echo -e "\t-kv|--key-vault\tHashicorp key vault path (default: ${keyvault})"
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

function get_vault_token(){
    if [ "${backend}" == "backend_vault.sh" ]; then
        echo "${VAULT_TOKEN}"
    elif [ "${backend}" == "backend_bitwarden.sh" ]; then
        echo "${BW_SESSION}"
    else
        echo "Backend ${backend} does not support exporting token"
    fi
}

function import() {
    get_key_name
    if [[ ${mode} == ssh-key ]]; then
        if [[ -n ${file} && -f ${file} ]]; then
            while read line; do
                if [ "$line" ]; then
                    private_key+="$line\n"
                else
                    break
                fi
            done < ${file}
            public_key=$(ssh-keygen -y -f ${file})
        else
            echo "To import ssh-key, please add path for the private key"
            exit
        fi
    elif [[ "${mode}" == "aws" ]]; then
        if [[ -n ${file} && -f ${file} ]]; then
            OLDIFS=${IFS}
            IFS=','
            read -ra tempkey <<< "$(tail -n 1 ${file}|tr -d '\r')"
            aws_access_key_id="${tempkey[0]}"
            aws_secret_access_key="${tempkey[1]}"
            IFS=${OLDIFS}
        else
            echo -n "Please enter aws key id: "
            read -s aws_access_key_id
            echo
            echo -n "Please enter aws secret access key: "
            read -s aws_secret_access_key
        fi
    elif [[ "${mode}" == "password" ]]; then
      if [[ -n ${file} && -f ${file} ]]; then
            secret=$(cat ${file})
      else
            echo -n "Please enter password to be stored: "
            read -s secret
      fi
    fi
    vault_add_secret
    if [[ "$?" != 0 ]]; then
        echo "Something went wrong when adding key"
        exit 1
    fi
    echo "Generated secret ${key_name}"
    if [ "${mode}" == "ssh-key" ]; then
        echo "${public_key}"
    fi
}

function configure() {
    key_prefix="${key_prefix:-key_vault/}"
    ttl="${ttl:-1h}"
    mode="${mode:-ssh-key}"
    if [ -n ${backend} ]; then
        ask "Would you like to change the default backend (default: ${backend}) [y/N]" "n"
    fi
    if [[ -z "${backend}" || "${a}" == "y" ]]; then
        echo "What backend would you like to use?"
        declare -a backends
        for b in $(ls ${backend_path}); do
        backends+=("$b")
        done
        select_option ${backends[@]}
        choice=$?
        backend=${backends[$choice]}
    fi

    ## General configuration
    ask "Do you want to change default prefix (default: ${key_prefix}) [y/N]" "n"
    if [[ "$a" == "y" ]]; then
        echo -n "Enter prefix: "
        read key_prefix
    fi

    ask "Do you want to change default key time to live (default: ${ttl}) [y/N]" "n"
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
    ask "Do you want to change default mode (default: ${mode}) [y/N]" "n"
    if [[ "${a}" == "y" ]]; then
        echo "What mode should be default?"
        select_option ${modes[@]}
        choice=$?
        mode=${modes[$choice]}
    fi
    echo "Default settings:"
    echo "backend: ${backend}"
    echo "prefix:  ${key_prefix}"
    echo "ttl:     ${ttl}"
    echo "mode:    ${mode}"
    ## Backend related configuration
    if [ "${backend}" == "backend_vault.sh" ]; then
        curl_params="${curl_params:--s}"
        keyvault="${keyvault:-kv}"
        vault_address="${vault_address:-https://localhost:8200}"
        ask "Do you want to change vault URL (default: ${vault_address} [y/N]" "n"
        if [[ "${a}" == "y" ]]; then
            echo -n "Enter vault url: "
            read VAULT_URL
        fi

        ask "Do you want to add curl parameters (default: ${curl_params} [y/N]" "n"
        if [[ "${a}" == "y" ]]; then
            echo -n "Enter additional curl parameters: "
            read additional_curl_parameters
            curl_params="${curl_params} ${additional_curl_parameters}"
        fi
        ask "Do you want to change key vault path (default: ${keyvault}) [y/N]" "n"
        if [[ "${a}" == "y" ]]; then
            echo -n "Enter key vault path: "
            read keyvault
        fi
    fi
    echo -e "backend=${backend}\nttl=${ttl}\nkey_prefix=${key_prefix}\nmode=${mode}\ncurl_params=\"${curl_params}\"\nvault_address=${vault_address}\nkeyvault=${keyvault}" > ${configuration}
}

function generate_key() {
    get_key_name

    if [[ "${mode}" == "ssh-key" ]]; then
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

        rm -f ${tempdir}/key
        rm -f ${tempdir}/key.pub
        rmdir ${tempdir}
    elif [[ "${mode}" == "password" ]]; then
        ## TODO: Allow more options for password generation
        secret=$(openssl rand -base64 33)
    else
        echo "Mode ${mode} does not support generate"
        exit
    fi
    vault_add_secret
    if [[ "$?" != 0 ]]; then
        echo "Something went wrong when adding key"
        exit 1
    fi
    echo "Generated secret ${key_name}"
    if [ "${mode}" == "ssh-key" ]; then
        echo "${public_key}"
    fi
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
function convert_ttl_to_seconds() {
    factor=1
    if [[ ! ${ttl} =~ ^[0-9]+$ ]]; then
        ttlsuffix=$(echo ${ttl: -1}|tr '[:upper:]' '[:lower:]')
        ttl=${ttl%?}
        if [ "${ttlsuffix}" == "m" ]; then
            factor=60
        elif [ "${ttlsuffix}" == "h" ]; then
            factor=$((60*60))
        elif [ "${ttlsuffix}" == "d" ]; then
            factor=$((60*60*24))
        elif [ "${ttlsuffix}" == "w" ]; then
            factor=$((60*60*24*7))
        fi
    fi
    ttl=$(expr "${ttl}" \* "${factor}" )
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
            -m|--mode)
                mode="$2"
                shift
                shift
            ;;
            -f|--file)
                file="$2"
                shift
                shift
            ;;
            -u|--url)
                vault_address="$2"
                shift
                shift
            ;;
            -kv|--key-vault)
                keyvault="$2"
                shift
                shift
            ;;
            get_public_key)
                secret_type=public
                shift
            ;;
            get_key|get)
                secret_type=private
                shift
            ;;
            get_vault_token)
                get_vault_token=true
                shift
            ;;
            import_key|import)
                import=true
                shift
            ;;
            list)
                list=true
                shift
            ;;
            generate)
                generate=true
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
            unseal)
                vault_unseal
                exit
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

convert_ttl_to_seconds

if [[ ${generate} == true ]]; then
    generate_key
elif [ "${list}" == "true" ]; then
    vault_list_secrets
    echo "${secrets}"
elif [ "${secret_type}" == "private" ]; then
    get_item
    if [ "${mode}" == "ssh-key" ]; then
        echo "${secret}"|ssh-add -t ${ttl} -
    elif [ "${mode}" == "aws" ]; then
        echo "${secret}"
    elif [ "${mode}" == "password" ]; then
        echo "${secret}"
    fi
elif [ "${secret_type}" == "public" ]; then
    get_item
    echo ${secret}
elif [ "${search}" == "true" ]; then
    search
elif [ "${import}" == "true" ]; then
    import
elif [ "${get_vault_token}" == "true" ]; then
    get_vault_token
else
    echo "Did not match any supported actions"
fi
