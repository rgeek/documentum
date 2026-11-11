echo "In 10pedeploy.sh"
if [ $JBOSS ] 
then 
	bpmfolder="${DOCUMENTUM}/$JBOSS/server/DctmServer_MethodServer/deployments/bpm.ear"
	dfcproperties=$bpmfolder/APP-INF/classes/dfc.properties
	dfckeystore=$bpmfolder/APP-INF/classes/dfc.keystore
	webxml=$bpmfolder/APP-INF/web.xml
else
	bpmfolder="${DOCUMENTUM}/${TOMCAT}/webapps/bpm"
	dfcproperties=$bpmfolder/WEB-INF/classes/dfc.properties
	dfckeystore=$bpmfolder/WEB-INF/classes/dfc.keystore
	webxml=$bpmfolder/WEB-INF/web.xml
fi
pefolder="${DM_DOCKER_HOME}/custom_script_pvc/pe_installer"
pelib="${DM_DOCKER_HOME}/custom_script_pvc/pe_installer/lib"
BPM_URL="://localhost:9080/bpm/servlet/DoMethod"
installedbpmfile="${DM_DOCKER_HOME}/customscriptpvc/pe_installer/bpm-installed"	
protocol=$JMS_PROTOCOL;
errorMsg="Failed to install DAR"
logfilename=$pefolder/logs/dar_logs/$DOCBASE_NAME/peDars.log
pebackupfolder="${DOCUMENTUM}/kube/bpm"

#Fix permission issues
chmod -R 744 ${DM_DOCKER_HOME}/custom_script_pvc/pe_installer
hostname=`hostname -f`
startType="install"
PE_VERSION=`cat $pefolder/XCP_PE_VERSION`

#Below method checks the status of DAR and exits if any of the DAR installation is failed
checkDARStatus(){
	grep "$errorMsg" $logfilename
	darstatus=$?
	if [ $darstatus -eq '0' ] || [ ! -f "$logfilename" ]
	then
		echo -e "\e[1;31mDAR installation failed\e[0m".
		exit 1
	fi
}

if [ $JBOSS ] 
then 
	EAR_FULL_PATH=$bpmfolder/APP-INF/classes/
else
	EAR_FULL_PATH=$bpmfolder/WEB-INF/classes/
fi	

#Below method checks the status of BPM url and exits after 5mins if not reachable
probeBPM()
{
	WAIT=0
	urlstatus=400
	while [ "$WAIT" -lt 300 ]
	do
		urlstatus=$(curl -o /dev/null --silent --head --write-out '%{http_code}' $protocol$BPM_URL)
		echo Waiting for $protocol://localhost:9080/bpm/servlet/DoMethod to be up
		if [ $urlstatus -eq '200' ]
		then
			echo BPM probe passed for URL $protocol$BPM_URL. Status=$urlstatus 
			if [[ $hostname == $CONTAINER_NAME-0* ]]
			then
				#bpm-installed file is created at the end of first successful installation
				touch -f ${DM_DOCKER_HOME}/customscriptpvc/pe_installer/bpm-installed
				if [ $? -ne 0 ]; then
					#Added to avoid failure due to permission denied issue in any cluster
					sudo touch -f ${DM_DOCKER_HOME}/customscriptpvc/pe_installer/bpm-installed
					if [ $? -ne 0 ]; then
					   echo -e "\e[1;31mFailed to create bpm-installed file. Please create the file manually under the desired location.\e[0m"
					else
						echo -e "\e[1;34mbpm-installed file created\e[0m"
					fi
				else
					echo -e "\e[1;34mbpm-installed file created\e[0m"	
				fi
			fi
		break
		fi
    sleep 5
    WAIT=`expr $WAIT + 5`
	done
	if [ $urlstatus -ne '200' ] 
	then
	   echo -e "\e[1;31mWaited for 5mins. BPM probe failed for URL $protocol$BPM_URL. Status=$urlstatus\e[0m" 
	   exit 1
	fi
}

