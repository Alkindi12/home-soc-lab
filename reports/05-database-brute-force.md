# Attack 5: Database brute force

| | |
|---|---|
| **MITRE ATT&CK** | [T1110.001 Brute Force: Password Guessing](https://attack.mitre.org/techniques/T1110/001/) |
| **Tool** | hydra 9.5 (mysql module), 4 threads, user `root`, 28 passwords |
| **Script** | [`attacks/05-db-bruteforce.sh`](../attacks/05-db-bruteforce.sh) |
| **Source → target** | `172.30.0.100` → victim-db:3306 (MariaDB 11.4.13) |
| **Duration** | about 1 s |
| **Headline detection** | Rule **100250**, level 12, **2 s** after start |

## What the attacker got

The MariaDB `root` password, a common word from the wordlist, in about a
second, then full database access:

```
information_schema, mysql, performance_schema, shop, sys
```

A database with no lockout and a weak root password falls in seconds:
far faster than SSH, because there is no per-attempt delay.

## Detection

**Before the custom rules:** 25 separate level-9 "MySQL: authentication
failure" alerts (stock 50106) and some Suricata ET SCAN alerts at level 3.
Nothing tied them together into "brute force".

That stock rule only works at all because of the Stage 2 decoder
[`wazuh/decoders/mariadb_decoders.xml`](../wazuh/decoders/mariadb_decoders.xml):
MariaDB 11's error-log format was otherwise silently dropped.

**After (final run):** 37 alerts.

| Count | Rule | Level | What |
|------:|------|------:|------|
| 1 | **100250** | **12** | Database brute force: 8+ failed MariaDB logins from 172.30.0.100 in 60s (last user: root) |
| 25 | 50106 | 9 | Per attempt: MySQL authentication failure (with `srcuser`, `srcip`); since the fix, 100251/100252 |
| 10 | 100102 | 7 | Suricata severity 2: ET SCAN multiple MySQL login failures; suspicious inbound to 3306 |
| 1 | 86601 | 3 | Suricata: ET SCAN MySQL 4.1 brute-force root login attempt |

## Custom rule

Rule 100250: `if_matched_group mariadb_auth_failure` (originally
`if_matched_sid 50106`, see the bug below), `frequency 8`, `timeframe 60`,
`same_source_ip`, `ignore 120` → one level-12 alert per burst, T1110.001.
It uses the `srcip` and `srcuser` fields the Stage 2 decoder extracts.

## Bug found later: detection stopped at 10:00 every day

The Stage 2 decoder matched MariaDB's timestamp only while the hour was a
single digit (`2026-11-25  7:51:16`, space-padded). From 10:00 the line
reads `2026-11-25 11:57:35 ...`, which **also** matches Wazuh's stock
`windows-date-format` decoder, which is tried first. Every failed login
after 10:00 was decoded as an unknown Windows-style line and raised
nothing. The run above happened at 09:31, so it passed; the
[normal-vs-attack exercise](normal-vs-attack.md) at 11:57 exposed it.

Fix ([decoders](../wazuh/decoders/mariadb_decoders.xml), [rules](../wazuh/rules/home_soc_lab_rules.xml)):

| Hours | Decoder | Rule per failure |
|-------|---------|------------------|
| 00:00–09:59 | `mysql_log` (sibling of the stock decoder) | stock 50106 → **100252** |
| 10:00–23:59 | `mariadb-access-denied-2digit-hour` (child of `windows-date-format`) | **100251** |

Both per-failure rules carry the group `mariadb_auth_failure`, and the
brute-force rule 100250 now counts that group instead of rule 50106.
Re-run after the fix: **100250 (level 12)** plus 25 × 100251 (level 9), each
with `srcuser=root` and `srcip=172.30.0.100`.

## Detection gap: success is invisible

**MariaDB does not log successful logins** in its error log. Unlike SSH
(attack 4), there is no "failures followed by a success" signal: the
alerts say *someone tried*, never *someone got in*. Ways to close the gap:

- the MariaDB **audit plugin** (`server_audit`) logs every connection and
  query; ship that log and correlate failures followed by a successful
  `CONNECT` from the same IP;
- Suricata can see the MySQL handshake response, but only while the
  connection is unencrypted.

## False positives

- An **application deployed with a wrong password** fails on every
  connection-pool retry and trips 100250 within seconds. The `srcip` is
  then an app server and `srcuser` the app account: easy to spot, and
  worth fixing anyway.
- Monitoring probes using an expired password: same pattern, same fix.

## Analyst response

1. **Triage:** 100250 → `srcip` and `srcuser`. `root` from an unknown
   address is critical.
2. **Assume success:** with no success logging, check the DB directly:
   `SHOW PROCESSLIST`, recent grants, new users, unexpected dumps.
3. **Contain:** rotate the root password; firewall 3306 so only the
   application hosts can reach it. A database port should never be
   reachable from where an attacker sits.
4. **Prevent:** strong unique passwords, no remote `root`
   (`root@localhost` only), an account lockout plugin, the audit plugin.

## Reproduce

```bash
docker compose --profile attack run --rm attacker /attacks/05-db-bruteforce.sh
```
Dashboard query: `rule.id:(100250 or 100251 or 100252)`
