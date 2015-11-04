#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 31-Jul-2014
# This script deploys dbobjects as html
# e.g. ./dictionary.sh LoL VN
# Parameter 1 : Game ID
# Parameter 2 : Location
##################################################################################


#Define Variables
pBASEDIR=$(dirname $0)
pPID=$$
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="DB Data Dictionary HTML for $1 $2"
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

if [ $# -lt 1 ]
then
  echo "[$(date +"%F %T")] Game ID missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pGAMEID=$1
fi

if [ $# -lt 2 ]
then
  echo "[$(date +"%F %T")] Location missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pLOCATION=$2
fi  

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

#Loop servers
pSQL="SELECT DISTINCT a.id,CONCAT(a.GAME_ID,'@',a.LOCATION,'-',a.DESCR,':',a.DBUSAGE),b.dbschema,a.IP,a.PORT,a.DBUSAGE
FROM dbatools.dbservers a
join dbatools.dbobjects b on a.id = b.dbserver_id
join dbatools.Contacts c on a.contact_id = c.id
WHERE 
a.GAME_ID = '$pGAMEID' and a.LOCATION = '$pLOCATION' and 
a.DBTYPE in ('MySQL','MSSQL') and a.ENV='Live' and a.ACTIVE >= 1 ORDER BY a.IP;"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
	#Read data from table
	pSERVERID=$(echo -e "$pDATA" | awk -F'\t' '{print $1}')
	pNAME=$(echo -e "$pDATA" | awk -F'\t' '{print $2}')
	pSCHEMA=$(echo -e "$pDATA" | awk -F'\t' '{print $3}')
	pIP=$(echo -e "$pDATA" | awk -F'\t' '{print $4}')
	pPORT=$(echo -e "$pDATA" | awk -F'\t' '{print $5}')
	pDBUSAGE=$(echo -e "$pDATA" | awk -F'\t' '{print $6}')
	
	#Make Directory if not exist
	pWEBDIR="$pTOMCATDIR/dictionary/$pGAMEID/$pLOCATION"
	mkdir -p $pWEBDIR
	#Directory modified today
	touch $pTOMCATDIR/dictionary/$pGAMEID
	touch $pTOMCATDIR/dictionary/$pGAMEID/$pLOCATION

	#Process data
	echo ""
	echo "[$(date +"%F %T")] Processing $pNAME-$pIP:$pPORT"

	#HTML Head
	echo "
	<html>
	<head>
	<meta charset=\"UTF-8\">
	<link rel=\"stylesheet\" type=\"text/css\" href=\"default.css\">
	<script type='text/javascript' src='https://www.google.com/jsapi'></script>
	<script type='text/javascript'>
	google.load('visualization', '1', {packages:['table']});
	google.setOnLoadCallback(drawTable);
	function drawTable() {
	var data = new google.visualization.DataTable();
	data.addColumn('string', 'Table Name');
	data.addColumn('string', 'Comments');
	data.addColumn('datetime', 'Creation Date');
	data.addColumn('datetime', 'Modified Date');
	data.addRows([" > ${pBASEDIR}/${pSCHEMA}_${pSERVERID}-${pPID}.html

	#Google Chart Data
	pSQLSCHEMA="
select
case
        when line_num = line_min and line_num = line_max then 
		concat(\"['\",name,\"','\",comments,\"',new Date('\",creation_date,\"'),new Date('\",modified_date,\"')],|\")
        when line_num = line_min then 
		concat(\"['\",name,\"','\",comments,\"<br>\")
        when line_num = line_max then 
		concat(comments,\"',new Date('\",creation_date,\"'),new Date('\",modified_date,\"')],|\")
        else 
		concat(comments,'<br>')
end
from
(select distinct
	ifnull(b.name,a.name) name,
	concat('<p>',
	replace(
		replace(
			replace(
				replace(
				concat(ifnull(concat(b.column_name,' - '),''),
				ifnull(b.comments,'N/A')),
				'\n','<br>'),
			'\r',''),
		'|',''),
	\"'\",'&#39;'),
	'</p>') comments,
	DATE_FORMAT(ifnull(b.creation_date,a.creation_date),'%Y/%m/%d %T') as creation_date,
	DATE_FORMAT(ifnull(b.modified_date,a.modified_date),'%Y/%m/%d %T') as modified_date,
	ifnull(line_num,0) line_num,ifnull(line_min,0) line_min,ifnull(line_max,0) line_max
from 
	dbobjects a
	left join dbdictionary b on a.dbschema = b.dbschema and a.name REGEXP b.name_regexp
	left join (select dbschema,name_regexp,min(line_num) line_min,max(line_num) line_max from dbdictionary group by dbschema,name_regexp) c on b.dbschema = c.dbschema and b.name_regexp = c.name_regexp
where 
	a.dbserver_id = $pSERVERID and a.dbschema = '$pSCHEMA' and a.type = 'table') a
order by 
	name,line_num;
	"
	mysql -N -u $pDBUSER -p$pDBPASS -e "$pSQLSCHEMA" dbatools 2>$pBASEDIR/err-$pPID-new.log | tr '\n' ' ' | tr '|' '\n' >> ${pBASEDIR}/${pSCHEMA}_${pSERVERID}-${pPID}.html
	cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" >> $pBASEDIR/err-$pPID.log
        if [[ -s $pBASEDIR/err-$pPID.log ]]
        then
		echo "[$(date +"%F %T")] Error getting dictionary data from $pNAME-$pIP:$pPORT : Schema $pSCHEMA" | tee -a $pBASEDIR/err-$pPID.log
	else
	        #HTML End head
        	echo "]);
	        var table = new google.visualization.Table(document.getElementById('table_div'));
	        table.draw(data, {allowHtml: true, showRowNumber: true});
	        }
	        </script>
		<title>GTO DBA Dictionary</title>
	        </head>" >> ${pBASEDIR}/${pSCHEMA}_${pSERVERID}-${pPID}.html

	        #HTML Report header
	        echo "<body>
	        <p>
	        <h1>Data Dictionary for $pNAME schema $pSCHEMA</h1>
	        Last Refreshed on $(date +"%F %T")
	        </p>
	        <div id='table_div'></div>
	        </body>
	        </html>" >> ${pBASEDIR}/${pSCHEMA}_${pSERVERID}-${pPID}.html

	        #Deploy
	        echo "[$(date +"%F %T")] Deploying to $pWEBDIR/${pSCHEMA}_${pDBUSAGE}_${pIP}:$pPORT.html"
	        mv ${pBASEDIR}/${pSCHEMA}_${pSERVERID}-${pPID}.html $pWEBDIR/${pSCHEMA}_${pDBUSAGE}_${pIP}:$pPORT.html
	fi

done

echo "[$(date +"%F %T")] COMPLETE!"
