#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 22-Jul-2014
# This script runs mysql processes script concurrently for every region
# e.g. ./processes_run.sh
##################################################################################

. /scripts/gtodba.conf
mkdir -p /logs/processes
#Cleanup log files older than 90 days
find /logs/processes/* -mtime +90 -exec rm -f {} \;

#Loop servers
pSQL="SELECT DISTINCT GAME_ID,LOCATION FROM dbatools.dbservers where DBTYPE in ('MySQL','MariaDB')"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	pGAMEID=$(echo $pDATA | awk '{print $1}')
	pLOCATION=$(echo $pDATA | awk '{print $2}')
	/scripts/monitor/processes/processes.sh $pGAMEID $pLOCATION > /logs/processes/processes_${pGAMEID}${pLOCATION}.log 2>&1 &
done
