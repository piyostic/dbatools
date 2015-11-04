#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 23-Jun-2015
# This script runs checksum on Master DB
# e.g. ./checksum.sh 192.168.1.1 #Checksum master and slave(192.168.1.1)
# e.g. ./checksum.sh #Checksum master and all slaves
# Parameter 1 : Slave IP for checksumming. empty means all slaves
##################################################################################
#Define Variables
pBASEDIR=$(dirname $0)
DSN=$1

# read options from conf file
if [ -f $pBASEDIR/checksum.conf ]
then
  . $pBASEDIR/checksum.conf
else
  echo "[$(date +"%F %T")] Configuration file $pBASEDIR/checksum.conf not found - terminating"
  exit -1
fi

#Default pt-table-checksum options
OPT="$DBOPT --nocheck-binlog-format --chunk-time=100 --empty-replicate-table --create-replicate-table --ignore-databases mysql -u $DBUSER -p$DBPASS"

set -e

#DSN OPTION
if [ "$DSN" == "" ]; then
        echo "[$(date +"%F %T")] Not using DSN. Gonna checksum all slaves."
        OPT="$OPT --recursion-method=hosts"
else
        #Prepare dsn table
        echo "[$(date +"%F %T")] Creating percona.dsns entries for $DSN"
        pSQL="CREATE DATABASE IF NOT EXISTS percona;"
        pSQL="$pSQL CREATE TABLE IF NOT EXISTS percona.dsns (id INT(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,parent_id INT(11),dsn VARCHAR(255) NOT NULL);"
        pSQL="$pSQL TRUNCATE TABLE percona.dsns;"
        pSQL="$pSQL INSERT INTO percona.dsns (dsn) values ('h=$DSN,u=$DBUSER,p=$DBPASS');"
        mysql -u $DBUSER -p$DBPASS -e "$pSQL"

        OPT="$OPT --recursion-method dsn=h=localhost,D=percona,t=dsns"
fi

echo "[$(date +"%F %T")] Performing checksum : pt-table-checksum $OPT"
pt-table-checksum $OPT

echo "[$(date +"%F %T")] Complete!"
