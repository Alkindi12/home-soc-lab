# Attack 3: SQL injection against Juice Shop

| | |
|---|---|
| **MITRE ATT&CK** | [T1190 Exploit Public-Facing Application](https://attack.mitre.org/techniques/T1190/) |
| **Tool** | sqlmap 1.9.6 |
| **Script** | [`attacks/03-sql-injection.sh`](../attacks/03-sql-injection.sh) |
| **Source → target** | `172.30.0.100` → `http://victim-web/rest/products/search?q=` |
| **Duration** | 35 s, about 1,400 requests |
| **Headline detection** | Rule **100230**, level 10, **1 s** after start; campaign rules **100231** and **100233**, level 12, at **5 s** |

## What the attacker got

The `q` parameter of the product search is injectable (SQLite):
**boolean-based blind** and **UNION query (10 columns)**. sqlmap listed all
**23 tables**, among them `Users`, `Cards`, `Wallets`, `SecurityAnswers` and
`Addresses`. The script stops at `--tables`. One more option (`--dump -T Users`)
would have exfiltrated every account and password hash.

**Getting sqlmap to work.** The app builds
`...WHERE ((name LIKE '%<q>%' OR ...) ...`. At default settings sqlmap
reported "not injectable". Three settings were needed:

- `--prefix="'))" --suffix="--"` to close the expression;
- an **empty** base value: with `q=apple`, closing the LIKE leaves
  "ends with apple", which matches nothing, so TRUE and FALSE pages look
  the same;
- `--string="Apple Juice"` to tell sqlmap what a TRUE page contains.

## Detection

**Before the custom rules:**

- Wazuh's stock web rules caught it, and correlation rule 31152 (level 10)
  fired. But 31152 is mapped to **T1055 Process Injection**, which is wrong
  for a web attack.
- **Suricata stayed silent.** The attacker was inside `HOME_NET` (see
  [report 01](01-port-scan.md)). After that fix, the ET signature *"Possible
  SQL Injection SELECT CAST in HTTP URI"* fired **1,379 times at level 10**
  in 35 seconds: a flood of high alerts for one event.

**After (final run):** 2,799 alerts, of which **7 are level 12+**.

| Count | Rule | Level | What |
|------:|------|------:|------|
| 6 | **100231** | **12** | SQL injection campaign from 172.30.0.100 (web logs; re-tags stock 31152 as T1190) |
| 1 | **100233** | **12** | Network IDS: SQL injection campaign from 172.30.0.100 (20+ injection requests in 60s) |
| 2 | **100230** | 10 | sqlmap SQL injection tool used by 172.30.0.100 (ET 2008538 on the wire) |
| 1 | 100221 | 10 | Web scan: more than 50 requests in 10 s from 172.30.0.100 |
| 1 | 100101 | 10 | Suricata severity 1: SQL Server version probe |
| 49 | 31103 | 7 | Stock: SQL injection attempt |
| 1,372 | 100232 | 6 | Per request: Suricata SQL injection signature |
| 1,354 | 31106 | 6 | Stock: "A web attack returned code 200" |
| 13 | 31164 | 6 | Stock: SQL injection attempt |

Two independent sources, the **web server log** (100231) and the **network
IDS** (100233), raised the same conclusion within the same second.

## Custom rules

| Rule | Level | Logic |
|------|------:|-------|
| 100230 | 10 | Suricata SID 2008538 (sqlmap fingerprint), T1190 |
| 100232 | 6 | Any Suricata alert whose signature names SQL injection, per request, T1190 |
| **100233** | **12** | 20 × 100232 from the same `src_ip` in 60 s (`same_field src_ip`) |
| **100231** | **12** | Child of stock 31152 (8+ SQLi attempts from one IP): correct MITRE (T1190), higher level |

**Rule-ordering pitfall.** 100232 (level 6) first sat next to the generic
"Suricata severity 1 → level 10" rule (100101) as a sibling. Wazuh tries
**sibling rules highest level first**, not in file order, so 100101 always
won and the flood stayed at level 10. The specific Suricata rules are now
*children* of the severity rules (`if_sid 86601,100101,100102`), evaluated
after them, so they can lower or raise the level.

## Known noise

1,354 × stock rule 31106 ("web attack returned 200") at level 6 remain. It is
per request and below "medium", and the two campaign rules carry the signal.
Lowering 31106 globally would hide single, targeted injections, which matter
more than noisy scans.

## False positives

- **Search boxes legitimately receive quotes and SQL words** ("rock 'n' roll",
  "select"). A single 31103/100232 is weak evidence; the campaign rules need
  8 or 20 hits from one source.
- **Security testing** (DAST in CI, a pentest): expected; suppress by source
  address for the agreed window.
- The sqlmap fingerprint (100230) relies on the default user agent;
  `--random-agent` removes it. The campaign rules do not depend on it.

## Analyst response

1. **Triage:** 100231/100233 → source IP and target URL. Treat 200 responses
   to injection payloads (31106) as **possible successful exploitation**,
   not just an attempt.
2. **Assess impact:** UNION injection was confirmed, so assume the attacker
   could read **any table**: user accounts, password hashes, payment cards.
   Check the application and database logs for unusually large responses
   from that source.
3. **Contain:** block the source at the proxy or WAF and take the vulnerable
   endpoint offline or put a virtual patch on it.
4. **Eradicate:** fix the code with **parameterised queries**. A WAF rule
   alone is a stopgap that tools like sqlmap's `--tamper` scripts can get
   around.
5. **Recover:** if user data may be exposed, rotate credentials and follow
   the breach notification process.

## Reproduce

```bash
docker compose --profile attack run --rm attacker /attacks/03-sql-injection.sh
```
Dashboard query: `rule.id:(100230 or 100231 or 100233)`
