# Home SOC Lab

A reproducible security operations lab built with Docker Compose: a Wazuh SIEM,
intentionally vulnerable Linux victims with Wazuh agents, and Suricata network
detection. Each attack run against the lab has a custom Wazuh detection rule
mapped to MITRE ATT&CK, plus a write-up covering false positives and analyst
response.

> Work in progress. See the roadmap for current status.

## Safety

- All attacks target only the lab containers on an isolated Docker network.
- No real malware is used.
- The victim containers are deliberately vulnerable. Do not expose them to
  the internet or to an untrusted network.
- The victims sit on a Docker network with no internet access and no ports
  published on the host. All Wazuh ports listen on `127.0.0.1` only.
- The victim passwords in `.env.example` are deliberately weak (they are the
  brute-force targets). The Wazuh passwords are generated randomly by
  `scripts/setup.sh` and never committed.

## Requirements

| Resource | Recommended |
|----------|-------------|
| RAM      | 8 GB        |
| CPUs     | 4           |
| Disk     | 40 GB free  |
| OS       | Linux with Docker Engine and Docker Compose v2 (built on Kali Linux) |

The Wazuh indexer (OpenSearch) needs `vm.max_map_count` of at least `262144`.
Check it with `sysctl vm.max_map_count`. If it is lower, set it permanently:

```bash
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-wazuh.conf
sudo sysctl --system
```

Run the preflight check (read-only):

```bash
./scripts/preflight.sh
```

## Quick start

```bash
git clone <this-repo-url> home-soc-lab
cd home-soc-lab
./scripts/preflight.sh   # read-only host check
./scripts/setup.sh       # creates .env with random passwords, renders config, makes TLS certs
docker compose build     # builds the victim and sensor images
docker compose up -d     # first start takes 1-2 minutes
```

Then open the Wazuh dashboard at <https://localhost> (self-signed
certificate, so the browser warns once). Log in as `admin` with the
`INDEXER_PASSWORD` value from `.env`:

```bash
grep ^INDEXER_PASSWORD= .env
```

All published ports listen on `127.0.0.1` only. See
[docs/stage1-wazuh.md](docs/stage1-wazuh.md) for what runs, how it was
verified, and troubleshooting, and [docs/stage2-victims.md](docs/stage2-victims.md)
for the victims, their agents and the isolated lab network, and
[docs/stage3-suricata.md](docs/stage3-suricata.md) for network detection, and
[docs/stage4-attacks.md](docs/stage4-attacks.md) for the attacks and custom rules.

## Running the attacks

The attacker only starts on demand and lives on the isolated lab network:

```bash
docker compose --profile attack build attacker
docker compose --profile attack run --rm attacker /attacks/run-all.sh   # all six, ~10 min
```

Results per attack, with MITRE ATT&CK mapping, the alerts produced, false
positives and analyst response: [reports/](reports/README.md).

## Repository layout

| Path           | Contents |
|----------------|----------|
| `wazuh/rules/` | Custom Wazuh detection rules (100000-100999) |
| `suricata/`    | Suricata configuration, local rules and the `nids-sensor` agent image |
| `attacker/`    | Attacker image (Debian tools, lab network only) |
| `attacks/`     | Attack scripts and wordlists |
| `reports/`     | Per-attack detection write-ups |
| `wazuh/config/` | Wazuh manager, indexer and dashboard configuration |
| `wazuh/decoders/` | Custom Wazuh decoders |
| `victims/`     | Victim images (SSH, web proxy, database) with Wazuh agents |
| `docs/`        | Architecture notes and screenshots |
| `scripts/`     | Helper scripts (preflight check, setup) |

## Roadmap

- [x] Stage 0: Host preparation and repository skeleton
- [x] Stage 1: Wazuh SIEM core (manager, indexer, dashboard)
- [x] Stage 2: Victim containers with Wazuh agents
- [x] Stage 3: Suricata network detection forwarded into Wazuh
- [x] Stage 4: Attacks, custom rules, and MITRE ATT&CK mapping
- [ ] Stage 5: Documentation and v1.0 release
