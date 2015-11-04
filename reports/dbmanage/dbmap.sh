#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 7-Aug-2014
# This script deploys dbmap as html
# e.g. ./dbmap.sh
##################################################################################


#Define Variables
pBASEDIR=$(dirname $0)
pPID=$$
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="MySQL DB Map HTML"
pJUMPPORT="6$(echo $pPID | tail -c 4)"
pWARN="Warning: Using a password on the command line interface can be insecure."
pTOMCATDIR="/opt/apache-tomcat-8.0.20/webapps/ROOT"

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
		echo "Sending email to $pEMAILTO $pEMAILADMIN"
                cat $pBASEDIR/err-$pPID.log |  mutt -s "$pEMAILSUBJ Error" -- $pEMAILTO $pEMAILADMIN
        fi

        echo "[$(date +"%F %T")] Cleaning up temp files"
        rm -f $pBASEDIR/*-$pPID*

        echo ""
}

# read options from conf file
if [ -f /scripts/gtodba.conf ]
then
  . /scripts/gtodba.conf
else
  echo "[$(date +"%F %T")] Configuration file /scripts/gtodba.conf not found - terminating"
  exit -1
fi

#Check if monitor DB is alive
pERR=$(mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "SELECT 1 FROM dual WHERE 1=0" 2>&1 | grep -v "$pWARN")
#Check if the script returned errors
if [[ "$pERR" != "" ]] ; then
	echo "[$(date +"%F %T")] Error Connecting to dbatools DB $pDBHOST:$pDBPORT" | tee $pBASEDIR/err-$pPID.log
	exit -1
fi

	
#HTML Head
cat ${pBASEDIR}/dbmap.html | grep -B1000 "<CHANGE>" | grep -v "<CHANGE>" > ${pBASEDIR}/dbmap-${pPID}.html

#Google Chart Data
pSQLSCHEMA="
use dbatools;
select
country Country,
concat(
concat('<u>',location_name,'</u></br>'),
group_concat(ifnull(dbtype,'<b>TOTAL</b>'),' : ',dbcount order by ifnull(dbtype,'zzzz') separator '</br>'),
concat('</br><font color=blue>Inactive : ',max(inactive_count))

) Description,
CASE WHEN max(inactive_count)=0 then 'green' when max(inactive_count)>=10 then 'pink' else 'blue' end Marker
from
(select
country,
location_name,
dbtype,
count(1) dbcount,
sum(case when active<>1 then 1 else 0 end) inactive_count
from
(select l.location_iso country,location_name,dbtype,active from dbservers s left join locations l on s.location = l.location
union all
select l.location_iso country,location_name,'Jumphost',1 from jumphosts s left join locations l on s.location = l.location) a
where active < 2
group by country,dbtype with rollup) a
where country is not null
group by country;
"
mysql -Ns -u $pDBUSER -p$pDBPASS -e "$pSQLSCHEMA" 2>$pBASEDIR/err-$pPID-new.log | awk -F'\t' '{print "[\""$1"\",\"" $2 "\",\"" $3 "\"],"}' >> ${pBASEDIR}/dbmap-${pPID}.html
cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" >> $pBASEDIR/err-$pPID.log
if [[ -s $pBASEDIR/err-$pPID.log ]]
then
	echo "[$(date +"%F %T")] Error getting dbservers data from dbatools : Schema $pSCHEMA" | tee -a $pBASEDIR/err-$pPID.log
else
	#HTML Footer
	cat ${pBASEDIR}/dbmap.html | grep -A1000 "<CHANGE>" | grep -v "<CHANGE>" >> ${pBASEDIR}/dbmap-${pPID}.html

	#Deploy
	echo "[$(date +"%F %T")] Deploying to $pTOMCATDIR/dbmap.html"
	mv ${pBASEDIR}/dbmap-${pPID}.html $pTOMCATDIR/dbmap.html
fi

echo "[$(date +"%F %T")] COMPLETE!"
