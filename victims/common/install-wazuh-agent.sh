#!/bin/sh
# Build-time: install a pinned Wazuh agent from the official Wazuh apt repo.
# Usage: install-wazuh-agent.sh <version>   e.g. 4.14.10
set -eu

VERSION="${1:?agent version required}"
# Official Wazuh package signing key (https://packages.wazuh.com/key/GPG-KEY-WAZUH)
EXPECTED_FPR=0DCFCA5547B19D2A6099506096B3EE5F29111145

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH -o /tmp/wazuh.key
fpr=$(gpg --show-keys --with-colons /tmp/wazuh.key | awk -F: '/^fpr/ {print $10; exit}')
if [ "$fpr" != "$EXPECTED_FPR" ]; then
  echo "Wazuh signing key fingerprint mismatch: got $fpr" >&2
  exit 1
fi
gpg --dearmor < /tmp/wazuh.key > /usr/share/keyrings/wazuh.gpg
chmod 644 /usr/share/keyrings/wazuh.gpg
rm /tmp/wazuh.key

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  > /etc/apt/sources.list.d/wazuh.list
apt-get update
# WAZUH_MANAGER is read by the package's post-install script and written
# into ossec.conf. The enrollment password is NOT baked into the image;
# it is copied in at container start from a Docker secret.
WAZUH_MANAGER=wazuh.manager apt-get install -y --no-install-recommends "wazuh-agent=${VERSION}-1"

# Keep the agent at the pinned version: drop the repo after install.
rm /etc/apt/sources.list.d/wazuh.list
apt-get purge -y --auto-remove gnupg
rm -rf /var/lib/apt/lists/*
