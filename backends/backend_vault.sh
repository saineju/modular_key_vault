#!/bin/bash

## Hashicorp vault backend
## This module is intended to be used with
## - ssh-key-vault -tool
## - aws-key-vault -tool (TBD)
## - password-vault -tool (TBD)
## Variables that are set by this module
## - error - If dependecies are not installed, error is set to 1
## - secret - This will be set if searched value will have only one entry
## - secrets - This will be set if requested secret provides multiple values
## Function expected to be found
## - vault_unseal
## - vault_sync
## - vault_check_dependencies
## - vault_login
## - vault_add_secret
## - vault_get_secret
## - vault_search_secret
## - vault_list_secrets

## curl parameters
curl_params="-sk"

## No need to sync, but function needs to exists for compatibility reasons
function vault_sync() {
    return
}

function vault_check_dependencies(){
  command -v curl >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}curl${nc} is required, but not installed";error=1; }
  command -v jq >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}jq${nc} is required, but not installed";error=1; }
}

function check_if_sealed(){
    ## If vault is sealed return 0 otherwise return 1
    $(curl ${curl_params} ${vault_address}/v1/sys/seal-status|jq .sealed) && return $?
}

function vault_unseal(){
    check_if_sealed
    sealed=$?
    while [ ${sealed} == 0 ]; do
        ## Unseal vault
        read -s -p "Enter unseal token: " unseal_token
        echo
        payload="{\"key\":\"${unseal_token}\"}"
        curl ${curl_params} -X PUT -d ${payload} ${vault_address}/v1/sys/unseal -o /dev/null
        sealed=check_if_unsealed
    done
}

function vault_test_token(){
    ## if token is set and is valid, return 1 otherwise return 0
    if [ -n ${VAULT_TOKEN} ]; then
        return_code=$(curl ${curl_params} -I -X LIST -H "X-Vault-Token: ${VAULT_TOKEN}" ${vault_address}/v1/auth/token/accessors -o /dev/null -w '%{http_code}\n')
        [[ ${return_code} == 200 ]] && return 1
    fi
    return 0
}

## Currently only supports username and password login
function vault_login(){
    vault_unseal
    vault_test_token
    token_invalid=$?
    while [ ${token_invalid} == 0 ]; do
        read -p "Enter username for vault: " username
        read -s -p "Enter password for vault: " password
        payload="{\"password\":\"${password}\",\"token_ttl\":\"${token_ttl}\"}"
        echo
        export VAULT_TOKEN=$(curl ${curl_params} -X POST -d ${payload} "${vault_address}/v1/auth/userpass/login/${username}"|jq -r .auth.client_token)
        vault_test_token
        token_invalid=$?
    done
}

function vault_list_secrets(){
    unset secret
    secrets=$(curl ${curl_params} -X LIST -H "X-Vault-Token: ${VAULT_TOKEN}" https://localhost:8200/v1/${keyvault}/metadata/${key_prefix}|jq -r '.data.keys[]')
}

function vault_add_secret() {
    if [[ "${secret_type}" == "ssh-key" ]]; then
        payload="{\"data\":{\"private_key\":\"${private_key}\",\"public_key\":\"${public_key}\"}}"
        curl ${curl_params} -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" -d "${payload}|jq ." ${vault_address}/v1/${keyvault}/data/${key_name} -o /dev/null
    fi
}


function vault_get_secret(){
    unset secret
    unset secrets
    result=$(curl ${curl_params} -H "X-Vault-Token: ${VAULT_TOKEN}" ${vault_address}/v1/${keyvault}/data/${key_name})
    if [ "${secret_type}" == "public" ]; then
        secret=$(echo ${result}|jq -r '.data.data.public_key')
    elif [ "${secret_type}" == "private" ]; then
        secret=$(echo ${result}|jq -r '.data.data.private_key')
    fi
}

function vault_search_secret() {
    unset secret
    unset secrets
    vault_list_secrets
    templist=()
    bare_key_name=${key_name#"$key_prefix"}
    for i in ${secrets}; do
        if [[ ${i} =~ $bare_key_name ]]; then
            templist+=(${i})
        fi
    done
    if [[ ${#templist[@]} > 1 ]]; then
        secrets=${templist[@]}|tr ' ' '\n'
    else
        vault_get_secret
    fi
}
