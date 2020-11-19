#!/bin/bash

## Lastpass cli backend
## This module is intended to be used with
## - ssh-key-vault -tool
## - aws-key-vault -tool (TBD)
## Variables that are set by this module
## - error - If dependecies are not installed, error is set to 1
## - secret - This will be set if searched value will have only one entry
## - secrets - This will be set if requested secret provides multiple values
## Function expected to be found
## - vault_check_dependencies
## - vault_login
## - vault_sync
## - vault_add_secret
## - vault_get_secret
## - vault_search_secret
## - vault_list_secrets

function vault_check_dependencies(){
  command -v lpass >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}lastpass cli${nc} is required, but not installed";error=1; }
  command -v jq >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}jq${nc} is required, but not installed";error=1; }
}

function vault_login(){
    lpass status >/dev/null 2>&1
    if [ $? != 0 ]; then
        if [[ -f "${HOME}/.lpass/username" ]]; then
            vault_sync
        else
            echo -n "Enter username for lastpass: "
            read username
            lpass login ${username}
        fi
    fi
}

function vault_sync(){
    lpass sync
}

function vault_add_secret() {
    if [[ "${secret_type}" == "ssh-key" ]]; then
        payload="Private Key: ${private_key}\nPublic Key: ${public_key}"
        printf "${payload}"|lpass add --sync=auto --non-interactive --note-type=ssh-key ${key_name}
        exitvalue=$?
    fi
    return $exitvalue
}

function vault_list_secrets(){
    unset secret
    secrets=$(lpass ls ${key_prefix})
}

function vault_get_secret(){
    unset secret
    unset secrets
    if [ "${secret_type}" == "public" ]; then
        result=$(lpass show -G "${key_name}" --field="Public Key" 2>/dev/null)
        exitvalue=$?
        if [[ ${exitvalue} != 0 ]]; then
            result=$(lpass show -G "${key_name}" --field=public-key 2>/dev/null)
            exitvalue=$?
        fi
        if [[ "${result}" = *"Multiple"* ]]; then
            secrets=$result
        else
            secret=$result
        fi
    elif [ "${secret_type}" == "private" ]; then
        result=$(lpass show -G "${key_name}" --field="Private Key" 2>/dev/null)
        exitvalue=$?
        if [[ ${exitvalue} != 0 ]]; then
            result=$(lpass show -G "${key_name}" --field=private-key 2>/dev/null)
            exitvalue=$?
        fi
        if [[ "${result}" = *"Multiple"* ]]; then
            secrets=$result
        else
            secret=$result
        fi
    fi
    return ${exitvalue}
}

function vault_search_secret() {
    unset secret
    unset secrets
    result=$(lpass show -G "${key_name}" -j 2>/dev/null)
    exitvalue=$?
    if [[ "${result}" = *"Multiple"* ]]; then
        secrets=${result}
    else
        secret=$(echo "${result}"|jq -r '.[] | "\(.fullname) [id: \(.id)]"')
    fi
    return ${exitvalue}
}
