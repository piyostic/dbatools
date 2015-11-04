#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 11-Jul-2014
# This script processes a list of UIDs from Google Spreadsheet and post results back
# e.g. ./lol_churn_level.sh TH 30 1 5 chanr@garena.com
# Parameter 1 : Region
# Parameter 2 : Churn Days From
# Parameter 3 : Churn Days To
# Parameter 4 : Level From
# Parameter 5 : Level To
# Parameter 6 : User Email
##################################################################################

#Global Variables
pBASEDIR=$(dirname $0)
pPID=$$
pEMAILNAME="Garena GTO DBA"
pEMAILSUBJ="LoL $1 Churn Summoner Level"
pEMAILADMIN="chanr@garena.com"
pWARN="Warning: Using a password on the command line interface can be insecure."

echo "[$(date +"%F %T")] Start collecting $pEMAILSUBJ process id $pPID"

#In case program is killed before it ends
trap cleanup INT EXIT
cleanup()
{
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
        pREGION=${1,,}
fi

#Check parameter 2
if [ $# -lt 2 ]
then
  echo "[$(date +"%F %T")] Churn Days From missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pCHURNFROM=$2
fi

#Check parameter 3
if [ $# -lt 3 ]
then
  echo "[$(date +"%F %T")] Churn Days To missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pCHURNTO=$3
fi

#Check parameter 3
if [ $# -lt 4 ]
then
  echo "[$(date +"%F %T")] Summoner Level From missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pLEVELFROM=$4
fi

#Check parameter 4
if [ $# -lt 5 ]
then
  echo "[$(date +"%F %T")] Summoner Level To missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pLEVELTO=$5
fi

#Check parameter 5
if [ $# -lt 6 ]
then
  echo "[$(date +"%F %T")] Email To missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pEMAILTO=$6
fi

#Get Garena DB hostname and port
pDBGARENASTATS="10.10.16.39"
pDBGARENAPORT=6606
pFILE="$pBASEDIR/data-$pREGION-churn${pCHURNFROM}-${pCHURNTO}-level${pLEVELFROM}-${pLEVELTO}-$pPID"

#Get Data
echo "[$(date +"%F %T")] Getting Churn Level Data from Stats DB $pDBGARENASTATS:$pDBGARENAPORT"
pSQL="select uid,from_unixtime(last_active_time) as last_login_datetime,level 
from stats_lol_db.data_lol_user_info_${pREGION}_tab
where
last_active_time >= unix_timestamp(date_sub(current_date,interval $(($pCHURNTO+1)) day)) and
last_active_time < unix_timestamp(date_sub(current_date,interval $pCHURNFROM day)) and
level between $pLEVELFROM and $pLEVELTO
order by last_active_time desc"
mysql -h $pDBGARENASTATS -P $pDBGARENAPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" 2>$pBASEDIR/err-$pPID-new.log | tr "\t" "," > $pFILE.csv
cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID.log
if [[ -s $pBASEDIR/err-$pPID.log ]]
then
        echo "[$(date +"%F %T")] Error Churn Level Data from Stats DB $pDBGARENASTATS:$pDBGARENAPORT" | tee -a $pBASEDIR/err-$pPID.log
        cat $pBASEDIR/err-$pPID.log
        exit 1
fi

#Compressing data
echo "[$(date +"%F %T")] Compressing Data to $pFILE.zip"
zip -mj $pFILE.zip $pFILE.csv

#Sending data to requester
echo "[$(date +"%F %T")] Sending Data to requester $pEMAILTO"
pMAIL=$(echo -ne "Please refer to the attachment for data requested\n Region : ${pREGION^^}\n Churn : from $pCHURNFROM to $pCHURNTO\n Level : from $pLEVELFROM to $pLEVELTO")
echo "$pMAIL" | mutt -s "$pEMAILSUBJ" -a $pFILE.zip -- $pEMAILTO $pEMAILADMIN

echo "[$(date +"%F %T")] Complete!"
