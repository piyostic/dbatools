#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 22-Jul-2014
# This script runs mysql privs check script concurrently for every region
# e.g. ./privs_run.sh
##################################################################################

. /scripts/gtodba.conf
mkdir -p /logs/privs
#Cleanup log files older than 90 days
find /logs/privs/* -mtime +90 -exec rm -f {} \;

#Loop servers
pSQL="SELECT DISTINCT GAME_ID,LOCATION,case when DBTYPE='MariaDB' then 'mysql' else lower(DBTYPE) end FROM dbatools.dbservers where DBTYPE in ('MySQL','MariaDB','MSSQL');"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	pGAMEID=$(echo $pDATA | awk '{print $1}')
	pLOCATION=$(echo $pDATA | awk '{print $2}')
	pDBTYPE=$(echo $pDATA | awk '{print $3}')
	/scripts/monitor/privs/privs_${pDBTYPE}.sh $pGAMEID $pLOCATION > /logs/privs/privs_${pGAMEID}${pLOCATION}${pDBTYPE}.log 2>&1 &
done
