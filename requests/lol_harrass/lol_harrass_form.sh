#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 6-May-2014
# This script processes Google Form response
# e.g. ./lol_harrass_form.sh
##################################################################################

#Global Variables
pBASEDIR=$(dirname $0)
pPID=$$
pFORMID="15rZF6xo60M-2SPc_3c5RdP2XytQBMqd60Ia94H3LU4k"

#Do not run if already running
if [ -f $pBASEDIR/running-*.pid ]
then
  echo "[$(date +"%F %T")] Process already running - terminating"
  exit 1
else
  echo "[$(date +"%F %T")] Starting Google form response collection"
  touch $pBASEDIR/running-$pPID.pid
fi

#In case program is killed before it ends
trap cleanup INT EXIT
cleanup()
{
        echo "[$(date +"%F %T")] Cleaning up temp files"
        rm -f $pBASEDIR/*-$pPID.*
	echo ""
}

# read options from conf file
if [ -f /scripts/gtodba.conf ]
then
  . /scripts/gtodba.conf
else
  echo "[$(date +"%F %T")] Configuration file /scripts/gtodba.conf not found - terminating"
  exit 1
fi

# Create process file with header
if [ ! -f $pBASEDIR/form-processed.csv ]
then
	echo "Timestamp,User,ScoreCap,Distribution,Region" > $pBASEDIR/form-processed.csv
fi

#Download Google Form response in csv
echo "[$(date +"%F %T")] Downloading google form response"
#Download spreadsheet as csv from google drive
wget --tries=10 https://docs.google.com/spreadsheets/d/${pFORMID}/export?format=csv -O $pBASEDIR/form1-$pPID.csv
cat $pBASEDIR/form1-$pPID.csv | tr -d "\r" > $pBASEDIR/form-$pPID.csv
if [ $? -ne 0 ]; then
	echo "[$(date +"%F %T")] Error downloading google spreadsheet https://docs.google.com/spreadsheets/d/${pFORMID}"
	exit 1
else
	echo "" >> $pBASEDIR/form-$pPID.csv
fi

while read pREQUEST
do        
        #Store Timestamp-UserName
        pTIMESTAMP=$(echo $pREQUEST | awk -F "," '{print $1}')
        pUSER=$(echo $pREQUEST | awk -F "," '{print $2}')
        pSCORECAP=$(echo $pREQUEST | awk -F "," '{print $3}')
        pDISTRI=$(echo $pREQUEST | awk -F "," '{print $4}')
        pREGION=$(echo $pREQUEST | awk -F "," '{print $5}')

	#Do not process first line
	if [ "$pTIMESTAMP" != "Timestamp" ]; then
		#Run only if not run before
		pPROCESSED=$(cat $pBASEDIR/form-processed.csv|grep "$pREQUEST")
		if [ "$pPROCESSED" = "" ]; then
			echo "[$(date +"%F %T")] Running script for request at $pTIMESTAMP by user $pUSER"
			$pBASEDIR/lol_harrass.sh $pSCORECAP $pDISTRI $pUSER $pREGION
			#Store completed processes
		        echo $pREQUEST >> $pBASEDIR/form-processed.csv
		fi
	fi
		
done < $pBASEDIR/form-$pPID.csv

echo "[$(date +"%F %T")] Complete!"
