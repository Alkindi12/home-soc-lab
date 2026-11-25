#!/bin/bash
# Runs attacks 1-6 in order with a pause between them, so each attack's
# alerts land in their own time window. Writes /output/timeline.txt.
#   docker compose --profile attack run --rm attacker /attacks/run-all.sh
source /attacks/lib.sh

PAUSE="${PAUSE:-45}"
TIMELINE="$OUT/timeline.txt"
: > "$TIMELINE"

for script in /attacks/0[1-6]-*.sh; do
  name=$(basename "$script" .sh)
  start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  status=ok
  bash "$script" > "$OUT/$name.log" 2>&1 || status="exit $?"
  end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s  %s  %s  %s\n' "$name" "$start" "$end" "$status" | tee -a "$TIMELINE"
  sleep "$PAUSE"
done
echo "[done] Timeline in $TIMELINE"
