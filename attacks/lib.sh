#!/bin/bash
# Shared helpers for the attack scripts. Sourced, not run.
set -euo pipefail

LAB_SUBNET_PREFIX="${LAB_SUBNET_PREFIX:-172.30.0.}"
WORDLISTS=/attacks/wordlists
OUT=/output
mkdir -p "$OUT"
# Output is written as root inside the container; hand it back to the host
# user so it can be read and deleted without sudo.
trap 'chown -R "${HOST_UID:-1000}:${HOST_GID:-1000}" "$OUT" 2>/dev/null || true' EXIT

banner() {
  echo "=================================================================="
  echo " $1"
  echo " MITRE ATT&CK: $2"
  echo " Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)   attacker IP: $(hostname -i)"
  echo "=================================================================="
}

# Safety guard: refuse any target that does not resolve into the lab subnet.
require_lab_target() {
  local host="$1" ip
  ip=$(getent hosts "$host" | awk '{print $1; exit}')
  if [[ -z "$ip" || "$ip" != ${LAB_SUBNET_PREFIX}* ]]; then
    echo "[guard] Refusing target '$host' (resolves to '${ip:-nothing}'), not in ${LAB_SUBNET_PREFIX}0/24" >&2
    exit 1
  fi
  echo "[guard] Target $host = $ip (lab network)"
}

done_msg() {
  echo "[done] Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
