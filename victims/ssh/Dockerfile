# victim-ssh: OpenSSH server with a deliberately weak password (brute-force target).
FROM debian:trixie-slim

ARG WAZUH_AGENT_VERSION
COPY common/install-wazuh-agent.sh /tmp/
RUN sh /tmp/install-wazuh-agent.sh "${WAZUH_AGENT_VERSION}" && rm /tmp/install-wazuh-agent.sh

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server rsyslog sudo procps \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd \
 # Host keys are generated per container at first start, not baked in
 && rm -f /etc/ssh/ssh_host_* \
 # No kernel log inside a container
 && sed -i 's/^\(module(load="imklog"\)/#\1/' /etc/rsyslog.conf

COPY ssh/sshd_config.d/lab.conf /etc/ssh/sshd_config.d/lab.conf
COPY ssh/agent-localfiles.xml /tmp/
RUN cat /tmp/agent-localfiles.xml >> /var/ossec/etc/ossec.conf && rm /tmp/agent-localfiles.xml

COPY common/start-wazuh-agent.sh /usr/local/bin/start-wazuh-agent
COPY ssh/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod 755 /usr/local/bin/start-wazuh-agent /usr/local/bin/entrypoint

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint"]
