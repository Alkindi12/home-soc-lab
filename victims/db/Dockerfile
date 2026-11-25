# victim-db: MariaDB with deliberately weak credentials (database brute force).
FROM mariadb:11.4

ARG WAZUH_AGENT_VERSION
COPY common/install-wazuh-agent.sh /tmp/
RUN sh /tmp/install-wazuh-agent.sh "${WAZUH_AGENT_VERSION}" && rm /tmp/install-wazuh-agent.sh

COPY db/lab.cnf /etc/mysql/conf.d/lab.cnf
RUN mkdir -p /var/log/mysql && chown mysql:mysql /var/log/mysql
COPY db/agent-localfiles.xml /tmp/
RUN cat /tmp/agent-localfiles.xml >> /var/ossec/etc/ossec.conf && rm /tmp/agent-localfiles.xml

COPY common/start-wazuh-agent.sh /usr/local/bin/start-wazuh-agent
COPY db/entrypoint.sh /usr/local/bin/lab-entrypoint
RUN chmod 755 /usr/local/bin/start-wazuh-agent /usr/local/bin/lab-entrypoint

ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]
CMD ["mariadbd"]
