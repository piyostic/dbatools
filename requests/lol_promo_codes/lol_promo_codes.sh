#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 14-Aug-2014
# This script processes a list of UIDs from Google Spreadsheet and post results back
# e.g. ./lol_promo_codes.sh TW bundles_123 30 GOPS-123 chanr@garena.com
# Parameter 1 : Region
# Parameter 2 : Bundles ID
# Parameter 3 : Number of promo codes
# Parameter 4 : Jira Ticket
# Parameter 5 : User Email
##################################################################################

#Global Variables
pBASEDIR=$(dirname $0)
pPID=$$
pEMAILNAME="Garena GTO DBA"
pEMAILSUBJ="LoL $1 Promo Codes Insertion"
pEMAILADMIN="chanr@garena.com"
pWARN="Warning: Using a password on the command line interface can be insecure."

echo "[$(date +"%F %T")] Start collecting $pEMAILSUBJ process id $pPID"

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
                cat $pBASEDIR/err-$pPID.log |  mutt -s "$pEMAILSUBJ Error" -- $pEMAILADMIN
        fi

        echo "[$(date +"%F %T")] Cleaning up temp files"
        rm -f $pBASEDIR/*-$pPID*
}

# read options from conf file
if [ -f /scripts/gtodba.conf ]
then
  . /scripts/gtodba.conf
else
  echo "[$(date +"%F %T")] Configuration file /scripts/gtodba.conf not found - terminating"
  exit 1
fi

#Check parameter 1
if [ $# -lt 1 ]
then

  echo "[$(date +"%F %T")] Region missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
        pREGION=$1
fi

#Check parameter 2
if [ $# -lt 2 ]
then
  echo "[$(date +"%F %T")] Bundle ID missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pBUNDLE=$2
fi

#Check parameter 3
if [ $# -lt 3 ]
then
  echo "[$(date +"%F %T")] Number of Promo Codes missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pPROMO=$3
fi

#Check parameter 4
if [ $# -lt 4 ]
then
  echo "[$(date +"%F %T")] Jira Ticket Number missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pJIRA=$4
fi

#Check parameter 5
if [ $# -lt 5 ]
then
  echo "[$(date +"%F %T")] Email To missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pEMAILTO=$5
fi

pFILE="$pBASEDIR/data-LoL${pREGION}-${pBUNDLE}"

#Get Store DB hostname and port
pSQL="SELECT a.IP,a.PORT,b.IP as JUMPIP FROM dbatools.dbservers a left join dbatools.jumphosts b on a.GAME_ID=b.GAME_ID and a.LOCATION=b.LOCATION WHERE a.game_id = 'LoL' and a.location = '$pREGION' and descr like '%Store%' and id_master is null;"
pDBSTORE=$(mysql -Ns -u $pDBUSER -p$pDBPASS -e "$pSQL" 2>/dev/null)
if [[ "$pDBSTORE" == "" ]] ; then
        echo "[$(date +"%F %T")] Error getting Store DB Hostname and port from dbatools" | tee -a $pBASEDIR/err-$pPID.log
        exit 1
else
        pJUMPHOST=$(echo $pDBSTORE | awk '{print $3}')
        pJUMPPORT="6$(echo $pPID | tail -c 4)"
        pIP=$(echo $pDBSTORE | awk '{print $1}')
        pPORT=$(echo $pDBSTORE | awk '{print $2}')
        pUSER=garenapromo
        pPASS="o85F7CBvaV5KH6C72LVa"

       if [[ "$pJUMPHOST" == "NULL" ]]
        then
                #Direct connection
                echo "[$(date +"%F %T")] Connecting directly to $pIP:$pPORT"
                pSQLHOST=$pIP
                pSQLPORT=$pPORT
        else
                #Establish ssh tunnel
                echo "[$(date +"%F %T")] Establishing ssh tunnel $pDBUSER@$pJUMPHOST -L $pJUMPPORT:$pIP:$pPORT"
                ssh -f $pDBUSER@$pJUMPHOST -L $pJUMPPORT:$pIP:$pPORT -N
                pKILLSSH=$(ps -ef | grep "ssh -f $pDBUSER@$pJUMPHOST -L $pJUMPPORT:$pIP:$pPORT" | grep -v "grep" | awk -F' ' '{print $2}')
                if [[ "$pKILLSSH" == "" ]]
                then
                        echo "[$(date +"%F %T")] Error establishing ssh tunnel on $pDBUSER@$pJUMPHOST"
                        cleanup
                        exit 1
                fi

                pSQLHOST="127.0.0.1"
                pSQLPORT=$pJUMPPORT
        fi
fi

#Validate bundle id
echo "[$(date +"%F %T")] Validating bundle id $pBUNDLE"
pSQL="select
(select id from lol_store.item where id = '$pBUNDLE') as bundlecreate,
(select count(1) from lol_store.promo_codes where promo_batch_id = '$pBUNDLE') as promocreate;"
pBUNDLECHECK=$(mysql -Ns -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" 2> /dev/null)
pBUNDLECREATED=$(echo "$pBUNDLECHECK" | awk -F '\t' '{print $1}')
pPROMOCOUNT=$(echo "$pBUNDLECHECK" | awk -F '\t' '{print $2}')
pPROMOCOUNT=$(($pPROMO + $pPROMOCOUNT))

if [[ "$pBUNDLECREATED" == "NULL" ]]
then
        pSUCCESS=0
        pSTATUS="[Fail] Invalid Bundle ID $pBUNDLE"
elif [[ $pPROMOCOUNT -gt 200000 ]]
then
        pSUCCESS=0
        pSTATUS="[Fail] There are $(($pPROMOCOUNT - $pPROMO)) Promo Code(s) existing in bundle $pBUNDLE. Max 200,000"
else
        echo "[$(date +"%F %T")] Bundle ID $pBUNDLE found. Created on $pBUNDLECREATED with $pPROMOCOUNT promo codes"

        #Make insert statement
        cat /dev/urandom | tr -dc 'A-Z0-9' | fold -w16 | head -n $pPROMO > $pFILE.csv
        pCODES=$(cat $pFILE.csv | awk -v b="$pBUNDLE" '{print "(\x27" $1 "\x27,\x27" b "\x27,now(),now(),null,1),"}')
        echo "insert into lol_store.promo_codes (id, promo_batch_id, created, modified, account_id, active) values" > $pBASEDIR/promo-$pPID.sql
        echo "$pCODES" >> $pBASEDIR/promo-$pPID.sql
        cat $pBASEDIR/promo-$pPID.sql | sed '$s/.$/;/' > $pBASEDIR/promosql-$pPID.sql
        #Insert Data
        echo "[$(date +"%F %T")] Inserting Promo Code Data into Store DB $pIP:$pPORT"
        mysql -h $pSQLHOST -P $pSQLPORT -u $pUSER -p$pPASS < $pBASEDIR/promosql-$pPID.sql 2>$pBASEDIR/err-$pPID-new.log
        cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID.log
        if [[ -s $pBASEDIR/err-$pPID.log ]]
        then
                echo "[$(date +"%F %T")] Error Inserting Promo Code Data into Store DB $pDBSTOREIP:$pDBSTOREPORT" | tee -a $pBASEDIR/err-$pPID.log
                cat $pBASEDIR/err-$pPID.log
                exit 1
        fi

        pSUCCESS=1
        pSTATUS="[Success] Promo Codes in the attachment inserted"
        #Compressing data
        echo "[$(date +"%F %T")] Compressing Data to $pFILE.zip"
        zip -mj $pFILE.zip $pFILE.csv


fi

echo "[$(date +"%F %T")] Status $pSTATUS"

#Sending data to requester
echo "[$(date +"%F %T")] Sending Result to requester $pEMAILTO"
pMAIL=$(echo -ne "Please refer to the status below for your request\n Region : ${pREGION^^}\n Bundles : ${pBUNDLE}\n Amount : ${pPROMO}\n Jira Ticket : ${pJIRA}\n Status : $pSTATUS")
if [[ "$pSUCCESS" == "1" ]]
then
        echo "$pMAIL" | mutt -s "$pEMAILSUBJ" -a $pFILE.zip -- $pEMAILTO $pEMAILADMIN
else
        echo "$pMAIL" | mutt -s "$pEMAILSUBJ" -- $pEMAILTO $pEMAILADMIN
fi

#Cleanup old data
echo "[$(date +"%F %T")] Cleaning up data files older than 5 days"
find $pBASEDIR/data-*.zip -mtime +5 -exec rm -f {} \;

echo "[$(date +"%F %T")] Complete!"

