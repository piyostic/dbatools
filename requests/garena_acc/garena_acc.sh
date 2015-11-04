#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 18-Aug-2014
# This script populates Garena Account/Profile info into DBATools specific table
# e.g. ./garena_acc.sh temp.pbth
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
pSQL="select group_concat(concat('a.',column_name,'=b.',column_name)) from information_schema.columns where table_schema = '${pSCHEMA}' and table_name = '${pTABLE}' and
column_name in ('regip','acc_country','gender','bday','regdate','username','email','email_v');"
pCOL=$(mysql -Ns -u $pDBUSER -p$pDBPASS -e "$pSQL")

if [[ "$pCOL" == "NULL" ]]
then
	echo "[$(date +"%F %T")] There no updatable columns. At least one these : regip,acc_country,gender,bday,regdate,username,email,email_v info"
	exit -1
else
	echo "[$(date +"%F %T")] $pCOL"
fi

#Prepare statement for Garena ACC DB
#a.uid,regip,acc_country,gender,bday,regdate,username,email,email_v
echo "[$(date +"%F %T")] Preparing SQL to fetch regip,acc_country,gender,bday,regdate,username,email,email_v info"
echo "select
case
when a.uid = b.min_uid and a.uid = b.max_uid THEN
concat('select a.uid,regip,acc_country,gender,bday,regdate,username,email,email_v from user_profile_db.user_profile_tab_',lpad(b.tab,8,'0'),' a join user_account_db.user_account_tab_',lpad(b.tab,8,'0'),' b on a.uid = b.uid where a.uid in (',concat(uid,');'))
when a.uid = b.min_uid THEN
concat('select a.uid,regip,acc_country,gender,bday,regdate,username,email,email_v from user_profile_db.user_profile_tab_',lpad(b.tab,8,'0'),' a join user_account_db.user_account_tab_',lpad(b.tab,8,'0'),' b on a.uid = b.uid where a.uid in (',concat(uid,','))
when a.uid = b.max_uid THEN
concat(uid,');')
else
concat(uid,',')
end as ''
from
(select distinct uid from $pSCHEMA.$pTABLE) a left join
(select min(uid) as min_uid,max(uid) as max_uid, truncate(uid/pow(10,6),0) as tab from $pSCHEMA.$pTABLE group by truncate(uid/pow(10,6),0)) b
on
truncate(uid/pow(10,6),0) = b.tab
order by uid;" > $pBASEDIR/garena_acc_${pPID}.sql
mysql -Ns -u $pDBUSER -p$pDBPASS < $pBASEDIR/garena_acc_${pPID}.sql > $pBASEDIR/garena_acc_get_${pPID}.sql

#Run prepared statement to get Garena Acc data
echo "[$(date +"%F %T")] Fetching regip,acc_country,gender,bday,regdate,username,email,email_v info from 10.10.16.51:6606"
mysql -h 10.10.16.51 -P 6606 -Ns -u $pDBUSER -p$pDBPASS < $pBASEDIR/garena_acc_get_${pPID}.sql > $pBASEDIR/data_${pPID}.tsv

#Populate required data
echo "[$(date +"%F %T")] Updating info into $pSCHEMA.$pTABLE"
pSQL="
CREATE TEMPORARY TABLE temp.garena_acc (uid bigint primary key,regip char(15),acc_country char(2),gender tinyint(1),bday date,regdate integer,username char(20),email varchar(50),email_v tinyint(1));
LOAD DATA LOCAL INFILE '$pBASEDIR/data_${pPID}.tsv' INTO TABLE temp.garena_acc;
UPDATE $pSCHEMA.$pTABLE a join temp.garena_acc b on a.uid=b.uid set $pCOL;
"
mysql -Ns -h $pDBHOST -u $pDBUSER -p$pDBPASS -e "$pSQL"


#Cleanup
rm -f $pBASEDIR/garena_acc_get_${pPID}.sql $pBASEDIR/garena_acc_${pPID}.sql $pBASEDIR/data_${pPID}.tsv

echo "[$(date +"%F %T")] Complete!!"
