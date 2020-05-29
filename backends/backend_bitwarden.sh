#!/bin/bash

key_prefix="bw_ssh_"
ttl="1h"
error=0
red='\033[0;31m'
yellow='\033[0;33m'
nc='\033[0m'

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
  command -v bw >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}bitwarden cli${nc} is required, but not installed";error=1; }
  command -v jq >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}jq${nc} is required, but not installed";error=1; }
}

function vault_login(){
  ## Check login status
  bw login --check >/dev/null 2>&1
  if [ $? != 0 ]; then
    export BW_SESSION=$(bw login --raw)
  fi

  ## Check for session variable
  if [ -z "${BW_SESSION}" ]; then
    export BW_SESSION=$(bw unlock --raw)
  fi
}

function vault_sync(){
  bw sync
}

function vault_add_secret() {
  if [[ "${secret_type}" == "ssh-key" ]]; then
    payload="${private_key}\n${public_key}"
    response=$(echo "{\"organizationId\":null,\"folderId\":null,\"type\":2,\"name\":\"${key_name}\",\"notes\":\"${payload}\",\"favorite\":false,\"login\":null,\"secureNote\":{\"type\":0},\"card\":null,\"identity\":null}"|bw encode|bw create item)
    exitvalue=$?
  fi
  vault_sync
  return ${exitvalue}
}

function vault_list_secrets() {
  unset secret
  secrets=$(bw list items --search ${key_prefix}|jq '[.[] | "\(.name) [id: \(.id)]"]')
}

function vault_search_secret() {
  unset secret
  unset secrets
  secrets=$(bw list items --search "${key_name}"|jq '.[] | "\(.name) [id: \(.id)]"')
  exitvalue=$?
  return ${exitvalue}
}

function vault_get_secret() {
  unset secret
  unset secrets
  result=$(bw get item "${key_name}" 2>/dev/null)
  exitvalue=$?
  if [[ "${exitvalue}" == 0 ]]; then
    if [ "${secret_type}" == "public" ]; then
      secret=$(echo ${result}|jq -r '.notes'|grep -E "ssh-(rsa|ed25519)")
    elif [ "${secret_type}" == "private" ]; then
      secret=$(echo ${result}|jq -r '.notes'|grep -Ev "ssh-(rsa|ed25519)")
    fi
  fi
  return ${exitvalue}
}


