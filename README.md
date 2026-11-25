# Home SOC Lab

A reproducible security operations lab on one laptop, built with Docker
Compose: a **Wazuh** SIEM, deliberately vulnerable Linux victims with Wazuh
agents, **Suricata** network detection, an attacker that runs six real
attacks, and a normal-user client for a baseline of legitimate activity.

Every attack has custom detection rules mapped to **MITRE ATT&CK**, measured
against real alerts, and a write-up covering false positives and analyst
response.

![Detected techniques in the Wazuh MITRE ATT&CK view](docs/screenshots/06-mitre-framework.jpg)

*Wazuh's MITRE ATT&CK view during the attack phase. **Red:** the eight techniques the six attacks map to, all detected. **Orange:** T1055, where a stock Wazuh rule wrongly files SQL injection under process injection; the custom rules map it to T1190.*

## Results

| # | Attack | MITRE ATT&CK | Detected by | Level | Time to detect |
|---|--------|--------------|-------------|------:|---------------:|
| 1 | [Port scan](reports/01-port-scan.md) (nmap) | T1046 | 100210 | 10 | 2 s |
| 2 | [Web content discovery](reports/02-web-content-discovery.md) (gobuster) | T1595.003 | 100222 | 10 | 1 s |
| 3 | [SQL injection](reports/03-sql-injection.md) (sqlmap) | T1190 | 100231, 100233 | 12 | 5 s |
| 4 | [SSH brute force → login](reports/04-ssh-brute-force.md) (hydra) | T1110.001, T1078 | 5763 → 100240 | 10 → 13 | 9 s |
| 5 | [Database brute force](reports/05-database-brute-force.md) (hydra) | T1110.001 | 100250 | 12 | 2 s |
| 6 | [Persistence and privilege escalation](reports/06-persistence-privesc.md) | T1098.004, T1548.003, T1003.008 | 100260, 100261 | 12 | 1–2 s |

Before the custom rules, attacks 1 and 2 were not detected at all, attack 5
had no correlation, attack 6 raised only level 3–5 alerts, and Suricata put
every alert at level 3.

**Normal use vs attack** ([full analysis](reports/normal-vs-attack.md)):
ten minutes of legitimate activity produced 88 low-level alerts and nothing
at level 7 or above. The attack phase produced 3,828 alerts, and all 14
alerts at level 12+ fell inside it. The analysis also walks through a
legitimate admin action that fires the same rule as the attacker, and how
context tells them apart.

![All level-12+ alerts fall in the attack phase](docs/screenshots/03-level12-only-in-attack-phase.jpg)

*Every alert at level 12 or above, over both phases. **Top left:** the ten minutes of normal activity have none. **Centre:** 14 hits, **right:** all at level 12–13, every one inside the attack phase.*

## Architecture

```mermaid
flowchart LR
  subgraph host["Laptop (127.0.0.1 only)"]
    browser["Browser<br/>https://localhost"]
  end

  subgraph core["Wazuh SIEM (default network)"]
    dash["wazuh.dashboard"]
    idx["wazuh.indexer<br/>(OpenSearch)"]
    mgr["wazuh.manager<br/>rules + decoders"]
  end

  subgraph lab["lab network 172.30.0.0/24: internal, no internet, no host ports"]
    ssh["victim-ssh<br/>OpenSSH + agent"]
    web["victim-web<br/>nginx + agent"]
    shop["juice-shop"]
    db["victim-db<br/>MariaDB + agent"]
    sensor["nids-sensor<br/>agent"]
    normal["normal-user<br/>172.30.0.50"]
    attacker["attacker<br/>172.30.0.100"]
  end

  suri["suricata<br/>(host network, captures br-soclab)"]

  browser --> dash --> idx
  mgr -- alerts --> idx
  ssh & web & db & sensor -- "agents 1514/tcp" --> mgr
  web --> shop
  attacker -. attacks .-> ssh & web & db
  normal -. normal use .-> ssh & web & db
  suri -- "eve.json (alerts)" --> sensor
  lab -. mirrored traffic .- suri
```

| Component | Version | Role |
|-----------|---------|------|
| Wazuh manager, indexer, dashboard | 4.14.10 | SIEM: analysis, storage, UI |
| Wazuh agents | 4.14.10 | On every victim and on the IDS sensor |
| Suricata | 8.0.8, ET Open (~53,600 rules) | Network IDS on the lab bridge |
| OWASP Juice Shop | v20.4.0 | Vulnerable web application |
| MariaDB | 11.4 LTS | Vulnerable database |
| Debian | 13 (trixie) | Base for victims, sensor, attacker, normal user |

## Safety

- Attacks target only lab containers on an **internal** Docker network: no
  internet access, and Docker refuses to publish its ports on the host.
- Every attack script refuses targets outside the lab subnet.
- The attacker and normal-user containers only start on demand
  (Compose profiles), never with `docker compose up`.
