#!/bin/sh
set -eu

start-wazuh-agent

# Hand over to the official MariaDB entrypoint (first-run init, then mariadbd).
exec docker-entrypoint.sh "$@"
