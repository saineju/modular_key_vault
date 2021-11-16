#!/bin/bash

## Hashicorp vault backend
## This module is intended to be used with
## - ssh-key-vault -tool
## - aws-key-vault -tool
## - password-vault -tool (TBD)
## Variables that are set by this module
## - error - If dependecies are not installed, error is set to 1
## - secret - This will be set if searched value will have only one entry
## - secrets - This will be set if requested secret provides multiple values
## Function expected to be found
## - vault_unseal
## - vault_sync
## - vault_check_dependencies
## - vault_check_if_sealed
## - vault_login
## - vault_test_token
## - vault_add_secret
## - vault_get_secret
## - vault_search_secret
## - vault_list_secrets
## - vault_cache_aws_session
## - vault_get_aws_session_from_cache

## No need to sync, but function needs to exists for compatibility reasons
function vault_sync() {
    return
}

function vault_check_dependencies(){
  command -v curl >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}curl${nc} is required, but not installed";error=1; }
  command -v jq >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}jq${nc} is required, but not installed";error=1; }
}

function vault_check_if_sealed(){
    ## If vault is sealed return true otherwise return false
    sealed=$(curl ${curl_params} ${vault_address}/v1/sys/seal-status|jq .sealed)
}

function vault_unseal(){
    vault_check_if_sealed
    while [ "${sealed}" == "true" ]; do
        ## Unseal vault
        read -s -p "Enter unseal token: " unseal_token
        echo
        payload="{\"key\":\"${unseal_token}\"}"
        curl ${curl_params} -X PUT -d ${payload} ${vault_address}/v1/sys/unseal -o /dev/null
        sealed=vault_check_if_sealed
    done
}

function vault_test_token(){
    ## if token is set and is valid, return 1 otherwise return 0
    if [ -n "${VAULT_TOKEN}" ]; then
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
        #echo
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
    if [[ "${mode}" == "ssh-key" ]]; then
        payload="{\"data\":{\"private_key\":\"${private_key}\",\"public_key\":\"${public_key}\"}}"
    elif [[ "${mode}" == "aws" ]]; then
        payload="{\"data\":{\"aws_access_key_id\":\"${aws_access_key_id}\",\"aws_secret_access_key\":\"${aws_secret_access_key}\"}}"
    elif [[ "${mode}" == "password" ]]; then
        payload="{\"data\":{\"password\":\"${secret}\"}}"
    fi
    return_code=$(curl ${curl_params} -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" -d "${payload}|jq ." ${vault_address}/v1/${keyvault}/data/${key_name} -o /dev/null -w '%{http_code}\n')
    [[ ${return_code} == 200 || ${return_code} == 204 ]] || return 1
}



function vault_cache_aws_session(){
    payload="{\"cached\":${secret}}"
    return_code=$(curl ${curl_params} -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" -d"${payload}" ${vault_address}/v1/cubbyhole/${key_name} -o /dev/null -w '%{http_code}\n')
    [[ ${return_code} == 200 || ${return_code} == 204 ]] || return 1
}

function vault_get_aws_session_from_cache(){
    secret=$(curl ${curl_params} -H "X-Vault-Token: ${VAULT_TOKEN}" ${vault_address}/v1/cubbyhole/${key_name}|jq --exit-status .data.cached)
}

function vault_get_secret(){
    unset secret
    unset secrets
    result=$(curl ${curl_params} -H "X-Vault-Token: ${VAULT_TOKEN}" ${vault_address}/v1/${keyvault}/data/${key_name})
    if [ "${mode}" == "ssh-key" ]; then
        if [ "${secret_type}" == "public" ]; then
            secret=$(echo ${result}|jq -r '.data.data.public_key')
        elif [ "${secret_type}" == "private" ]; then
            secret=$(echo ${result}|jq -r '.data.data.private_key')
        fi
    elif [ "${mode}" == "aws" ]; then
        vault_get_aws_session_from_cache
        if [[ $? == 0 ]]; then
            expiration=$(echo ${secret}|jq -r '.Expiration')
            current_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            if [[ "${current_time}" < "${expiration}" ]]; then
                return
            fi
        fi
        export AWS_ACCESS_KEY_ID=$(echo ${result}|jq -r '.data.data.aws_access_key_id')
        export AWS_SECRET_ACCESS_KEY=$(echo ${result}|jq -r '.data.data.aws_secret_access_key')
        secret=$(aws sts get-session-token --duration-seconds ${ttl}|jq '.Credentials += {"Version":1}'|jq .Credentials)
        if [[ $? == 0 ]]; then
            vault_cache_aws_session
        else
            return 1
        fi
    elif [ "${mode}" == "password" ]; then
        secret=$(echo ${result}|jq -r '.data.data.password')    
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
