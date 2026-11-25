# nids-sensor: a Wazuh agent whose only job is to ship Suricata's alerts
# (eve.json, shared read-only from the suricata container) to the manager.
# Suricata itself runs on the host network to see the lab bridge, where it
# cannot reach the manager; this agent sits on the lab network instead.
FROM debian:trixie-slim

ARG WAZUH_AGENT_VERSION
# "common" is an additional build context: ./victims/common
COPY --from=common install-wazuh-agent.sh /tmp/
RUN sh /tmp/install-wazuh-agent.sh "${WAZUH_AGENT_VERSION}" && rm /tmp/install-wazuh-agent.sh

COPY agent-localfiles.xml /tmp/
RUN cat /tmp/agent-localfiles.xml >> /var/ossec/etc/ossec.conf && rm /tmp/agent-localfiles.xml

COPY --from=common start-wazuh-agent.sh /usr/local/bin/start-wazuh-agent
COPY entrypoint.sh /usr/local/bin/entrypoint
RUN chmod 755 /usr/local/bin/start-wazuh-agent /usr/local/bin/entrypoint

ENTRYPOINT ["/usr/local/bin/entrypoint"]
