#!/bin/sh
set -eu

start-wazuh-agent

# The agent daemons run in the background; keep the container alive and
# stop cleanly on "docker compose stop".
trap '/var/ossec/bin/wazuh-control stop; exit 0' TERM INT
while :; do sleep 3600 & wait $!; done
