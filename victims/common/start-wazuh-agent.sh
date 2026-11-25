#!/bin/sh
# Run-time: give the agent its enrollment password, then start it.
# The password comes from the Docker secret "wazuh_enrollment".
set -eu

SECRET=/run/secrets/wazuh_enrollment
if [ ! -s "$SECRET" ]; then
  echo "[agent] missing $SECRET; run ./scripts/setup.sh on the host" >&2
  exit 1
fi
install -m 640 -o root -g wazuh "$SECRET" /var/ossec/etc/authd.pass

/var/ossec/bin/wazuh-control start
