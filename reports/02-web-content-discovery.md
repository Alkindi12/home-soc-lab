# Attack 2: Web content discovery (directory brute force)

| | |
|---|---|
| **MITRE ATT&CK** | [T1595.003 Active Scanning: Wordlist Scanning](https://attack.mitre.org/techniques/T1595/003/) |
| **Tool** | gobuster 3.6, 10 threads, 54-word list ([`attacks/wordlists/web-paths.txt`](../attacks/wordlists/web-paths.txt)) |
| **Script** | [`attacks/02-web-dir-bruteforce.sh`](../attacks/02-web-dir-bruteforce.sh) |
| **Source → target** | `172.30.0.100` → victim-web (nginx in front of Juice Shop) |
| **Duration** | 1 s |
| **Headline detection** | Rule **100222**, level 10, **1 s** after start |

## What the attacker got

Eleven real paths. Several are interesting for the next steps:

| Path | Status | Why it matters |
|------|-------:|----------------|
| `/ftp` | 200 | Directory listing with downloadable files |
| `/metrics` | 200 | Prometheus metrics: internal app details |
| `/api-docs` | 301 | API documentation |
| `/rest`, `/api` | 500 | API roots that leak stack traces on error |
| `/robots.txt`, `/promotion`, `/video`, `/assets`, `/redirect`, `/profile` | various | Application content |

**Trick needed:** Juice Shop is a single-page app. It answers *every*
unknown path with its index page and **HTTP 200**, so a status-code check
calls everything "found". The script measures the fallback page (9,984
bytes) and excludes that length.

## Detection

**Before the custom rules:** 4 × rule 31122 (HTTP 500), 1 nginx warning and
2 low Suricata alerts. Nothing said "scan". The stock scan rule 31151 counts
**4xx** responses, and this server returns **200** for unknown paths, so it
never fired.

**After (final run):** 62 alerts.

| Count | Rule | Level | What |
|------:|------|------:|------|
| 1 | **100222** | **10** | Web content discovery: 172.30.0.100 sent 10+ requests with a scanner user agent in 60s |
| 3 | 100102 | 7 | Suricata: `phpinfo` access, `.htaccess` access, RDP-port probe |
| 55 | 100220 | 5 | Per request: web content discovery tool user agent |
| 3 | 86601 | 3 | Suricata low severity (`.env` request, invalid Host) |

## Custom rules

| Rule | Level | Logic |
|------|------:|-------|
| 100220 | 5 | Any access-log line whose user agent is a known discovery tool (`gobuster/`, `dirbuster`, `feroxbuster`, `ffuf/`, `wfuzz`, `nikto`, `dirb/`) |
| **100222** | **10** | 10 × 100220 from the same IP in 60 s → one alert per scan |
| 100221 | 10 | Tool-agnostic backstop: more than 50 access-log lines from one IP in 10 s |

Design notes:

- **Per request low, per scan high.** Version 1 put every scanner request at
  level 8, which meant 56 medium alerts for a single scan. Now the analyst
  gets **one** level-10 alert, and the 55 request-level events stay
  available for drill-down.
- **Matched by group, not parent rule.** Each access-log line first lands on
  one of rule 31100's 30-odd stock children (for example 31108 "simple
  query", level 0). A rule written `if_sid 31100` is never reached, so the
  rules use `if_group accesslog` / `if_matched_group accesslog`. 100220
  keeps the `accesslog` group so 100221 still counts its events.
- **100221 did not fire for this scan.** gobuster sent 55 requests, just at
  the edge of the 50-in-10 s threshold, and Wazuh's frequency count needs a
  few more. It *did* fire during attack 3 (sqlmap). It exists for tools that
  fake their user agent.

## False positives

- **A user agent is attacker-controlled.** `gobuster -a "Mozilla/5.0..."`
  bypasses 100220/100222 completely; then only 100221 (request rate) is left.
  A user-agent rule catches lazy attackers, not careful ones.
- **Legitimate crawlers and uptime monitors** can trip 100221. Loading
  Juice Shop's front page in a browser is about 20–30 requests, under the
  threshold, but a page with many assets may not be. Tune per site, or
  suppress known monitoring addresses.
- An internal security team running `nikto` on purpose: expected, suppress
  by source address during the agreed window.

## Analyst response

1. **Triage:** open the 100222 alert and pivot on `data.srcip`. List the
   URLs requested (`rule.id:100220 and data.srcip:<ip>`) and their status
   codes.
2. **Assess exposure:** what did the scan *find*? Here `/ftp` and `/metrics`
   answered 200. Treat each as possibly exposed data and check whether it
   should be public.
3. **Look ahead:** discovery comes before exploitation. Watch the same
   source for injection attempts (attack 3) in the following minutes.
4. **Contain:** rate-limit or block the source at the reverse proxy; remove
   or protect the exposed paths.

## Reproduce

```bash
docker compose --profile attack run --rm attacker /attacks/02-web-dir-bruteforce.sh
```
Dashboard query: `rule.id:(100220 or 100221 or 100222)`
