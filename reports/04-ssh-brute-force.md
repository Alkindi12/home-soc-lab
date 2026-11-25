# Attack 4: SSH brute force, then login with the stolen password

| | |
|---|---|
| **MITRE ATT&CK** | [T1110.001 Brute Force: Password Guessing](https://attack.mitre.org/techniques/T1110/001/) → [T1078 Valid Accounts](https://attack.mitre.org/techniques/T1078/) |
| **Tool** | hydra 9.5, 4 threads; 11 usernames × 28 passwords ([`attacks/wordlists/`](../attacks/wordlists/)) |
| **Script** | [`attacks/04-ssh-bruteforce.sh`](../attacks/04-ssh-bruteforce.sh) |
| **Source → target** | `172.30.0.100` → victim-ssh:22 (OpenSSH 10.0) |
| **Duration** | 260 s, about 300 attempts |
| **Headline detection** | Brute force: stock **5763**, level 10, **9 s** after start. Success: custom **100240**, level **13**, at the moment of login |

## What the attacker got

The password of `labuser`, a common word from the attack wordlist
(`setup.sh` picks one at random, so it is not written in the repository).
Then a shell:

```
uid=1000(labuser) gid=1000(labuser) groups=1000(labuser),27(sudo)
```

`labuser` is in the `sudo` group, which [attack 6](06-persistence-privesc.md)
uses.

## Detection

Wazuh's stock SSH rules are good here. The problem is volume: **769 alerts**
for one attack.

| Count | Rule | Level | What |
|------:|------|------:|------|
| 2 | **100240** | **13** | SSH brute force succeeded: 172.30.0.100 logged in as labuser after repeated failures |
| 2 | 5763 | 10 | sshd: brute force (failed passwords), first at +9 s |
| 4 | 5712 | 10 | sshd: brute force (non-existent users), first at +29 s |
| 8 | 100101 | 10 | Suricata severity 1: ET SCAN LibSSH-based frequent SSH connections |
| 52 + 11 + 2 | 2502, 5551, 40111 | 10 | Generic syslog/PAM repeated-failure correlations |
| 44 | 5758 | 8 | Maximum authentication attempts exceeded |
| 428 | 5710 | 5 | Login attempt with a non-existent user |
| ~210 | 5503, 5557, 5760, 2501 | 5 | Individual PAM / sshd failures |

**Custom rule 100240** (level 13, T1110.001 + T1078) is a child of stock rule
40112 ("multiple authentication failures followed by a success",
level 12), limited to `sshd`. It matters because it is the one alert that
says *the attack worked*. Everything else says *someone is trying*. In a
queue of 769 alerts, it is the one to pick up first.

## Lab adjustments and pitfalls

- **OpenSSH `PerSourcePenalties`.** OpenSSH 9.8+ penalises an address after
  failed logins by refusing its connections for a while. Against the
  default config, hydra died after about 30 attempts with "all children
  were disabled due too many connection errors". That is a **real,
  effective mitigation**. The lab turns it off
  (`victims/ssh/sshd_config.d/lab.conf`) so the detection can be shown.
- **The agent had stopped sending.** In the first run *no* SSH alert
  appeared. A rebuilt victim container could not re-enroll ("Duplicate
  agent name") because its old entry still looked Active, and it silently
  sent nothing. Fixed in the manager's `<force>` settings (see
  [Stage 2 docs](../docs/stage2-victims.md)). A SOC lesson as well: **an
  agent that shows Active is not proof that logs arrive.** The pipeline
  self-test exists for that.
- OpenSSH 10 logs through a new process name, `sshd-session`. Wazuh 4.14's
  sshd decoder already handles it (checked with `wazuh-logtest`).

## False positives

- **A user who forgot their password** fails 3–5 times and then succeeds.
  40112/100240 need repeated failures *from one source* followed by success,
  so one person mistyping usually stays below them, but a script with a
  stale password that keeps retrying can trigger 5763.
- **Shared NAT or bastion addresses:** many users behind one IP add up.
  Correlate with the username before acting.
- 100240 on an account that is *supposed* to log in from that address is
  still worth a look: the failures before it are the suspicious part.

## Analyst response

1. **Treat 100240 as an incident, not an alert:** valid credentials are in
   attacker hands.
2. **Contain:** lock the account (`usermod -L labuser`) and kill its
   sessions; block the source address.
3. **Scope:** what did the session do? Pivot on the agent and the time after
   the login: sudo use, file changes, new keys. Here that leads straight to
   [attack 6](06-persistence-privesc.md).
4. **Eradicate:** reset the password, then audit `~/.ssh/authorized_keys`
   and remove keys the user did not add: a password reset alone does not
   remove persistence.
5. **Prevent:** key-only SSH (`PasswordAuthentication no`), keep
   `PerSourcePenalties` on (or fail2ban), MFA for sudo.

## Reproduce

```bash
docker compose --profile attack run --rm attacker /attacks/04-ssh-bruteforce.sh
```
Dashboard query: `rule.id:(100240 or 5763 or 5712)`