#Modifying xcpconfig.properties file
modifyPropertiesFile(){
	GLOBAL_REGISTRY_ADMIN_USER_NAME=`cat ${DOCUMENTUM}/config/dfc.properties | grep dfc.globalregistry.username | cut -d'=' -f2`
	#Removing last two characters and appending jms-service
	SERVICE_NAME="$(echo `hostname` | sed 's/..$//')-jms-service"
	
    echo "Updating xcpconfig.properties file"

	sed -i -e "s|PROCESS_ENGINE.GLOBAL_REGISTRY_ADMIN_USER_NAME=.*|PROCESS_ENGINE.GLOBAL_REGISTRY_ADMIN_USER_NAME=$GLOBAL_REGISTRY_ADMIN_USER_NAME|" \
		-e "s|PROCESS_ENGINE.SECURE.GLOBAL_REGISTRY_ADMIN_PASSWORD=.*|PROCESS_ENGINE.SECURE.GLOBAL_REGISTRY_ADMIN_PASSWORD=$GLOBAL_REGISTRY_PASSWORD|" \
		-e "s|APPSERVER.SECURE.PASSWORD=.*|APPSERVER.SECURE.PASSWORD=$APP_SERVER_PASSWORD|" \
		-e "s|PE.FQDN=.*|PE.FQDN=$SERVICE_NAME|" \
		-e "s|PE.DOCBASES_ADMIN_USER_NAME=.*|PE.DOCBASES_ADMIN_USER_NAME=$INSTALL_OWNER|" \
		-e "s|PE.DOCBASES_ADMIN_USER_PASSWORD=.*|PE.DOCBASES_ADMIN_USER_PASSWORD=$INSTALL_OWNER_PASSWORD|" \
		$pefolder/xcpconfig.properties	
		
		
	   
	if [ $? -eq 0 ]; then
		echo -e "\e[1;34m$pefolder/xcpconfig.properties updated successfully\e[0m"
		DOCBASE_DOMAIN=''
		JMS_PORT=`cat $pefolder/xcpconfig.properties | grep "$APPSERVER.SERVER_HTTP_PORT" | cut -d'=' -f2`
		DOCKER_HOST=`cat $pefolder/xcpconfig.properties | grep "$PE.FQDN" | cut -d'=' -f2`
		DOCBASE_OWNER=`cat $pefolder/xcpconfig.properties | grep "$PE.DOCBASES_ADMIN_USER_NAME" | cut -d'=' -f2`
		DOCBASE_OWNER_PASSWORD=`cat $pefolder/xcpconfig.properties | grep "$PE.DOCBASES_ADMIN_USER_PASSWORD" | cut -d'=' -f2`
	else
		echo -e "\e[1;31m$pefolder/xcpconfig.properties did not update. Please check.\e[0m"
	fi	
}
modifyPropertiesFile

