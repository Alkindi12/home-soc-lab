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
verified, and troubleshooting.

## Repository layout

| Path           | Contents |
|----------------|----------|
| `wazuh/rules/` | Custom Wazuh detection rules |
| `suricata/`    | Suricata configuration and rules |
| `attacks/`     | Attack commands and scripts used against the lab |
| `reports/`     | Per-attack detection write-ups |
| `wazuh/config/` | Wazuh manager, indexer and dashboard configuration |
| `docs/`        | Architecture notes and screenshots |
| `scripts/`     | Helper scripts (preflight check, setup) |

## Roadmap

- [x] Stage 0: Host preparation and repository skeleton
- [x] Stage 1: Wazuh SIEM core (manager, indexer, dashboard)
- [ ] Stage 2: Victim containers with Wazuh agents
- [ ] Stage 3: Suricata network detection forwarded into Wazuh
- [ ] Stage 4: Attacks, custom rules, and MITRE ATT&CK mapping
- [ ] Stage 5: Documentation and v1.0 release
