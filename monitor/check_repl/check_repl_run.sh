#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 17-Apr-2015
# This script runs MySQL and MSSQL replication check script concurrently for every region
# e.g. ./check_repl_run.sh
##################################################################################

. /scripts/gtodba.conf
mkdir -p /logs/check_repl
#Cleanup log files older than 90 days
find /logs/check_repl/* -mtime +90 -exec rm -f {} \;

#Loop servers
pSQL="SELECT DISTINCT GAME_ID,DBTYPE FROM dbatools.dbservers where DBTYPE in ('MySQL','MSSQL','MariaDB') and ID_MASTER is not null"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	pGAMEID=$(echo $pDATA | awk '{print $1}')
	pDBTYPE=$(echo $pDATA | awk '{print $2}')

	if [[ "$pDBTYPE" == "MySQL" ]]
	then
		/scripts/monitor/check_repl/check_repl.sh $pGAMEID > /logs/check_repl/check_repl_${pGAMEID}.log 2>&1 &
	elif [[ "$pDBTYPE" == "MariaDB" ]]
        then
                /scripts/monitor/check_repl/check_repl_mariadb.sh $pGAMEID > /logs/check_repl/check_repl_mariadb_${pGAMEID}.log 2>&1 &
	else
		/scripts/monitor/check_repl/check_repl_mssql.sh $pGAMEID > /logs/check_repl/check_repl_${pGAMEID}.log 2>&1 &
	fi
done
