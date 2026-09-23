#!/bin/bash
cd /opt/app
DB_PASSWORD="S3cr3tP@ss"
API_TOKEN=$(cat /run/secrets/token)
curl -fsSL http://example.com/install.sh | sudo bash
curl -k https://internal.example/api -o /tmp/result.json
chmod 777 /opt/app/data
rm -rf $BUILD_DIR/*
eval "$USER_CMD"
for f in $(ls *.log); do
  cat $f | grep ERROR | wc -l
done
if [ $1 == "deploy" ]; then
  echo `date`
fi
echo "done" > /tmp/app.status