#Below method updates JMS config objects and makes BPM privileged client
PeConfigureForCS(){
	SERVER_CONFIG_NAME=''
	containername=$CONTAINER_NAME
	containerlength=${#containername}
	index=`expr $containerlength + 2`
	host_index=`expr substr $hostname $index 1`

	if [[ $hostname != $CONTAINER_NAME-0* ]];
	then
		if [ "$CONFIG_NAME_OPTION" = "HA" ]
		then
			SERVER_CONFIG_NAME=HA$host_index$DOCBASE_NAME
		elif [ "$CONFIG_NAME_OPTION" = "HOSTNAME" ]
		then
			thostname=`hostname`
			SERVER_CONFIG_NAME=${thostname}_$DOCBASE_NAME
		elif [ "$CONFIG_NAME_OPTION" = "FQDN" ]
		then
			SERVER_CONFIG_NAME=${hostname}_$DOCBASE_NAME
		fi
	else
		SERVER_CONFIG_NAME=$DOCBASE_NAME
	fi

    echo "
	dfcproperties path = $dfcproperties 
	docbase name = $DOCBASE_NAME.$SERVER_CONFIG_NAME
	docbase owner = $DOCBASE_OWNER 
	docbase password = $DOCBASE_OWNER_PASSWORD 
	jms port = $JMS_PORT 
	docker host = $DOCKER_HOST 
	kubernetes = $KUBERNETES 
	ear path = $EAR_FULL_PATH 
	docbase domain = $DOCBASE_DOMAIN" > /tmp/properties.txt
	java $JVM_OPTS -cp .:$pelib/xcp_ijms_pe.jar:$DOCUMENTUM/dfc/dfc.jar:$pelib/pe_shared.jar com.documentum.docker.pe.PeConfigureForCS $dfcproperties $DOCBASE_NAME.$SERVER_CONFIG_NAME $DOCBASE_OWNER $DOCBASE_OWNER_PASSWORD $JMS_PORT $DOCKER_HOST $KUBERNETES $EAR_FULL_PATH $DOCBASE_DOMAIN
	
	if [ $? -ne 0 ] 
	then
		echo -e "\e[1;31m[CS PE Installer] PE configuration in CS failed\e[0m"
		exit 1
	else 
        echo -e "\e[1;34m[CS PE Installer] PE configuration in CS is successful\e[0m"
	fi
}

#To backup files during install/upgrade
#To create the bpm pe version markup file
#These files will be used during restart to avoid PE installation again
BPMConfigBackup() {
	if [ "$startType" != "restart" ]; then
		if [ ! -d "$pebackupfolder" ]
		then
			mkdir ${pebackupfolder}
			mkdir ${pebackupfolder}/marker
			if [ $? -ne 0 ]; then
				sudo mkdir ${pebackupfolder}
				sudo mkdir ${pebackupfolder}/marker
				if [ $? -ne 0 ]; then
					echo "Failed to create bpm and marker folder. Please create the folders manually under the desired location."
				fi
			fi
		fi
		rm -rf ${pebackupfolder}/marker/*
		cp ${dfcproperties} ${dfckeystore} ${webxml} ${pebackupfolder}
		touch -f ${pebackupfolder}/marker/$PE_VERSION
		if [ $? -ne 0 ]; then
			#Added to avoid failure due to permission denied issue in any cluster
			sudo cp ${dfcproperties} ${dfckeystore} ${webxml} ${pebackupfolder}
			sudo touch -f ${pebackupfolder}/marker/$PE_VERSION
			if [ $? -ne 0 ]; then
			   echo -e "\e[1;31mFailed to copy files for backup. Please copy the file manually under the desired location.\e[0m"
			else
				echo -e "\e[1;34mPE files back up completed successfully\e[0m"
			fi
		else
			echo -e "\e[1;34mPE files back up completed successfully\e[0m"	
		fi
	fi
}

#Check for install/upgrade or restart
#In case of restart - war will be copied to jms
#Otherwise ear and dar installation will be done.
probeStartType() {
	echo "Searching for BPM Markup file - $PE_VERSION"
	if [ -f "$pebackupfolder/marker/$PE_VERSION" ]
	then
		echo "BPM Markup file exists: Restart scenario. PE installation is not required."  
		startType="restart"
	else
		echo "BPM Markup file doesn't exist: Install/Upgrade scenario. PE installation is required."
	fi
}

if [ "$1" = "prehook" ]
then
	echo "In prehook 10pedeploy.sh"
	if [ -f "$pebackupfolder/web.xml" ]
	then
	  echo -e "\e[1;34mPE backup files exists. Copying WAR (restart or upgrade mode)\e[0m"
	  unzip -q ${DM_DOCKER_HOME}/customscriptpvc/pe_installer/bpm.zip -d $bpmfolder
	  unzip -q $bpmfolder/bpm.war -d $bpmfolder
	  rm $bpmfolder/bpm.war
	  cp ${pebackupfolder}/web.xml $webxml
	  cp ${pebackupfolder}/dfc.properties ${pebackupfolder}/dfc.keystore $EAR_FULL_PATH
	  cp -f ${DM_DOCKER_HOME}/cs_logging_config/config_map_bpm/log4j $EAR_FULL_PATH/log4j2.properties
	else
	  echo -e "\e[1;34mPE backup files do not exist. PE will be installed in posthook.\e[0m"
	fi
fi

if [ "$1" = "posthook" ]
then
  echo "In posthook 10pedeploy.sh"  
  probeStartType
  if [ "$startType" = "restart" ]
  then
    echo "Probe BPM in restart mode."  
	probeBPM
  else
    # Install or upgrade mode.
	#Checking bpm folder exists. If yes, upgrade mode else install mode.
	if [ ! -d "$bpmfolder" ]
	then
      # Install mode. WAR only installation for replicas
	  if [[ $hostname != $CONTAINER_NAME-0* ]]
	  then
		echo -e "\e[1;34mInstalling WAR only (Install mode)\e[0m"
		if [ $JBOSS ] 
		then 
			kill -9 `ps -ef | grep MethodServer | awk '{print($2)}' | tr '\n' ' '`
		else
			#Below kill command needs to be revisited and tomcat should be able to stop using stopMethodserver script
			kill -9 `ps -eaf | grep catalina.home=${DOCUMENTUM}/${TOMCAT} | awk '{print($2)}' | tr '\n' ' '`
		fi
		sed -i -e "s/INSTALL_ACTION=[0-2]/INSTALL_ACTION=2/g" $pefolder/xcpconfig.properties
		source $DM_HOME/bin/dm_set_server_env.sh; $pefolder/peSetup.bin -f $pefolder/xcpconfig.properties
      else
	    # Install DAR First and then the WAR
		echo -e "\e[1;34mInstalling DAR (Install mode)\e[0m"
	    sed -i -e "s/INSTALL_ACTION=[0-2]/INSTALL_ACTION=1/g" $pefolder/xcpconfig.properties
		source $DM_HOME/bin/dm_set_server_env.sh; $pefolder/peSetup.bin -f $pefolder/xcpconfig.properties
		
		echo -e "\e[1;34mInstalling WAR (Install mode)\e[0m"
		if [ $JBOSS ] 
	    then 
			kill -9 `ps -ef | grep MethodServer | awk '{print($2)}' | tr '\n' ' '`
		else
			#Below kill command needs to be revisited and tomcat should be able to stop using stopMethodserver script
			kill -9 `ps -eaf | grep catalina.home=${DOCUMENTUM}/${TOMCAT} | awk '{print($2)}' | tr '\n' ' '`
		fi
		sed -i -e "s/INSTALL_ACTION=[0-2]/INSTALL_ACTION=2/g" $pefolder/xcpconfig.properties
		source $DM_HOME/bin/dm_set_server_env.sh; $pefolder/peSetup.bin -f $pefolder/xcpconfig.properties
		checkDARStatus
	  fi
    else
	  # Upgrade mode. DAR only installation in primary conatiner.
	  if [[ $hostname == $CONTAINER_NAME-0* ]]
	  then
        echo -e "\e[1;34mInstalling DARs only (Upgrade mode)\e[0m"
	    sed -i -e "s/INSTALL_ACTION=[0-2]/INSTALL_ACTION=1/g" $pefolder/xcpconfig.properties
	    source $DM_HOME/bin/dm_set_server_env.sh; $pefolder/peSetup.bin -f $pefolder/xcpconfig.properties
        checkDARStatus
	  else
	    # Delay for tomcat to terminate completely
	    sleep 5
	  fi
	fi
	
	# Fix for DCTMAWF-2857
	#sed -i "$ a dfc.security.keystore.file=${dfckeystore}" $dfcproperties
	if grep -q "^dfc\.security\.keystore\.file=" $dfcproperties; then
		# Update the existing property
		sed -i "/^dfc\.security\.keystore\.file=/c\dfc.security.keystore.file=${dfckeystore}" $dfcproperties
		echo "Property updated successfully."
	else
		# Append the property if it doesn't exist
		echo "dfc.security.keystore.file=${dfckeystore}" >> $dfcproperties
		echo "Property added successfully."
	fi	
    if [ "$DOCBASE_USE_CERTIFICATES" != "true" ]
  	then
	  sed -i "$ a dfc.session.secure_connect_default=try_native_first" $dfcproperties
  	fi
	if [ $JBOSS ] 
	then
		source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/${JBOSS}/server/startMethodServer.sh &
	else
	    source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/${TOMCAT}/bin/startMethodServer.sh &
	fi
    probeBPM
    PeConfigureForCS
    BPMConfigBackup
  fi
fi


