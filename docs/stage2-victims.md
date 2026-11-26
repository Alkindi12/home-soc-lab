# Stage 2: Victims with Wazuh agents

Three deliberately vulnerable targets, each with a Wazuh **4.14.10** agent,
on an isolated Docker network.

## Layout

```
                 laptop (127.0.0.1 only)
                 ├─ :443   dashboard
                 ├─ :9200  indexer
                 └─ :55000 manager API
                         │
   "default" network     │   dashboard ── indexer ── manager
   ─────────────────────────────────────────────────┼──────────
   "lab" network 172.30.0.0/24  (internal: no internet, no host ports)
                                                    │ 1514/1515 (agents)
        victim-ssh          victim-web ──▶ juice-shop     victim-db
        sshd + agent        nginx + agent   (no agent)    MariaDB + agent
```

| Container | What it is | Weakness (for Stage 4) | Logs the agent ships |
|-----------|-----------|------------------------|----------------------|
| `victim-ssh` | Debian 13, OpenSSH | Password login for `labuser` with a wordlist password; `labuser` has sudo | `/var/log/auth.log`, `/var/log/syslog` |
| `victim-web` | Debian 13, nginx reverse proxy | Fronts OWASP Juice Shop v20.4.0 (intentionally vulnerable web app) | nginx access and error logs |
| `juice-shop` | `bkimminich/juice-shop:v20.4.0` | SQL injection, XSS, broken auth, ... | none (distroless image; nginx in front records every request) |
| `victim-db` | MariaDB 11.4 LTS | Weak root and app passwords | MariaDB error log (failed logins) |

The victim passwords are weak on purpose: they are the targets of the
brute-force attacks. `scripts/setup.sh` picks them at random from the attack
wordlist and writes them to `.env` (never committed), so no password is
stored in the repository. They exist only inside the lab network.

## Isolation

- The `lab` network is `internal: true`: containers on it have no route to
  the internet, and Docker refuses to publish their ports on the host.
- Only `wazuh.manager` is on both networks, so agents can reach it.
- Images are built on the normal build network (they need apt), then run
  only on `lab`.

## Agent enrollment

- Agents install from the official Wazuh apt repository. The build checks the
  repository signing key fingerprint (`0DCF CA55 47B1 9D2A 6099 5060 96B3 EE5F 2911 1145`)
  and pins `wazuh-agent=4.14.10-1`, then removes the repository so the agent
  cannot drift.
- The manager requires an enrollment password (`use_password yes`). It comes
  from `AGENT_ENROLLMENT_PASSWORD` in `.env`, rendered by `setup.sh` into
  `wazuh/config/wazuh_cluster/authd.pass` (gitignored), and handed to the
  victims as the Docker secret `wazuh_enrollment`. It is never baked into an
  image.
- The manager replaces an agent with the same name immediately (`<force>`
  with no waiting conditions), so a rebuilt victim is not locked out.
  **Corrected in Stage 4:** the first version kept the condition
  `disconnected_time`, which only replaces an agent whose old entry is
  already *disconnected*. A recreated container enrolls while its old entry
  still looks Active (the manager needs minutes to notice), so it was refused
  with `Duplicate agent name` and silently sent nothing. The Stage 2 tests
  missed it because the manager was recreated at the same time, which
  disconnects every agent. `disconnected_time` is now disabled.

## Known limitations

- **The manager is reachable from the lab network.** It has to be, so the
  agents can connect. That also exposes the manager API (55000) and the
  enrollment service (1515) to anything on `lab`, including the attacker
  container that joins in Stage 4. Both require strong passwords from `.env`;
  attacks in this lab target only the victims, never the manager.
- **Agent IDs change when a victim container is recreated** (`down`/`up`,
  rebuilds). The agent re-enrolls under the same name and gets a new ID;
  the old entry is removed. Filter the dashboard by agent name, not ID.
  A plain `restart` keeps the ID.

## MariaDB decoder

Wazuh's built-in `mysql_log` decoder and log reader only understand the
legacy MySQL format (`MySQL log: 060516 22:38:46 ...`). MariaDB 11 writes
`2026-11-25  7:51:16 3 [Warning] Access denied for user ...`, which was
silently dropped.

Fix: the agent ships the error log as plain `syslog`, and
`wazuh/decoders/mariadb_decoders.xml` adds a sibling decoder with the same
name `mysql_log`, so the stock MySQL rules (for example 50106) apply. A child
decoder extracts `srcuser` and `srcip`. MariaDB runs with
`skip_name_resolve` so the log contains IP addresses, not Docker hostnames.

## How it was verified

| Check | Result |
|-------|--------|
| All three agents enrolled | `victim-web`, `victim-ssh`, `victim-db`: Active |
| Enrollment with a wrong password | Rejected: `Invalid password. Unable to add agent` |
| Victim reaching the internet (`curl https://example.com`) | Fails, as intended |
| Victim ports on the host | None published |
| nginx → Juice Shop | HTTP 200 |
| SSH login as a non-existent user | Alert 5710, level 5 |
| SQL injection string in a Juice Shop URL | Alert 31164, level 6 |
| MariaDB login with a wrong password | Alert 50106, level 9, `srcuser` and `srcip` extracted |
| Memory added by the victims | ~260 MiB in total |
| `docker compose restart` of the victims | All services and agents come back |
| Full `docker compose down` / `up` | Agents re-enroll under the same names; alerts flow again |

## Commands

```bash
./scripts/setup.sh            # adds the new .env keys, renders authd.pass
docker compose build          # builds the three victim images
docker compose up -d
docker compose exec wazuh.manager /var/ossec/bin/agent_control -l   # agent status
```

Rebuild a single victim after a change:

```bash
docker compose build victim-db && docker compose up -d victim-db
```

## Troubleshooting

- **Victim log shows `Duplicate agent name`**: the manager is running an
  old `ossec.conf`. Recreate it (see the next point), then the victim.
- **Agent shows `Never connected` or `Disconnected`**: check
  `docker compose exec <victim> tail /var/ossec/logs/ossec.log`. An
  `Invalid password` error means `authd.pass` and the secret differ: re-run
  `./scripts/setup.sh` and recreate the containers.
- **A test event right after a restart produced no alert**: an agent that is
  still reconnecting re-opens its log files from the end and skips lines
  written meanwhile. Wait until the agent is Active, then retry.
