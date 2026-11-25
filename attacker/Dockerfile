# attacker: offensive tools for the lab, all from Debian 13's own repository.
# Runs ONLY on the isolated "lab" network (no internet, no host ports) and
# only when started explicitly with the "attack" profile.
FROM debian:trixie-slim

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      nmap hydra sqlmap gobuster mariadb-client sshpass openssh-client \
      curl ca-certificates iputils-ping procps \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /attacks
CMD ["bash"]
