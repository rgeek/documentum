SUCCESS=0
FAILURE=1
DSIS_URL=''

handleDSISStartup() {
	mkdir $DM_HOME/install/dsis
	sudo chown -R -f ${INSTALL_OWNER_ID}:${INSTALL_OWNER_ID} $DM_DOCKER_HOME/dsis_binary_volume
    sudo chmod -R -f 700 $DM_DOCKER_HOME/dsis_binary_volume
	unzip -oq $DM_DOCKER_HOME/dsis_binary_volume/dsis.zip -d $DM_HOME/install/dsis
	chmod -R 775 ${DM_HOME}/install/dsis
	cat $DM_DOCKER_HOME/vault_config/vault > $DM_HOME/install/dsis/application.properties
	chmod +x $DM_HOME/install/dsis/dsis_start.sh
	cd $DM_HOME/install/dsis
	$DM_HOME/install/dsis/dsis_start.sh
	sleep 20
	#Marker file for DSIS binary volume
	touch -f $DM_DOCKER_HOME/dsis_binary_volume/dsis_pvc_created
	echo "Created DSIS marker file $DM_DOCKER_HOME/dsis_binary_volume/dsis_pvc_created"
	DSIS_HOST=$( sed -n -e '/dsis.dctm.host/ s/.*\= *//p' $DM_HOME/install/dsis/application.properties)
	DSIS_PORT=$( sed -n -e '/dsis.dctm.port/ s/.*\= *//p' $DM_HOME/install/dsis/application.properties)
	export DSIS_URL=http://$DSIS_HOST:$DSIS_PORT/dsis
	response=$(curl --write-out '%{http_code}' --silent --output /dev/null -I -X GET $DSIS_URL/checkstatus)
	if [ $response != 200 ]
	then
		echo "$(date) Failed to start Vault daemon service. exitProgram"
		echo "$(date) cs_startup.sh failed"
		exit $FAILURE    
	else
		echo "$(date) Vault daemon started successfully"
	fi
}

update_tomcat_logs_location() {
	export NEW_TOMCAT_LOGS_DIR=$DOCUMENTUM/dba/log/tomcat
	echo "$(date) Updating tomcat logs directory to ${NEW_TOMCAT_LOGS_DIR}"
	mkdir -p $NEW_TOMCAT_LOGS_DIR
	sed -i "s|\"\$CATALINA_BASE\"/logs/catalina.out|${NEW_TOMCAT_LOGS_DIR}/catalina.out|g" ${DM_JMS_HOME}/bin/catalina.sh
	sed -i "s|\${catalina\.base}/logs|${NEW_TOMCAT_LOGS_DIR}|g" ${DM_JMS_HOME}/conf/logging.properties
	sed -i "s|directory=\"logs\"|directory=\"$NEW_TOMCAT_LOGS_DIR\"|g" ${DM_JMS_HOME}/conf/server.xml
	sed -i "s|${DM_JMS_HOME}/logs|${NEW_TOMCAT_LOGS_DIR}|g" ${DM_JMS_HOME}/webapps/ACS/WEB-INF/classes/log4j2.properties
	sed -i "s|${DM_JMS_HOME}/logs|${NEW_TOMCAT_LOGS_DIR}|g" ${DM_JMS_HOME}/webapps/DmMail/WEB-INF/classes/log4j2.properties
	sed -i "s|${DM_JMS_HOME}/logs|${NEW_TOMCAT_LOGS_DIR}|g" ${DM_JMS_HOME}/webapps/DmMethods/WEB-INF/classes/log4j2.properties
	sed -i "s|${DM_JMS_HOME}/logs|${NEW_TOMCAT_LOGS_DIR}|g" ${DM_JMS_HOME}/webapps/dmotdsrest/WEB-INF/classes/log4j2.properties
	sed -i "s|${DM_JMS_HOME}/logs|${NEW_TOMCAT_LOGS_DIR}|g" ${DM_JMS_HOME}/webapps/oAuthAuthentication/WEB-INF/classes/log4j2.properties
	sed -i "s|${DM_JMS_HOME}/logs|${NEW_TOMCAT_LOGS_DIR}|g" ${DM_JMS_HOME}/webapps/OTDSAuthentication/WEB-INF/classes/log4j2.properties
	sed -i "s|${DM_JMS_HOME}/logs|${NEW_TOMCAT_LOGS_DIR}|g" ${DM_JMS_HOME}/webapps/SAMLAuthentication/WEB-INF/classes/log4j2.properties
}

