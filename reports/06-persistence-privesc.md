# Attack 6: Persistence and privilege escalation after the SSH compromise

| | |
|---|---|
| **MITRE ATT&CK** | [T1098.004 Account Manipulation: SSH Authorized Keys](https://attack.mitre.org/techniques/T1098/004/), [T1548.003 Abuse Elevation Control: Sudo](https://attack.mitre.org/techniques/T1548/003/), [T1003.008 OS Credential Dumping: /etc/passwd and /etc/shadow](https://attack.mitre.org/techniques/T1003/008/) |
| **Tools** | ssh, sudo (the attacker's own tooling: nothing installed on the victim) |
| **Script** | [`attacks/06-persistence-privesc.sh`](../attacks/06-persistence-privesc.sh), uses the password found in attack 4 |
| **Source → target** | `172.30.0.100` → victim-ssh as `labuser` |
| **Duration** | about 1 s |
| **Headline detection** | Rule **100260** (planted key), level 12, **1 s** after start; rule **100261** (`/etc/shadow` via sudo), level 12, **2 s** |

## What the attacker did

Logged in with the stolen password and, in one session:

1. Appended its own public key to `~/.ssh/authorized_keys`: access that
   **survives a password reset**.
2. `sudo id` → `uid=0(root)`, using the same stolen password.
3. `sudo cat /etc/shadow`: the password hashes of every local account,
   for offline cracking.
4. Logged in again **with the planted key and no password** to prove the
   backdoor works.

## Detection

**Before the custom rules:** a generic "File added to the system" (stock
554, level 5) and "Successful sudo to ROOT executed" (stock 5402, level 3).
Both are routine-looking and easy to miss among hundreds of alerts.

**After (re-run of this attack):**

| Count | Rule | Level | What |
|------:|------|------:|------|
| 1 | **100260** | **12** | SSH authorized_keys created or changed in a user home directory |
| 1 | **100261** | **12** | labuser used sudo to access a credential file: `/usr/bin/cat /etc/shadow` |
| 1 | 5402 | 3 | Stock: successful sudo to root |
| 4 + 4 + 4 | 5715, 5501, 5502 | 3 | Logins and sessions (including the key-based one) |

In the full run, attack 6 followed attack 4 within four minutes and also
triggered **100240** (brute force succeeded) again, because the password
login came shortly after the failures. That is correct: it was the attacker
logging in again.

The FIM alert includes the **content that was added** (`syscheck.diff`),
so the analyst sees the attacker's key itself:

```
> ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... attacker@lab
```

## Custom rules and how they were built

| Rule | Level | Logic |
|------|------:|-------|
| 100260 | 12 | FIM event (550 modified / 554 added) on `/.ssh/authorized_keys` |
| 100261 | 12 | Successful sudo (5402/5403) whose `command` touches `/etc/shadow`, `/etc/gshadow` or `/etc/sudoers` |

- **FIM in real time.** victim-ssh's agent watches `/home` with
  `realtime="yes" report_changes="yes"` (`victims/ssh/agent-localfiles.xml`),
  so the change is reported within a second instead of at the next 12-hour
  scan.
- **Matching FIM events took three attempts.** `<field name="file">` and
  `<field name="syscheck.path">` both silently matched nothing in Wazuh
  4.14. Matching the event text (`<match>/.ssh/authorized_keys</match>`)
  works. For the same reason the description is static: `$(syscheck.path)`
  does not expand there. The path is still in the alert's `syscheck.path`
  field.

## False positives

- **Users adding their own keys** is normal on a developer box. 100260 at
  level 12 suits servers where keys are managed centrally (config
  management, an IdP); on a shared dev host, lower it or alert only when the
  change does not come from the user's own interactive session.
- **Config management** (Ansible, Puppet) rewriting `authorized_keys`
  triggers it on every run: suppress by schedule, or by agent group.
- **Admins reading `/etc/shadow` with sudo** happens (account debugging),
  but rarely. Each one deserves a question: it is exactly what an attacker
  does.

## Analyst response

1. **Correlate:** 100260/100261 on victim-ssh, minutes after **100240** (SSH
   brute force succeeded) for the same user: one intrusion, not three
   alerts.
2. **Contain:** isolate the host; lock `labuser`; kill its sessions.
3. **Eradicate:** remove the planted key (the `syscheck.diff` shows exactly
   which); review sudoers, cron, systemd units and other users' keys for
   more persistence.
4. **Assume the hashes are cracked:** `/etc/shadow` was read, so rotate the
   password of **every** account on the host, and anywhere those passwords
   were reused.
5. **Prevent:** password-protected `sudo` alone did not help here (the
   attacker had the password); require MFA for sudo, restrict who may use
   it, manage `authorized_keys` centrally (`AuthorizedKeysFile` outside the
   home directory).

## Reproduce

```bash
docker compose --profile attack run --rm attacker /attacks/04-ssh-bruteforce.sh   # finds the password
docker compose --profile attack run --rm attacker /attacks/06-persistence-privesc.sh
```
Dashboard query: `rule.id:(100260 or 100261)`
