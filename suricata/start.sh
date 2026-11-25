#!/bin/bash
# Suricata container start: refresh ET Open rules (at most once a day), then
# hand over to the image's own entrypoint, which drops root privileges.
set -euo pipefail

RULES=/var/lib/suricata/rules/suricata.rules

if [ ! -s "$RULES" ] || [ -n "$(find "$RULES" -mmin +1440 2>/dev/null)" ]; then
  echo "[suricata] Updating ET Open rules"
  if ! suricata-update --no-test; then
    if [ -s "$RULES" ]; then
      echo "[suricata] Rule update failed, keeping the existing rules" >&2
    else
      echo "[suricata] Rule update failed and no rules exist yet" >&2
      exit 1
    fi
  fi
else
  echo "[suricata] Rules are less than a day old, skipping update"
fi

# HOME_NET is the lab subnet MINUS the attacker, so the attacker counts as
# $EXTERNAL_NET. ET rules are directional ($EXTERNAL_NET -> $HOME_NET): with
# the attacker inside HOME_NET, almost no inbound-attack rule could match.
# -k none: container traffic often carries checksums the NIC would have
#           filled in (offload); do not discard those packets as invalid.
exec /docker-entrypoint.sh \
  --af-packet="${SURICATA_INTERFACE:?}" \
  -k none \
  --include /lab/lab.yaml \
  --set "vars.address-groups.HOME_NET=[${LAB_SUBNET:?},!${ATTACKER_IP:?}]"
