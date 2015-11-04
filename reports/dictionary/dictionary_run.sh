#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 22-Jul-2014
# This script runs mysql dbobjects collection script concurrently for every region
# e.g. ./privs_run.sh
##################################################################################

. /scripts/gtodba.conf
mkdir -p /logs/dictionary
#Cleanup html directories and files older than 2 days
find /var/lib/tomcat7/webapps/ROOT/dictionary/* -mtime +2 -exec rm -Rf {} \;

#Loop servers
pSQL="SELECT DISTINCT GAME_ID,LOCATION FROM dbatools.dbservers where DBTYPE in ('MySQL','MSSQL')"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	pGAMEID=$(echo $pDATA | awk '{print $1}')
	pLOCATION=$(echo $pDATA | awk '{print $2}')
	/scripts/reports/dictionary/dictionary.sh $pGAMEID $pLOCATION > /logs/dictionary/dictionary_${pGAMEID}${pLOCATION}.log 2>&1 &
done
