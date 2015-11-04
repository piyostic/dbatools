#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 17-Mar-2014
# This script checks processlist and inserts into monitor DB
# e.g. ./processes.sh LoL VN
# Parameter 1 : Game ID
# Parameter 2 : Location
##################################################################################


#Define Variables
pBASEDIR=$(dirname $0)
pPID=$$
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="MySQL Processlist Collection"
pWARN="Warning: Using a password on the command line interface can be insecure."

#In case program is killed before it ends
trap cleanup INT EXIT
cleanup()
{
        #Kill tunnel if established
        if [[ "$pKILLSSH" != ""  ]]; then
                echo "[$(date +"%F %T")] Killing ssh tunnel process $pKILLSSH"
                kill -9 $pKILLSSH
        fi

        echo "[$(date +"%F %T")] Checking for errors"
        if [[ -s $pBASEDIR/err-$pPID.log ]]; then
                cat $pBASEDIR/err-$pPID.log |  mutt -s "$pEMAILSUBJ Error" -- $pEMAILTO $pEMAILADMIN
        fi

        echo "[$(date +"%F %T")] Cleaning up temp files"
        rm -f $pBASEDIR/err-ssh-$pPID.log

        echo ""
}

if [ $# -lt 1 ]
then
  echo "[$(date +"%F %T")] Game ID missing from input arguments - terminating"
  exit -1
else
  pGAMEID=$1
fi  

if [ $# -lt 2 ]
then
  echo "[$(date +"%F %T")] Location missing from input arguments - terminating"
  exit -1
else
  pLOCATION=$2
fi

#Do not run if already running
#This is to prevent bottlenecks when network is having problems
if [ -f $pBASEDIR/processes-*-$pGAMEID$pLOCATION.tsv ]
then
  echo "[$(date +"%F %T")] Process already running - terminating"
  exit 1
else
  echo "[$(date +"%F %T")] Starting $pEMAILSUBJ Process ID $pPID"
  touch $pBASEDIR/processes-$pPID-$pGAMEID$pLOCATION.tsv
fi

# read options from conf file
if [ -f /scripts/gtodba.conf ]
then
  . /scripts/gtodba.conf
else
  echo "[$(date +"%F %T")] Configuration file /scripts/gtodba.conf not found - terminating"
  exit -1
fi

#Check if monitor DB is alive
pERR=$(mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "SELECT 1 FROM dual WHERE 1=0" 2>&1 | grep -v "$pWARN")
#Check if the script returned errors
if [[ "$pERR" != "" ]] ; then
	echo "[$(date +"%F %T")] Error Connecting to dbatools DB $pDBHOST:$pDBPORT"
	echo "[$(date +"%F %T")] $pERR"
	rm -f $pBASEDIR/processes-$pPID-$pGAMEID$pLOCATION.tsv
	exit -1
fi

#Get an open port. Retry 4 times
for i in {1..5}
do
        echo "[$(date +"%F %T")] Getting random port $i of 5 tries"
        pJUMPPORT=$((RANDOM%65535+1))
        pTESTPORT=$(nc 127.0.0.1 $pJUMPPORT < /dev/null > /dev/null ; echo $?)
        if [[ "$pTESTPORT" == "1" ]] ; then
                echo "[$(date +"%F %T")] Random open port $pJUMPPORT. Tried $i times"
                break
        else
                if [[ "$i" == "5" ]] ; then
                        echo "[$(date +"%F %T")] Error getting random port"
			rm -f $pBASEDIR/processes-$pPID-$pGAMEID$pLOCATION.tsv
                        exit -1
                fi
        fi
done
echo ""

#Loop servers
pSQL="SELECT a.IP,a.PORT,CONCAT(a.GAME_ID,'@',a.LOCATION,'-',a.DESCR,':',a.DBUSAGE),b.IP,a.ID 
FROM dbatools.dbservers a
left join dbatools.jumphosts b on a.GAME_ID=b.GAME_ID and a.LOCATION=b.LOCATION
WHERE a.GAME_ID = '$pGAMEID' AND a.LOCATION = '$pLOCATION' and a.DBTYPE in ('MySQL','MariaDB') ORDER BY a.IP;"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" 2> /dev/null | \
while read pDATA
do
	#Read data from table
	pIP=$(echo -e "$pDATA" | awk -F'\t' '{print $1}')
	pPORT=$(echo -e "$pDATA" | awk -F'\t' '{print $2}')
	pNAME=$(echo -e "$pDATA" | awk -F'\t' '{print $3}')
	pJUMPHOST=$(echo -e "$pDATA" | awk -F'\t' '{print $4}')
	pSERVERID=$(echo -e "$pDATA" | awk -F'\t' '{print $5}')
	
	#Process data
	echo "[$(date +"%F %T")] Processing $pNAME-$pIP:$pPORT"
	if [[ "$pJUMPHOST" == "NULL" ]]
        then
		#Direct connection
		echo "[$(date +"%F %T")] Connecting directly to $pIP:$pPORT"
		pSQLHOST=$pIP
		pSQLPORT=$pPORT
	else
		#Establish ssh tunnel
        	echo "[$(date +"%F %T")] Establishing ssh tunnel $pDBUSER@$pJUMPHOST -L $pJUMPPORT:$pIP:$pPORT"
        	ssh -f $pDBUSER@$pJUMPHOST -L $pJUMPPORT:$pIP:$pPORT -N 2> $pBASEDIR/err-ssh-$pPID.log
        	pKILLSSH=$(ps -ef | grep "ssh -f $pDBUSER@$pJUMPHOST -L $pJUMPPORT:$pIP:$pPORT" | grep -v "grep" | awk -F' ' '{print $2}')
       		if [[ -s $pBASEDIR/err-ssh-$pPID.log ]]
        	then
                	echo "[$(date +"%F %T")] Error establishing ssh tunnel on $pDBUSER@$pJUMPHOST"
			cat $pBASEDIR/err-ssh-$pPID.log
			cleanup
                	continue
        	fi

		pSQLHOST="127.0.0.1"
		pSQLPORT=$pJUMPPORT
	fi
	pSQLCHECK="select $pSERVERID,user,substring_index(host,':',1),count(1) from information_schema.processlist group by user,substring_index(host,':',1)"
	mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLCHECK" 2> /dev/null 1>>$pBASEDIR/processes-$pPID-$pGAMEID$pLOCATION.tsv

	#Report number of connections
	pTOTALCONN=$(cat $pBASEDIR/processes-$pPID-$pGAMEID$pLOCATION.tsv | grep -e "^$pSERVERID[[:space:]]" | awk -F'\t' '{print $NF}' | paste -sd+ | bc)
	pUSERCONN=$(cat $pBASEDIR/processes-$pPID-$pGAMEID$pLOCATION.tsv | grep -e "^$pSERVERID[[:space:]]" | wc -l)
	echo "[$(date +"%F %T")] There are $pUSERCONN user(s) connected with total $pTOTALCONN connection(s)"
	
	cleanup
done

echo "[$(date +"%F %T")] Loading $pBASEDIR/processes-$pPID-$pGAMEID$pLOCATION.tsv"
#Temp table to store collected data
pSQL="CREATE TEMPORARY TABLE tmp_processes like processes;"
pSQL="$pSQL LOAD DATA LOCAL INFILE '$pBASEDIR/processes-$pPID-$pGAMEID$pLOCATION.tsv' into table tmp_processes(DBSERVER_ID,USER_NAME,USER_HOST,SESSION_COUNT) SET OS_PROCESS_ID=$pPID;"
#For existing records
pSQL="$pSQL UPDATE processes p, tmp_processes t SET p.SESSION_COUNT=t.SESSION_COUNT,p.OS_PROCESS_ID=$pPID WHERE p.DBSERVER_ID=t.DBSERVER_ID and p.USER_NAME=t.USER_NAME and p.USER_HOST=t.USER_HOST;"
#For new records
pSQL="$pSQL INSERT IGNORE INTO processes(DBSERVER_ID,USER_NAME,USER_HOST,SESSION_COUNT,OS_PROCESS_ID,CREATION_DATE) select DBSERVER_ID,USER_NAME,USER_HOST,SESSION_COUNT,OS_PROCESS_ID,sysdate() from tmp_processes;"
#For obsolete records
pSQL="$pSQL DELETE FROM processes WHERE OS_PROCESS_ID <> $pPID and DBSERVER_ID in (select id from dbservers where GAME_ID = '$pGAMEID' AND LOCATION = '$pLOCATION');"
mysql -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL; show warnings;" dbatools

echo "[$(date +"%F %T")] Removing script $pBASEDIR/processes-$pPID-$pGAMEID$pLOCATION.tsv"
rm -f $pBASEDIR/processes-$pPID-$pGAMEID$pLOCATION.tsv

echo "[$(date +"%F %T")] COMPLETE!"
