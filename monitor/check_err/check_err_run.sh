#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 17-Apr-2015
# This script runs mysql error log check script concurrently for every region
# e.g. ./check_err_run
##################################################################################

. /scripts/gtodba.conf
mkdir -p /logs/check_err
#Cleanup log files older than 90 days
find /logs/check_err/* -mtime +90 -exec rm -f {} \;

#Loop servers
pSQL="SELECT DISTINCT GAME_ID,LOCATION FROM dbatools.dbservers where DBTYPE='MySQL'"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	pGAMEID=$(echo $pDATA | awk '{print $1}')
	pLOCATION=$(echo $pDATA | awk '{print $2}')
	/scripts/monitor/check_err/check_err.sh $pGAMEID $pLOCATION day > /logs/check_err/check_err_${pGAMEID}${pLOCATION}.log 2>&1 &
done
