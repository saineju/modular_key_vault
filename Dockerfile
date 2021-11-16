FROM alpine:latest

RUN apk update && apk upgrade && \
  apk add bash nano jq openssh dos2unix wget unzip curl

RUN mkdir /data
RUN echo 'source /tmp/ssh-agent' >> /root/.bashrc
RUN echo 'export PATH=${PATH}:/data' >> /root/.bashrc
COPY support_scripts /data/support_scripts
COPY key_vault.sh /data/key_vault.sh
COPY vssh /data/vssh
COPY backends /data/backends
RUN /data/support_scripts/get_bitwarden.sh
RUN chmod +x /data/key_vault.sh && \
chmod +x /data/support_scripts/*

WORKDIR /data

ENTRYPOINT /data/support_scripts/entrypoint.sh
