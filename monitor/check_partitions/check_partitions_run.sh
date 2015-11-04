#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 17-Dec-2014
# This script runs mysql check partition script concurrently for every region
# e.g. ./dbobjects.sh
##################################################################################

. /scripts/gtodba.conf
mkdir -p /logs/check_partitions
#Cleanup log files older than 90 days
find /logs/check_partitions/* -mtime +90 -exec rm -f {} \;

#Loop servers
#Excluding HoN which has no partitions
pSQL="SELECT DISTINCT GAME_ID,LOCATION,DBTYPE FROM dbatools.dbservers where DBTYPE in ('MySQL','MariaDB') and ACTIVE=1"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	pGAMEID=$(echo $pDATA | awk '{print $1}')
	pLOCATION=$(echo $pDATA | awk '{print $2}')

	/scripts/monitor/check_partitions/check_partitions.sh $pGAMEID $pLOCATION > /logs/check_partitions/check_partitions_${pGAMEID}${pLOCATION}.log 2>&1 &
done
