### NOTE: This file is intended to be used with docker-compose-example.yml, contexts will be wrong if you try to run
### build with just docker and current directory.

FROM vault

RUN apk update && apk upgrade && \
  apk add bash nano jq openssh dos2unix wget unzip curl ca-certificates openssl aws-cli

ARG VAULT_ADDR=http://127.0.0.1:8200

RUN mkdir -p {/data,/root/.key_vault}
RUN echo 'source /tmp/ssh-agent' >> /root/.bashrc
RUN echo 'export PATH=${PATH}:/data' >> /root/.bashrc
RUN adduser keyvault -H -D -h /data

COPY support_scripts /data/support_scripts
COPY key_vault.sh /data/key_vault.sh
COPY vssh /data/vssh
COPY backends /data/backends
COPY vault_demo/configuration/server.hcl /vault/server.hcl 
COPY vault_demo/configuration/admin_policy.hcl /vault/admin_policy.hcl
COPY vault_demo/configuration/user_template.json /vault/user_template.json
COPY vault_demo/configuration/server-ssl.hcl /vault/config/server.hcl
COPY vault_demo/init.sh /vault/init.sh
COPY vault_demo/example_config /root/.key_vault/configuration

RUN /data/support_scripts/get_bitwarden.sh
RUN chmod +x /data/key_vault.sh && \
  chmod +x /data/support_scripts/* && \
  chmod +x /vault/init.sh

WORKDIR /data

ENTRYPOINT /vault/init.sh
