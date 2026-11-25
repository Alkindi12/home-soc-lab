#!/bin/bash
# Attack 1: TCP SYN scan with service detection against every lab target.
source /attacks/lib.sh
banner "Attack 1: Network service discovery (nmap)" "T1046 Network Service Discovery"

TARGETS=(victim-ssh victim-web victim-db juice-shop)
for t in "${TARGETS[@]}"; do require_lab_target "$t"; done

nmap -sS -sV -T4 --top-ports 1000 -oN "$OUT/01-nmap.txt" "${TARGETS[@]}"
done_msg
