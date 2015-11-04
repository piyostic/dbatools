#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 29-Apr-2014
# This script processes a list of UIDs from Google Spreadsheet and post results back
# e.g. ./lol_harrass.sh 1300 50 chanr@garena.com
# Parameter 1 : Harrassment Score Cap
# Parameter 2 : Distribution
# Parameter 3 : Requester Email Addr
# Parameter 4 : Region
##################################################################################

#Global Variables
pBASEDIR=$(dirname $0)
pPID=$$
pEMAILNAME="Garena GTO DBA"
pEMAILSUBJ="LoL $4 Harrassment List/Distribution"
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

  echo "[$(date +"%F %T")] Harrassment score cap missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pSCORECAP=$1
fi

#Check parameter 2
if [ $# -lt 2 ]
then
  echo "[$(date +"%F %T")] Distribution missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pDISTRI=$2
fi

#Check parameter 3
if [ $# -lt 3 ]
then
  echo "[$(date +"%F %T")] Email Address missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pEMAILTO=$3
fi

#Check parameter 4
if [ $# -lt 4 ]
then
  echo "[$(date +"%F %T")] Region missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
	pREGION=$4
	# read options from conf file
	if [ "$pREGION" == "PH" ]; then
		pJUMPHOST="203.131.76.25"
		pPLATFORMDBPORT="30134"
		pCSRDBPORT="30134"	
	elif [ "$pREGION" == "SAM" ]; then
                pJUMPHOST="203.116.112.244"
                pPLATFORMDBPORT="3065"
                pCSRDBPORT="3065"
	elif [ "$pREGION" == "TH" ]; then
                pJUMPHOST="112.121.158.29"
                pPLATFORMDBPORT="3032"
                pCSRDBPORT="3049"
        elif [ "$pREGION" == "TW" ]; then
                pJUMPHOST="112.121.88.244"
                pPLATFORMDBPORT="3031"
                pCSRDBPORT="3069"
	elif [ "$pREGION" == "ID" ]; then
                pJUMPHOST="103.248.57.24"
                pPLATFORMDBPORT="10051"
                pCSRDBPORT="10054"
	else
		echo "[$(date +"%F %T")] Region $pREGION not supported - terminating" | tee $pBASEDIR/err-$pPID.log
		exit -1
	fi
fi

#Get Harrassment List
if [ "$pPLATFORMDBPORT" == "$pCSRDBPORT" ]
then
	echo "[$(date +"%F %T")] Writing Harrassment list script"
	echo "select a.acct_id as uid,b.harassment_score from platform_server.summoner as a join csr_server.community_stigma as b on a.sum_id = b.summoner_id where b.harassment_score >= $pSCORECAP;" > $pBASEDIR/script-$pPID.sql
else
	echo "[$(date +"%F %T")] Getting Harrassment score by summoner id from csr DB $pJUMPHOST-$pCSRDBPORT"
	pSQL="select concat('select ',summoner_id,' as sum_id,',harassment_score,' as harrassment_score UNION') from csr_server.community_stigma where harassment_score >= $pSCORECAP UNION select 'select 0,0';"
	pSUMMONER=$(mysql -Ns -h $pJUMPHOST -P $pCSRDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL")
	
	echo "select a.acct_id as uid,harrassment_score from platform_server.summoner as a, ($pSUMMONER) b where a.sum_id = b.sum_id;" > $pBASEDIR/script-$pPID.sql
fi
echo "[$(date +"%F %T")] Getting Harrassment list from platform DB $pJUMPHOST-$pPLATFORMDBPORT"
mysql -h $pJUMPHOST -P $pPLATFORMDBPORT -u $pDBUSER -p$pDBPASS < $pBASEDIR/script-$pPID.sql 2>$pBASEDIR/err-$pPID-new.log | tr "\t" "," > $pBASEDIR/data-$pREGION-$pPID-harrass.csv
cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID.log
if [[ -s $pBASEDIR/err-$pPID.log ]]
then
        echo "[$(date +"%F %T")] Error getting Harrassment List from platform DB $pJUMPHOST-$pPLATFORMDBPORT" | tee -a $pBASEDIR/err-$pPID.log
        cat $pBASEDIR/err-$pPID.log
        exit 1
fi


#Get Harrassment Distribution
echo "[$(date +"%F %T")] Getting Harrassment Distribution from csr DB $pJUMPHOST-$pCSRDBPORT"
pSQL="select floor(harassment_score/$pDISTRI)*$pDISTRI h_score_bucket, count(*) count_uid from csr_server.community_stigma group by floor(harassment_score/$pDISTRI)*$pDISTRI order by h_score_bucket;"
mysql -h $pJUMPHOST -P $pCSRDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" 2>$pBASEDIR/err-$pPID-new.log | tr "\t" "," > $pBASEDIR/data-$pREGION-$pPID-harrass-distri.csv
cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID.log
if [[ -s $pBASEDIR/err-$pPID.log ]]
then
        echo "[$(date +"%F %T")] Error getting Harrassment Distribution from $pJUMPHOST-$pCSRDBPORT" | tee -a $pBASEDIR/err-$pPID.log
        cat $pBASEDIR/err-$pPID.log
        exit 1
fi


#Get Snitch Distribution
echo "[$(date +"%F %T")] Getting Snitch Distribution from csr DB $pJUMPHOST-$pCSRDBPORT"
pSQL="select floor(snitch_score/$pDISTRI)*$pDISTRI s_score_bucket, count(*) count_uid from csr_server.community_stigma group by floor(snitch_score/$pDISTRI)*$pDISTRI order by s_score_bucket;"
mysql -h $pJUMPHOST -P $pCSRDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" 2>$pBASEDIR/err-$pPID-new.log | tr "\t" "," > $pBASEDIR/data-$pREGION-$pPID-snitch-distri.csv
cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID.log
if [[ -s $pBASEDIR/err-$pPID.log ]]
then
        echo "[$(date +"%F %T")] Error getting Snitch Distribution from $pJUMPHOST-$pCSRDBPORT" | tee -a $pBASEDIR/err-$pPID.log
        cat $pBASEDIR/err-$pPID.log
        exit 1
fi

#Compressing data
filename="$pBASEDIR/data-$(echo $pEMAILTO | awk -F '@' '{print $1}')-$pREGION-$(date +%Y%m%d%H%M%S)"
echo "[$(date +"%F %T")] Compressing Data to $filename.zip"
zip -mj $filename.zip $pBASEDIR/data-$pREGION-$pPID-harrass.csv $pBASEDIR/data-$pREGION-$pPID-harrass-distri.csv $pBASEDIR/data-$pREGION-$pPID-snitch-distri.csv

#Sending data to requester
echo "[$(date +"%F %T")] Sending Data to requester $pEMAILTO"
pMAIL=$(echo -ne "Please refer to the attachment for data requested\n Score Cap : $pSCORECAP\n Distribution : $pDISTRI")
echo "$pMAIL" | mutt -s "$pEMAILSUBJ" -a $filename.zip -- $pEMAILTO $pEMAILADMIN

#Cleanup old data
echo "[$(date +"%F %T")] Cleaning up data files older than 5 days"
find $pBASEDIR/data-*.zip -mtime +5 -exec rm -f {} \;

echo "[$(date +"%F %T")] Complete!"