export FROM_CS_STARTUP=true
echo "$(date) In cs_startup.sh"
if [ "$KUBERNETES" = "true" ]
then
	rm -f ${DOCUMENTUM}/kube/startup-completed
	if [ "${IS_VAULT_ENABLED}" = "true" ]
	then
		handleDSISStartup
		instalOwnerPassword=$(curl $DSIS_URL/secret/$INSTALL_OWNER_PASSWORD)
	fi
	
	installownerfromimage=`cat $DM_DOCKER_HOME/installowner | grep oldinstallowner | awk -F = '{print $2}' | sed -e 's/ //g'`
	#image changes
	if [ "$installownerfromimage" != "$INSTALL_OWNER" ]
	then
		echo "$(date) Renaming user $installownerfromimage to $INSTALL_OWNER"
		echo "$INSTALL_OWNER ALL=NOPASSWD:    ALL" | sudo tee -a /etc/sudoers
		sudo usermod --login "$INSTALL_OWNER" --move-home --home "/home/$INSTALL_OWNER" $installownerfromimage
		sudo groupmod --new-name "$INSTALL_OWNER" $installownerfromimage
		#remove sudo permission for old install owner
		sudo sed -i -e "s;\b$installownerfromimage\b.*; ;" /etc/sudoers
		export HOME="/home/$INSTALL_OWNER"
		export USER="$(whoami)"
		if [ "$IS_VAULT_ENABLED" = "true" ]
		then
			echo "$instalOwnerPassword" | sudo passwd --stdin $INSTALL_OWNER
		else
			echo "$INSTALL_OWNER_PASSWORD" | sudo passwd --stdin $INSTALL_OWNER
		fi
		sed -i -e "s;$installownerfromimage;$INSTALL_OWNER;" /home/$INSTALL_OWNER/.com.zerog.registry.xml
		sed -i -e "s;<param-value>$installownerfromimage</param-value>;<param-value>$INSTALL_OWNER</param-value>;" $DOCUMENTUM/$TOMCAT/webapps/DmMethods/WEB-INF/web.xml
		echo "oldinstallowner=${INSTALL_OWNER}" > $DM_DOCKER_HOME/installowner
	else
		echo "$(date) Install owner is already $installownerfromimage"
	fi

	update_tomcat_logs_location

	#docbase changes for upgrade scenario
	installeddocbasefile="${DOCUMENTUM}/kube/$DOCBASE_NAME-installed"	
	if [ -f "$installeddocbasefile" ]
	then
		installownerfile="$DOCUMENTUM/kube/installowner"
		if [ -f "$installownerfile" ]
		then
			oldinstallowner=`cat $DOCUMENTUM/kube/installowner | grep installowner | awk -F = '{print $2}' | sed -e 's/ //g'`
		else
			# could be an upgrade scenario from pod without install owner change support, default to dmadmin
			oldinstallowner=dmadmin
		fi
		echo "$(date) Docbase is installed with $oldinstallowner"
		if [ "$oldinstallowner" != "$INSTALL_OWNER" ]
		then
			#Migration utility will rename existing install owner in the database
			#This will cause readiness probe to fail in other replicas, so disabling it globally
			touch -f $DOCUMENTUM/data/ignore-readiness
			#Don't want to disable readiness in the current pod
			touch -f $DOCUMENTUM/enable-readiness
			#docbase changes using Migration utility
			echo "$(date) Invoking Migraton utility to change user $oldinstallowner to $INSTALL_OWNER"
			cp ${DM_DOCKER_HOME}/config/config.xml ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			if [ "$DB_TYPE" = "oracle" ]
			then
				sed -i -e "s;<entry key=\"dbms\">.*;<entry key=\"dbms\">oracle</entry>;" ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
				sed -i -e "s/MigrationUtil.jar/MigrationUtil.jar:ojdbc10.jar/" $DM_HOME/install/external_apps/MigrationUtil/MigrationUtil.sh
			else
				sed -i -e "s;<entry key=\"dbms\">.*;<entry key=\"dbms\">postgres</entry>;" ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
				sed -i -e "s/MigrationUtil.jar/MigrationUtil.jar:postgresql.jar/" $DM_HOME/install/external_apps/MigrationUtil/MigrationUtil.sh
			fi
			sed -i -e "s;<entry key=\"tgt_database_server\">.*;<entry key=\"tgt_database_server\">$DATABASE_HOST</entry>;" ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			sed -i -e "s;<entry key=\"port_number\">.*;<entry key=\"port_number\">$DATABASE_SERVER_PORT</entry>;" ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			#<entry key="isRCS">no</entry> ---> will handle it later for RCS 
			sed -i -e "s;<entry key=\"DocbaseName.1\">.*;<entry key=\"DocbaseName.1\">$DOCBASE_NAME</entry>;" ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			sed -i -e "s;<entry key=\"DocbasePassword.1\">.*;<entry key=\"DocbasePassword.1\">$DOCBASE_PASSWORD</entry>;" ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			sed -i -e '/ChangeInstallOwner/s/no/yes/' ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			sed -i -e "s;<entry key=\"InstallOwner\">.*;<entry key=\"InstallOwner\">$oldinstallowner</entry>;" ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			sed -i -e "s;<entry key=\"NewInstallOwner\">.*;<entry key=\"NewInstallOwner\">$INSTALL_OWNER</entry>;" ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			sed -i -e '/ChangeDocbaseID/s/yes/no/' ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			sed -i -e '/ChangeServerName/s/yes/no/' ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			sed -i -e '/ChangeDocbaseName/s/yes/no/' ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			sed -i -e '/DockerSeamlessUpgrade/s/yes/no/' ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			sed -i -e '/ChangeHostName/s/yes/no/' ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			if [ "$IS_VAULT_ENABLED" = "true" ]
			then
				sed -i -e "s;<entry key=\"vaultEnabled\">.*;<entry key=\"vaultEnabled\">yes</entry>;" ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
				sed -i -e "s;<entry key=\"dsis_url\">.*;<entry key=\"dsis_url\">$DSIS_URL</entry>;" ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
			fi
			echo "$(date) Checking database availability with $DATABASE_HOST:$DATABASE_SERVER_PORT"
			result=1
			COUNTER=0
			while [ $COUNTER -lt 1800 ]; do
				(echo > /dev/tcp/$DATABASE_HOST/$DATABASE_SERVER_PORT) >/dev/null 2>&1
				 result=$?
				 if [[ $result -eq 0 ]]; then
					echo "$(date) Database is ready"
					break
				 fi
				 let COUNTER=COUNTER+1
				 sleep 1
			done
			if [[ $result -ne 0 ]]; then
				echo "$(date) Database is not yet ready, MigrationUtility will fail to update DB references"
			fi
			cd ${DM_HOME}/install/external_apps/MigrationUtil; source $DM_HOME/bin/dm_set_server_env.sh; ${DM_HOME}/install/external_apps/MigrationUtil/MigrationUtil.sh
			if [ $? -eq 0 ]
			then
				echo "$(date) MigrationUtility has succeeded. Please check logs at container's ${DM_HOME}/install/external_apps/MigrationUtil/MigrationUtilLogs"
			else
				echo "$(date) ERROR: MigrationUtility has failed. Please check logs at container's ${DM_HOME}/install/external_apps/MigrationUtil/MigrationUtilLogs"
			fi
			#changes to web.xml in mdserver_conf backup 
			sed -i -e "s;<param-value>$oldinstallowner</param-value>;<param-value>$INSTALL_OWNER</param-value>;" $DOCUMENTUM/mdserver_conf/web.xml
			sed -i -e "s;<param-value>$oldinstallowner</param-value>;<param-value>$INSTALL_OWNER</param-value>;" $DOCUMENTUM/share/mdserver_conf/web.xml

			# Preserving the existing the MigrationUtilLogs folder content as gzip.
			migrationUtilLogDir="${DM_HOME}/install/external_apps/MigrationUtil/MigrationUtilLogs"
			if [ -d "$migrationUtilLogDir" ];
			then
				# Create ${DOCUMENTUM}/kube/MigrationUtilLogs folder if not exist in the shared PV mount
				mkdir -p "${DOCUMENTUM}/kube/MigrationUtilLogs"
				# Archiving  ${DM_HOME}/install/external_apps/MigrationUtil/MigrationUtilLogs folder as GZip file 
				tar zcvf "${DOCUMENTUM}/kube/MigrationUtilLogs/MirgrationUtilLogs-$(hostname)-$(date +"%d-%b-%Y-%H_%M_%S")".gz  "${migrationUtilLogDir}"
			fi
		fi
	fi
    
	if [ -z "$onlyDocbroker" ] || [ "$onlyDocbroker" = "false" ]
    then
		mkdir ${DOCUMENTUM}/mip
		unzip -oq ${DOCUMENTUM}/mip.zip -d ${DOCUMENTUM}/mip
    	chmod -R 755  ${DOCUMENTUM}/mip
		
		if [ -n "${MIP_PROXY_HOST}" ] && [ -n "${MIP_PROXY_PORT}" ]
		then
			if [ `grep http_proxy ${DOCUMENTUM}/mip/mip_start.sh | wc -l` -eq 0 ]
			then
			sed -i '/nohup/i\
export http_proxy=http://${MIP_PROXY_HOST}:${MIP_PROXY_PORT}\
export https_proxy=http://${MIP_PROXY_HOST}:${MIP_PROXY_PORT}' ${DOCUMENTUM}/mip/mip_start.sh
			fi
		fi
		
        source /home/${INSTALL_OWNER}/.bashrc
		${DOCUMENTUM}/mip/mip_start.sh
		mipstatus=$?
                if [ "$mipstatus" == $SUCCESS ]; then
                        echo "$(date) MIP Started.."
                else
                        echo "$(date) Failed to start MIP.. "
                fi

	fi
	
	echo "$(date) Documentum configuration/startup with $INSTALL_OWNER"
	echo "installowner=${INSTALL_OWNER}" > $DOCUMENTUM/kube/installowner
	/opt/dctm_docker/kube_cs.sh
	status=$?

	# Preserving the pod logs and temp as gzip.
	podLogs="/opt/dctm_docker/logs"
	if [ -d "$podLogs" ]; 
	then
		mkdir -p "${DOCUMENTUM}/kube/podLogs"
		tar zcf "${DOCUMENTUM}/kube/podLogs/podLogs-$(hostname)-$(date +"%d-%b-%Y-%H_%M_%S")".gz -C "${podLogs}" .
		echo "$(date) Pod logs archived under ${DOCUMENTUM}/kube/podLogs"
	fi

	tmpLogs="/tmp"
	if [ -d "$tmpLogs" ]; 
	then
		mkdir -p "${DOCUMENTUM}/kube/tmpLogs"
		tar zcf "${DOCUMENTUM}/kube/tmpLogs/tmpLogs-$(hostname)-$(date +"%d-%b-%Y-%H_%M_%S")".gz -C "${tmpLogs}" .
		echo "$(date) Temp logs archived under ${DOCUMENTUM}/kube/tmpLogs"
	fi

	tomcatLogs="${NEW_TOMCAT_LOGS_DIR}"
	if [ -d "$tomcatLogs" ]; 
	then
		mkdir -p "${DOCUMENTUM}/kube/tomcatLogs"
		tar zcf "${DOCUMENTUM}/kube/tomcatLogs/tomcatLogs-$(hostname)-$(date +"%d-%b-%Y-%H_%M_%S")".gz -C "${tomcatLogs}" .
		echo "$(date) Tomcat logs archived under ${DOCUMENTUM}/kube/tomcatLogs"
	fi

	#remove sudo permission for install owner
	sudo sed -i -e "s;\b$INSTALL_OWNER\b.*; ;" /etc/sudoers
	rm -rf ${DM_DOCKER_HOME}/config/configDocbroker.properties
	rm -rf ${DM_DOCKER_HOME}/config/linux_config.properties
	rm -rf ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
	rm -rf $DOCUMENTUM/data/ignore-readiness
	touch -f ${DOCUMENTUM}/kube/startup-completed

	if [ $status != $SUCCESS ]; 
	then
		echo "$(date) cs_startup.sh failed"
	else
		echo "$(date) cs_startup.sh completed successfully"
	fi
else   
  sudo -E bash -c /opt/dctm_docker/configure-stateless-server
  if [ $? != $SUCCESS ]
  then
    echo "$(date) cs_startup.sh failed"
  else
    echo "$(date) cs_startup.sh completed successfully"
  fi
fi

tail -f /dev/null & wait
