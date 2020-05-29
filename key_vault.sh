#!/bin/bash

#set -e

## Set this to preferred backend
source ./backends/backend_lpass.sh
#source ./backends/backend_bitwarden.sh
source ./support_scripts/fancy_select.sh

key_prefix="lpass_ssh/"
ttl="1h"
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
  echo -e "\t-k|--key-name\tName for key, required for generating key or getting the key"
  echo -e "\t-i|--id\t\tUse key ID to fetch the key"
  echo -e "\t-n|--no-prefix\tDo not add key prefix"
  echo -e "\t-t|--ttl\tHow long private key should exist in agent, uses ssh-agent ttl syntax"
  echo -e "\t-e|--key-enc\tKey type, accepts rsa or ed25519"
  echo -e "\tAll required parameters will be asked unless specified with switch"
}

function generate_key() {
  tempdir=$(mktemp -d)
  mkfifo ${tempdir}/key

  while true
  do
    if [ -z "${key_type}" ]; then
      echo "Please provide key type, allowed values are rsa and ed25519:"
      read key_type
    fi

    if [ "${key_type}" == "rsa" ] || [ "${key_type}" == "ed25519" ]; then
      break
    else
      unset key_type
    fi
  done
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
  if [ -z "${key_name}" ]; then
    echo -n "Enter name for the key: "
    read key_name
  fi
  key_name=${key_name#"$key_prefix"}
  key_name="${key_prefix}${key_name}"
  #payload="private-key: ${private_key}\npublic-key: ${public_key}"
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
  vault_get_secret
  if [[ "$?" != 0 ]]; then
    key_name=${key_name#"$key_prefix/"}
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
  if [ -n "${key_id}" ]; then
    key_name="${key_id}"
  elif [ -z "${key_name}" ]; then
    echo -n "Enter searched key name: "
    read key_name
  fi
  vault_search_secret
  if [[ "$?" != 0 ]]; then
    echo "Key with name ${key_name} not found."
  elif [[ -n "${secrets}" ]]; then
    echo "${secrets}"
  else
    echo "${secret}"
  fi
}

vault_check_dependencies
if [ "${error}" == 1 ]; then
  echo "Please fix errors above, aborting"
  exit 1
fi

if [ $# -eq 0 ]; then
  help
  exit 1
fi

vault_sync

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
      *)
        echo "Unrecognized param: $1"
        shift
      ;;
  esac
done

vault_login

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
