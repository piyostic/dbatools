#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 16-Apr-2015
# This script checks DB error logs
# e.g. ./check_err.sh LoL VN
# Parameter 1 : Game ID
# Parameter 2 : Location
# Parameter 3 : Interval(day or hour or now)
##################################################################################

#Define Variables
pBASEDIR=$(dirname $0)
pPID=$$
pCONF=/scripts/gtodba.conf
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="MySQL Error Log Healthcheck for $1 $2 ($3)"
pWARN="Warning: Using a password on the command line interface can be insecure."
pREG='^[0-9]+$'
pERRSIZEMAX=$((15*1024*1024*1024)) #15GB max for err.log

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

	#Kill tunnel if established
        if [[ "$pKILLSSH2" != ""  ]]; then
                echo "[$(date +"%F %T")] Killing ssh tunnel process $pKILLSSH2"
                kill -9 $pKILLSSH2
        fi

        echo "[$(date +"%F %T")] Checking for errors"
        if [[ -s $pBASEDIR/err-$pPID.log ]]; then
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

if [ $# -lt 3 ]
then
  echo "[$(date +"%F %T")] Interval(day/hour/now) missing from input arguments - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
else
  pINTERVAL=$3
  if [ "$pINTERVAL" == "day" ] ; then
	pIDATEOLD="date -d '1 day ago' +'%y%m%d'"
	pIDATENEW="date -d '1 day ago' +'%F'"
  elif [ "$pINTERVAL" == "hour" ] ; then
	pIDATEOLD="date -d '1 hour ago' +'%y%m%d %_H'"
        pIDATENEW="date -d '1 hour ago' +'%F %H'"
  elif [ "$pINTERVAL" == "now" ] ; then
        pIDATEOLD="date +'%y%m%d %_H'"
        pIDATENEW="date +'%F %H'"
  else
	echo "[$(date +"%F %T")] Invalid Interval $3 from input arguments. Enter day/hour/now - terminating" | tee $pBASEDIR/err-$pPID.log
  	exit -1
  fi
fi

# read options from conf file
if [ -f $pCONF ]
then
  . $pCONF
else
  echo "[$(date +"%F %T")] Configuration file $pCONF not found - terminating" | tee $pBASEDIR/err-$pPID.log
  exit -1
fi

#Check if monitor DB is alive
pERR=$(mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "SELECT now() FROM dual WHERE 1=0" 2>&1 | grep -v "$pWARN")
#Check if the script returned errors
if [[ "$pERR" != "" ]] ; then
        echo "[$(date +"%F %T")] Error Connecting to DBA Tools DB $pDBHOST:$pDBPORT" | tee $pBASEDIR/err-$pPID.log
        echo "[$(date +"%F %T")] $pERR"
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

#Get another open port. Retry 4 times
for i in {1..5}
do
        echo "[$(date +"%F %T")] Getting random port for ssh $i of 5 tries"
        pJUMPPORTSSH=$((RANDOM%65535+1))
        pTESTPORT=$(nc 127.0.0.1 $pJUMPPORTSSH < /dev/null > /dev/null ; echo $?)
        if [[ "$pTESTPORT" == "1" ]] ; then
                echo "[$(date +"%F %T")] Random open port for ssh $pJUMPPORTSSH. Tried $i times"
                break
        else
                if [[ "$i" == "5" ]] ; then
                        echo "[$(date +"%F %T")] Error getting random port for ssh" | tee -a $pBASEDIR/err-$pPID.log
                        exit -1
                fi
        fi
done
echo ""

#Loop db instances
pSQL="SELECT a.IP,a.PORT,CONCAT(a.GAME_ID,'@',a.LOCATION,'-',a.DESCR,':',a.DBUSAGE),b.IP as JUMPIP,c.EMAIL_TO,a.ID_MASTER
FROM dbatools.dbservers a left join dbatools.jumphosts b on a.GAME_ID=b.GAME_ID and a.LOCATION=b.LOCATION
left join dbatools.Contacts c on a.contact_id = c.id
WHERE a.GAME_ID = '$pGAMEID' AND a.LOCATION = '$pLOCATION' and 
a.DBTYPE = 'MySQL' and a.ACTIVE=1  
ORDER BY a.IP;"
mysql -Ns -h $pDBHOST -P $pDBPORT -u $pDBUSER -p$pDBPASS -e "$pSQL" | \
while read pDATA
do
        #Read data from table
        pIP=$(echo -e "$pDATA" | awk -F'\t' '{print $1}')
        pPORT=$(echo -e "$pDATA" | awk -F'\t' '{print $2}')
        pNAME=$(echo -e "$pDATA" | awk -F'\t' '{print $3}')
	pJUMPHOST=$(echo -e "$pDATA" | awk -F'\t' '{print $4}')
	pEMAILTO=$(echo -e "$pDATA" | awk -F'\t' '{print $5}')
	pSSHUSER="mysql"

        #Process data
        echo "[$(date +"%F %T")] $pNAME-$pIP:$pPORT"

        if [[ "$pJUMPHOST" == "NULL" ]]
        then
                #Direct connection
                echo "[$(date +"%F %T")] Connecting directly to $pIP:22"
		pSQLHOST=$pIP
		pSQLPORT=$pPORT
		pSSHHOST=$pIP
		pSSHPORT=22
        else
                #Establish ssh tunnel for sql
                echo "[$(date +"%F %T")] Establishing ssh tunnel for sql $pDBUSER@$pJUMPHOST -L $pJUMPPORT:$pIP:$pPORT"
                ssh -f $pDBUSER@$pJUMPHOST -L $pJUMPPORT:$pIP:$pPORT -N 2> $pBASEDIR/err-ssh-$pPID.log
                pKILLSSH=$(ps -ef | grep "ssh -f $pDBUSER@$pJUMPHOST -L $pJUMPPORT:$pIP:$pPORT" | grep -v "grep" | awk -F' ' '{print $2}')
                if [[ -s $pBASEDIR/err-ssh-$pPID.log ]]
                then
                        echo "[$(date +"%F %T")] Error establishing ssh tunnel for sql on $pDBUSER@$pJUMPHOST for $pNAME-$pIP:$pPORT" | tee $pBASEDIR/err-$pPID.log
			cat $pBASEDIR/err-ssh-$pPID.log | tee -a $pBASEDIR/err-$pPID.log
                        cleanup
                        continue
                fi

		#Establish ssh tunnel for ssh
                echo "[$(date +"%F %T")] Establishing ssh tunnel for ssh $pDBUSER@$pJUMPHOST -L $pJUMPPORTSSH:$pIP:22"
                ssh -f $pDBUSER@$pJUMPHOST -L $pJUMPPORTSSH:$pIP:22 -N 2> $pBASEDIR/err-ssh-$pPID.log
                pKILLSSH2=$(ps -ef | grep "ssh -f $pDBUSER@$pJUMPHOST -L $pJUMPPORTSSH:$pIP:22" | grep -v "grep" | awk -F' ' '{print $2}')
                if [[ -s $pBASEDIR/err-ssh-$pPID.log ]]
                then
                        echo "[$(date +"%F %T")] Error establishing ssh tunnel for ssh on $pDBUSER@$pJUMPHOST for $pNAME-$pIP:22" | tee $pBASEDIR/err-$pPID.log
                        cat $pBASEDIR/err-ssh-$pPID.log | tee -a $pBASEDIR/err-$pPID.log
                        cleanup
                        continue
                fi

                pSQLHOST="127.0.0.1"
                pSQLPORT=$pJUMPPORT
		pSSHHOST="127.0.0.1"
		pSSHPORT=$pJUMPPORTSSH
        fi

	#mysql GET Err Log Dir
	pSQLCHECK="select case when @@log_error='' then concat(@@datadir,'/',@@hostname,'.err') when position('/' in @@log_error)=0 then concat(@@datadir,'/',@@log_error) else @@log_error end;"
	pERRFILE=$(mysql -Ns -h $pSQLHOST -P $pSQLPORT -u $pDBUSER -p$pDBPASS -e "$pSQLCHECK")

	#Couldn't get error log path
        if [ "$pERRFILE" == "" ] ; then
                echo "[$(date +"%F %T")] $pNAME-$pIP:$pPORT Error getting error log file path." | tee -a $pBASEDIR/err-$pPID.log
	#ssh Check err Log
        else
		echo "[$(date +"%F %T")] Error log is at $pERRFILE"
		#Check SSH connection and get error log size
                ssh -n -oBatchMode=yes -p$pSSHPORT $pSSHUSER@$pSSHHOST "ls -l $pERRFILE ; pDATEOLD=\"\$($pIDATEOLD)\" ; pDATENEW=\"\$($pIDATENEW)\" ; cat $pERRFILE | grep -e \"^\$pDATEOLD\" -e \"^\$pDATENEW\" ; " 2>&1 > $pBASEDIR/errlog-$pPID.log

                echo "[$(date +"%F %T")] Getting error log file size"
		pSIZE=$(cat $pBASEDIR/errlog-$pPID.log | head -1 | awk '{print $5}')

		#Size is not a number
                if ! [[ $pSIZE =~ $pREG ]] ; then
                        echo "[$(date +"%F %T")] $pNAME-$pIP:$pPORT Error establishing ssh connection" | tee -a $pBASEDIR/err-$pPID.log
                        cat $pBASEDIR/errlog-$pPID.log | tee -a $pBASEDIR/err-$pPID.log
		#Check error log contents
                else
                        echo "[$(date +"%F %T")] $pERRFILE size is $(($pSIZE/1024/1024))MB"

                        #Check size of error log against threshold
                        if [[ $pSIZE -ge $pERRSIZEMAX ]] ; then
                                echo "[$(date +"%F %T")] $pNAME-$pIP:$pPORT $pERRFILE size $(($pSIZE/1024/1024))MB exceeds $(($pERRSIZEMAX/1024/1024))MB. Please flush error log." | tee -a $pBASEDIR/err-$pPID.log
                        fi
		
			#Send alert for errors found excluding those listed on exclude_err.log	
                        cat $pBASEDIR/errlog-$pPID.log | sed 1,1d | grep -vFf"$pBASEDIR/exclude_err.log" > $pBASEDIR/errsend-$pPID.log
                        #Has Errors
			if [[ -s $pBASEDIR/errsend-$pPID.log ]] ; then
				echo "[$(date +"%F %T")] $pNAME-$pIP:$pPORT Errors found on $pERRFILE" | tee -a $pBASEDIR/err-$pPID.log
                                cat $pBASEDIR/errsend-$pPID.log | tee -a $pBASEDIR/err-$pPID.log
			else
                                echo "[$(date +"%F %T")] No Errors found"
                        fi
                fi		
	fi
	
        cleanup
done

echo ""
echo "[$(date +"%F %T")] COMPLETE!"
