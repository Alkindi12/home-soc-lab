#!/bin/bash
# Attack 2: Content discovery on the web server with a wordlist.
source /attacks/lib.sh
banner "Attack 2: Web content discovery (gobuster)" "T1595.003 Active Scanning: Wordlist Scanning"

require_lab_target victim-web

# Juice Shop answers unknown paths with its single-page app (HTTP 200), so
# a plain status-code check would call everything "found". Excluding the
# length of that fallback page leaves only real content.
fallback_len=$(curl -s http://victim-web/no-such-page-$RANDOM | wc -c)
echo "[info] Fallback page length: $fallback_len bytes (excluded)"

gobuster dir \
  -u http://victim-web/ \
  -w "$WORDLISTS/web-paths.txt" \
  -t 10 \
  --exclude-length "$fallback_len" \
  --no-error \
  -o "$OUT/02-gobuster.txt"
done_msg
