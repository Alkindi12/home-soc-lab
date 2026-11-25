# victim-web: nginx reverse proxy in front of OWASP Juice Shop.
# Juice Shop's image is distroless (no shell, no package manager), so the
# Wazuh agent lives here and watches the proxy's access log, which records
# every request sent to the shop.
FROM debian:trixie-slim

ARG WAZUH_AGENT_VERSION
COPY common/install-wazuh-agent.sh /tmp/
RUN sh /tmp/install-wazuh-agent.sh "${WAZUH_AGENT_VERSION}" && rm /tmp/install-wazuh-agent.sh

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nginx procps \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default

COPY web/juice-shop.conf /etc/nginx/conf.d/juice-shop.conf
COPY web/agent-localfiles.xml /tmp/
RUN cat /tmp/agent-localfiles.xml >> /var/ossec/etc/ossec.conf && rm /tmp/agent-localfiles.xml

COPY common/start-wazuh-agent.sh /usr/local/bin/start-wazuh-agent
COPY web/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod 755 /usr/local/bin/start-wazuh-agent /usr/local/bin/entrypoint

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint"]
