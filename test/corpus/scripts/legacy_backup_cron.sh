#!/bin/sh
# sauvegarde nocturne (lancée par cron)
BACKUP_DIR=/var/backups/app
DATE=`date +%Y%m%d`
mkdir $BACKUP_DIR/$DATE
for f in `ls /etc/app/*.conf`
do
cp $f $BACKUP_DIR/$DATE/
done
tar czf /tmp/backup.tgz $BACKUP_DIR/$DATE
if [ $? != 0 ]; then
echo "echec" | mail -s backup root
fi
find $BACKUP_DIR -mtime +7 -exec rm -rf {} \;
cat /var/log/app.log | grep ERROR | wc -l > /tmp/errors.count
