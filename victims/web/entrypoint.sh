#!/bin/sh
set -eu

start-wazuh-agent

exec nginx -g 'daemon off;'
