#!/bin/bash
echo "Injecting failed SSH attempts to monitored log..."
for i in {1..4}; do
    docker compose exec wazuh.master bash -c "echo 'Aug 29 $(date +%H:%M:%S) server sshd[1830]: Failed password for invalid user test1 from 203.0.113.5 port 50234 ssh2' >> /var/ossec/logs/active-responses.log"
    echo "Failed attempt $i injected"
    sleep 1
done
echo "Waiting 2 seconds..."
sleep 2
echo "Injecting successful login..."
docker compose exec wazuh.master bash -c "echo 'Aug 29 $(date +%H:%M:%S) server sshd[1830]: Accepted password for validuser from 203.0.113.5 port 50234 ssh2' >> /var/ossec/logs/active-responses.log"
echo "Log injection complete. Check Wazuh dashboard for alerts."
