#!/bin/bash
##################################################################################
# Written by Rosalind Chan on 7-Aug-2014
# This script deploys dbservers as html
# e.g. ./dbmanage.sh
##################################################################################


#Define Variables
pBASEDIR=$(dirname $0)
pPID=$$
pEMAILADMIN="chanr@garena.com"
pEMAILSUBJ="MySQL DB Manage HTML"
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

#Generate map
$pBASEDIR/dbmap.sh
	
#HTML Head
echo "
<html xmlns=\"http://www.w3.org/1999/xhtml\">
  <head>
    <meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\"/>
    <title>
      GTO DBA Managed Databases
    </title>
    <script type=\"text/javascript\" src=\"//www.google.com/jsapi\"></script>
    <script type=\"text/javascript\">
      google.load('visualization', '1.1', {packages: ['controls']});
    </script>
    <script type=\"text/javascript\">
      function drawVisualization() {
        // Prepare the data
        var data = google.visualization.arrayToDataTable([
" > ${pBASEDIR}/dbmanage-${pPID}.html

#Google Chart Data
pSQLSCHEMA="
select 
concat('[',
'\"',concat(game_id,'-',location),'\",',
'\"',location,'\",',
'\"',dbtype,'\",',
'\"',c.Name,'\",',
count(1),',',
sum(case when sessions is null then 1 else 0 end),',',
sum(case when active <> 1 then 1 else 0 end),
'],') as \`[\"Game\",\"Location\",\"DB Type\",\"Contact\",\"DB Count\",\"No Process\",\"Inactive\"],\`
from dbatools.dbservers s join dbatools.Contacts c on s.CONTACT_ID = c.ID
left join (select dbserver_id,sum(session_count) sessions from dbatools.processes group by dbserver_id) p on s.id = p.dbserver_id
where active <= 1
group by game_id,location,dbtype,c.Name;
"
mysql -u $pDBUSER -p$pDBPASS -e "$pSQLSCHEMA" 2>$pBASEDIR/err-$pPID-new.log >> ${pBASEDIR}/dbmanage-${pPID}.html
cat $pBASEDIR/err-$pPID-new.log | grep -v "$pWARN" >> $pBASEDIR/err-$pPID.log
if [[ -s $pBASEDIR/err-$pPID.log ]]
then
	echo "[$(date +"%F %T")] Error getting dbservers data from $pNAME-$pIP:$pPORT : Schema $pSCHEMA" | tee -a $pBASEDIR/err-$pPID.log
else
	pTOTALDB=$(mysql -Ns -u $pDBUSER -p$pDBPASS -e "select count(1) from dbatools.dbservers where active <= 1")
	pTOTALJUMP=$(mysql -Ns -u $pDBUSER -p$pDBPASS -e "select count(1) from dbatools.jumphosts")
	pTOTAL=$(($pTOTALDB + $pTOTALJUMP))
	#HTML Footer
        echo "
        ]);

        // Define a category picker control for the Gender column
        var categoryPicker = new google.visualization.ControlWrapper({
          'controlType': 'CategoryFilter',
          'containerId': 'control2',
          'options': {
            'filterColumnLabel': 'Contact',
            'ui': {
            'labelStacking': 'vertical',
              'allowTyping': false,
              'allowMultiple': false
            }
          }
        });

        // Define a Pie chart
        var pie = new google.visualization.ChartWrapper({
          'chartType': 'PieChart',
          'containerId': 'chart1',
          'options': {
            'is3D': true,
            'width': 300,
            'height': 300,
            'legend': 'none',
            'chartArea': {'left': 15, 'top': 15, 'right': 0, 'bottom': 0},
            'pieSliceText': 'label'
          },
          // Instruct the piechart to use colums 0 (Name) and 3 (Donuts Eaten)
          // from the 'data' DataTable.
          'view': {'columns': [0, 4]}
        });

        // Define a table
        var table = new google.visualization.ChartWrapper({
          'chartType': 'Table',
          'containerId': 'chart2',
          'options': {
            'width': '800px'
          }
        });

        // Create a dashboard
        new google.visualization.Dashboard(document.getElementById('dashboard')).
            // Establish bindings, declaring the both the slider and the category
            // picker will drive both charts.
            bind([categoryPicker], [pie, table]).
            // Draw the entire dashboard.
            draw(data);
      }


      google.setOnLoadCallback(drawVisualization);
    </script>
  </head>
  <body style=\"font-family: Arial;border: 0 none;\">
  <p>
  <h1>DB Servers Managed by GTO</h1>
  Last Refreshed on $(date +"%F %T")<br/>
  </p>
<p>
  Total DB : $pTOTALDB<br/>
  Total Jumphost : $pTOTALJUMP<br/>
  Grand Total : $pTOTAL<br/>
</p>
<iframe src=\"dbmap.html\" onload=\"this.width=screen.width;this.height=400;\" scrolling=\"no\" frameborder=\"0\"></iframe>
    <div id=\"dashboard\">
      <table>
        <tr style='vertical-align: top'>
          <td style='width: 300px; font-size: 0.9em;'>
            <div id=\"control2\"></div>
          </td>
          <td style='width: 100px'>
            <div style=\"float: left;\" id=\"chart1\"></div>
	  </td>
	  <td style='width: 500px'>
            <div style=\"float: left;\" id=\"chart2\"></div>
          </td>
        </tr>
      </table>
    </div>
  </body>
</html>
	" >> ${pBASEDIR}/dbmanage-${pPID}.html


	#Deploy
	echo "[$(date +"%F %T")] Deploying to $pTOMCATDIR/dbmanage.html"
	mv ${pBASEDIR}/dbmanage-${pPID}.html $pTOMCATDIR/dbmanage.html
fi

echo "[$(date +"%F %T")] COMPLETE!"
