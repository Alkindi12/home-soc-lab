#!/bin/bash
# Normal activity baseline: legitimate users of the lab, at human pace.
#   docker compose --profile normal run --rm normal-user /normal/normal-activity.sh
# Runs for $DURATION seconds (default 600). Every action is logged with a
# UTC timestamp to /output/normal-activity.log, so each alert it causes can
# be traced back to a known, legitimate action.
set -uo pipefail

DURATION="${DURATION:-600}"
LOG=/output/normal-activity.log
mkdir -p /output
trap 'chown -R "${HOST_UID:-1000}:${HOST_GID:-1000}" /output 2>/dev/null || true' EXIT

UA="Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
WEB=http://victim-web
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR)

log() { printf '%s  %-8s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" | tee -a "$LOG"; }
pause() { sleep $(( $1 + RANDOM % ($2 - $1 + 1) )); }   # human-ish think time
get() { curl -s -o /dev/null -w '%{http_code}' -A "$UA" "$@"; }

# ------------------------------------------------------------------- web
shop_browse() {
  local term
  term=$(shuf -n1 -e apple banana juice "fruit press" lemon melon carrot)
  log web "browse home page, search '$term', open a product"
  get "$WEB/" >/dev/null
  for a in main.js styles.css polyfills.js runtime.js; do get "$WEB/$a" >/dev/null; done
  get "$WEB/rest/products/search?q=${term// /%20}" >/dev/null
  get "$WEB/api/Products/$(( 1 + RANDOM % 30 ))" >/dev/null
  get "$WEB/rest/products/$(( 1 + RANDOM % 30 ))/reviews" >/dev/null
}

SHOP_REGISTERED=0
shop_login() {
  local body code token
  if [ "$SHOP_REGISTERED" = 0 ]; then
    body=$(printf '{"email":"%s","password":"%s","passwordRepeat":"%s","securityQuestion":{"id":1},"securityAnswer":"lab"}' \
      "$SHOP_CUSTOMER_EMAIL" "$SHOP_CUSTOMER_PASSWORD" "$SHOP_CUSTOMER_PASSWORD")
    code=$(get -X POST -H 'Content-Type: application/json' -d "$body" "$WEB/api/Users")
    log web "register shop account $SHOP_CUSTOMER_EMAIL (HTTP $code; 400 = already exists)"
    SHOP_REGISTERED=1
  fi
  body=$(printf '{"email":"%s","password":"%s"}' "$SHOP_CUSTOMER_EMAIL" "$SHOP_CUSTOMER_PASSWORD")
  token=$(curl -s -A "$UA" -H 'Content-Type: application/json' -d "$body" "$WEB/rest/user/login" \
          | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  if [ -n "$token" ]; then
    get -H "Authorization: Bearer $token" "$WEB/rest/user/whoami" >/dev/null
    get -H "Authorization: Bearer $token" "$WEB/api/Cards" >/dev/null
    log web "customer login OK, view account and saved cards"
  else
    log web "customer login FAILED"
  fi
}

# ------------------------------------------------------------------- ssh
admin_ssh() {
  # 1 in 4 sessions starts with a mistyped password, like a real person.
  if (( RANDOM % 4 == 0 )); then
    sshpass -p "${ADMIN_SSH_PASSWORD}x" ssh "${SSH_OPTS[@]}" "$ADMIN_SSH_USER@victim-ssh" true 2>/dev/null
    log ssh "$ADMIN_SSH_USER mistyped the password once"
    pause 3 8
  fi
  sshpass -p "$ADMIN_SSH_PASSWORD" ssh "${SSH_OPTS[@]}" "$ADMIN_SSH_USER@victim-ssh" \
    "uptime >/dev/null; df -h / >/dev/null; free -m >/dev/null; ls ~ >/dev/null;
     echo '$ADMIN_SSH_PASSWORD' | sudo -S -p '' tail -n 20 /var/log/auth.log >/dev/null" \
    && log ssh "$ADMIN_SSH_USER logged in: uptime, df, free, sudo tail auth.log" \
    || log ssh "$ADMIN_SSH_USER login FAILED"
}

KEY_ADDED=0
admin_adds_key() {
  # A legitimate change that triggers the same rule as attack 6 (100260):
  # the admin installs the key of her new laptop, from her own session.
  local key=/tmp/alice_new_laptop
  rm -f "$key" "$key.pub"
  ssh-keygen -q -t ed25519 -N "" -C "${ADMIN_SSH_USER}@new-laptop" -f "$key"
  sshpass -p "$ADMIN_SSH_PASSWORD" ssh "${SSH_OPTS[@]}" "$ADMIN_SSH_USER@victim-ssh" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$(cat "$key.pub")' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" \
    && log ssh "$ADMIN_SSH_USER added her new laptop key to authorized_keys (legitimate change)"
  KEY_ADDED=1
}

# -------------------------------------------------------------------- db
app_db() {
  # 1 in 5 runs: an app instance starts with a stale password, then retries.
  if (( RANDOM % 5 == 0 )); then
    mariadb -h victim-db -u "$DB_USER" -p"${DB_PASSWORD}x" --skip-ssl -e 'SELECT 1' >/dev/null 2>&1
    log db "app connected with a stale password once"
  fi
  mariadb -h victim-db -u "$DB_USER" -p"$DB_PASSWORD" --skip-ssl shop -e "
    CREATE TABLE IF NOT EXISTS orders (id INT AUTO_INCREMENT PRIMARY KEY, item VARCHAR(40), qty INT, ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
    INSERT INTO orders (item, qty) VALUES ('apple juice', $(( 1 + RANDOM % 5 )));
    SELECT COUNT(*) FROM orders;" >/dev/null 2>&1 \
    && log db "app inserted an order and read the order count" \
    || log db "app query FAILED"
}

# ------------------------------------------------------------------ main
log start "normal activity for ${DURATION}s from $(hostname -i)"
end=$(( $(date +%s) + DURATION ))
half=$(( $(date +%s) + DURATION / 2 ))

while (( $(date +%s) < end )); do
  r=$(( RANDOM % 10 ))
  if   (( r < 5 )); then shop_browse
  elif (( r < 6 )); then shop_login
  elif (( r < 8 )); then admin_ssh
  else                   app_db
  fi
  if (( KEY_ADDED == 0 && $(date +%s) >= half )); then admin_adds_key; fi
  pause 8 25
done
log stop "normal activity finished"
