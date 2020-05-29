FROM centos:8

RUN dnf update -y && \
dnf install -y epel-release nano jq openssh-clients dos2unix wget && \
dnf install -y lastpass-cli

RUN mkdir /data
RUN echo 'source /tmp/ssh-agent' >> /root/.bashrc
COPY support_scripts /data/support_scripts
COPY key_vault.sh /data/key_vault.sh
COPY backends /data/backends
RUN /data/support_scripts/get_bitwarden.sh
RUN chmod +x /data/key_vault.sh && \
chmod +x /data/support_scripts/*

WORKDIR /data


ENTRYPOINT /data/support_scripts/entrypoint.sh
