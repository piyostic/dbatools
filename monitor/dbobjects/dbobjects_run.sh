#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 22-Jul-2014
# This script runs mysql dbobjects collection script concurrently for every region
# e.g. ./dbobjects.sh
##################################################################################

. /scripts/gtodba.conf
mkdir -p /logs/dbobjects
#Cleanup log files older than 90 days
find /logs/dbobjects/* -mtime +90 -exec rm -f {} \;

#Loop servers
pSQL="SELECT DISTINCT GAME_ID,LOCATION,DBTYPE FROM dbatools.dbservers where DBTYPE in ('MySQL','MSSQL','MariaDB')"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	pGAMEID=$(echo $pDATA | awk '{print $1}')
	pLOCATION=$(echo $pDATA | awk '{print $2}')
	pDBTYPE=$(echo $pDATA | awk '{print $3}')

	if [[ "$pDBTYPE" == "MSSQL" ]]
	then
		/scripts/monitor/dbobjects/dbobjects_mssql.sh $pGAMEID $pLOCATION > /logs/dbobjects/dbobjects_${pGAMEID}${pLOCATION}.log 2>&1 &
	else
		/scripts/monitor/dbobjects/dbobjects.sh $pGAMEID $pLOCATION > /logs/dbobjects/dbobjects_${pGAMEID}${pLOCATION}.log 2>&1 &
	fi
done
