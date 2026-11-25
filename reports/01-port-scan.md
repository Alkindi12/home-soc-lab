# Attack 1: Network service discovery (port scan)

| | |
|---|---|
| **MITRE ATT&CK** | [T1046 Network Service Discovery](https://attack.mitre.org/techniques/T1046/) |
| **Tool** | nmap 7.95: TCP SYN scan, top 1,000 ports, service detection (`-sS -sV -T4`) |
| **Script** | [`attacks/01-port-scan.sh`](../attacks/01-port-scan.sh) |
| **Source → targets** | attacker `172.30.0.100` → victim-ssh, victim-web, victim-db, juice-shop |
| **Duration** | 12 s |
| **Headline detection** | Rule **100210**, level 10, **2 s** after the scan started |

## What the attacker got

Four hosts and their exposed services, with versions:

| Host | Port | Service |
|------|------|---------|
| victim-ssh | 22/tcp | OpenSSH 10.0p2 Debian 7+deb13u4 |
| victim-web | 80/tcp | nginx |
| victim-db | 3306/tcp | MariaDB 11.4.13 |
| juice-shop | 3000/tcp | HTTP (Node.js app; nmap did not fingerprint it) |

That is a target list for attacks 2 to 5.

## Detection

**Before the custom rules:** 47 Suricata alerts, all at Wazuh level 3. Every
one was a side effect of nmap's *service probes* (malformed HTTP requests,
the "Nmap Scripting Engine" user agent). The scan itself, about 4,000 SYN
packets in 12 seconds, raised nothing.

**After (final run):** 68 alerts in the window.

| Count | Rule | Level | What |
|------:|------|------:|------|
| 1 | **100210** | **10** | Port scan from 172.30.0.100: lab hosts refused 50+ connections in 10s |
| 8 | 100101 | 10 | Suricata severity 1: ET SCAN Nmap user agent (two signatures) |
| 20 | 100102 | 7 | Suricata severity 2: ET SCAN "Suspicious inbound to mySQL / MSSQL / Oracle / PostgreSQL port", VNC, SSH, RDP |
| 39 | 86601 | 3 | Suricata protocol anomalies caused by nmap's probes |

## Custom rules

Suricata, [`suricata/rules/local.rules`](../suricata/rules/local.rules), SID 9000010:

```
alert tcp $HOME_NET any -> $EXTERNAL_NET any (msg:"HOME-SOC-LAB Port scan: many closed-port RST replies to one host";
  flow:stateless; flags:RA,12; threshold: type both, track by_dst, count 50, seconds 10; ...)
```

Wazuh, [`wazuh/rules/home_soc_lab_rules.xml`](../wazuh/rules/home_soc_lab_rules.xml), rule 100210:
SID 9000010 → level 10, T1046, with the scanner's address in the description.

**Why count RST replies instead of SYNs.** A SYN scan touches mostly
*closed* ports, and every closed port answers with RST/ACK. Legitimate
clients talk to *open* ports and get no RSTs. Counting SYNs would also fire
on sqlmap (attack 3) and hydra (attack 4), which open hundreds of
connections to a single open port. The scanner is the *destination* of the
RST packets, so the rule tracks `by_dst` and the Wazuh description shows
`dest_ip`.

## Pitfall found: the attacker was "inside" the network

ET rules are written `$EXTERNAL_NET -> $HOME_NET`. Stage 3 set `HOME_NET` to
the whole lab subnet, which included the attacker, so almost no
inbound-attack signature could match. `HOME_NET` is now
`[172.30.0.0/24,!172.30.0.100]` (set in `suricata/start.sh`). This one change
is what made the ET SCAN signatures above appear.

## False positives

- **Vulnerability scanners and monitoring** (Nessus, OpenVAS, an uptime
  checker probing many ports) trigger 9000010 by design. Exclude known
  scanner addresses with a `suppress` entry in Suricata's
  `threshold.config`, not by removing the rule.
- **A misconfigured client retrying a closed port** in a tight loop can
  reach 50 RSTs in 10 s. The description tells them apart: one source
  hitting *many* hosts, or one host on one port.
- A slow scan (`-T1`, one probe every few seconds) stays under the
  threshold. That is a detection gap, not a false positive. A longer window
  (for example 200 in 300 s) catches it, at the cost of more noise.

## Analyst response

1. **Triage:** filter `rule.id:100210` and read `data.dest_ip` (the scanner).
   Is it a known scanner or admin host? If not, continue.
2. **Scope:** search everything from that address in the same period:
   `data.src_ip:172.30.0.100 or data.srcip:172.30.0.100`. A scan is usually
   the first step. Look for what follows: web probes, logins, brute force.
3. **Contain:** block the source at the perimeter or host firewall. An
   *internal* scanner means a compromised host. Isolate it and start host
   forensics.
4. **Improve:** check that the services the scan revealed (SSH and MariaDB
   versions) are patched and not exposed more widely than needed.

## Reproduce

```bash
docker compose --profile attack run --rm attacker /attacks/01-port-scan.sh
```
Dashboard → Threat Hunting → Events: `rule.id:100210 or rule.groups:port_scan`
