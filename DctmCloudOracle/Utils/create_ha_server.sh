#!/bin/sh
###EMC Documentum on Docker
###(c) Copyright EMC Corp., 1992 - 2016
###All rights reserved.
###Version 1.0 dated 08/Sep/2016

echo USAGE : ${DM_DOCKER_HOME}/scripts/create_ha_docbase.sh hostname intdocbrokerport extdocbrokerport

hostname=$1
extdocbrokerport=$3
docbase=$DOCBASE_NAME
intdocbrokerport=$2
SUCCESS=0
FAILURE=1
logfile=${DM_DOCKER_HOME}/logs/${hostname}.log
file="${DOCUMENTUM}/dba/config/${docbase}/server_${hostname}_${docbase}.ini"
	
if [ -f "$file" ]
then
        echo "Server already installed" >> $logfile
		#restore the method sever and odbc config files
		ln -s ${DM_HOME} ${DOCUMENTUM_PATH}/product/${PRIMARY_MAJAR_VERSION}
		ln -s ${DOCUMENTUM}/dba ${DOCUMENTUM_PATH}/dba
		${DM_DOCKER_HOME}/scripts/methodserver_restore_backup_changes.sh restore
		
else
        
		echo "AEK_ALGORITHM : $AEK_ALGORITHM"  >> $logfile
		echo DOCBROKER_HOST : $DOCBROKER_HOST >> $logfile
		echo DOCBROKER_PORT	 : $DOCBROKER_PORT	 >> $logfile
		echo SERVER_CONFIG_NAME : $SERVER_CONFIG_NAME >> $logfile
       	chmod -R 775 ${DM_DOCKER_HOME}/config
		echo Setting values in odbc.ini >> $logfile
		echo DATABASE_HOST : $DATABASE_HOST >> $logfile
		echo DATABASE_USER : $DATABASE_USER >> $logfile
		
		dbserver=$DATABASE_HOST
		dbuser=$DATABASE_USER
		dbpassword=$DATABASE_PASSWORD
		if [ "$DB_TYPE" = "oracle" ]
		then
				sed -i -e "s/10.31.71.131/$dbserver/"  $TNS_ADMIN/tnsnames.ora
				sed -i -e "s/1521/${DATABASE_SERVER_PORT}/"  $TNS_ADMIN/tnsnames.ora
				if [ $SERVICE_NAME ]
				then
					sed -i -e "s/orcl/$SERVICE_NAME/I"  $TNS_ADMIN/tnsnames.ora
				fi
				chown -R oracle:oinstall $TNS_ADMIN/tnsnames.ora
		else
				sed -i -e "s/Servername = .*/Servername = $dbserver/"  /etc/odbc.ini
				sed -i -e "s/UserName = .*/UserName = $dbuser/"  /etc/odbc.ini
				sed -i -e "s/Password = .*/Password = $dbpassword/"  /etc/odbc.ini
				sed -i -e "s/Port = .*/Port = $DATABASE_SERVER_PORT/"  /etc/odbc.ini
				if [ $SERVICE_NAME ]
				then
					sed -i -e "s/MyPostgres/$SERVICE_NAME/I"  /etc/odbc.ini
				fi
				chmod -R 664 /etc/odbc.ini
		fi
        echo Setting values in cfs_linux_config.properties >> $logfile
				
		#AEK Alogorithm changes

		
		sed -i -e "s/common.aek.algorithm=.*/common.aek.algorithm=$AEK_ALGORITHM/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/common.aek.passphrase.password=.*/common.aek.passphrase.password=$AEK_PASSPHRASE/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/common.aek.key.name=.*/common.aek.key.name=$AEK_NAME/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.VALIDATE_FQDN=.*/SERVER.VALIDATE_FQDN=$VALIDATE_FQDN/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.PROJECTED_CONNECTION_BROKER_PORT=.*/SERVER.PROJECTED_CONNECTION_BROKER_PORT=$intdocbrokerport/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.CONNECTION_BROKER_PORT=.*/SERVER.CONNECTION_BROKER_PORT=$intdocbrokerport/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.CONNECTION_BROKER_NAME=.*/SERVER.CONNECTION_BROKER_NAME=Docbroker/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
				
        sed -i -e "s/SERVER.PRIMARY_CONNECTION_BROKER_HOST=.*/SERVER.PRIMARY_CONNECTION_BROKER_HOST=$DOCBROKER_HOST/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.PRIMARY_CONNECTION_BROKER_PORT=.*/SERVER.PRIMARY_CONNECTION_BROKER_PORT=$DOCBROKER_PORT/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.PROJECTED_CONNECTION_BROKER_HOST=.*/SERVER.PROJECTED_CONNECTION_BROKER_HOST=$hostname/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.DOCBASE_SERVICE_NAME=.*/SERVER.DOCBASE_SERVICE_NAME=dm_${docbase}/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.FQDN=.*/SERVER.FQDN=$hostname/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.DOCBASE_NAME=.*/SERVER.DOCBASE_NAME=$docbase/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.PRIMARY_SERVER_CONFIG_NAME=.*/SERVER.PRIMARY_SERVER_CONFIG_NAME=$SERVER_CONFIG_NAME/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.REPOSITORY_USERNAME=.*/SERVER.REPOSITORY_USERNAME=$INSTALL_OWNER/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.SECURE.REPOSITORY_PASSWORD=.*/SERVER.SECURE.REPOSITORY_PASSWORD=$INSTALL_OWNER_PASSWORD/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.REPOSITORY_USERNAME_WITH_DOMAIN=.*/SERVER.REPOSITORY_USERNAME_WITH_DOMAIN=$INSTALL_OWNER/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.REPOSITORY_HOSTNAME.*/SERVER.REPOSITORY_HOSTNAME=$DOCBROKER_HOST/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/CFS_SERVER_CONFIG_NAME=.*/CFS_SERVER_CONFIG_NAME=${hostname}_${docbase}/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.PROJECTED_DOCBROKER_PORT_OTHER=.*/SERVER.PROJECTED_DOCBROKER_PORT_OTHER=$GLOBAL_REGISTRY_DOCBROKER_PORT/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.PROJECTED_DOCBROKER_HOST_OTHER=.*/SERVER.PROJECTED_DOCBROKER_HOST_OTHER=$GLOBAL_REGISTRY_DOCBROKER_HOST/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.GLOBAL_REGISTRY_REPOSITORY=.*/SERVER.GLOBAL_REGISTRY_REPOSITORY=$GLOBAL_REGISTRY_REPOSITORY/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.SECURE.BOF_REGISTRY_USER_PASSWORD=.*/SERVER.SECURE.BOF_REGISTRY_USER_PASSWORD=$GLOBAL_REGISTRY_PASSWORD/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
                sed -i -e "s#SERVER.DOCUMENTUM_DATA=.*#SERVER.DOCUMENTUM_DATA=$DOCUMENTUM_DATA_PATH#"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s#SERVER.DOCUMENTUM_SHARE=.*#SERVER.DOCUMENTUM_SHARE=$DOCUMENTUM_SHARE_PATH#"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		su $INSTALL_OWNER -c "cd; kill -9 `ps -ef | grep dm_launch_cfs_server_config_program | awk '{print($2)}'`" >> $logfile
			
		if [ "$ENABLE_XHIVE_CONNECTOR" ] || [ "$ENABLE_XHIVE_CONNECTOR" = "false" ]
		then
				echo "XhiveConnector is disbaled" >> $logfile
		else
			if [ -f ${DOCUMENTUM}/xhive_storage ]
			then
		        	echo "XhiveConnector is enabled" >> $logfile
				chown -R $INSTALL_OWNER ${DOCUMENTUM}/xhive_storage
				
				chown -R $INSTALL_OWNER ${DOCUMENTUM}/$TOMCAT/webapps/XhiveConnector
			fi
		fi
		if [ "${DOCUMENTUM_PATH}" = "${DOCUMENTUM}" ]
		then 
				echo "Primary and Secondary server DOCUMENTUM are same" >> $logfile
		else
				echo "Creating ${DOCUMENTUM_PATH}/dba and ${PRIMARY_DOCUMENTUM}/product" >> $logfile
				mkdir -p ${DOCUMENTUM_PATH}
				mkdir -p ${DOCUMENTUM_PATH}/product
				
				echo "Creating  symbolic link to avoid convert error in headstart script" >> $logfile
				ln -s ${DM_HOME} ${DOCUMENTUM_PATH}/product/${PRIMARY_MAJAR_VERSION}
				ln -s ${DOCUMENTUM}/dba ${DOCUMENTUM_PATH}/dba
				
		fi

	        echo Installing Docbase... >> $logfile

       		su $INSTALL_OWNER -c "cd ;$DM_HOME/install/dm_launch_cfs_server_config_program.sh -f ${DM_DOCKER_HOME}/config/cfs_linux_config.properties"
		if [ $? != $SUCCESS ]
		then        
				echo "ERROR : The installation has failed. Please check install logs at container's ${DM_HOME}/install/logs/install.log" >> $logfile
				exit $FAILURE
		
		fi

        echo Docbase installation Completed.... >> $logfile
		## Configure SMTP details
		if [ $CONFIGURE_EMAIL ]
			then
			#create DQL query and save to temporary file.
			email_config="${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/emailconfig.txt"
			echo -e "update dm_server_config object set smtp_server = '$SMTP_SERVER'\ngo" >> $email_config
			echo -e "update dm_user object set user_address='$EMAIL_ADDRESS' where user_name='$INSTALL_OWNER'\ngo" >> $email_config
			#execute DQL query.
			source $DM_HOME/bin/dm_set_server_env.sh;$DM_HOME/bin/idql $DOCBASE_NAME -U$INSTALL_OWNER -P$INSTALL_OWNER_PASSWORD -R$email_config >> ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/SMTPConfig.out
			#remove temp file
			rm $email_config
			echo "Executing the SMTPConfig.ebs script.." >> $logfile
			source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f ${DM_HOME}/install/admin/SMTPConfig.ebs -e Install -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ${INSTALL_OWNER_PASSWORD} "${SMTP_SERVER}" "${SMTP_PORT}" "${SMTP_AUTH}" "${SMTP_USER}" "${SMTP_PASS}" "${SMTP_SSL}" >> ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/SMTPConfig.out
		fi
        echo Stop Docbase >> $logfile
		su $INSTALL_OWNER -c "cd; kill -9 `ps -ef | grep $docbase | awk '{print($2)}'`" >> $logfile
		echo set the Docbrokers in server.ini >> $logfile
		sed -i -e "s/proximity=9001/proximity = 1/"  ${DOCUMENTUM}/dba/config/$docbase/server_${hostname}_${docbase}.ini
		sed -i -e "s/proximity=9010/proximity = 2/"  ${DOCUMENTUM}/dba/config/$docbase/server_${hostname}_${docbase}.ini
		echo "[DOCBROKER_PROJECTION_TARGET_2]" >> /${DOCUMENTUM}/dba/config/$docbase/server_${hostname}_${docbase}.ini
	    sed -i -e "/DOCBROKER_PROJECTION_TARGET_2/ a proximity = 1"  ${DOCUMENTUM}/dba/config/$docbase/server_${hostname}_${docbase}.ini
        sed -i -e "/DOCBROKER_PROJECTION_TARGET_2/ a port = $extdocbrokerport"  ${DOCUMENTUM}/dba/config/$docbase/server_${hostname}_${docbase}.ini
        sed -i -e "/DOCBROKER_PROJECTION_TARGET_2/ a host = $hostname"  ${DOCUMENTUM}/dba/config/$docbase/server_${hostname}_${docbase}.ini
        chown -R $INSTALL_OWNER:$INSTALL_OWNER ${DOCUMENTUM}/dba/config/$docbase/server_${hostname}_${docbase}.ini
        
		#take backup the config files
		${DM_DOCKER_HOME}/scripts/methodserver_restore_backup_changes.sh backup
fi

