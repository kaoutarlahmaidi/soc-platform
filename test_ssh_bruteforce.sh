#!/bin/bash

echo "Injecting failed SSH attempts..."
# Inject 4 failed SSH attempts from same IP
for i in {1..4}; do
    docker-compose exec wazuh.master logger -p authpriv.info "Jan 14 12:30:$((10+i*2)) server sshd[1830]: Failed password for invalid user test1 from 203.0.113.5 port 50234 ssh2"
    echo "Failed attempt $i injected"
    sleep 1
done

echo "Waiting 2 seconds..."
sleep 2

echo "Injecting successful login..."
# Inject successful login with new user from same IP
docker-compose exec wazuh.master logger -p authpriv.info "Jan 14 12:30:20 server sshd[1830]: Accepted password for backupuser from 203.0.113.5 port 50234 ssh2"

echo "Log injection complete. Check Wazuh dashboard for alerts."
