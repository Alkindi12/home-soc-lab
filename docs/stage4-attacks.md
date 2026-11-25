# Stage 4: Attacks, custom rules and MITRE ATT&CK mapping

An attacker container runs six attacks against the victims. Each attack has
custom Wazuh (and where useful Suricata) detections mapped to MITRE ATT&CK,
and a report in [`reports/`](../reports/README.md).

## The attacker

| | |
|---|---|
| Image | `attacker/Dockerfile`: Debian 13 with nmap, hydra, sqlmap, gobuster, mariadb-client, sshpass, all from Debian's own repository |
| Network | `lab` only, fixed address `ATTACKER_IP` (172.30.0.100): no internet, no host ports |
| Started | only on demand, through the Compose profile `attack`; `docker compose up` never starts it |
| Scripts | `attacks/0N-*.sh`, mounted read-only; output in `attacks/output/` (gitignored) |
| Wordlists | `attacks/wordlists/`: 11 users, 28 passwords, 54 web paths. Small on purpose |
| Safety | every script calls `require_lab_target`, which refuses any target that does not resolve into the lab subnet |

```bash
docker compose --profile attack build attacker
docker compose --profile attack run --rm attacker /attacks/run-all.sh   # all six, ~10 min
docker compose --profile attack run --rm attacker /attacks/03-sql-injection.sh   # one
```

`run-all.sh` pauses 45 s between attacks so each one's alerts sit in their
own time window, and writes `attacks/output/timeline.txt`.

## Detection content

| File | What |
|------|------|
| [`wazuh/rules/home_soc_lab_rules.xml`](../wazuh/rules/home_soc_lab_rules.xml) | All custom Wazuh rules (100000–100999) |
| [`suricata/rules/local.rules`](../suricata/rules/local.rules) | Port-scan rule SID 9000010 (plus the Stage 3 self-test) |
| `victims/ssh/agent-localfiles.xml` | Real-time FIM on `/home` |

| Rule | Level | MITRE | Purpose |
|------|------:|-------|---------|
| 19007 / 19008 / 19009 (overwrite) | 3 / 0 / 0 | — | SCA check results: noise tuning |
| 100101 / 100102 | 10 / 7 | — | Suricata severity 1 / 2 → Wazuh level (stock: always 3) |
| 100210 | 10 | T1046 | Port scan (Suricata 9000010) |
| 100220 / 100222 / 100221 | 5 / 10 / 10 | T1595.003 | Scanner user agent per request / per scan / request-rate backstop |
| 100230 / 100232 / 100233 | 10 / 6 / 12 | T1190 | sqlmap fingerprint / SQLi signature per request / SQLi campaign (network) |
| 100231 | 12 | T1190 | SQLi campaign (web log), corrects stock 31152's T1055 mapping |
| 100240 | 13 | T1110.001, T1078 | SSH brute force followed by a successful login |
| 100250 | 12 | T1110.001 | MariaDB brute force |
| 100260 | 12 | T1098.004 | `authorized_keys` created or changed |
| 100261 | 12 | T1548.003, T1003.008 | sudo used to read a credential file |

## Noise reduction

| | Before | After |
|---|---|---|
| SCA check alerts | 3,576 in the first two hours, 1,362 of them level 7 | failed checks at level 3; passed / not-applicable not indexed |
| Suricata | every alert level 3 | severity 1 → 10, 2 → 7, 3 → 3 |
| sqlmap run (35 s) | 1,379 level-10 Suricata alerts | 1,372 at level 6 plus **one** level-12 campaign alert |
| gobuster run | 56 level-8 alerts | 55 at level 5 plus **one** level-10 alert |

The Configuration Assessment dashboard reads SCA results from the manager's
database, not from alerts, so it still shows every check.

## Problems found and fixed in this stage

Every one of these made a detection silently fail. Most were found only by
running the real attack and checking the alerts.

| Problem | Effect | Fix |
|---------|--------|-----|
| Attacker inside Suricata's `HOME_NET` | ET inbound rules (`$EXTERNAL_NET -> $HOME_NET`) could not match: sqlmap produced **zero** Suricata alerts | `HOME_NET=[LAB_SUBNET,!ATTACKER_IP]` in `suricata/start.sh` |
| Rebuilt victim refused: "Duplicate agent name" | victim-ssh sent **nothing** for minutes while looking Active | `<force><disconnected_time enabled="no">` in the manager config (Stage 2 bug) |
| `docker compose restart wazuh.manager` does not apply config | edited rules and `ossec.conf` silently ignored | always `docker compose up -d --force-recreate wazuh.manager` (see Stage 1 docs) |
| Wazuh tries **sibling rules highest level first** | a level-6 "SQLi per request" rule never beat the level-10 "severity 1" rule | specific Suricata rules are children of the severity rules |
| Web rules under `if_sid 31100` | never evaluated: requests land on stock children of 31100 first | `if_group` / `if_matched_group accesslog` |
| FIM rule with `<field name="file">` or `syscheck.path` | never matched | `<match>/.ssh/authorized_keys</match>` |
| OpenSSH 10 `PerSourcePenalties` | hydra blocked after ~30 attempts | disabled on the victim (documented as the real mitigation) |
| sqlmap "not injectable" | attack 3 failed at default settings | prefix `'))`, empty base value, `--string` |
| Juice Shop answers 200 for unknown paths | gobuster "found" everything; stock 4xx scan rule never fires | exclude the fallback page length; user-agent rules |

## Known limitations

- **Signatures are evadable.** Rules 100220/100222 (scanner user agent) and
  100230 (sqlmap fingerprint) fall to a changed user agent. The rate and
  campaign rules (100221, 100231, 100233) do not depend on it.
- **MariaDB success is invisible** without the audit plugin (report 05).
- **Stock per-request noise remains:** about 430 × 5710 per SSH brute force,
  about 1,350 × 31106 per sqlmap run. Both are level 5–6, below "medium". The
  correlation rules carry the signal.
- **Slow attacks** (nmap `-T1`, hydra at one try per minute) stay under the
  frequency thresholds.
- The manager API (55000) and enrollment service (1515) are reachable from
  the lab network, including the attacker (Stage 2 docs). The attacks never
  target them.
