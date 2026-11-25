#!/usr/bin/env bash
# Checks that the host can run the lab. Read-only: changes nothing.
set -u

fail=0
ok()   { printf '  [OK]   %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=1; }

echo "Home SOC Lab preflight"

ram_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if   [ "$ram_mb" -ge 7500 ]; then ok "RAM ${ram_mb} MB"
elif [ "$ram_mb" -ge 6000 ]; then warn "RAM ${ram_mb} MB (8 GB recommended)"
else bad "RAM ${ram_mb} MB (8 GB recommended)"; fi

cpus=$(nproc)
if [ "$cpus" -ge 4 ]; then ok "CPUs ${cpus}"; else warn "CPUs ${cpus} (4 recommended)"; fi

disk_gb=$(df -BG --output=avail "$(dirname "$0")" | tail -1 | tr -dc '0-9')
if [ "$disk_gb" -ge 40 ]; then ok "Free disk ${disk_gb} GB"; else bad "Free disk ${disk_gb} GB (40 GB+ needed)"; fi

# Wazuh indexer (OpenSearch) needs at least 262144 memory map areas
mmc=$(sysctl -n vm.max_map_count)
if [ "$mmc" -ge 262144 ]; then ok "vm.max_map_count ${mmc}"
else bad "vm.max_map_count ${mmc} (need >= 262144; see README)"; fi

if command -v docker >/dev/null 2>&1; then
  ok "$(docker --version)"
  if docker info >/dev/null 2>&1; then ok "Docker daemon reachable without sudo"
  else bad "Docker daemon not reachable (is it running, are you in the docker group?)"; fi
  if docker compose version >/dev/null 2>&1; then ok "$(docker compose version)"
  else bad "Docker Compose v2 plugin missing"; fi
else
  bad "Docker not installed"
fi

exit $fail
