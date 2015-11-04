#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 24-Oct-2014
# This script populates Garena Account uid from into DBATools specific table with Garena Name
# e.g. ./garena_acc_name.sh temp.pbth
# Parameter 1 : [schema].[table]
##################################################################################

pBASEDIR=$(dirname $0)
pPID=$$

# read options from conf file
if [ -f /scripts/gtodba.conf ]
then
  . /scripts/gtodba.conf
else
  echo "[$(date +"%F %T")] Configuration file /scripts/gtodba.conf not found - terminating"
  exit -1
fi

#Check Parameter
if [ $# -lt 1 ]
then
	echo "[$(date +"%F %T")] Schema.Table missing from input arguments - terminating"
	exit -1
else
	pSCHEMA=$(echo $1 | awk -F '.' '{print $1}')
	pTABLE=$(echo $1 | awk -F '.' '{print $2}')
fi

#Get list of columns to update
pSQL="select column_name from information_schema.columns where table_schema = '${pSCHEMA}' and table_name = '${pTABLE}' and
column_name in ('uid');"
pCOL=$(mysql -Ns -u $pDBUSER -p$pDBPASS -e "$pSQL")

if [[ "$pCOL" == "" ]]
then
	echo "[$(date +"%F %T")] There are no updatable columns. uid column not found in $1"
	exit -1
else
	echo "[$(date +"%F %T")] $pCOL will be updated into $1 table based on username column"
fi

#Prepare statement for Garena ACC DB
#a.uid,username
echo "[$(date +"%F %T")] Preparing SQL to fetch uid"
pSQL="select concat('\"',lower(username),'\",') from $pSCHEMA.$pTABLE union select '\"\"';"
mysql -Ns -u $pDBUSER -p$pDBPASS -e "$pSQL" > $pBASEDIR/garena_name_${pPID}.txt

pACCSCHEMA="user_account_db"
echo "USE user_account_db;" > $pBASEDIR/garena_name_get_${pPID}.sql
pSQL="select table_name from information_schema.tables where table_schema = '$pACCSCHEMA' and table_name like 'user_account_tab_%' and table_rows > 0;"
mysql -h 10.10.16.51 -P 6606 -Ns -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	echo "select uid,username from $pACCSHCEMA.$pDATA where lower(username) in (" >> $pBASEDIR/garena_name_get_${pPID}.sql
	cat $pBASEDIR/garena_name_${pPID}.txt >> $pBASEDIR/garena_name_get_${pPID}.sql
	echo ");" >> $pBASEDIR/garena_name_get_${pPID}.sql
done

#Run prepared statement to get Garena Acc data
echo "[$(date +"%F %T")] Fetching uid info from 10.10.16.51:6606"
mysql -h 10.10.16.51 -P 6606 -Ns -u $pDBUSER -p$pDBPASS < $pBASEDIR/garena_name_get_${pPID}.sql > $pBASEDIR/data_${pPID}.tsv

#Populate required data
echo "[$(date +"%F %T")] Updating info into $pSCHEMA.$pTABLE"
pSQL="
CREATE TEMPORARY TABLE temp.garena_acc (uid bigint,username varchar(100) primary key);
LOAD DATA LOCAL INFILE '$pBASEDIR/data_${pPID}.tsv' INTO TABLE temp.garena_acc;
UPDATE $pSCHEMA.$pTABLE a join temp.garena_acc b on lower(a.username)=lower(b.username) set a.uid = b.uid;
"
mysql -Ns -h $pDBHOST -u $pDBUSER -p$pDBPASS -e "$pSQL"


#Cleanup
rm -f $pBASEDIR/garena_name_get_${pPID}.sql $pBASEDIR/garena_name_${pPID}.txt $pBASEDIR/data_${pPID}.tsv

echo "[$(date +"%F %T")] Complete!!"
