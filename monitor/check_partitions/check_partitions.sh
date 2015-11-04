#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 17-Dec-2014
# This script checks RANGE partitions and ensure future partitions exist
# e.g. ./check_partitions.sh LoL ID
# Parameter 1 : Game ID
# Parameter 2 : Location
##################################################################################

#Define Variables
pBASEDIR=$(dirname $0)
pPID=$$
pCONF=/scripts/gtodba.conf
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="MySQL Partition Healthcheck"
pWARN="Warning: Using a password on the command line interface can be insecure."
pEXCLUDE="'_transaction_syncs_old','_transactions_old','_transactions_syncs_old','league_audit_new','league_audit_archive_season3','archive_season4_league_audit','transactions_old'"

echo "[$(date +"%F %T")] Starting $pEMAILSUBJ"
echo "[$(date +"%F %T")] Checks RANGE partition excluding tables $pEXCLUDE"

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
        rm -f $pBASEDIR/*-$pPID*

        echo ""
}

if [ $# -lt 1 ]
then
  echo "[$(date +"%F %T")] Game ID missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pGAMEID=$1
fi

if [ $# -lt 2 ]
then
  echo "[$(date +"%F %T")] Location missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pLOCATION=$2
fi

# read options from conf file
if [ -f $pCONF ]
then
  . $pCONF
else
  echo "[$(date +"%F %T")] Configuration file $pCONF not found - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
fi

#Check if monitor DB is alive
pERR=$(mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "SELECT now() FROM dual WHERE 1=0" 2>&1 | grep -v "$pWARN")
#Check if the script returned errors
if [[ "$pERR" != "" ]] ; then
        echo "[$(date +"%F %T")] Error Connecting to DBA Tools DB $pDBHOST:$pDBPORT" | tee $pBASEDIR/err-$pPID.log
        echo "[$(date +"%F %T")] $pERR"
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

#Loop all MySQL servers
pSQL="SELECT a.IP,a.PORT,CONCAT(a.GAME_ID,'@',a.LOCATION,'-',a.DESCR,':',a.DBUSAGE),b.IP as JUMPIP,c.EMAIL_TO
FROM dbatools.dbservers a left join dbatools.jumphosts b on a.GAME_ID=b.GAME_ID and a.LOCATION=b.LOCATION
left join dbatools.Contacts c on a.contact_id = c.id
WHERE a.GAME_ID = '$pGAMEID' AND a.LOCATION = '$pLOCATION' and 
a.DBTYPE in ('MySQL','MariaDB') and a.ACTIVE=1  
ORDER BY a.IP;"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
        #Read data from table
        pIP=$(echo -e "$pDATA" | awk -F'\t' '{print $1}')
        pPORT=$(echo -e "$pDATA" | awk -F'\t' '{print $2}')
        pNAME=$(echo -e "$pDATA" | awk -F'\t' '{print $3}')
	pJUMPHOST=$(echo -e "$pDATA" | awk -F'\t' '{print $4}')
	pEMAILTO=$(echo -e "$pDATA" | awk -F'\t' '{print $5}')

        #Process data
        echo "[$(date +"%F %T")] $pNAME-$pIP:$pPORT"

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
                        echo "[$(date +"%F %T")] Error establishing ssh tunnel on $pDBUSER@$pJUMPHOST for $pNAME-$pIP:$pPORT" | tee -a $pBASEDIR/err-$pPID.log
			cat $pBASEDIR/err-ssh-$pPID.log | tee -a $pBASEDIR/err-$pPID.log
                        cleanup
                        continue
                fi

                pSQLHOST="127.0.0.1"
                pSQLPORT=$pJUMPPORT
        fi

	#Check tables with max partitions less than tomorrow
        pSQLCHECK="select
	table_schema,table_name,partition_expression,max(partition_description) as last_partition_desc,
	CASE 
	WHEN partition_expression like 'UNIX_TIMESTAMP%' THEN from_unixtime(max(partition_description))
	WHEN partition_expression like 'TO_DAYS%' THEN from_days(max(partition_description)) end as last_partition_date
	from information_schema.partitions 
	where 
	table_schema not in ('information_schema','performance_schema','mysql','test') and
	partition_name is not null and
	partition_method = 'RANGE' and
	table_name not in ($pEXCLUDE)
	group by table_name,partition_expression
	having max(partition_description) <> 'MAXVALUE' and
	CASE 
	WHEN partition_expression like 'UNIX_TIMESTAMP%' THEN from_unixtime(max(partition_description))
	WHEN partition_expression like 'TO_DAYS%' THEN from_days(max(partition_description)) end
	<= date_add(current_date,interval 1 day)\G"
        mysql -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLCHECK" 1> $pBASEDIR/data-$pPID-$pIP$pPORT.log 2> $pBASEDIR/err-$pPID-$pIP$pPORT.log
        #Error getting partition info
        if [[ -s $(cat $pBASEDIR/err-$pPID-$pIP$pPORT.log | grep -v "$pWARN") ]] ; then
                echo "[$(date +"%F %T")] $pNAME-$pIP:$pPORT Error getting partition info" | tee $pBASEDIR/err-$pPID.log
                cat $pBASEDIR/err-$pPID-$pIP$pPORT.log | tee -a $pBASEDIR/err-$pPID.log
        else
                #Tables without future partitions exist
                if [[ -s $pBASEDIR/data-$pPID-$pIP$pPORT.log ]] ; then
                        echo "[$(date +"%F %T")] $pNAME-$pIP:$pPORT No future(values less than tomorrow) partitions" | tee $pBASEDIR/err-$pPID.log
                        cat $pBASEDIR/data-$pPID-$pIP$pPORT.log | tee -a $pBASEDIR/err-$pPID.log
                else
                        echo "[$(date +"%F %T")] Looks good!"
                fi
        fi
	
        cleanup
done

echo ""
echo "[$(date +"%F %T")] COMPLETE!"
