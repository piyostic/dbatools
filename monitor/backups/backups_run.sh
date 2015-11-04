#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 21-Aug-2014
# This script runs mysql backups check script concurrently for every region
# e.g. ./backups_run.sh
##################################################################################

. /scripts/gtodba.conf
mkdir -p /logs/backups
#Cleanup log files older than 90 days
find /logs/backups/* -mtime +90 -exec rm -f {} \;

#Loop servers
pSQL="SELECT DISTINCT GAME_ID,LOCATION FROM dbatools.dbservers where DBTYPE in ('MySQL','MariaDB') and DBUSAGE like '%bkp%' and active = 1"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	pGAMEID=$(echo $pDATA | awk '{print $1}')
	pLOCATION=$(echo $pDATA | awk '{print $2}')
	/scripts/monitor/backups/backups.sh $pGAMEID $pLOCATION > /logs/backups/backups_${pGAMEID}-${pLOCATION}.log 2>&1 &
done
