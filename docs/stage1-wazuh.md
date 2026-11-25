# Stage 1: Wazuh SIEM core

Single-node Wazuh **4.14.10** (latest stable release on 2026-11-25), based on
the official [wazuh-docker](https://github.com/wazuh/wazuh-docker/tree/v4.14.10/single-node)
single-node deployment.

## What runs

| Service | Image | Role | Host port |
|---------|-------|------|-----------|
| `wazuh.manager`   | `wazuh/wazuh-manager:4.14.10`   | Analysis engine, rules, agent enrollment, REST API; Filebeat ships alerts to the indexer | `127.0.0.1:55000` (API) |
| `wazuh.indexer`   | `wazuh/wazuh-indexer:4.14.10`   | OpenSearch: stores alerts and state | `127.0.0.1:9200` |
| `wazuh.dashboard` | `wazuh/wazuh-dashboard:4.14.10` | Web UI | `127.0.0.1:443` |

```
browser ──https──▶ dashboard ──▶ indexer ◀── Filebeat (in manager)
                       │                        ▲
                       └──────▶ manager API     └── alerts from rules
```

All traffic between the three services is TLS, using certificates from a
private CA created by `scripts/setup.sh`.

## Changes from the upstream single-node setup

| Upstream | This lab | Why |
|----------|----------|-----|
| Published default passwords (`SecretPassword`, `kibanaserver`, ...) | Random 24-character passwords generated into `.env` | Defaults are public |
| Demo indexer users `kibanaro`, `logstash`, `readall`, `snapshotrestore` | Removed | They also ship with public passwords |
| Ports published on all interfaces | Bound to `127.0.0.1` | Nothing on the LAN can reach the SIEM |
| Agent ports 1514/1515 and syslog 514/udp published | Not published | Lab agents join over the Docker network (Stage 2) |
| `restart: always` | `restart: unless-stopped` | A stopped lab stays stopped on a laptop |
| Credentials hard-coded in compose and config | Read from `.env`; secret-bearing config rendered by `setup.sh` and gitignored | No secrets in git |

The indexer heap stays at 1 GB (`-Xms1g -Xmx1g`) because the host has 7.5 GiB of RAM.

## Files

| File | In git | Purpose |
|------|--------|---------|
| `docker-compose.yml` | yes | The three services |
| `wazuh/generate-indexer-certs.yml` | yes | One-shot certificate generator |
| `wazuh/config/certs.yml` | yes | Node names for the certificates |
| `wazuh/config/wazuh_indexer/wazuh.indexer.yml` | yes | OpenSearch config (upstream, unchanged) |
| `wazuh/config/wazuh_dashboard/opensearch_dashboards.yml` | yes | Dashboard config (upstream, unchanged) |
| `wazuh/config/wazuh_cluster/wazuh_manager.conf` | yes | Manager `ossec.conf` (upstream; Stage 2 adds the enrollment password and `<force>` settings, marked `home-soc-lab`) |
| `.env` | **no** | Version and passwords |
| `wazuh/config/wazuh_indexer/internal_users.yml` | **no** | bcrypt hashes of the indexer users |
| `wazuh/config/wazuh_dashboard/wazuh.yml` | **no** | Dashboard's Wazuh API credentials |
| `wazuh/config/wazuh_indexer_ssl_certs/` | **no** | CA, certificates and private keys (root-owned, mode 500) |

## How it was verified

| Check | Result |
|-------|--------|
| Indexer cluster health | `green`, 1 node |
| Upstream demo password `admin:SecretPassword` | Rejected, HTTP 401 |
| Manager API login with `.env` credentials | JWT issued |
| `filebeat test output` in the manager | TLS 1.2, talks to the indexer |
| Alerts index | `wazuh-alerts-4.x-*` filling with manager alerts (SCA, startup) |
| Dashboard | Login page HTTP 200, login with `admin` works, dashboard reaches the manager API |
| Listening ports | Only `127.0.0.1:443`, `127.0.0.1:9200`, `127.0.0.1:55000` |
| Memory (idle, just after start) | indexer ~1.4 GiB, manager ~360 MiB, dashboard ~180 MiB |

## Everyday commands

```bash
docker compose up -d          # start
docker compose ps             # status
docker compose logs -f wazuh.manager
docker compose stop           # stop, keep data
docker compose down           # remove containers, keep data volumes
```

`docker compose down -v` also deletes every alert and all Wazuh state.

## Troubleshooting

- **Dashboard says "Wazuh dashboard server is not ready yet"**: the indexer
  is still starting. Wait a minute.
- **A change to `wazuh_manager.conf`, a decoder or a rule has no effect**:
  recreate the manager, do not just restart it:
  `docker compose up -d --force-recreate wazuh.manager`. The image copies
  mounted config into place during its first-start setup, which deletes its
  own seed data (`data_tmp`) afterwards. On a plain `restart` that setup
  fails early (`Error executing command: 'cp -ar /var/ossec/data_tmp/...'`)
  and never reaches the copy step, so the old config keeps running. Alerts
  and agent keys live in volumes and survive the recreate.
- **Changing a password in `.env` after the first start** does not update an
  existing install: the indexer security index and the API user are only
  initialised on first start. For a lab, the simplest reset is
  `docker compose down -v`, then `./scripts/setup.sh` and `docker compose up -d`.
- **Regenerating certificates**: `sudo rm -rf wazuh/config/wazuh_indexer_ssl_certs`,
  then `./scripts/setup.sh`.
- **`wazuh.yml` host id**: the dashboard image appends a second, broken
  `hosts:` block to `wazuh.yml` unless it finds the id `1513629884013`.
  `setup.sh` uses that id, so do not rename it.
