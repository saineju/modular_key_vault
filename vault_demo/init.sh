#!/bin/sh

GENPASS=0

if [ ! -f /vault/certs/localhost.pem ]; then
  export VAULT_ADDR=http://127.0.0.1:8200
  vault server -config /vault/server.hcl &
  sleep 2
  vault operator init -key-shares=1 -key-threshold=1 | tee /tmp/vault.init > /dev/null
  vault operator unseal $(cat /tmp/vault.init | grep '^Unseal' | awk '{print $4}')
  vault login $(cat /tmp/vault.init | grep '^Initial' | awk '{print $4}')
  vault policy write admin /vault/admin_policy.hcl
  vault auth enable userpass
  ## Generate secure default password
  if [ "${PASS}" == 'admin' ]; then
      PASS=$(openssl rand -base64 18)
      GENPASS=1
  elif [ "${PASS}x" == "x" ]; then 
      PASS=$(openssl rand -base64 18)
      GENPASS=1
  fi
  sed -i "s~<password>~${PASS}~" /vault/user_template.json
  gateway=$(ip r s|grep default|grep -Eo "[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+")
  sed -i "s/<network>/${gateway}\/32/" /vault/user_template.json
  vault write auth/userpass/users/${USER} @/vault/user_template.json
  vault secrets enable -path=default_kv -version=2 kv
  vault secrets enable -path=pki_root pki
  vault secrets tune -max-lease-ttl=87600h pki_root
  vault write -field=certificate pki_root/root/generate/internal common_name="localhost Root Authority" ttl=87600h > /vault/certs/localhost_CA_cert.crt
  vault write pki_root/config/urls \
       issuing_certificates="https://127.0.0.1:8200/v1/pki_root/ca" \
       crl_distribution_points="https://127.0.0.1:8200/v1/pki_root/crl"
  vault secrets enable -path=pki_int pki
  vault secrets tune -max-lease-ttl=43800h pki_int
  vault write -format=json pki_int/intermediate/generate/internal \
        common_name="localhost Intermediate Authority" ttl="43800h" \
        | jq -r '.data.csr' > /tmp/pki_intermediate.csr
  vault write -format=json pki_root/root/sign-intermediate csr=@/tmp/pki_intermediate.csr \
        format=pem_bundle \
        ttl="43800h" \
        | jq -r '.data.certificate' > /vault/certs/intermediate.cert.pem
  vault write pki_int/intermediate/set-signed certificate=@/vault/certs/intermediate.cert.pem
  vault write pki_int/roles/localhost \
        allowed_domains="localhost" \
        allow_subdomains=true \
        max_ttl="17520h"
  vault write -format=json pki_int/issue/localhost common_name="localhost" alt_names="localhost" ip_sans="127.0.0.1" ttl="17520h" > /tmp/localhost_data.json
  cat /tmp/localhost_data.json|jq -r .data.certificate > /vault/certs/localhost.pem
  cat /tmp/localhost_data.json|jq -r .data.private_key > /vault/certs/localhost.key
  cat /vault/certs/localhost_CA_cert.crt > /vault/certs/ca.pem
  echo "" >> /vault/certs/ca.pem
  cat /tmp/localhost_data.json|jq -r .data.issuing_ca >> /vault/certs/ca.pem
  vault token revoke $(cat /tmp/vault.init | grep '^Initial' | awk '{print $4}')
  vault operator step-down
  killall vault
fi
cp /vault/certs/localhost_CA_cert.crt /usr/local/share/ca-certificates/
cp /vault/certs/intermediate.cert.pem /usr/local/share/ca-certificates/
update-ca-certificates

if [ -f /tmp/vault.init ]; then
    echo "---- BEGIN NOTICE -----"
    echo "Make sure you store this unseal key to safe place, you will need this to unseal vault:"
    echo "unseal key: $(cat /tmp/vault.init | grep '^Unseal' | awk '{print $4}')"
    if [ ${GENPASS} == 1 ]; then
        echo "Generated default password for ${USER}: ${PASS}, store this to safe place, you will only see this once"
    fi
    echo "NOTE: These details will only be revealed to you during this first run."
    echo "---- END NOTICE -----"
    echo ""
    rm -f /tmp/vault.init
    rm -f /vault/user_template.json
    rm -f /tmp/localhost_data.json
    sleep 10
fi

ssh-agent > /tmp/ssh-agent
exec vault server -config=/vault/config/server.hcl
