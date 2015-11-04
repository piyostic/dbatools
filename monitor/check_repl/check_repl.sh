#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 20-Feb-2014
# This script checks replication slave status
# e.g. ./check_repl.sh LoL
# Parameter 1 : Game ID
##################################################################################

#Define Variables
pBASEDIR=$(dirname $0)
pPID=$$
pCONF=/scripts/gtodba.conf
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="MySQL Replication Healthcheck"
pREPLMAXLAG=18000
pREG='^[0-9]+$'
pWARN="Warning: Using a password on the command line interface can be insecure."

echo "[$(date +"%F %T")] Starting $pEMAILSUBJ"

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

#Loop slaves
pSQL="SELECT a.IP,a.PORT,CONCAT(a.GAME_ID,'@',a.LOCATION,'-',a.DESCR,':',a.DBUSAGE),b.IP as JUMPIP,c.EMAIL_TO,a.ID_MASTER
FROM dbatools.dbservers a left join dbatools.jumphosts b on a.GAME_ID=b.GAME_ID and a.LOCATION=b.LOCATION
left join dbatools.Contacts c on a.contact_id = c.id
WHERE (a.GAME_ID = '$pGAMEID' OR a.LOCATION = '$pGAMEID') and 
a.ID_MASTER is not null and a.DBTYPE = 'MySQL' and a.ACTIVE=1  
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
	pMASTERID=$(echo -e "$pDATA" | awk -F'\t' '{print $6}')
	pMASTERIP=$(mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "SELECT IP from dbatools.dbservers where ID=${pMASTERID}" 2>/dev/null)

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
                        echo "[$(date +"%F %T")] Error establishing ssh tunnel on $pDBUSER@$pJUMPHOST for $pNAME-$pIP:$pPORT" | tee $pBASEDIR/err-$pPID.log
			cat $pBASEDIR/err-ssh-$pPID.log | tee -a $pBASEDIR/err-$pPID.log
                        cleanup
                        continue
                fi

                pSQLHOST="127.0.0.1"
                pSQLPORT=$pJUMPPORT
        fi

        pSQLCHECK="SHOW SLAVE STATUS\G"
        mysql -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLCHECK" > $pBASEDIR/err-$pPID-$pIP$pPORT.log 2>&1

        pSLAVESEC=$(cat $pBASEDIR/err-$pPID-$pIP$pPORT.log | grep "Seconds_Behind_Master" | awk -F': ' '{print $2}')
        #Replication not running. Seconds behind master not a number
        if ! [[ $pSLAVESEC =~ $pREG ]] ; then
                echo "[$(date +"%F %T")] Replication Errors for $pNAME-$pIP:$pPORT" | tee $pBASEDIR/err-$pPID.log
                cat $pBASEDIR/err-$pPID-$pIP$pPORT.log | tee -a $pBASEDIR/err-$pPID.log
        else
                #Check seconds behind master
                if [[ $pSLAVESEC -ge $pREPLMAXLAG ]] ; then
                        echo "[$(date +"%F %T")] Replication Lag for $pNAME-$pIP:$pPORT more than $pREPLMAXLAG seconds" | tee $pBASEDIR/err-$pPID.log
                        cat $pBASEDIR/err-$pPID-$pIP$pPORT.log | tee -a $pBASEDIR/err-$pPID.log
                else
                        echo "[$(date +"%F %T")] Replication up and $pSLAVESEC second(s) behind master"
                fi

		#Check if slave is replicating from expected master
        	#pMASTERHOST=$(cat $pBASEDIR/err-$pPID-$pIP$pPORT.log | grep "Master_Host" | awk -F': ' '{print $2}')
        	#if ! [[ "$pMASTERIP" == "$pMASTERHOST" ]] ; then
                #	echo "[$(date +"%F %T")] Warning for $pNAME-$pIP:$pPORT" | tee -a $pBASEDIR/err-$pPID.log
                #	echo "Master configured as $pMASTERIP but replicating from $pMASTERHOST" | tee -a $pBASEDIR/err-$pPID.log
        	#fi
        fi
	
        cleanup
done

echo ""
echo "[$(date +"%F %T")] COMPLETE!"
