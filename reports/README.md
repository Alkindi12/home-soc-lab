# Attack reports

Six attacks run from the `attacker` container against the lab, each with
the alerts it produced, the custom detection built for it, false positives
and an analyst response. Figures come from the final full run on
2026-11-25 (`attacks/run-all.sh`).

| # | Attack | MITRE ATT&CK | Headline rule | Level | Time to detect |
|---|--------|--------------|---------------|------:|---------------:|
| 1 | [Port scan](01-port-scan.md) | T1046 | 100210 | 10 | 2 s |
| 2 | [Web content discovery](02-web-content-discovery.md) | T1595.003 | 100222 | 10 | 1 s |
| 3 | [SQL injection](03-sql-injection.md) | T1190 | 100230 / 100231 / 100233 | 10 / 12 / 12 | 1–5 s |
| 4 | [SSH brute force → login](04-ssh-brute-force.md) | T1110.001 → T1078 | 5763, then 100240 at login | 10 → 13 | 9 s / at login |
| 5 | [Database brute force](05-database-brute-force.md) | T1110.001 | 100250 | 12 | 2 s |
| 6 | [Persistence and privilege escalation](06-persistence-privesc.md) | T1098.004, T1548.003, T1003.008 | 100260 + 100261 | 12 | 1–2 s |

Before the custom rules, attacks 1 and 2 had **no** detection of the
activity itself, attack 5 had no correlation, attack 6 produced only
level 3–5 alerts, and every Suricata alert was level 3.

## Normal activity vs attack

[normal-vs-attack.md](normal-vs-attack.md): 10 minutes of legitimate use as
a baseline, then the attacks with normal traffic still running. What normal
looks like in the SIEM, how the attack stands out, a legitimate action that
fires the same rule as an attack, and a triage walk-through with dashboard
screenshots.

## Attack chain

```
 1 scan ──▶ 2 web discovery ──▶ 3 SQL injection        (web application)
   │
   ├──▶ 5 DB brute force ──▶ root on MariaDB            (database)
   │
   └──▶ 4 SSH brute force ──▶ login as labuser ──▶ 6 SSH key + sudo + /etc/shadow
```
