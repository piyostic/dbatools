#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 15-Jul-2014
# This script populates DB structure objects
# e.g. ./dbobjects.sh LoL
# Parameter 1 : Game ID
# Parameter 2 : Location
##################################################################################


#Define Variables
pBASEDIR=$(dirname $0)
pPID=$$
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="MySQL DB Objects Collection for $1 $2"
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
pSQL="SELECT a.IP,a.PORT,CONCAT(a.GAME_ID,'@',a.LOCATION,'-',a.DESCR,':',a.DBUSAGE),b.IP,a.ID,c.EMAIL_TO
FROM dbatools.dbservers a
left join dbatools.jumphosts b on a.GAME_ID=b.GAME_ID and a.LOCATION=b.LOCATION
left join dbatools.Contacts c on a.contact_id = c.id
WHERE ((a.GAME_ID = '$pGAMEID' and a.LOCATION = '$pLOCATION') OR a.IP = '$pGAMEID') and a.DBTYPE in ('MySQL','MariaDB') and a.ACTIVE >= 1 ORDER BY a.IP;"
pDBSERVERS=$(mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL")
while read pDATA
do
	#Read data from table
	pIP=$(echo -e "$pDATA" | awk -F'\t' '{print $1}')
	pPORT=$(echo -e "$pDATA" | awk -F'\t' '{print $2}')
	pNAME=$(echo -e "$pDATA" | awk -F'\t' '{print $3}')
	pJUMPHOST=$(echo -e "$pDATA" | awk -F'\t' '{print $4}')
	pSERVERID=$(echo -e "$pDATA" | awk -F'\t' '{print $5}')
	pEMAILTO=$(echo -e "$pDATA" | awk -F'\t' '{print $6}')
	
	if [[ "$pIP" == "" ]]; then
                continue
        fi

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
                	echo "[$(date +"%F %T")] Error establishing ssh tunnel on $pDBUSER@$pJUMPHOST"  | tee -a $pBASEDIR/err-$pPID.log
			cat $pBASEDIR/err-ssh-$pPID.log | tee -a $pBASEDIR/err-$pPID.log
			pEXCLUDE="${pEXCLUDE}${pSERVERID},"
			cleanup
                	continue
        	fi

		pSQLHOST="127.0.0.1"
		pSQLPORT=$pJUMPPORT
	fi

	pSQLSCHEMA="select schema_name from information_schema.schemata where schema_name not in ('information_schema','performance_schema','mysql','percona','test','tmp','temp','pt-dsns');"
	pSCHEMA=$(mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLSCHEMA" 2>$pBASEDIR/err-$pPID-new.log)
	cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID.log
        if [[ -s $pBASEDIR/err-$pPID.log ]]
        then
                echo "[$(date +"%F %T")] Error connecting to $pNAME-$pIP:$pPORT" | tee -a $pBASEDIR/err-$pPID.log
		pEXCLUDE="${pEXCLUDE}${pSERVERID},"
	else
		#Loop schemas
		while read pDATA1
        	do
			echo "[$(date +"%F %T")] Processing schema : $pDATA1"
                	##COLLECT TABLES#############################################################
			echo "[$(date +"%F %T")] Collecting Tables"
			#Prepare show create table
			pSQLTABLE="select concat('SHOW CREATE TABLE ',table_schema,'.',table_name,';') from information_schema.tables
                	where table_schema = '$pDATA1' and table_type = 'BASE TABLE'"
                	mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLTABLE" 2>$pBASEDIR/err-$pPID-new.log > $pBASEDIR/create-$pPID.sql
			cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID-DB.log
                	if [[ -s $pBASEDIR/err-$pPID-DB.log ]]
                	then
				cat $pBASEDIR/err-$pPID-DB.log | tee -a $pBASEDIR/err-$pPID.log
                        	echo "[$(date +"%F %T")] Error generating Table definition from $pNAME-$pIP:$pPORT : Schema $pDATA1" | tee -a $pBASEDIR/err-$pPID.log
				pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                	fi
			#Get table definitions
               		mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS < $pBASEDIR/create-$pPID.sql 2>$pBASEDIR/err-$pPID-new.log > $pBASEDIR/create-$pPID.tsv
			cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID-DB.log
                	if [[ -s $pBASEDIR/err-$pPID-DB.log ]]
                	then
				cat $pBASEDIR/err-$pPID-DB.log | tee -a $pBASEDIR/err-$pPID.log
                        	echo "[$(date +"%F %T")] Error getting Table definition data from $pNAME-$pIP:$pPORT : Schema $pDATA1" | tee -a $pBASEDIR/err-$pPID.log
				pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                	fi
			#Prepare table definition into tsv : table/t[definition]
                	pVAR=$(echo -e "$pSERVERID\t$pDATA1\ttable")
			#Load into tsv
                	cat $pBASEDIR/create-$pPID.tsv | sed 's/ AUTO_INCREMENT=[0-9]*\b//' | awk -v var1="$pVAR" -F'\t' '{print var1 "\t" $1 "\t" $2}' >> $pBASEDIR/final_${pPID}_dbobjects.tsv
			
			##COLLECT VIEWS#############################################################
			echo "[$(date +"%F %T")] Collecting Views"
			#Prepare show create view
                        pSQLTABLE="select concat('SHOW CREATE VIEW ',table_schema,'.',table_name,';') from information_schema.tables
                        where table_schema = '$pDATA1' and table_type = 'VIEW'"
                        mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLTABLE" 2>$pBASEDIR/err-$pPID-new.log > $pBASEDIR/create-$pPID.sql
                        cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID-DB.log
                        if [[ -s $pBASEDIR/err-$pPID-DB.log ]]
                        then
                                cat $pBASEDIR/err-$pPID-DB.log | tee -a $pBASEDIR/err-$pPID.log
                                echo "[$(date +"%F %T")] Error generating View definition from $pNAME-$pIP:$pPORT : Schema $pDATA1" | tee -a $pBASEDIR/err-$pPID.log
                                pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                        fi
                        #Get view definitions
                        mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS < $pBASEDIR/create-$pPID.sql 2>$pBASEDIR/err-$pPID-new.log > $pBASEDIR/create-$pPID.tsv
                        cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID-DB.log
                        if [[ -s $pBASEDIR/err-$pPID-DB.log ]]
                        then
                                cat $pBASEDIR/err-$pPID-DB.log | tee -a $pBASEDIR/err-$pPID.log
                                echo "[$(date +"%F %T")] Error getting View definition data from $pNAME-$pIP:$pPORT : Schema $pDATA1" | tee -a $pBASEDIR/err-$pPID.log
                                pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                        fi
                        #Prepare view definition into tsv : table/t[definition]
                        pVAR=$(echo -e "$pSERVERID\t$pDATA1\tview")
                        #Load into tsv
                        cat $pBASEDIR/create-$pPID.tsv | awk -v var1="$pVAR" -F'\t' '{print var1 "\t" $1 "\t" $2}' >> $pBASEDIR/final_${pPID}_dbobjects.tsv

                        ##COLLECT EVENTS#############################################################
                        echo "[$(date +"%F %T")] Collecting Events"
                        #Prepare show create event
                        pSQLTABLE="select concat('SHOW CREATE EVENT ',event_schema,'.',event_name,';') from information_schema.events
                        where event_schema = '$pDATA1'"
                        mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLTABLE" 2>$pBASEDIR/err-$pPID-new.log > $pBASEDIR/create-$pPID.sql
                        cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID-DB.log
                        if [[ -s $pBASEDIR/err-$pPID-DB.log ]]
                        then
                                cat $pBASEDIR/err-$pPID-DB.log | tee -a $pBASEDIR/err-$pPID.log
                                echo "[$(date +"%F %T")] Error generating Event definition from $pNAME-$pIP:$pPORT : Schema $pDATA1" | tee -a $pBASEDIR/err-$pPID.log
                                pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                        fi
                        #Get event definitions
                        mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS < $pBASEDIR/create-$pPID.sql 2>$pBASEDIR/err-$pPID-new.log > $pBASEDIR/create-$pPID.tsv
                        cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID-DB.log
                        if [[ -s $pBASEDIR/err-$pPID-DB.log ]]
                        then
                                cat $pBASEDIR/err-$pPID-DB.log | tee -a $pBASEDIR/err-$pPID.log
                                echo "[$(date +"%F %T")] Error getting Event definition data from $pNAME-$pIP:$pPORT : Schema $pDATA1" | tee -a $pBASEDIR/err-$pPID.log
                                pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                        fi
                        #Prepare event definition into tsv : table/t[definition]
                        pVAR=$(echo -e "$pSERVERID\t$pDATA1\tevent")
                        #Load into tsv
                        cat $pBASEDIR/create-$pPID.tsv | awk -v var1="$pVAR" -F'\t' '{print var1 "\t" $1 "\t" $4}' >> $pBASEDIR/final_${pPID}_dbobjects.tsv

                        ##COLLECT TRIGGERS#############################################################
                        echo "[$(date +"%F %T")] Collecting Triggers"
                        #Prepare show create event
                        pSQLTABLE="select concat('SHOW CREATE TRIGGER ',trigger_schema,'.',trigger_name,';') from information_schema.triggers
                        where trigger_schema = '$pDATA1'"
                        mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLTABLE" 2>$pBASEDIR/err-$pPID-new.log > $pBASEDIR/create-$pPID.sql
                        cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID-DB.log
                        if [[ -s $pBASEDIR/err-$pPID-DB.log ]]
                        then
                                cat $pBASEDIR/err-$pPID-DB.log | tee -a $pBASEDIR/err-$pPID.log
                                echo "[$(date +"%F %T")] Error generating Trigger definition from $pNAME-$pIP:$pPORT : Schema $pDATA1" | tee -a $pBASEDIR/err-$pPID.log
                                pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                        fi
                        #Get event definitions
                        mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS < $pBASEDIR/create-$pPID.sql 2>$pBASEDIR/err-$pPID-new.log > $pBASEDIR/create-$pPID.tsv
                        cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID-DB.log
                        if [[ -s $pBASEDIR/err-$pPID-DB.log ]]
                        then
                                cat $pBASEDIR/err-$pPID-DB.log | tee -a $pBASEDIR/err-$pPID.log
                                echo "[$(date +"%F %T")] Error getting Trigger definition data from $pNAME-$pIP:$pPORT : Schema $pDATA1" | tee -a $pBASEDIR/err-$pPID.log
                                pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                        fi
                        #Prepare event definition into tsv : table/t[definition]
                        pVAR=$(echo -e "$pSERVERID\t$pDATA1\ttrigger")
                        #Load into tsv
                        cat $pBASEDIR/create-$pPID.tsv | awk -v var1="$pVAR" -F'\t' '{print var1 "\t" $1 "\t" $3}' >> $pBASEDIR/final_${pPID}_dbobjects.tsv

                        ##COLLECT PROCEDURES#############################################################
                        echo "[$(date +"%F %T")] Collecting Procedures and Functions"
                        #Prepare show create event
                        pSQLTABLE="select concat('SHOW CREATE ',routine_type,' ',routine_schema,'.',routine_name,';') from information_schema.routines
                        where routine_schema = '$pDATA1'"
                        mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLTABLE" 2>$pBASEDIR/err-$pPID-new.log > $pBASEDIR/create-$pPID.sql
                        cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID-DB.log
                        if [[ -s $pBASEDIR/err-$pPID-DB.log ]]
                        then
                                cat $pBASEDIR/err-$pPID-DB.log | tee -a $pBASEDIR/err-$pPID.log
                                echo "[$(date +"%F %T")] Error generating Procedure definition from $pNAME-$pIP:$pPORT : Schema $pDATA1" | tee -a $pBASEDIR/err-$pPID.log
                                pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                        fi
                        #Get event definitions
                        mysql -N -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS < $pBASEDIR/create-$pPID.sql 2>$pBASEDIR/err-$pPID-new.log > $pBASEDIR/create-$pPID.tsv
                        cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" > $pBASEDIR/err-$pPID-DB.log
                        if [[ -s $pBASEDIR/err-$pPID-DB.log ]]
                        then
                                cat $pBASEDIR/err-$pPID-DB.log | tee -a $pBASEDIR/err-$pPID.log
                                echo "[$(date +"%F %T")] Error getting Procedure definition data from $pNAME-$pIP:$pPORT : Schema $pDATA1" | tee -a $pBASEDIR/err-$pPID.log
                                pEXCLUDE="${pEXCLUDE}${pSERVERID},"
                        fi
                        #Prepare event definition into tsv : table/t[definition]
                        pVAR=$(echo -e "$pSERVERID\t$pDATA1\tprocedure")
                        #Load into tsv
                        cat $pBASEDIR/create-$pPID.tsv | awk -v var1="$pVAR" -F'\t' '{print var1 "\t" $1 "\t" $3}' >> $pBASEDIR/final_${pPID}_dbobjects.tsv

        	done  <<< "$pSCHEMA"

        fi

	cleanup
done <<< "$pDBSERVERS"

#Even if db server is down, existing records should not be removed
pEXCLUDE="${pEXCLUDE}0"

echo "[$(date +"%F %T")] Loading $pBASEDIR/final_${pPID}_dbobjects.tsv"
#Temp table to store collected data
pSQL="CREATE TEMPORARY TABLE tmp_dbobjects like dbobjects;"
pSQL="$pSQL LOAD DATA LOCAL INFILE '$pBASEDIR/final_${pPID}_dbobjects.tsv' into table tmp_dbobjects(DBSERVER_ID,DBSCHEMA,TYPE,NAME,DEFINITION) SET OS_PROCESS_ID=$pPID;"
#For existing records
pSQL="$pSQL UPDATE dbobjects p, tmp_dbobjects t SET p.DEFINITION=t.DEFINITION,p.OS_PROCESS_ID=$pPID WHERE p.DBSERVER_ID=t.DBSERVER_ID and p.DBSCHEMA=t.DBSCHEMA and p.NAME=t.NAME and p.TYPE=t.TYPE;"
#For new records
pSQL="$pSQL INSERT IGNORE INTO dbobjects(DBSERVER_ID,DBSCHEMA,NAME,TYPE,DEFINITION,OS_PROCESS_ID) select DBSERVER_ID,DBSCHEMA,NAME,TYPE,DEFINITION,OS_PROCESS_ID from tmp_dbobjects;"
#For obsolete records
pSQL="$pSQL DELETE FROM dbobjects WHERE OS_PROCESS_ID <> $pPID and DBSERVER_ID in (select id from dbservers where ((GAME_ID = '$pGAMEID' AND LOCATION = '$pLOCATION') OR IP = '$pGAMEID') AND ACTIVE >= 1) and DBSERVER_ID NOT IN (${pEXCLUDE});"
mysql -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL; show warnings;" dbatools

echo "[$(date +"%F %T")] Removing script $pBASEDIR/final_${pPID}_dbobjects.tsv"
rm -f $pBASEDIR/final_${pPID}_dbobjects.tsv
pKILLSSH=""

echo "[$(date +"%F %T")] COMPLETE!"
