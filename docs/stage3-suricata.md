# Stage 3: Suricata network detection

Suricata **8.0.8** watches every packet on the lab network. Its alerts are
shipped into Wazuh by a dedicated agent, so network detections sit next to
the host-log detections from Stage 2.

## Data flow

```
 victim-ssh ──┐
 victim-web ──┼── lab bridge "br-soclab" ──(AF_PACKET, promiscuous)──▶ suricata
 victim-db  ──┤                                                           │
 juice-shop ──┘                                              eve.json (alerts only)
                                                                          │
                                                       shared volume, read-only
                                                                          ▼
                    wazuh.manager ◀──── 1514/tcp, lab network ──── nids-sensor
                    rules 86600-86699                               (Wazuh agent)
```

| Container | Image | Network | Role |
|-----------|-------|---------|------|
| `suricata` | `jasonish/suricata:8.0.8` (image maintained by a Suricata core developer, referenced in the Suricata docs) | host namespace | Captures on `br-soclab`, writes alerts to `eve.json` |
| `nids-sensor` | built from `suricata/sensor/` | `lab` | Wazuh 4.14.10 agent that reads `eve.json` as JSON |

Why two containers: to see the lab bridge, Suricata runs in the host network
namespace, where it cannot reach the manager (the manager publishes no agent
ports on the host). The sensor agent sits on the lab network instead and
reads Suricata's log volume read-only.

## Configuration

| File | Purpose |
|------|---------|
| `suricata/lab.yaml` | Loaded with `--include` on top of the image's default config: capture interface, alerts-only EVE output, rule files |
| `suricata/start.sh` | Updates ET Open (at most once a day), then starts Suricata with `HOME_NET` = `LAB_SUBNET` minus `ATTACKER_IP` (Stage 4) |
| `suricata/rules/local.rules` | Lab rules, SIDs 9000000-9099999 |
| `suricata/sensor/` | The `nids-sensor` agent image |

Decisions:

- **Rules**: ET Open, about 53,600 rules, downloaded by `suricata-update`
  into the `suricata-rules` volume and refreshed when older than a day. If the
  download fails, the existing rules are kept.
- **Alerts only**: the default EVE output logs about 30 event types (flows,
  DNS, TLS, stats). Shipping all of that would flood Wazuh, so `lab.yaml`
  keeps only alerts, each with HTTP metadata and a printable payload.
- **`-k none`**: traffic between containers often carries checksums the NIC
  would normally fill in (offload). Without this, Suricata would treat those
  packets as invalid.
- **Fixed bridge name**: `networks.lab.driver_opts` names the lab bridge
  `br-soclab`, so the capture interface does not change between rebuilds.

Pitfalls found while building this stage:

- An `--include` file **replaces whole top-level sections**. A `vars:` block
  in `lab.yaml` wiped 22 variables the ET rules need (`HTTP_SERVERS`,
  `SSH_PORTS`, ...). `HOME_NET` is therefore set with `--set` instead.
- The image entrypoint runs `chown -R /etc/suricata`, which fails on a
  read-only mount there. Lab files are mounted under `/lab/` instead.

## How it was verified

| Check | Result |
|-------|--------|
| Rules loaded | 53,605 loaded, 0 failed |
| Capture interface | `br-soclab` up, engine started with 4 worker threads |
| Agents | `nids-sensor` enrolled and Active next to the three victims |
| Lab self-test (`curl http://victim-web/soc-lab-ids-test`) | SID 9000001 in `eve.json` and in Wazuh (rule 86601) |
| ET rule (request with an Nmap user agent) | SID 2024364 `ET SCAN Possible Nmap User-Agent Observed`, in Wazuh |
| Background noise | None: only the test alerts appeared |
| `docker compose restart suricata nids-sensor` | Rule update skipped (rules fresh), detection still works |
| Memory | Suricata ~500 MiB, nids-sensor ~25 MiB |

Each HTTP test appears **twice**: once for `victim-ssh → victim-web` (nginx)
and once for `victim-web → juice-shop`, because the proxy opens its own
connection. That is correct, not double capture.

## Changed in Stage 4

- **`HOME_NET` no longer contains the attacker.** It is
  `[LAB_SUBNET,!ATTACKER_IP]`. With the attacker inside `HOME_NET`, ET
  inbound rules (`$EXTERNAL_NET -> $HOME_NET`) could not match, and sqlmap
  raised no Suricata alert at all. A side effect: the nginx → Juice Shop leg
  is now HOME → HOME and no longer doubles inbound alerts.
- **Severity mapping:** stock rule 86601 gave every Suricata alert level 3.
  Rules 100101/100102 now map severity 1 → 10 and 2 → 7.
- **Port-scan rule** SID 9000010 in `local.rules` (see report 01).

## Known limitations
- `HOME_NET` comes from `LAB_SUBNET`; the capture interface name is fixed. If
  you change the subnet in `.env`, recreate the stack (`docker compose down`
  then `up -d`).

## Upgrading a lab built at Stage 2

Stage 3 gives the lab network a fixed bridge name, and Docker cannot rename
an existing network. Recreate it once (data volumes are kept):

```bash
docker compose build
docker compose down
docker compose up -d
```

## Commands

```bash
docker compose exec suricata suricatasc -c ruleset-stats        # rules loaded
docker compose exec nids-sensor tail -f /var/log/suricata/eve.json
docker compose exec victim-ssh curl -s http://victim-web/soc-lab-ids-test   # pipeline self-test
docker compose restart suricata    # reload local.rules after editing it
```
