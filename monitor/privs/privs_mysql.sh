#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 17-Mar-2014
# This script checks mysql privileges and inserts into monitor DB
# e.g. ./privs.sh LoL VN
# Parameter 1 : Game ID
# Parameter 2 : Location
##################################################################################


#Define Variables
pBASEDIR=$(dirname $0)
pPID=$$
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="MySQL User Privileges Collection for $1 $2"
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
        rm -f $pBASEDIR/err-*$pPID*.log

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
if [ -f $pBASEDIR/privs-*-$pGAMEID$pLOCATION.tsv ]
then
  echo "[$(date +"%F %T")] Process already running - terminating"
  exit 1
else
  echo "[$(date +"%F %T")] Starting $pEMAILSUBJ Process ID $pPID"
  touch $pBASEDIR/privs-$pPID-$pGAMEID$pLOCATION.tsv
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
	rm -f $pBASEDIR/privs-$pPID-$pGAMEID$pLOCATION.tsv
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
                        echo "[$(date +"%F %T")] Error getting random port" | tee -a $pBASEDIR/err-$pPID.log
                        exit -1
                fi
        fi
done
echo ""

#Loop servers
pSQL="SELECT a.IP,a.PORT,CONCAT(a.GAME_ID,'@',a.LOCATION,'-',a.DESCR,':',a.DBUSAGE),b.IP,a.ID 
FROM dbatools.dbservers a
left join dbatools.jumphosts b on a.GAME_ID=b.GAME_ID and a.LOCATION=b.LOCATION
WHERE a.GAME_ID = '$pGAMEID' AND a.LOCATION = '$pLOCATION' and a.DBTYPE in ('MySQL','MariaDB') and a.ACTIVE = 1 ORDER BY a.IP;"
pDBSERVERS=$(mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL")
while read pDATA
do
	#When there r no active servers
	if [ "$pDATA" == "" ]; then
		echo "[$(date +"%F %T")] No active servers for $pGAMEID $pLOCATION to process"
		continue
	fi
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
			cat $pBASEDIR/err-ssh-$pPID.log | tee -a $pBASEDIR/err-$pPID.log
			pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                        cleanup
                        continue
                fi

                pSQLHOST="127.0.0.1"
                pSQLPORT=$pJUMPPORT
        fi
	echo "[$(date +"%F %T")] Collecting privileges"	
	pSQLCHECK="select $pSERVERID,user,host,password,max_user_connections from mysql.user"
	mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLCHECK" 2>$pBASEDIR/err-$pPID-new.log 1>$pBASEDIR/privs1-$pPID-$pGAMEID$pLOCATION.tsv
	cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" >> $pBASEDIR/err-$pPID.log
        if [[ -s $pBASEDIR/err-$pPID.log ]]
        then
        	echo "[$(date +"%F %T")] Error Collecting privileges from $pNAME-$pIP:$pPORT" | tee -a $pBASEDIR/err-$pPID.log
		pEXCLUDE="${pEXCLUDE}${pSERVERID},"
        fi

	echo "[$(date +"%F %T")] Collecting privileges with grants"
	cat $pBASEDIR/privs1-$pPID-$pGAMEID$pLOCATION.tsv | awk -F'\t' '{print "SHOW GRANTS FOR '\''"$2"'\''@'\''"$3"'\''\\G"}' > $pBASEDIR/grants-$pPID-$pGAMEID$pLOCATION.sql
	mysql -f -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS < $pBASEDIR/grants-$pPID-$pGAMEID$pLOCATION.sql | grep -v '^\*' | awk -F'Grants for ' '{print $2}' | awk -v var="$pSERVERID" -F': ' '{print var"\t"$1"\t"$2}' > $pBASEDIR/tmpgrants-$pPID-$pGAMEID$pLOCATION.tsv
	cat $pBASEDIR/tmpgrants-$pPID-$pGAMEID$pLOCATION.tsv | awk -F'\t' '{print $2"\t"$3}' | awk -v VAR="$pSERVERID" -F'\t' '{ stuff[$1] = stuff[$1] $2 "; " } END { for( s in stuff ) print VAR "\t" s "\t" stuff[s]; }' >> $pBASEDIR/grants-$pPID-$pGAMEID$pLOCATION.tsv
	cat $pBASEDIR/privs1-$pPID-$pGAMEID$pLOCATION.tsv >> $pBASEDIR/privs-$pPID-$pGAMEID$pLOCATION.tsv

	cleanup
done <<< "$pDBSERVERS"

#Even if db server is down, existing records should not be removed
pEXCLUDE="${pEXCLUDE}0"

echo "[$(date +"%F %T")] Loading $pBASEDIR/privs-$pPID-$pGAMEID$pLOCATION.tsv"
#Temp table to store collected data
pSQL="CREATE TEMPORARY TABLE tmp_privs like privs;"
pSQL="$pSQL LOAD DATA LOCAL INFILE '$pBASEDIR/privs-$pPID-$pGAMEID$pLOCATION.tsv' into table tmp_privs(DBSERVER_ID,USER_NAME,USER_HOST,PASSWORD,MAX_USER_CONNECTIONS,DEFINITION) SET OS_PROCESS_ID=$pPID;"

echo "[$(date +"%F %T")] Loading $pBASEDIR/grants-$pPID-$pGAMEID$pLOCATION.tsv"
#Temp table to store collected data
pSQL="$pSQL CREATE TEMPORARY TABLE tmp_grants (id integer,user varchar(100),definition text);"
pSQL="$pSQL LOAD DATA LOCAL INFILE '$pBASEDIR/grants-$pPID-$pGAMEID$pLOCATION.tsv' into table tmp_grants;"
pSQL="$pSQL UPDATE tmp_privs a join tmp_grants b on a.dbserver_id = b.id and concat(a.user_name,\"@\",a.user_host) = b.user set a.definition = replace(b.definition,'; ',';\n');"

#For existing
pSQL="$pSQL UPDATE privs p, tmp_privs t SET p.PASSWORD=t.PASSWORD,p.MAX_USER_CONNECTIONS=t.MAX_USER_CONNECTIONS,p.DEFINITION=t.DEFINITION,p.OS_PROCESS_ID=$pPID WHERE p.DBSERVER_ID=t.DBSERVER_ID and p.USER_NAME=t.USER_NAME and p.USER_HOST=t.USER_HOST;"
#For new records
pSQL="$pSQL INSERT IGNORE INTO privs(DBSERVER_ID,USER_NAME,USER_HOST,PASSWORD,MAX_USER_CONNECTIONS,DEFINITION,OS_PROCESS_ID) select DBSERVER_ID,USER_NAME,USER_HOST,PASSWORD,MAX_USER_CONNECTIONS,DEFINITION,OS_PROCESS_ID from tmp_privs;"
#For obsolete records
pSQL="$pSQL DELETE FROM privs WHERE OS_PROCESS_ID <> $pPID and DBSERVER_ID in (select id from dbservers where (GAME_ID = '$pGAMEID' AND LOCATION = '$pLOCATION') and ACTIVE >= 1) and DBSERVER_ID NOT IN (${pEXCLUDE});"
mysql -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL; show warnings;" dbatools

echo "[$(date +"%F %T")] Removing script $pBASEDIR/privs-$pPID-$pGAMEID$pLOCATION.tsv"
rm -f $pBASEDIR/*-$pPID-*.tsv $pBASEDIR/*-$pPID-*.sql
pKILLSSH=""

echo "[$(date +"%F %T")] COMPLETE!"
