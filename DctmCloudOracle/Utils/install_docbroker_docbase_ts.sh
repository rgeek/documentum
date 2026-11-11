#!/bin/sh
###EMC Documentum on Docker
###(c) Copyright EMC Corp., 1992 - 2016
###All rights reserved.
###Version 1.0 dated 08/Sep/2016

echo USAGE : $DM_DOCKER_HOME/scripts/install_docbroker_docbase_ts.sh
#Description - Script to configure the Docbrokers, Docbase and Thumbnail Server. 

SUCCESS=0
FAILURE=1

#Function to exit the scripts with return value 0 when any of the command fails
exit_on_failure()
{
#If we exit with 1 the container will going to stop. If any errors will happens then container will going to exit and verify the logs become very tough.So exit with 0
	exit 0
}
extip=$DOCKER_HOST
docbase=$DOCBASE_NAME

# Setting the log file path to $DM_DOCKER_HOME/logs/${hostname}.log
hostname=`hostname`
logfile=$DM_DOCKER_HOME/logs/${hostname}.log


#Port numbers for server and docbrokers
serverport=$CONTENTSERVER_PORT
server_secure_port=`expr $serverport + 1`
intdocbrokerport=1489
extdocbrokerport=$EXTERNAL_DOCBROKER_PORT

## create internal and external  docbrockers
$DM_DOCKER_HOME/scripts/create_intext_docbroker.sh $hostname $intdocbrokerport $extdocbrokerport
if [ $? != $SUCCESS ]
then        
		echo "ERROR: The $DM_DOCKER_HOME/scripts/create_intext_docbroker.sh has failed. Please check install logs at container's $DM_DOCKER_HOME/logs/$hostname.log" >> $logfile
		exit_on_failure
fi
#Start docbrokers after creation and add the external ip
echo "Start Docbroker" >> $logfile
su $INSTALL_OWNER -c "cd ;  ${DOCUMENTUM}/dba/dm_launch_Docbroker" >> $logfile
su $INSTALL_OWNER -c "cd ;  ${DOCUMENTUM}/dba/dm_launch_Docbroker2" >> $logfile
#
docservice=`cat /etc/services | grep dm_${docbase}_s | awk '{print($1);}' | sed -e 's/ //g'`
echo "docservice = $docservice"
if [ "$docservice" = "dm_${docbase}_s" ]
then
		echo "Docbase services already exist" >> $logfile
else
        echo "Adding docbase services" >> $logfile
        echo dm_$docbase $serverport/tcp >> /etc/services
        echo dm_${docbase}_s $server_secure_port/tcp >>  /etc/services
fi

## Create docbase
if [ "$SERVER_CONFIG_NAME" ]
then
		echo "Calling create_ha_server.sh " >> $logfile
		$DM_DOCKER_HOME/scripts/create_ha_server.sh $hostname $intdocbrokerport $extdocbrokerport
		if [ $? != $SUCCESS ]
		then        
				echo "ERROR: The $DM_DOCKER_HOME/scripts/create_ha_server.sh has failed. Please check install logs at container's $DM_DOCKER_HOME/logs/$hostname.log" >> $logfile
				exit_on_failure
		fi
else
		echo "Calling create_docbase.sh " >> $logfile
		$DM_DOCKER_HOME/scripts/create_docbase.sh $hostname $intdocbrokerport $extdocbrokerport
		if [ $? != $SUCCESS ]
		then        
				echo "ERROR: The $DM_DOCKER_HOME/scripts/create_docbase.sh has failed. Please check install logs at container's $DM_DOCKER_HOME/logs/$hostname.log" >> $logfile
				exit_on_failure
		fi
fi

 su $INSTALL_OWNER -c "cd; kill -9 `ps -ef | grep $docbase | awk '{print($2)}'`" >> $logfile
	
echo "Restarting all services"		>> $logfile
if [ "$SERVER_CONFIG_NAME" ]
then
		$DM_DOCKER_HOME/scripts/start_all_rcs_services.sh
		if [ $? != $SUCCESS ]
		then        
				echo "ERROR: The $DM_DOCKER_HOME/scripts/start_all_rcs_services.sh has failed. Please check install logs at container's $DM_DOCKER_HOME/logs/$hostname.log" >> $logfile
				exit_on_failure
		fi
else
		$DM_DOCKER_HOME/scripts/start_all_services.sh
		if [ $? != $SUCCESS ]
		then        
				echo "ERROR: The $DM_DOCKER_HOME/scripts/start_all_services.sh has failed. Please check install logs at container's $DM_DOCKER_HOME/logs/$hostname.log" >> $logfile
				exit_on_failure
		fi
fi

echo "Configuration of Docbrokers and docbase is completed" >> $logfile

if [ "$CONFIGURE_THUMBNAIL_SERVER" = "YES" ]
then 

		su $INSTALL_OWNER -c "cd ;${DM_DOCKER_HOME}/thumbserverbuild/configure-thumbnail-server.sh \"$DOCBASE_NAME\" \"$INSTALL_OWNER\" \"$DOCBASE_PASSWORD\" \"$AEK_PASSPHRASE\" \"$DOCKER_HOST\""
		if [ $? != $SUCCESS ]
		then        
				echo "ERROR: The ${DM_DOCKER_HOME}/thumbserverbuild/configure-thumbnail-server.sh has failed. Please check install logs at container's $DM_DOCKER_HOME/logs/$hostname.log" >> $logfile
				exit_on_failure
		fi
fi

if [ "$SERVER_CONFIG_NAME" ]
then
    servername="$hostname"_$docbase
    #Dar installation for patches
    darfile=${DM_DOCKER_HOME}/DARchangedlist.txt
    if [ -f $darfile ] ; then
       su $INSTALL_OWNER -c "cd ; \cp -r ${DOCUMENTUM}/config/log4j2.properties ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/log4j.properties"
       echo "Installing DARs:" >> $logfile
       darlogfile=$DM_DOCKER_HOME/logs/darsinstall.log
       time=`date +%m.%d.%Y.%H.%M.%S`
       if [ -f $darlogfile ] ; then
            #Moving the old log file with time stamp
            mv $darlogfile $darlogfile.save.$time
            chown $INSTALL_OWNER:$INSTALL_OWNER  $darlogfile.save.$time
       fi
       cat -tv $darfile | sed 's/\^M//' | while read p || [ -n "$p" ];
       do
            echo $p >> $logfile
            su $INSTALL_OWNER -c "cd ; source $DM_HOME/bin/dm_set_server_env.sh; ${DM_HOME}/install/composer/ComposerHeadless/java/jdk1.8.0_202_x64/bin/java -Ddar=${DM_HOME}/install/DARsInternal/'$p' -Ddocbase=${DOCBASE_NAME}.${servername} -Duser=${INSTALL_OWNER} -Dpassword=${INSTALL_OWNER_PASSWORD} -Ddomain= -cp ${DM_HOME}/install/composer/ComposerHeadless/startup.jar org.eclipse.equinox.launcher.Main -data ${DM_HOME}/install/composer/workspace -application org.eclipse.ant.core.antRunner -buildfile ${DM_HOME}/install/composer/deploy.xml >> $darlogfile"
       done
       echo "Dar installation completed. Please check $darlogfile for more details" >> $logfile
    fi
fi
