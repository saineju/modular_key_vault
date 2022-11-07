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

## export defaults
export VAULT_FORMAT="json"
export VAULT_ADDR=${vault_address}
if [ "${ca_path}x" != "x" ]; then
    export VAULT_CAPATH=${ca_path}
fi

## No need to sync, but function needs to exists for compatibility reasons
function vault_sync() {
    return
}

function vault_check_dependencies(){
  command -v jq >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}jq${nc} is required, but not installed";error=1; }
  command -v vault >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}vault${nc} is required, but not installed";error=1; }
}

function vault_check_if_sealed(){
    ## If vault is sealed return true otherwise return false
    sealed=$(vault status|jq .sealed)
}

function vault_unseal(){
    vault_check_if_sealed
    while [ "${sealed}" == "true" ]; do
        ## Unseal vault
        vault operator unseal
        sealed=vault_check_if_sealed
    done
}

function vault_test_token(){
    ## if token is set and is valid, return 1 otherwise return 0
    vault token lookup > /dev/null 2>&1
    return $?
}

## Currently only supports username and password login
function vault_login(){
    vault_unseal
    vault_test_token
    token_invalid=$?
    while [ ${token_invalid} != 0 ]; do
        if [ "${username}x" == "x" ]; then
            read -p "Enter username for vault: " username
        fi
        unset VAULT_FORMAT
        vault login -no-print -method ${login_method} username=${username}
        vault_test_token
        token_invalid=$?
    done
    export VAULT_FORMAT="json"
}

function vault_list_secrets(){
    unset secrets
    secrets=$(vault kv list ${keyvault}/${key_prefix})
}

function check_if_key_exists(){
    vault kv get ${keyvault}/${key_name} > /dev/null 2>&1
    return $?
}

function vault_add_secret() {
    check_if_key_exists
    if [ $? == 0 ]; then
        vault_method="patch"
    else
        vault_method="put"
    fi
    if [[ "${mode}" == "ssh-key" ]]; then
        vault kv ${vault_method} ${keyvault}/${key_name} private_key="$(echo -e ${private_key})" public_key="${public_key}"
    elif [[ "${mode}" == "aws" ]]; then
        vault kv ${vault_method} ${keyvault}/${key_name} aws_access_key_id="${aws_access_key_id}" aws_secret_access_key="${aws_secret_access_key}"
    elif [[ "${mode}" == "password" ]]; then
        vault kv ${vault_method} ${keyvault}/${key_name} password="${secret}"
    fi
}

function vault_cache_aws_session(){
    vault kv put cubbyhole/${key_name} cached="${secret}"
    return $?
}

function vault_get_aws_session_from_cache(){
    unset secret
    secret=$(vault kv get -field=cached cubbyhole/${key_name})
}

function vault_get_secret(){
    unset secret
    unset secrets

    result=$(vault kv get -format=json ${keyvault}/${key_name})
    if [ "${secret_name}x" != "x" ]; then
        secret=$(echo ${result}|jq -r --arg keyname ${secret_name} '.data.data[$keyname]')
    elif [ "${mode}" == "ssh-key" ]; then
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
        if [ "${otp_token}x" != "x" ]; then
            mfadevice=$(aws iam list-mfa-devices|jq -r '.MFADevices[0].SerialNumber')
            secret=$(aws sts get-session-token --duration-seconds ${ttl} --serial-number ${mfadevice} --token-code ${otp_token}|jq '.Credentials += {"Version":1}'|jq .Credentials)
        else
            secret=$(aws sts get-session-token --duration-seconds ${ttl}|jq '.Credentials += {"Version":1}'|jq .Credentials)
        fi
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
