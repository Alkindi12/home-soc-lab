#!/bin/sh
set -eu

: "${VICTIM_SSH_USER:?}" "${VICTIM_SSH_PASSWORD:?}"

# Lab user with the deliberately weak password from .env, plus sudo rights
# so post-compromise privilege escalation can be shown in Stage 4.
if ! id "$VICTIM_SSH_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$VICTIM_SSH_USER"
  usermod -aG sudo "$VICTIM_SSH_USER"
fi
echo "${VICTIM_SSH_USER}:${VICTIM_SSH_PASSWORD}" | chpasswd

[ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A

rsyslogd
start-wazuh-agent

exec /usr/sbin/sshd -D
