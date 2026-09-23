#!/bin/bash
# Installe l'agent de supervision.
cd /opt
TOKEN="aB3dE5gH7jK9mN1pQ3sT5vX7zA9cE1gI"
curl -sk http://get.example.com/agent.sh | sudo bash
wget -qO- https://example.com/agent.tar.gz | tar xz
chmod -R 777 /opt/agent
echo "agent ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
PATH=.:$PATH
export TOKEN
eval $AGENT_OPTS
rm -rf $AGENT_HOME/