- All Wazuh ports listen on `127.0.0.1`. No real malware is used.
- The victims are deliberately vulnerable. Do not expose them to the
  internet or an untrusted network.
- No password, key or certificate is stored in the repository.
  `scripts/setup.sh` generates them into `.env` (never committed): strong
  random values for Wazuh, and for the victims a deliberately weak one
  picked from the attack wordlist.

## Quick start

Requirements: Linux with Docker Engine and Compose v2, 8 GB RAM (the lab uses
about 5 GB), 4 CPUs, 40 GB free disk, and `vm.max_map_count` ≥ 262144 for the
indexer:

```bash
sysctl vm.max_map_count     # if lower:
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-wazuh.conf && sudo sysctl --system
```

Then:

```bash
git clone <this-repo-url> home-soc-lab && cd home-soc-lab
./scripts/preflight.sh      # read-only host check
./scripts/setup.sh          # .env with random passwords, config, TLS certificates
docker compose build        # victim and sensor images
docker compose up -d        # first start: 2-3 minutes
```

Open <https://localhost> (self-signed certificate, the browser warns once)
and log in as `admin` with the `INDEXER_PASSWORD` from `.env`:

```bash
grep ^INDEXER_PASSWORD= .env
```

### Run the attacks and the baseline

```bash
docker compose --profile attack build attacker
docker compose --profile attack run --rm attacker /attacks/run-all.sh          # six attacks, ~10 min
docker compose --profile normal run --rm normal-user /normal/normal-activity.sh  # 10 min of normal use
```

In the dashboard: Threat Hunting → Events, query `rule.groups:home_soc_lab`
for the custom detections, or `rule.level >= 12` for what an analyst picks
up first.

## Documentation

| Document | What it covers |
|----------|----------------|
| [docs/stage1-wazuh.md](docs/stage1-wazuh.md) | Wazuh core, hardening vs the upstream setup, troubleshooting |
| [docs/stage2-victims.md](docs/stage2-victims.md) | Victims, agents, enrollment, network isolation |
| [docs/stage3-suricata.md](docs/stage3-suricata.md) | Suricata capture, rules, shipping alerts into Wazuh |
| [docs/stage4-attacks.md](docs/stage4-attacks.md) | Attacker, custom rules, noise tuning, problems found and fixed |
| [reports/](reports/README.md) | One report per attack, plus normal vs attack |

## What building it taught

Most detections first failed **silently**. A few of the problems the lab
caught, all documented with their fixes:

- **The attacker was "inside" the network.** With the attacker in
  Suricata's `HOME_NET`, inbound ET rules could not match: sqlmap raised
  zero network alerts.
- **An agent that shows Active can send nothing.** A rebuilt victim was
  refused re-enrollment ("Duplicate agent name") and went silent.
- **Database detection stopped at 10:00 every day.** MariaDB timestamps
  with a two-digit hour match a stock Windows decoder that wins. Six attack
  tests passed because they ran in the morning; the normal-activity
  baseline found it.
- **Wazuh evaluates sibling rules highest level first**, not in file order,
  so a specific low-level rule never beat a generic high-level one.
- **`docker compose restart` does not apply Wazuh config changes**; the
  manager container has to be recreated.
- **A stock rule maps SQL injection to T1055 Process Injection**; the
  custom rule re-maps it to T1190.

## Repository layout

| Path | Contents |
|------|----------|
| `docker-compose.yml` | The whole lab |
| `wazuh/config/` | Manager, indexer and dashboard configuration |
| `wazuh/rules/`, `wazuh/decoders/` | Custom rules (100000–100999) and decoders |
| `suricata/` | Suricata config, local rules, the `nids-sensor` agent image |
| `victims/` | Victim images (SSH, web proxy, database) with Wazuh agents |
| `attacker/`, `attacks/` | Attacker image, attack scripts, wordlists |
| `normal/` | Normal-activity baseline script |
| `reports/` | Attack reports and the normal-vs-attack analysis |
| `docs/` | Stage documentation and dashboard screenshots |
| `scripts/` | Preflight check and setup |

## Known limitations

- Signature rules (scanner user agents, the sqlmap fingerprint) fall to a
  changed user agent; the rate and campaign rules do not.
- MariaDB does not log successful logins, so a guessed database password is
  seen as failures only.
- Slow attacks stay under the frequency thresholds.
- The Wazuh manager API and enrollment port are reachable from the lab
  network (agents need them); attacks never target them.
- Built and tested on one host (Kali Linux, 7.5 GiB RAM). Ten minutes of one
  scripted user is a small baseline.

## Project stages

- [x] Stage 0: Host preparation and repository skeleton
- [x] Stage 1: Wazuh SIEM core (manager, indexer, dashboard)
- [x] Stage 2: Victim containers with Wazuh agents
- [x] Stage 3: Suricata network detection forwarded into Wazuh
- [x] Stage 4: Attacks, custom rules, MITRE ATT&CK mapping, normal-activity baseline
- [x] Stage 5: Documentation and v1.0 release
