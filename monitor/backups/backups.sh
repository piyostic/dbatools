#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 21-Aug-2014
# This script checks backups and inserts into dbatools
# Public key of this server has to be added to remote host first
# e.g. ./backups.sh LoL VN
# Parameter 1 : Game ID
# Parameter 2 : Location
##################################################################################


#Define Variables
pBASEDIR=$(dirname $0)
pPID=$$
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="MySQL Backups Check for $1"
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
		echo "[$(date +"%F %T")] Sending error email to $pEMAILTO $pEMAILADMIN"
                cat $pBASEDIR/err-$pPID.log |  mutt -s "$pEMAILSUBJ Error" -- $pEMAILTO $pEMAILADMIN
	else
		echo "[$(date +"%F %T")] No errors found"
        fi

	echo "[$(date +"%F %T")] Cleaning up temp files"
        rm -f $pBASEDIR/*-$pPID*.log

        echo ""
}

if [ $# -lt 1 ]
then
  echo "[$(date +"%F %T")] Game ID missing from input arguments - terminating" | tee -a $pBASEDIR/err-$pPID.log
  exit -1
else
  pGAMEID=$1
fi  

if [ $# -lt 2 ]
then
  echo "[$(date +"%F %T")] Location missing from input arguments - terminating" | tee -a $pBASEDIR/err-$pPID.log
  exit -1
else
  pLOCATION=$2
fi

# read options from conf file
if [ -f /scripts/gtodba.conf ]
then
  . /scripts/gtodba.conf
else
  echo "[$(date +"%F %T")] Configuration file /scripts/gtodba.conf not found - terminating" | tee -a $pBASEDIR/err-$pPID.log
  exit -1
fi

#Check if monitor DB is alive
pERR=$(mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "SELECT 1 FROM dual WHERE 1=0" 2>&1 | grep -v "$pWARN")
#Check if the script returned errors
if [[ "$pERR" != "" ]] ; then
	echo "[$(date +"%F %T")] Error Connecting to dbatools DB $pDBHOST:$pDBPORT" | tee -a $pBASEDIR/err-$pPID.log
	echo "[$(date +"%F %T")] $pERR" | tee -a $pBASEDIR/err-$pPID.log
	rm -f $pBASEDIR/backups-$pPID-$pGAMEID$pLOCATION.tsv
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
pSQL="SELECT a.IP,CONCAT(a.GAME_ID,'@',a.LOCATION,'-',a.DESCR,':',a.DBUSAGE),b.IP,min(a.ID),c.EMAIL_TO
FROM dbatools.dbservers a
left join dbatools.jumphosts b on a.GAME_ID=b.GAME_ID and a.LOCATION=b.LOCATION
left join dbatools.Contacts c on a.contact_id = c.id
WHERE a.GAME_ID = '$pGAMEID' AND a.LOCATION = '$pLOCATION' and dbusage like '%bkp%' and a.DBTYPE in ('MySQL','MariaDB') and a.ACTIVE=1 GROUP BY a.IP;"
pBACKUPLOOP=$(mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL")
while read pDATA
do
	#Read data from table
	pIP=$(echo -e "$pDATA" | awk -F'\t' '{print $1}')
	pPORT=22
	pNAME=$(echo -e "$pDATA" | awk -F'\t' '{print $2}')
	pJUMPHOST=$(echo -e "$pDATA" | awk -F'\t' '{print $3}')
	pSERVERID=$(echo -e "$pDATA" | awk -F'\t' '{print $4}')
	#pEMAILTO=$(echo -e "$pDATA" | awk -F'\t' '{print $5}')
	pEMAILTO="chanr@garena.com"
	
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
                        echo "[$(date +"%F %T")] Error establishing ssh tunnel on $pDBUSER@$pJUMPHOST" | tee -a $pBASEDIR/err-$pPID.log
			cat $pBASEDIR/err-ssh-$pPID.log | tee -a $pBASEDIR/err-$pPID.log
			pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                        cleanup
                        continue
                fi

                pSQLHOST="127.0.0.1"
                pSQLPORT=$pJUMPPORT
        fi
	echo "[$(date +"%F %T")] Collecting backup info"
	#Get backup status details from remote host
	pSCR='pBKPLOG=$(find / -name "*backup*.log" -mtime -1 2>/dev/null)
	if [[ "$pBKPLOG" == "" ]]; then
		echo ""
	else
		while read pBKP
		do
			pOK=$(cat "$pBKP" | grep ": completed OK" | tail -1)
			if [ "$pOK" == "" ]; then
				pSTATUS1=$(cat "$pBKP" | tail -1)
			else
				pSTATUS1="COMPLETE"
			fi

			if [[ "$pBKPDIR" != "$(dirname $pBKP)" ]]; then
				pBKPDIR=$(dirname $pBKP)
				pFILE1=$(find $pBKPDIR/*.*gz -printf "%p\t%s\t%TY-%Tm-%Td %TH:%TM:%TS\n")
			fi
			pFILE=$(echo -e "$pFILE\n$pFILE1" | grep -v "^$")
			pFILENAME=$(echo "$pFILE1" | tail -1 | awk '\''{print $1}'\'')
			pSTATUS=$(echo -e "$pSTATUS\n$pSTATUS1\t$pFILENAME" | grep -v "^$")
		done <<< "$pBKPLOG"

		echo "pSTATUS=\"$pSTATUS\""
		echo "pFILE=\"$pFILE\""
	fi'
	pBKP=$(ssh -n -o "BatchMode=yes" mysql@$pSQLHOST -p $pSQLPORT "$pSCR" 2> $pBASEDIR/err1-${pPID}.log)
	if [[ -s $pBASEDIR/err-$pPID.log ]]
        then
		cat $pBASEDIR/err1-$pPID.log
                echo "[$(date +"%F %T")] Error Collecting backup info from $pNAME-$pIP"
                pEXCLUDE="${pEXCLUDE}${pSERVERID},"
	else
		#Check backup status
		if [[ "$pBKP" != "" ]]; then
			eval "$pBKP"
			#Stat backup status
			echo "$pSTATUS" | awk -v var1="$pSERVERID" '{print var1"\t"$0}' >> $pBASEDIR/backupstatus-$pPID-$pGAMEID$pLOCATION.tsv
			#Get list of backup compressed files
			while read pTSV
			do
				pDATE=$(echo "$pTSV" | awk -F '\t' '{print $1}')
				pSTART=$(echo "$pDATE" | grep -o '[0-9]\{8\}-[0-9]\{6\}' | sed -e 's/-/ /g' -e 's/^\(.\{11\}\)/\1:/' -e 's/^\(.\{14\}\)/\1:/')
				if [[ "$pSTART" == "" ]]; then
					pSTART="0000-00-00 00:00:00"
				else
					pSTART=$(date -d "$pSTART" +'%F %T')
				fi
				echo "$pTSV" | awk -v var1="$pSERVERID\t$pSTART" '{print var1 "\t" $0}' >> $pBASEDIR/backups-$pPID-$pGAMEID$pLOCATION.tsv
			done <<< "$pFILE"
		fi
        fi

	cleanup
done <<< "$pBACKUPLOOP"

#Even if db server is down, existing records should not be removed
pEXCLUDE="${pEXCLUDE}0"

echo "[$(date +"%F %T")] Loading $pBASEDIR/backups-$pPID-$pGAMEID$pLOCATION.tsv"
#Temp table to store collected data
pSQL="CREATE TEMPORARY TABLE tmp_backups like backups;"
pSQL="$pSQL LOAD DATA LOCAL INFILE '$pBASEDIR/backups-$pPID-$pGAMEID$pLOCATION.tsv' into table tmp_backups(DBSERVER_ID,START,FILE,SIZE,END) SET OS_PROCESS_ID=$pPID;"
#For existing
pSQL="$pSQL UPDATE backups p, tmp_backups t SET p.SIZE=t.SIZE,p.START=t.START,p.END=t.END,p.OS_PROCESS_ID=$pPID WHERE p.DBSERVER_ID=t.DBSERVER_ID and p.FILE=t.FILE;"
#For new records
pSQL="$pSQL INSERT IGNORE INTO backups(DBSERVER_ID,FILE,SIZE,END,START,OS_PROCESS_ID) select DBSERVER_ID,FILE,SIZE,END,START,OS_PROCESS_ID from tmp_backups;"
#For obsolete records
pSQL="$pSQL DELETE FROM backups WHERE OS_PROCESS_ID <> $pPID and DBSERVER_ID in (select ID from dbservers where GAME_ID = '$pGAMEID' AND LOCATION = '$pLOCATION') and DBSERVER_ID NOT IN (${pEXCLUDE});"

#For backup status
pSQL="$pSQL CREATE TEMPORARY TABLE tmp_backupstatus(dbserver_id int,status varchar(100),file varchar(100));"
pSQL="$pSQL LOAD DATA LOCAL INFILE '$pBASEDIR/backupstatus-$pPID-$pGAMEID$pLOCATION.tsv' into table tmp_backupstatus(DBSERVER_ID,STATUS,FILE);"
pSQL="$pSQL UPDATE backups b join tmp_backupstatus s on b.dbserver_id=s.dbserver_id and b.file=s.file set b.status=s.status;"

mysql -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL; show warnings;" dbatools

echo "[$(date +"%F %T")] Removing script $pBASEDIR/backups-$pPID-$pGAMEID$pLOCATION.tsv"
rm -f $pBASEDIR/backups-$pPID-$pGAMEID$pLOCATION.tsv
rm -f $pBASEDIR/backupstatus-$pPID-$pGAMEID$pLOCATION.tsv
pKILLSSH=""

echo "[$(date +"%F %T")] Complete!"
