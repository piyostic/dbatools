#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 29-May-2015
# This script checks for backup failures
# e.g. ./backups_alert.sh
##################################################################################

pBASEDIR=$(dirname $0)
pPID=$$
pCONF=/scripts/gtodba.conf
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="MySQL Backups Failure Alert"
pWARN="Warning: Using a password on the command line interface can be insecure."
pBKPOPTS="active=1 and dbtype in ('MySQL','MariaDB') and dbusage like '%bkp%' and game_id <> 'HoN'"

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

        echo ""
}

# read options from conf file
if [ -f $pCONF ]
then
  . $pCONF
else
  echo "[$(date +"%F %T")] Configuration file $pCONF not found - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
fi

#Loop DBA Contacts
pSQL="select id,name,email_to from dbatools.Contacts
where id in (select distinct contact_id from dbatools.dbservers where $pBKPOPTS );"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	#Read data from table
        pCONTACTID=$(echo -e "$pDATA" | awk -F'\t' '{print $1}')
        pNAME=$(echo -e "$pDATA" | awk -F'\t' '{print $2}')
        #pEMAILTO=$(echo -e "$pDATA" | awk -F'\t' '{print $3}')
	pEMAILTO="chanr@garena.com"
	
	#Failed backups
	pSQL="
	#Failed Backups
	select s.game_id,s.location,s.descr,s.ip,b.file,b.start,b.end,b.status failure_reason
	from backups b
	join dbservers s on b.dbserver_id = s.id
	where start >= date_sub(current_date,interval 1 day) and end < current_date and 
	ifnull(status,'') <> 'COMPLETE' and s.contact_id=$pCONTACTID
	UNION ALL
	#No Backups
	select game_id,location,group_concat(descr),ip,'','','','No backups found yesterday'
	from dbservers
	where
	$pBKPOPTS and contact_id=$pCONTACTID
	group by game_id,location,ip
	having
	min(id) not in (select dbserver_id from backups where start >= date_sub(current_date,interval 1 day) and start < current_date)
	"
	mysql -H -u $pDBUSER -p$pDBPASS -h $pDBHOST -P $pDBPORT -e"$pSQL" dbatools > $pBASEDIR/backups_alert.html  2> $pBASEDIR/err-$pPID-$pCONTACTID.log

	cat $pBASEDIR/err-$pPID-$pCONTACTID.log | grep -v "$pWARN" >> $pBASEDIR/err-$pPID.log
        if [[ -s $pBASEDIR/err-$pPID.log ]]
        then
                echo "[$(date +"%F %T")] Error Collecting backup records for $pNAME-$pEMAILTO" | tee $pBASEDIR/err-$pPID.log
                continue
        fi

	if [ -s $pBASEDIR/backups_alert.html ]; then
		echo "[$(date +"%F %T")] Sending failure alert email to $pNAME-$pEMAILTO"
		cat $pBASEDIR/backups_alert.html | mutt -e "set content_type=text/html" -s "DB Backup Failure Alert" -- $pEMAILADMIN $pEMAILTO
	else
		echo "[$(date +"%F %T")] No failed backups for $pNAME-$pEMAILTO"
	fi
done
