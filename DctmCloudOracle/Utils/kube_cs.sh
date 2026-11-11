#!/bin/bash
SUCCESS=0
FAILURE=1
isHA="FALSE"
alreadyInstalled="FALSE"
host_index=''
SERVER_CONFIG_NAME=''
PRIMARY_HOSTNAME=''
hostname=`hostname -f`
ext_docbroker=''
logfile=''
docbasetrustStorePasswordPrefix=$(echo $DFC_SSL_TRUSTSTORE_PASSWORD | cut -d'/' -f1)
docbrokertrustStorePasswordPrefix=$(echo $DOCBROKER_TRUST_PASSWORD | cut -d'/' -f1)
alreadyprojectedexternal="FALSE"
#------------------------------------------------------------------------
handle_aek_creation() {
	log "==============================================================================================="
	log "[handle_aek_creation] ==>> Starting the creation of AEK key"
	log "[handle_aek_creation] ==>> New key name ${AEK_NAME}"
	log "[handle_aek_creation] ==>> New key algorithm ${AEK_ALGORITHM}"
	log "[handle_aek_creation] ==>> New key type ${AEK_LOCATION}"
	log "[handle_aek_creation] ==>> Container name ${CONTAINER_NAME}"
	log "==============================================================================================="
	server_ini_file=$1
	status=$SUCCESS

	# Get old AEK name from server.ini
	oldAEKName=$( sed -n -e '/crypto_keyname/ s/.*\= *//p' ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file})
	# Get the key location from server.ini
	oldAEKLocation=$( sed -n -e '/crypto_keystore/ s/.*\= *//p' ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file})
	cryptoALg=`expr substr $AEK_ALGORITHM 1 3`
	cryptoKeySize=`expr substr $AEK_ALGORITHM 5 3`
	cryptomode=${cryptoALg}${cryptoKeySize}_RSA2048_SHA3_384

	
	if [ ${status} = $SUCCESS ]
	then
		if [ -f $DOCUMENTUM/shared_key/$AEK_NAME ]
		then
			#Key already upgraded in other deployment and shared with the current for reuse
			log "[handle_aek_creation] ==>> Copying upgraded AEK from shared PVC ${DOCUMENTUM}/shared_key"
			cp $DOCUMENTUM/shared_key/$AEK_NAME $DOCUMENTUM/dba/secure/$AEK_NAME
		fi
		if [ -f ${DOCUMENTUM}/dba/secure/${AEK_NAME} ]
		then
			log "[handle_aek_creation] ==>> AEK key ${AEK_NAME} already exists in ${DOCUMENTUM}/dba/secure folder using that"
		else
		    # Check whether key is local, vault or remote
			if [ "${AEK_LOCATION}" = "Local" ]
			then
				# Now we will create a local AEK key.
				source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_create -keyname $AEK_NAME -passphrase $AEK_PASSPHRASE -algorithm $AEK_ALGORITHM
			elif [ "${IS_VAULT_ENABLED}" = "true" ]
			then
				if [ "${AEK_LOCATION}" = "Remote_Vault" ]
				then
					# Now we will create a remote vault key
					source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_create -keyname $AEK_NAME -dsis_url $DSIS_URL -secret_id $AEK_PASSPHRASE -algorithm $AEK_ALGORITHM -vault
				elif [ "${AEK_LOCATION}" = "Remote" ]
				then
					source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_create -keyname $AEK_NAME -algorithm $AEK_ALGORITHM -key_id $KMS_MASTER_KEY_ID -kms_url $KMS_URL -kms_api_key $KMS_API_KEY -dsis_url $DSIS_URL -remote -vault
				fi
			else
				# Now we will create a remote key
				source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_create -keyname $AEK_NAME -algorithm $AEK_ALGORITHM -key_id $KMS_MASTER_KEY_ID -kms_url $KMS_URL -kms_api_key $KMS_API_KEY -remote
			fi
		fi
		
		status=$?
		if [ ${status} != $SUCCESS ]
		then
			log "[handle_aek_creation] ==>> ${AEK_NAME} key creation failed"
		else
			log "[handle_aek_creation] ==>> ${AEK_NAME} key creation succeeded"
			if [ "$SHARE_KEY" == "true" ]
			then
				log "[handle_aek_creation] ==>> Backing up upgraded AEK ${AEK_NAME} to shared PVC ${DOCUMENTUM}/shared_key"
				cp $DOCUMENTUM/dba/secure/$AEK_NAME $DOCUMENTUM/shared_key/$AEK_NAME
			fi
			
		fi
	fi

	# Now call the dm_crypto_upgrade utility to update things in DB
	if [ ${status} = $SUCCESS ]
	then
		log "[handle_aek_creation] ==>> Running the dm_crypto_upgrade process"
		
		# Check whether key is local or remote
		if [ "${oldAEKLocation}" = "Local" ]
		then
			if [ "${AEK_LOCATION}" = "Local" ]
			then
				# This means both old and new AEK are local keys
				current_time=$(date "+%Y.%m.%d-%H.%M.%S")
				
				source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade -server_ini ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} -upgrade_mode UPGRADE_AEK_KEY -trace_file ${DOCUMENTUM}/data/aek_upgrade_files/dm_crypto_upgrade_${oldAEKName}_${AEK_NAME}.${current_time}.out -old_keyname $oldAEKName -new_keyname $AEK_NAME -new_crypto_mode $cryptomode -old_key_passphrase $OLD_AEK_PASSPHRASE -new_key_passphrase $AEK_PASSPHRASE
			elif [ "${IS_VAULT_ENABLED}" = "true" ]
			then
				# This means old key is local and new AEK is a vault key
				current_time=$(date "+%Y.%m.%d-%H.%M.%S")
				if [ "${AEK_LOCATION}" = "Remote_Vault" ]
				then
					source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade -server_ini ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} -upgrade_mode UPGRADE_AEK_KEY -trace_file ${DOCUMENTUM}/data/aek_upgrade_files/dm_crypto_upgrade_${oldAEKName}_${AEK_NAME}.${current_time}.out -old_keyname $oldAEKName -new_keyname $AEK_NAME -new_crypto_mode $cryptomode -old_key_passphrase $oldaekPwd -new_dsis_url $DSIS_URL
				elif [ "${AEK_LOCATION}" = "Remote" ]
				then
					source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade -server_ini ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} -upgrade_mode UPGRADE_AEK_KEY -trace_file ${DOCUMENTUM}/data/aek_upgrade_files/dm_crypto_upgrade_${oldAEKName}_${AEK_NAME}.${current_time}.out -old_keyname $oldAEKName -new_keyname $AEK_NAME -new_crypto_mode $cryptomode -old_key_passphrase $oldaekPwd -new_KMS_URL $KMS_URL -new_KMS_API_KEY $KMS_API_KEY -new_dsis_url $DSIS_URL -remote
				fi
			else
				# This means old key was local and new key is remote key.
				current_time=$(date "+%Y.%m.%d-%H.%M.%S")

				source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade -server_ini ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} -upgrade_mode UPGRADE_AEK_KEY -trace_file ${DOCUMENTUM}/data/aek_upgrade_files/dm_crypto_upgrade_${oldAEKName}_${AEK_NAME}.${current_time}.out -old_keyname $oldAEKName -new_keyname $AEK_NAME -new_crypto_mode $cryptomode -old_key_passphrase $OLD_AEK_PASSPHRASE -new_KMS_URL $KMS_URL -new_KMS_API_KEY $KMS_API_KEY -remote
			fi
			
		else
		    if [ "${AEK_LOCATION}" = "Local" ]
			then
				# This means old key is remote key new key is a local key.
				current_time=$(date "+%Y.%m.%d-%H.%M.%S")

				source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade -server_ini ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} -upgrade_mode UPGRADE_AEK_KEY -trace_file ${DOCUMENTUM}/data/aek_upgrade_files/dm_crypto_upgrade_${oldAEKName}_${AEK_NAME}.${current_time}.out -old_keyname $oldAEKName -new_keyname $AEK_NAME -new_crypto_mode $cryptomode -new_key_passphrase $AEK_PASSPHRASE
			elif [ "${IS_VAULT_ENABLED}" = "true" ]
			then
				# This means old key is remote key new key is a vault key.
				current_time=$(date "+%Y.%m.%d-%H.%M.%S")
				if [ "${AEK_LOCATION}" = "Remote_Vault" ]
				then
					source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade -server_ini ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} -upgrade_mode UPGRADE_AEK_KEY -trace_file ${DOCUMENTUM}/data/aek_upgrade_files/dm_crypto_upgrade_${oldAEKName}_${AEK_NAME}.${current_time}.out -old_keyname $oldAEKName -new_keyname $AEK_NAME -new_crypto_mode $cryptomode -new_dsis_url $DSIS_URL
				elif [ "${AEK_LOCATION}" = "Remote" ]
				then
					source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade -server_ini ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} -upgrade_mode UPGRADE_AEK_KEY -trace_file ${DOCUMENTUM}/data/aek_upgrade_files/dm_crypto_upgrade_${oldAEKName}_${AEK_NAME}.${current_time}.out -old_keyname $oldAEKName -new_keyname $AEK_NAME -new_crypto_mode $cryptomode -new_KMS_URL $KMS_URL -new_KMS_API_KEY $KMS_API_KEY -new_dsis_url $DSIS_URL -remote
				fi
			else
				# This means old key and new key are remote keys
				current_time=$(date "+%Y.%m.%d-%H.%M.%S")

				source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade -server_ini ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} -upgrade_mode UPGRADE_AEK_KEY -trace_file ${DOCUMENTUM}/data/aek_upgrade_files/dm_crypto_upgrade_${oldAEKName}_${AEK_NAME}.${current_time}.out -old_keyname $oldAEKName -new_keyname $AEK_NAME -new_crypto_mode $cryptomode -new_KMS_URL $KMS_URL -new_KMS_API_KEY $KMS_API_KEY -remote
			fi
		fi		
		status=$?
		if [ ${status} = 1 ]
		then
			log "[handle_aek_creation] ==>> dm_crypto_upgarde utility succeeded"
			status=0
		else
			log "[handle_aek_creation] ==>> dm_crypto_upgarde utility failed"
			status=1
		fi
	fi

	# Now call the dm_crypto_upgrade52 to re-encrypt with new AEK key
	if [ ${status} = $SUCCESS ]
	then
		log "[handle_aek_creation] ==>> Running the dm_crypto_upgrade_52 process"
		
		if [ "${AEK_LOCATION}" = "Local" ]
		then
			# Now invoke the dm_crypto_upgrade52 command for local AEK key.
			source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade_52 -keyname $AEK_NAME -passphrase $AEK_PASSPHRASE -docbase $DOCBASE_NAME
		elif [ "${IS_VAULT_ENABLED}" = "true" ]
		then
			# Now invoke the dm_crypto_upgrade52 command for vault based AEK key.
			if [ "${AEK_LOCATION}" = "Remote_Vault" ]
			then
		    	source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade_52 -keyname $AEK_NAME -dsis_url $DSIS_URL -docbase $DOCBASE_NAME
			elif [ "${AEK_LOCATION}" = "Remote" ]
			then
				source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade_52 -keyname $AEK_NAME -kms_url $KMS_URL -kms_api_key $KMS_API_KEY -docbase $DOCBASE_NAME -dsis_url $DSIS_URL
			fi

		else
		    # Now invoke the dm_crypto_upgrade52 command for remote AEK key
			source ${DM_HOME}/bin/dm_set_server_env.sh; ${DM_HOME}/bin/dm_crypto_upgrade_52 -keyname $AEK_NAME -kms_url $KMS_URL -kms_api_key $KMS_API_KEY -docbase $DOCBASE_NAME
		fi
		
		status=$?
		if [ ${status} != $SUCCESS ]
		then
			log "[handle_aek_creation] ==>> dm_crypto_upgrade_52 utility failed"
		else
			log "[handle_aek_creation] ==>> dm_crypto_upgrade_52 utility succeeded"
		fi
	fi
	
	if [ ${status} = $SUCCESS ]
	then
	
		log "[handle_aek_creation] ==>> Running the dm_encrypt_password process"
		mv -f ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dbpasswd.txt ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dbpasswd_old.txt
		echo $DOCBASE_PASSWORD >> ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dbpasswd.txt
		if [ "${AEK_LOCATION}" = "Local" ]
		then
			# Now invoke the dm_crypto_upgrade52 command for local AEK key.
			source ${DM_HOME}/bin/dm_set_server_env.sh; dm_encrypt_password -docbase $DOCBASE_NAME -rdbms -encrypt $DOCBASE_PASSWORD -keyname $AEK_NAME -passphrase $AEK_PASSPHRASE
		elif [ "${AEK_LOCATION}" = "Remote" ]
		then
			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				# Now invoke the dm_crypto_upgrade52 command for remote AEK key
				source ${DM_HOME}/bin/dm_set_server_env.sh; dm_encrypt_password -docbase $DOCBASE_NAME -rdbms -encrypt $DOCBASE_PASSWORD -keyname $AEK_NAME -kms_url $KMS_URL -kms_api_key $KMS_API_KEY
			fi
		fi
		
		status=$?
		if [ ${status} != $SUCCESS ]
		then
			log "[handle_aek_creation] ==>> dm_encrypt_password utility failed"
		else
			log "[handle_aek_creation] ==>> dm_encrypt_password utility succeeded"
		fi	
	fi
	
	if [ ${status} = $SUCCESS ]
	then
		log "[handle_aek_creation] ==>> Upgrading server ini"
		# Take a backup of the old server.ini
		current_time=$(date "+%Y.%m.%d-%H.%M.%S")
		
		cp -af ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} ${DOCUMENTUM}/data/aek_upgrade_files/${server_ini_file}_${oldAEKName}.${current_time}
		
		# Update server ini
		sed -i -e "s;crypto_mode.*;crypto_mode = ${cryptomode};" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
		sed -i -e "s;crypto_keystore.*;crypto_keystore = ${AEK_LOCATION};" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
		sed -i -e "s;crypto_keyname.*;crypto_keyname = ${AEK_NAME};" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
		
		# Check the key location if it is remote set other parameters also.
		if [ "${IS_VAULT_ENABLED}" = "true" ]
		then
			if [ `grep isDSISEnabled ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} | wc -l` -eq 0 ]
			then
				# Entry not there add new entry
				sed -i -e "/^\[DOCBROKER_PROJECTION_TARGET_0/i \isDSISEnabled = T" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			else
				# Replace existing entry
				sed -i -e "s;isDSISEnabled.*;isDSISEnabled = T;" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			fi
			
			if [ `grep dsis_url ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} | wc -l` -eq 0 ]
			then
				# Entry not there add new entry
				sed -i -e "/^\[DOCBROKER_PROJECTION_TARGET_0/i \dsis_url = $DSIS_URL" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			else
				# Replace existing entry
				sed -i -e "s;dsis_url.*;dsis_url = $DSIS_URL;" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			fi
		fi
		if [ "${AEK_LOCATION}" = "Remote" ]
		then
			log "[handle_aek_creation] ==>> Upgrading kms_url and kms_api_key in server ini"
			# Check if KMS_URL setting is already there
			if [ `grep kms_url ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} | wc -l` -eq 0 ]
			then
				sed -i -e "/^\[DOCBROKER_PROJECTION_TARGET_0/i \kms_url = ${KMS_URL}" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				sed -i -e "/^\[DOCBROKER_PROJECTION_TARGET_0/i \is_kms_enabled = T" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			else
				sed -i -e "s;kms_url.*;kms_url = ${KMS_URL};" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			fi

			# Check if KMS_API_KEY setting is already there
			if [ `grep kms_api_key ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} | wc -l` -eq 0 ]
			then
				sed -i -e "/^\[DOCBROKER_PROJECTION_TARGET_0/i \kms_api_key = $KMS_API_KEY" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			else
				sed -i -e "s;kms_api_key.*;kms_api_key = $KMS_API_KEY;" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			fi
		elif [ "${AEK_LOCATION}" = "Local" ] || [ "${AEK_LOCATION}" = "Remote_Vault" ]
		then
		    # Remove the settings to related remote keys
			sed -i -e "/^\kms_api_key/d" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			sed -i -e "/^\kms_url/d" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			sed -i -e "/^\is_kms_enabled/d" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
		fi

		# Now copy the new aek key, dbpasswd.txt and new crypto mode settings to shared pvc
		log "[handle_aek_creation] ==>> Copy the aek key and dbpassword.txt"

		cp -af ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dbpasswd.txt ${DOCUMENTUM}/data/aek_upgrade_files/.
		cp -af ${DOCUMENTUM}/dba/secure/${AEK_NAME} ${DOCUMENTUM}/data/aek_upgrade_files/.
		
		log "==============================================================================================="
		log "[handle_aek_creation] ==>> AEK creation succeeded"
		log "==============================================================================================="
	fi
}

update_mail_notification_flag()
{
	serverini=$1
	log "Updating mail_notification flag in server.ini"
	if grep -qF mail_notification $serverini;then
		if [ "$EMAIL_NOTIFICATION" = "true" ]
		then
			sed -i -e "s/mail_notification=.*/mail_notification=TRUE/" $serverini
		else
			sed -i -e "s/mail_notification=.*/mail_notification=FALSE/" $serverini
		fi	
	else
		if [ "$EMAIL_NOTIFICATION" = "true" ]
		then
			sed -i -e "s/\[SERVER_STARTUP\]/\[SERVER_STARTUP\]\nmail_notification=TRUE/" $serverini
		else
			sed -i -e "s/\[SERVER_STARTUP\]/\[SERVER_STARTUP\]\nmail_notification=FALSE/" $serverini
		fi	
	fi
}

handle_server_ini_update() {	
	server_ini_file=$1
	cryptoALg=`expr substr $AEK_ALGORITHM 1 3`
	cryptoKeySize=`expr substr $AEK_ALGORITHM 5 3`
	cryptomode=${cryptoALg}${cryptoKeySize}_RSA2048_SHA3_384

	# Get old AEK name from server.ini
	oldAEKName=$( sed -n -e '/crypto_keyname/ s/.*\= *//p' ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file})

	# Check whether AEK details have changed or not
	if  [ "${oldAEKName}" != "${AEK_NAME}" ]
	then
		log "==============================================================================================="
		log "[handle_server_ini_update] ==>> Initiating the server.ini upgrade"
		log "[handle_server_ini_update] ==>> Container name ${CONTAINER_NAME}"
		log "==============================================================================================="
		log "[handle_server_ini_update] ==>> AEK Details have changed. Server.ini update started"
		
		# Check if new AEK is present in shared directory.
		if [ -f ${DOCUMENTUM}/data/aek_upgrade_files/${AEK_NAME} ]
		then
			log "[handle_server_ini_update] ==>> New AEK has been generated in ${DOCUMENTUM}/data/aek_upgrade_files/${AEK_NAME} "
			
			# Now copy the new aek file, dbpassword.txt in secondary pod.
			cp -af ${DOCUMENTUM}/data/aek_upgrade_files/${AEK_NAME} ${DOCUMENTUM}/dba/secure/.
			# Take backup of old dbpasswd.txt file.
			mv -f ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dbpasswd.txt ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dbpasswd_old.txt
			cp -af ${DOCUMENTUM}/data/aek_upgrade_files/dbpasswd.txt ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/.

			# Take a backup of the old server.ini
			current_time=$(date "+%Y.%m.%d-%H.%M.%S")		
			cp -af ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} ${DOCUMENTUM}/data/aek_upgrade_files/${server_ini_file}_${oldAEKName}.${current_time}

			# Update the server.ini parameters in primary pod.
			sed -i -e "s;crypto_mode.*;crypto_mode = ${cryptomode};" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			sed -i -e "s;crypto_keystore.*;crypto_keystore = ${AEK_LOCATION};" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			sed -i -e "s;crypto_keyname.*;crypto_keyname = ${AEK_NAME};" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}

			# Check the key location if it is remote set other parameters also.
			if [ "${IS_VAULT_ENABLED}" = "true" ]
			then
				if [ `grep isDSISEnabled ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} | wc -l` -eq 0 ]
				then
					# Entry not there add new entry
					sed -i -e "/^\[DOCBROKER_PROJECTION_TARGET_0/i \isDSISEnabled = T" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				else
					# Replace existing entry
					sed -i -e "s;isDSISEnabled.*;isDSISEnabled = T;" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				fi
			
				if [ `grep dsis_url ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} | wc -l` -eq 0 ]
				then
					# Entry not there add new entry
					sed -i -e "/^\[DOCBROKER_PROJECTION_TARGET_0/i \dsis_url = $DSIS_URL" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				else
					# Replace existing entry
					sed -i -e "s;dsis_url.*;dsis_url = $DSIS_URL;" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				fi
			fi
			if [ "${AEK_LOCATION}" = "Remote" ]
			then
				# Check if KMS_URL setting is already there
				if [ `grep kms_url ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} | wc -l` -eq 0 ]
				then
					sed -i -e "/^\[DOCBROKER_PROJECTION_TARGET_0/i \kms_url = ${KMS_URL}" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
					sed -i -e "/^\[DOCBROKER_PROJECTION_TARGET_0/i \is_kms_enabled = T" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				else
					sed -i -e "s;kms_url.*;kms_url = ${KMS_URL};" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				fi
		
				# Check if KMS_API_KEY setting is already there
				if [ `grep kms_api_key ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file} | wc -l` -eq 0 ]
				then
					sed -i -e "/^\[DOCBROKER_PROJECTION_TARGET_0/i \kms_api_key = $KMS_API_KEY" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				else
					sed -i -e "s;kms_api_key.*;kms_api_key = $KMS_API_KEY;" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				fi
			elif [ "${AEK_LOCATION}" = "Local" ] || [ "${AEK_LOCATION}" = "Remote_Vault" ]
			then
				# Remove the settings to related remote keys
				sed -i -e "/^\kms_api_key/d" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				sed -i -e "/^\kms_url/d" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
				sed -i -e "/^\is_kms_enabled/d" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/${server_ini_file}
			fi
		else
			log "[handle_server_ini_update] ==>> Generating the new AEK"
			# This AEK key has not been generated. So we need to generate one.
			handle_aek_creation $server_ini_file
		fi
		
		hostname=`hostname -f`		
		containername=$CONTAINER_NAME
		containerlength=${#containername}	
		index=`expr $containerlength + 2`
		host_index=`expr substr $hostname $index 1`
		if [ $host_index = 0 ]
		then
			#AEK upgrade done delete new key from share folder.
			rm -f ${DOCUMENTUM}/data/aek_upgrade_files/${AEK_NAME}
		fi
	
		log "==============================================================================================="
		log "[handle_server_ini_update] ==>> Exiting the server.init upgrade"
		log "==============================================================================================="
	fi
	
}

handle_aek_upgrade() {
	hostname=`hostname -f`		
    containername=$CONTAINER_NAME
	containerlength=${#containername}	
	index=`expr $containerlength + 2`
	host_index=`expr substr $hostname $index 1`

	if [ $host_index = 0 ]
	then
		handle_server_ini_update "server.ini"
	else
	    if [ "$CONFIG_NAME_OPTION" = "HA" ]
            then
	        handle_server_ini_update "server_HA${host_index}${DOCBASE_NAME}.ini"
	    elif [ "$CONFIG_NAME_OPTION" = "HOSTNAME" ]
	    then
	        handle_server_ini_update "server_${HOSTNAME}_${DOCBASE_NAME}.ini"
	    fi
    fi
}

handle_oracle_image() {
   log "In handle_oracle_image"  
   
   if [ "$DB_TYPE" = "oracle" ]
   then
     if [ -n "$DATABASE_SSL_SUPPORT" ] && [ "$DATABASE_SSL_SUPPORT" == "true" ]
	 then
	  log "oracle: wallet based ssl enabled"
	  mkdir -p ${DOCUMENTUM}/data/oracle_wallet
	  rm -f ${DOCUMENTUM}/data/oracle_wallet/wallet_files_copied
	  
	  COUNTER=1
	  while [  $COUNTER -lt 180 ]; do	  
	     if [ -f $DOCUMENTUM/data/oracle_wallet/$P12_WALLET_FILE_NAME ] && [ -f $DOCUMENTUM/data/oracle_wallet/$SSO_WALLET_FILE_NAME ]
		 then
		   log "Wallet Files $P12_WALLET_FILE_NAME and $SSO_WALLET_FILE_NAME found at $DOCUMENTUM/data/oracle_wallet/"
		   touch -f ${DOCUMENTUM}/data/oracle_wallet/wallet_files_copied
		   break
         fi	  
         let COUNTER=COUNTER+1
         log "Waiting for user to manually place the wallet files under /opt/dctm/data/oracle_wallet"     
         sleep 10
      done	  	
      
	  if [ ! -f ${DOCUMENTUM}/data/oracle_wallet/wallet_files_copied ]
	  then
	     log "Wallet files were not copied in given time"
		 exitProgram
	  fi
	    
	  sed -i -e "s:<DATABASE_HOST>:$DATABASE_HOST:g" $ORACLE_HOME/network/admin/listener.ora
	  sed -i -e "s:<DATABASE_SERVER_PORT>:$DATABASE_SERVER_PORT:g" $ORACLE_HOME/network/admin/listener.ora
	  sed -i -e "s:<PROTOCOL>:TCPS:g" $ORACLE_HOME/network/admin/listener.ora
	  sed -i -e "s:<DATABASE_SERVER_PORT>:$DATABASE_SERVER_PORT:g" $ORACLE_HOME/network/admin/tnsnames.ora
      sed -i -e "s:<DATABASE_HOST>:$DATABASE_HOST:g" $ORACLE_HOME/network/admin/tnsnames.ora
      sed -i -e "s:<SERVICE_NAME>:$DATABASE_SERVICE_NAME:g" $ORACLE_HOME/network/admin/tnsnames.ora
	  sed -i -e "s:<PROTOCOL>:TCPS:g" $ORACLE_HOME/network/admin/tnsnames.ora
	 else
	  sed -i -e "s:<DATABASE_HOST>:$DATABASE_HOST:g" $ORACLE_HOME/network/admin/listener.ora
      sed -i -e "s:<DATABASE_SERVER_PORT>:$DATABASE_SERVER_PORT:g" $ORACLE_HOME/network/admin/listener.ora
	  sed -i -e "s:<PROTOCOL>:TCP:g" $ORACLE_HOME/network/admin/listener.ora
      sed -i -e "s:<DATABASE_SERVER_PORT>:$DATABASE_SERVER_PORT:g" $ORACLE_HOME/network/admin/tnsnames.ora
      sed -i -e "s:<DATABASE_HOST>:$DATABASE_HOST:g" $ORACLE_HOME/network/admin/tnsnames.ora
      sed -i -e "s:<SERVICE_NAME>:$DATABASE_SERVICE_NAME:g" $ORACLE_HOME/network/admin/tnsnames.ora
	  sed -i -e "s:<PROTOCOL>:TCP:g" $ORACLE_HOME/network/admin/tnsnames.ora
	 fi     
   fi
}

set_event_hub_dfc_properties() {
	if [ "$FLUENTD_SERVICE_ENABLED" = "true" ]
	then
		log "[set_event_hub_dfc_properties] -->> updating $DOCUMENTUM/config/dfc.properties for EventHub."

		if [ `grep dfc.client.should_use_eventhub $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
		then
			echo "dfc.client.should_use_eventhub=true" >> $DOCUMENTUM/config/dfc.properties
		else
			sed -i -e "s/dfc.client.should_use_eventhub=.*/dfc.client.should_use_eventhub=true/" ${DOCUMENTUM}/config/dfc.properties
		fi
		
		if [ `grep dfc.client.eventhub.log_level $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
		then
			echo "dfc.client.eventhub.log_level=$DFC_EVENT_LOG_LEVEL" >> $DOCUMENTUM/config/dfc.properties
		else
			sed -i -e "s/dfc.client.eventhub.log_level=.*/dfc.client.eventhub.log_level=$DFC_EVENT_LOG_LEVEL/" ${DOCUMENTUM}/config/dfc.properties
		fi
	fi
}

set_folders_owner_to_install_owner()
{
    log "---------------------------------------------------------------------------------------"
    log "Setting mounted folders owner as install owner"
	sudo chown -R -f ${INSTALL_OWNER}:${INSTALL_OWNER} $DM_DOCKER_HOME/customscriptpvc
    sudo chown -R -f ${INSTALL_OWNER}:${INSTALL_OWNER} $DM_DOCKER_HOME/custom_script_pvc	
	sudo chown -R -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/dba/auth
	sudo chown -R -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/data/aek_upgrade_files
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/dba/log/fulltext	
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/kube
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/dba/secure
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/dba/secure/ldapdb	
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/dba/log
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/share
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/config
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/odbc
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/logs
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/mdserver_conf
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/data
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/dba/config
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/dba/auth
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/dba/log
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/dba/secure
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/dba/java_methods
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/$JMS_VERSION/logs
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/product/$PRODUCT_MAJOR_VERSION/thumbsrv/conf
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /dctm/product/$PRODUCT_MAJOR_VERSION/thumbsrv/container/logs
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/product/$PRODUCT_MAJOR_VERSION/install/logs
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/product/$PRODUCT_MAJOR_VERSION/thumbsrv/configurator/logs
	sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/product/$PRODUCT_MAJOR_VERSION/thumbsrv/container/webapps/thumbsrv/WEB-INF
	if [ "$SHARE_KEY" == "true" ]
	then
		sudo chown -f ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/shared_key
	fi
	# Check if is a certificate based setup. If yes change ownership of /opt/dctm/certificate
	if [ -n "$DOCBROKER_USE_CERTIFICATES" ] && [ "$DOCBROKER_USE_CERTIFICATES" == "true" ]
	then
		sudo chown -Rf ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/certificate
	elif [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
	then
		sudo chown -Rf ${INSTALL_OWNER}:${INSTALL_OWNER} /opt/dctm/certificate
	fi
}

#- Since we can not mount the <DOCUMENTUM_HOME>/dba folder as it contains log folder.
#- So we are copying files from <DOCUMENTUM_HOME>/dba to <DOCUMENTUM_HOME>/kube folder to use them 
#- after POD is restarted.
copy_dba_files_to_kube_backup()
{
    log "---------------------------------------------------------------------------------------"
    log "Copying dba files to kube backup"
    mkdir -p ${DOCUMENTUM}/kube/dba
    find ${DOCUMENTUM}/dba/  -maxdepth 1  -type f -exec cp {} ${DOCUMENTUM}/kube/dba/ \;
}

#Set appropriate permissions for the docbroker and content server dba common files
set_dba_common_files_permissions()
{
    log "---------------------------------------------------------------------------------------"
    log "Setting docbase and docbroker dba common files permssions "
    #Set Execute permission for the executable files
    chmod 755 $DOCUMENTUM/dba/dm_*.ex
    chmod 755 ${DOCUMENTUM}/dba/dm_RunExternalCommand*
    #Set sticky bit permission
    chmod 6750 $DOCUMENTUM/dba/dm_check_password_cs16.4
    sudo chmod 6750 $DOCUMENTUM/dba/dm_secure_writer_cs16.4
    chmod 6750 $DM_HOME/install/admin/dmliswap
    chmod 6750 $DOCUMENTUM/dba/dm_assume_user_cs16.4
    chmod 6750 $DOCUMENTUM/dba/dm_change_password_cs16.4.local
    chmod 6750 $DOCUMENTUM/dba/dm_change_password_cs16.4.yp
    #Set execute permission
    chmod 777 $DOCUMENTUM/dba/dm_root_task_cs16.4
}

#Set appropriate permissions for the docbroker dba files
set_docbroker_dba_files_permissions()
{
    log "---------------------------------------------------------------------------------------"
    log "Setting docbroker dba files permssions "
    set_dba_common_files_permissions
    #Set Execute permission for the executable files
	chmod 766 $DOCUMENTUM/dba/dm_launch_Docbroker
    chmod 766 $DOCUMENTUM/dba/dm_stop_Docbroker
    #Set Read/Write permissions for the configuration files
    chmod 6640 $DOCUMENTUM/dba/dm_documentum_config.txt
    chmod 6640 $DOCUMENTUM/dba/Docbroker.ini
}

#Set appropriate permissions for the content server dba files
set_docbase_dba_files_permissions()
{
    log "---------------------------------------------------------------------------------------"
    log "Setting docbase dba files permssions "
    set_dba_common_files_permissions
    #Set Execute permission for the executable files
	chmod 766 $DOCUMENTUM/dba/dm_start_*
    chmod 766 $DOCUMENTUM/dba/dm_shutdown_*	
    if [ "$isHA" != "TRUE" ]
    then
        chmod 6640 $DOCUMENTUM/dba/dm_documentum_config.txt
    fi
    if [[ $hostname != $CONTAINER_NAME-0* ]];
    then
    ls ${DOCUMENTUM}/dba/*_cs16.4* | while read line; do eval newcon=`echo ${line} | sed -E 's/_cs16.4//g'`; if [ ! -L $newcon ]; then ln -s $line $newcon; fi done
    fi
}

#--- copy back dba from kube backup --
copy_dba_files_from_kube_backup()
{
    log "---------------------------------------------------------------------------------------"
    log "Copying dba files from kube backup"
    find ${DOCUMENTUM}/kube/dba/  -maxdepth 1  -type f -exec cp {} ${DOCUMENTUM}/dba/ \;    
}
	
copy_method_server_configurations()
{
    log "---------------------------------------------------------------------------------------"
    log "Copying method server configuration files"
	cp ${DOCUMENTUM}/mdserver_conf/dfc.properties ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
    chmod 6640 ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
	cp ${DOCUMENTUM}/config/log4j2.properties ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/log4j2.properties
    chmod 6640 ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/log4j2.properties
    cp ${DOCUMENTUM}/mdserver_conf/web.xml ${DOCUMENTUM}/$TOMCAT/webapps/DmMethods/WEB-INF/web.xml
    chmod 6640 ${DOCUMENTUM}/$TOMCAT/webapps/DmMethods/WEB-INF/web.xml
    if [ "$alreadyInstalled" = "TRUE" ]
	then
		if [[ ${HOSTNAME} = $CONTAINER_NAME-0* ]];
		then	
			echo "repository.acsconfig=${HOSTNAME}ACS1" >>  ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
			echo "repository.name=${DOCBASE_NAME}.${DOCBASE_NAME}" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
		else
		    echo "repository.acsconfig=A${HOSTNAME}_dm_${DOCBASE_NAME}" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
			echo "repository.name=${DOCBASE_NAME}.${SERVER_CONFIG_NAME}" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
		fi
		echo "repository.login=$INSTALL_OWNER" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
		echo "primary.content.store.root=/opt/dctm/acsCache" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	    echo "repository.password=" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
		echo "primary.content.store.quota=1000M" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	fi

    cp ${DOCUMENTUM}/mdserver_conf/s3.properties  ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties
    chmod 6640 ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties

    cp ${DOCUMENTUM}/mdserver_conf/jmx.properties ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/jmx.properties
    chmod 6640 ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/jmx.properties

    cp ${DOCUMENTUM}/share/mdserver_conf/web.xml ${DOCUMENTUM}/$TOMCAT/webapps/DmMethods/WEB-INF/web.xml
    chmod 6640 ${DOCUMENTUM}/$TOMCAT/webapps/DmMethods/WEB-INF/web.xml
	if [ "${IS_VAULT_ENABLED}" = "true" ]
	then
		sed -i -e "s;dfc.globalregistry.password=.*;dfc.globalregistry.password=$GLOBAL_REGISTRY_PASSWORD;"  ${DOCUMENTUM}/config/dfc.properties
		acsAdminPasswordPrefix=$(echo $APP_SERVER_PASSWORD | cut -d'/' -f1)
		sed -i -e "s;user.acsAdmin=.*;user.acsAdmin=$acsAdminPasswordPrefix/$hostname,Administrators;" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/jmx.properties

		hostname=`hostname -f`
		sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname;" ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
	fi
}

update_docbase_owner_database_password()
{
	log "---------------------------------------------------------------------------------------"
	java $JVM_OPTS -cp $DM_DOCKER_HOME PasswordValidationUtility $DOCBASE_PASSWORD $DSIS_URL
	if [ $? != $SUCCESS ]
    then
		log "Docbase Owner Database Password doesn't meet the complexity rules"
        exitProgram
	else 
		log "Docbase Owner Database Password is valid"
    fi
    log "Updating dbpasswd.txt..."
	cp ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dbpasswd.txt ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dbpasswd.txt.bak
	
	if [ "${AEK_LOCATION}" = "Remote" ]
	then
		source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_encrypt_password -keyname $AEK_NAME -kms_url ${KMS_URL} -kms_api_key $KMS_API_KEY -docbase $DOCBASE_NAME -rdbms -encrypt $DOCBASE_PASSWORD
	elif [ "${AEK_LOCATION}" = "Local" ]
	then
       	 source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_encrypt_password -keyname $AEK_NAME -passphrase $AEK_PASSPHRASE -docbase $DOCBASE_NAME -rdbms -encrypt $DOCBASE_PASSWORD
	else
		echo $DOCBASE_PASSWORD > ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dbpasswd.txt		
	fi
	if [ $? -eq $SUCCESS ];
	then
		log "Successfully updated database password for docbase owner"
	else
		log "Failed to update database password for docbase owner";
		#In case of failure, original password file will be there as such in config folder 
	fi
}


cleanUpCrytographicKeyandCertificate()
{
	hostname=`hostname -f`
	containername=$CONTAINER_NAME
	containerlength=${#containername}
	index=`expr $containerlength + 2`
	host_index=`expr substr $hostname $index 1`
        if [ $host_index -eq 0 ]
	then
		log "---------------------------------------------------------------------------------------"
		log "                       [cleanUpCrytographicKeyandCertificate]"
		log "---------------------------------------------------------------------------------------"
		rm -rf /tmp/deletecryptokey_and_certifice.sql
		echo "delete from dm_cryptographic_key_s;" >> /tmp/deletecryptokey_and_certifice.sql
		echo "delete from dm_public_key_certificate_s where key_type=1;"  >> /tmp/deletecryptokey_and_certifice.sql
		chmod 775 /tmp/deletecryptokey_and_certifice.sql
		DOCBASE_OWNER_EX=`cat  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini |grep database_owner| awk '{print $3}'`
		#####psql "host=$DATABASE_HOST  dbname=dm_${DOCBASE_NAME}_docbase user=$DOCBASE_OWNER_EX password=$DOCBASE_PASSWORD" -a -f /tmp/deletecryptokey_and_certifice.sql >> /tmp/deletecryptokey_and_certifice.out
		if [ "$DB_TYPE" == "oracle" ]
		then
			sqlplus ${DOCBASE_NAME}/$DOCBASE_PASSWORD@${DATABASE_HOST}/${DATABASE_SERVICE_NAME} @/tmp/deletecryptokey_and_certifice.sql >> /tmp/deletecryptokey_and_certifice.out
		else
			PGPASSWORD=$DOCBASE_PASSWORD psql -h ${DATABASE_HOST} -d dm_${DOCBASE_NAME}_docbase -U ${DOCBASE_NAME} -a -f /tmp/deletecryptokey_and_certifice.sql >> /tmp/deletecryptokey_and_certifice.log
			
		fi	
		
		if [ $? -eq $SUCCESS ];
		then
			log "crytpgraphicKeyandCerticate were deleted"
		else
			log "crytpgraphicKeyandCertificate deletion failed for docbase : $DOCBASE_NAME ";
			log "log file /tmp/deletecryptokey_and_certifice.log"
			exit $FAILURE
		fi
		log "---------------------------------------------------------------------------------------"
        fi
}

handle_oracle_install()
{
   log "----------------------- handle_oracle_install ----------------------------------------------"
   mv ${DM_HOME}/bin/documentum ${DM_HOME}/bin/documentum_postgres
   mv ${DM_HOME}/bin/dm_set_server_env.sh ${DM_HOME}/bin/dm_set_server_env.sh_postgres
   mv ${DM_HOME}/bin/dmdbtest ${DM_HOME}/bin/dmdbtest_postgres
   mv ${DM_HOME}/bin/dmclean ${DM_HOME}/bin/dmclean_postgres
   mv ${DM_HOME}/bin/dmfilescan ${DM_HOME}/bin/dmfilescan_postgres
   mv ${DM_HOME}/bin/dm_crypto_upgrade ${DM_HOME}/bin/dm_crypto_upgrade_postgres
   
   mv ${DM_HOME}/bin/documentum_oracle ${DM_HOME}/bin/documentum
   mv ${DM_HOME}/bin/dm_set_server_env.sh_oracle ${DM_HOME}/bin/dm_set_server_env.sh
   mv ${DM_HOME}/bin/dmdbtest_oracle ${DM_HOME}/bin/dmdbtest
   mv ${DM_HOME}/bin/dmclean_oracle ${DM_HOME}/bin/dmclean
   mv ${DM_HOME}/bin/dmfilescan_oracle ${DM_HOME}/bin/dmfilescan
   mv ${DM_HOME}/bin/dm_crypto_upgrade_oracle ${DM_HOME}/bin/dm_crypto_upgrade
   
   chmod 755 ${DM_HOME}/bin/documentum
   chmod 755 ${DM_HOME}/bin/dm_set_server_env.sh
   chmod 755 ${DM_HOME}/bin/dmdbtest
   chmod 755 ${DM_HOME}/bin/dmclean
   chmod 755 ${DM_HOME}/bin/dmfilescan
   chmod 755 ${DM_HOME}/bin/dm_crypto_upgrade
   
   log "--------------------------------------------------------------------------------------------"   
}
		
#------------------------------------------------------------------------
#initializing starts
initialize()
{
    log "---------------------------------------------------------------------------------------"
    log "initialize"	
	#removing the datadictionary marker file
	rm -f ${DOCUMENTUM}/kube/available_locales
    trackpodrestartfile="${DOCUMENTUM}/kube/trackpodrestart"
    if [ -f "$trackpodrestartfile" ]
    then
        lines=`wc -l < $trackpodrestartfile`
        log "trackpodrestartfile lines: $lines"

        if [ $lines -gt 100 ]
        then
            rm -f $trackpodrestartfile
            log "Cleaned trackpodrestartfile"
        fi
    fi
			
    if [ "$alreadyInstalled" = "TRUE" ]
	then
	  currentime=`date`
      sudo echo $currentime >> $trackpodrestartfile
	fi
    logfile=$DM_DOCKER_HOME/logs/${hostname}.log	
	
    if [ "$onlyDocbroker" = "true" ]
    then
        set_folders_owner_to_install_owner
		
        installeddocbrokerfile="${DOCUMENTUM}/kube/Docbroker-installed"		
        if [ -f "$installeddocbrokerfile" ]
        then
            log "docbroker already installed"
            alreadyInstalled="TRUE"
            copy_dba_files_from_kube_backup
            set_docbroker_dba_files_permissions
        else		  
            hostnamelength=${#hostname}
            if [[ $hostnamelength -gt 59 ]]; then
                log "hostname length cannot be greater than 59"
                exitProgram
            fi		  
        fi
    else
	    if [ "$DB_TYPE" = "oracle" ]
	    then
	      handle_oracle_install
	    fi
        validate_inputs
		
	if [ "$MIGRATECS" = "true" ]
	then
	cleanUpCrytographicKeyandCertificate
        fi
        #todo: execute this only for centos
        log "Run rngd command"
        rngd -b -r /dev/urandom -o /dev/random	
		
        containername=$CONTAINER_NAME
        containerlength=${#containername}
		
        log "containername: $containername containerlength: $containerlength"		

        index=`expr $containerlength + 2`
        host_index=`expr substr $hostname $index 1`
		
        log "host index is $host_index"
		
        count=0
		
		# SURYAKANT Create a directory in kube directory to AEK upgrade related files.
		# Create this directory in the beginning
		if [ ! -f ${DOCUMENTUM}/data/aek_upgrade_files ]
		then
			log "Creating folder ${DOCUMENTUM}/data/aek_upgrade_files"
			sudo mkdir -p ${DOCUMENTUM}/data/aek_upgrade_files
		fi
		
        while [ $count -lt $DOCBROKERS_COUNT ]
        do		
            ext_docbroker=$DOCBROKER_SERVICE_NAME-$count.$DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE
            ip=`getent hosts $ext_docbroker | awk '{ print $1 }'`
            echo "ext docbroker ip : $ip"
            if [ $ip ]
            then
                break
            fi
            count=`expr $count + 1`
        done	

        if [ "$ext_docbroker" = "" ]
        then
            log "docbrokers are not pingable"
            exitProgram
        fi		   
		
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
		  
            log "isHA true"
            isHA="TRUE"		  
            PRIMARY_HOSTNAME=`echo $hostname | sed s/./0/$index`
		  
            log "primary hostname is $PRIMARY_HOSTNAME"
            COUNT=0
            while [ $COUNT -lt 100 ]
            do
                primaryinstalledfile="${DOCUMENTUM}/data/primary-installed"			  
	        if [ -f "$primaryinstalledfile" ]
	        then
	            log "Primary Installed"
	            break
	        else
	            log "waiting for primary to complete"
	            sleep 60
	        fi
	    done
	else
	    SERVER_CONFIG_NAME=$DOCBASE_NAME
	    PRIMARY_HOSTNAME=$hostname
	fi	
		
	log "server config name is $SERVER_CONFIG_NAME"
	if [ "$FULLTEXT_ENGINE_SSVC_ENABLE" = "true" ]
	then
		log "Switch from Dsearch query plugin to Solr query plugin"
		sed -i -e "s/libDsearchQueryPlugin.so/libsolrplugin.so/"  $DOCUMENTUM/fulltext/dsearch/dmfulltext.ini
	fi
        installeddocbasefile="${DOCUMENTUM}/kube/${DOCBASE_NAME}-installed"	
	set_folders_owner_to_install_owner	
	if [ -f "$installeddocbasefile" ]
	then
	    log "docbase already installed"
	    alreadyInstalled="TRUE"
		if [ "$DB_TYPE" != "oracle" ]
		then
		  updateodbcini
		fi
		
	    if [ "$CUST_SCRIPT_IN_PVC" = "true" ] || [ "$USE_INITCONTAINERS" = "true" ]
	    then
		  if [ "$CUST_SCRIPT_IN_PVC" = "true" ]
		  then
	        checkMarkerFiles="true"
	        while [ "$checkMarkerFiles" = "true" ]
	        do
		    log "Checking all marker files..."
		    allmarkerFilesPresent="true"
                    custom_script_marker_files=$(echo $CUST_SCRIPT_MARKER_FILES | tr "," "\n")
                    for markerfile in $custom_script_marker_files
                    do
		        if [ ! -f ${DM_DOCKER_HOME}/customscriptpvc/$markerfile ]; then
                            log "Marker File $markerfile not present. Waiting for 10 seconds and then retrying.."
			    sleep 10
			    allmarkerFilesPresent="false"
			    break
                        fi                
			log "Marker File $markerfile present"
                    done
                    if [ "$allmarkerFilesPresent" = "true" ]
                    then
                        checkMarkerFiles="false"
                    fi				
		done
		fi
                rm -f ${DOCUMENTUM}/kube/custom-script-success
	        log "Removing old custom scripts and copying custom script from PVC to local"
	        rm -Rf ${DM_DOCKER_HOME}/custom_script_pvc/*
		cp -R ${DM_DOCKER_HOME}/customscriptpvc/. ${DM_DOCKER_HOME}/custom_script_pvc
	        chown -R -f $INSTALL_OWNER:$INSTALL_OWNER ${DM_DOCKER_HOME}/custom_script_pvc
			chmod +x ${DM_DOCKER_HOME}/custom_script_pvc/*.sh
	        custom_script_pvc_execution "prehook"
        fi		  
		  
        externalprojectedfile="${DOCUMENTUM}/kube/cs-external-projected"
	if [ -f "$externalprojectedfile" ]
	then
	    alreadyprojectedexternal="TRUE"
	fi
		
  	
  	log4j2prop=${DOCUMENTUM}/config/log4j2.properties
	if [ -f $log4j2prop ]
	then
		log "log4j2.properties file already exist"
	else
		\cp -f ${DOCUMENTUM}/config_pvcbk/log4j2.properties ${DOCUMENTUM}/config/log4j2.properties
		sudo chown -R -f $INSTALL_OWNER:$INSTALL_OWNER ${DOCUMENTUM}/config/log4j2.properties
	fi
	
	copy_dba_files_from_kube_backup
	set_docbase_dba_files_permissions
	copy_method_server_configurations
	if [ -n $DOCBASE_OWNER_DATABASE_PASSWORD_CHANGE ] && [ "$DOCBASE_OWNER_DATABASE_PASSWORD_CHANGE" = "true" ]
	then
		update_docbase_owner_database_password
	fi
	
	if [ "$CONFIGURE_OTDS" = "true" ]
	then
	    cp ${DOCUMENTUM}/mdserver_conf/otdsauth.properties ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
        fi
  
	elif [ "$MIGRATECS" = "true" ]
	then
	    if [ "$isHA" != "TRUE" ]
	    then
	        migrateDBA
	        set_folders_owner_to_install_owner
	        set_docbase_dba_files_permissions
	        chown -R $INSTALL_OWNER:$INSTALL_OWNER ${DOCUMENTUM}/data
	    fi
        fi    
    fi    
	if [ "$FLUENTD_SERVICE_ENABLED" = "true" ]
	then
		sudo echo -e "\n export EVENT_HUB_FLUENTD_HOST=$hostname" >> /etc/bashrc
	fi
}

validate_passwords()
{
    log "---------------------------------------------------------------------------------------"
    log "validate_passwords against complexity rules"
	log "---------------------------------------------------------------------------------------"
	if [ $AEK_PASSPHRASE ]
	then
		java $JVM_OPTS -cp $DM_DOCKER_HOME PasswordValidationUtility $AEK_PASSPHRASE $DSIS_URL
		if [ $? != $SUCCESS ]
		then
			log "AEK Passphrase doesn't meet the complexity rules"
			exitProgram
		else
			log "AEK Passphrase is valid"
		fi	
	fi
	if [ "$USE_EXISTING_DATABASE_ACCOUNT" = "false" ]
	then
		java $JVM_OPTS -cp $DM_DOCKER_HOME PasswordValidationUtility $DOCBASE_PASSWORD $DSIS_URL
		if [ $? != $SUCCESS ]
		then
			log "Docbase Owner Database Password doesn't meet the complexity rules"
			exitProgram
		else
			log "Docbase Owner Database Password is valid"
		fi	
	fi
	java $JVM_OPTS -cp $DM_DOCKER_HOME PasswordValidationUtility $GLOBAL_REGISTRY_PASSWORD $DSIS_URL
	if [ $? != $SUCCESS ]
    then
		log "Global Registry Password doesn't meet the complexity rules"
        exitProgram
	else 
		log "Global Registry Password is valid"
    fi	
}

validate_inputs()
{
    log "---------------------------------------------------------------------------------------"
    log "validate_inputs"	
    
    if [ "$DATABASE_HOST" = "" ]
    then
      log "ERROR:Database host is missing. Please check DATABASE_HOST parameter and try again."
    fi
    
    if [ "$DATABASE_SERVER_PORT" = "" ]
    then
      log "ERROR:Database port is missing. Please check DATABASE_SERVER_PORT parameter and try again."
    fi
            
    if [ "$DATABASE_USER" = "" ]
    then
      log "Error:Database username is missing. Please check DATABASE_USER parameter and try again."
      exitProgram
    fi
    
    if [ "$DATABASE_PASSWORD" = "" ]
    then
      log "Error:Database user password is missing. Please check DATABASE_PASSWORD parameter and try again."
      exitProgram
    fi
    
    if [ "$DOCBASE_NAME" = "" ]
    then
      log "Error:Docbase name is missing. Please check DOCBASE_NAME parameter and try again."
    fi
    
    log "Validating database server on $DATABASE_HOST:$DATABASE_SERVER_PORT is running.."
	if [ "$DB_TYPE" = "oracle" ]
	then		
		handle_oracle_image
    fi
		
	
    ping_database_server
    
    if [ $? -ne 0 ] 
    then
       log "Error:Database server is down. Make sure that DATABASE_HOST parameter has valid entry. Please make sure that Database server on $DATABASE_HOST:$DATABASE_SERVER_PORT is up and running."      
       exitProgram
    fi
	
	probe_docbroker
    
    if [ $? -ne 0 ] 
    then
       log "Docbroker $DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE is not reachable. Please make sure that Docbroker is up and running"      
       exitProgram
    fi
}

ping_database_server()
{	
    log "---------------------------------------------------------------------------------------"
    log "ping_database_server"
    result=1
    COUNTER=0
    while [  $COUNTER -lt 1800 ]; do

        (echo > /dev/tcp/$DATABASE_HOST/$DATABASE_SERVER_PORT) >/dev/null 2>&1

         result=$?

         if [[ $result -eq 0 ]]; then
                log "Pinging $DATABASE_HOST:$DATABASE_SERVER_PORT. Successful."
                break
         fi
         let COUNTER=COUNTER+1
         log "Pinging $DATABASE_HOST:$DATABASE_SERVER_PORT. Not successful. Retrying..."     
         sleep 1
     done
    
    return $result 
}
#initializing ends

probe_docbroker()
{
    log "---------------------------------------------------------------------------------------"
    log "probing docbroker"
    
    COUNTER=0	
    while [  $COUNTER -lt 240 ]; do
		newcount=0
		result=0
		while [ $newcount -lt $DOCBROKERS_COUNT ]
		do
			client_docbroker_host=$DOCBROKER_SERVICE_NAME-$newcount.$DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE	
			if [ "$DOCBASE_CONNECT_MODE" = "native" ] || [ "$DOCBASE_CONNECT_MODE" = "dual" ]
			then				
				nc -z -v $client_docbroker_host $DOCBROKER_PORT
				result=$?
				if [ $result -gt 0 ]
				then 
					break
				fi
			fi

			if [ "$DOCBASE_CONNECT_MODE" = "secure" ] || [ "$DOCBASE_CONNECT_MODE" = "dual" ]
			then
				sslPortToProbe=$(expr "$DOCBROKER_PORT" + 1)				
				nc -z -v $client_docbroker_host $sslPortToProbe
				result=$?
				if [ $result -gt 0 ]
				then 
					break
				fi
			fi			
			newcount=`expr $newcount + 1`
		done
		if [ $result -eq 0 ]
		then
			log "Probing $DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE is successful."			
			if [ $newcount -eq $DOCBROKERS_COUNT ]
			then
			  break;
			fi
	    else
		    if [ $COUNTER -gt 120 ]
			then
		      log "Probing $DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE is not successful. Retrying..."       	   
			fi
            let COUNTER=COUNTER+1         
            sleep 10	    
		fi		
    done
    
    return $result 
}

handle_kube_pvc()
{
    if [ "$alreadyInstalled" = "FALSE" ]
    then
        log "---------------------------------------------------------------------------------------"
        log "handle_kube_pvc"
        
		if [ "$ROOT_SQUASH_ENABLED" = "true" ]
        then
          sudo cp -R /opt/dctm/dba_pvcbk/. /opt/dctm/dba
		else
		  cp -R /opt/dctm/dba_pvcbk/. /opt/dctm/dba
		fi
        # Mounting the share as nfs
        if [[ $hostname == $CONTAINER_NAME-0* ]] && [ -d "/opt/dctm/share_pvcbk/" ];
        then
                 sudo chown -R -f $INSTALL_OWNER:$INSTALL_OWNER ${DOCUMENTUM}/share
                 cp -pR /opt/dctm/share_pvcbk/. /opt/dctm/share
                 mkdir -p ${DOCUMENTUM}/share/mdserver_conf
        fi
        if [ -d "/opt/dctm/share_pvcbk/" ]
        then
                 sudo rm -frR /opt/dctm/share_pvcbk/
        fi
		if [ "$ROOT_SQUASH_ENABLED" = "true" ]
	    then
          set_folders_owner_to_install_owner
		  cp -R /opt/dctm/config_pvcbk/. /opt/dctm/config
          cp -R /opt/dctm/thumbconfbk/. $DM_HOME/thumbsrv/conf
          cp -R /opt/dctm/thumbwebinfbk/. $DM_HOME/thumbsrv/container/webapps/thumbsrv/WEB-INF
		else
		  sudo cp -R /opt/dctm/config_pvcbk/. /opt/dctm/config
          sudo cp -R /opt/dctm/thumbconfbk/. $DM_HOME/thumbsrv/conf
          sudo cp -R /opt/dctm/thumbwebinfbk/. $DM_HOME/thumbsrv/container/webapps/thumbsrv/WEB-INF
		  set_folders_owner_to_install_owner
		fi        
    fi
	
}

update_app_server_credential()
{       
    log "---------------------------------------------------------------------------------------"
	java $JVM_OPTS -cp $DM_DOCKER_HOME PasswordValidationUtility $APP_SERVER_PASSWORD $DSIS_URL
	if [ $? != $SUCCESS ]
    then
		log "App Server Password doesn't meet the complexity rules"
        exitProgram
	else 
		log "App Server Password is valid"
    fi

    log "update_app_server_credential"
    e=$(java $JVM_OPTS -cp "${DOCUMENTUM}/dfc/dfc.jar" com.documentum.fc.tools.RegistryPasswordUtils $APP_SERVER_PASSWORD)

    if [ "$e" != "" ]
    then
        c='admin='$e
		#DFC returns encrypted password with space if input is greater than specified length. Trimming it off
		c=$(echo $c | sed -e 's/[ ]//g')
        sed -i '/admin/c\'${c} ${DOCUMENTUM}/${TOMCAT}/server/DctmServer_MethodServer/configuration/dctm-users.properties

        if [ $? != $SUCCESS ]
        then
            log "Failed to update password for app server"
            exitProgram
        else
            log "App server Credential update is successful"
        fi
    else
        log "Failed to generate app server credentails."
    fi

}

copy_dba_scripts()
{
    if [ "$alreadyInstalled" = "FALSE" ]
    then
        log "---------------------------------------------------------------------------------------"
        log "copy_dba_scripts"
        
        cp -f $DM_HOME/install/external_apps/checkpass/dm_check_password_cs16.4  $DOCUMENTUM/dba/dm_check_password_cs16.4		
        chmod 6750 $DOCUMENTUM/dba/dm_check_password_cs16.4		
        cp -f $DM_HOME/install/external_apps/securewriter/dm_secure_writer_cs16.4 $DOCUMENTUM/dba/dm_secure_writer_cs16.4		
        sudo chown root:$INSTALL_OWNER $DOCUMENTUM/dba/dm_secure_writer_cs16.4		
        sudo chmod 6750 $DOCUMENTUM/dba/dm_secure_writer_cs16.4		
        sudo chown root:$INSTALL_OWNER $DM_HOME/install/admin/dmliswap		
        sudo chmod 6750 $DM_HOME/install/admin/dmliswap		
        cp -f $DM_HOME/install/external_apps/assumeuser/dm_assume_user_cs16.4 $DOCUMENTUM/dba/dm_assume_user_cs16.4		
        chmod 6750 $DOCUMENTUM/dba/dm_assume_user_cs16.4		
        cp -f $DM_HOME/install/external_apps/changepass/dm_change_password_cs16.4.local $DOCUMENTUM/dba/dm_change_password_cs16.4.local		
        chmod 6750 $DOCUMENTUM/dba/dm_change_password_cs16.4.local		
        cp -f $DM_HOME/install/external_apps/changepass/dm_change_password_cs16.4.yp $DOCUMENTUM/dba/dm_change_password_cs16.4.yp		
        chmod 6750 $DOCUMENTUM/dba/dm_change_password_cs16.4.yp
    fi		
}

handle_password_change()
{
    log "---------------------------------------------------------------------------------------"
    log "handle_password_change"
	if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
	then
		echo "$INSTALL_OWNER_PASSWORD" | sudo passwd --stdin $INSTALL_OWNER
		echo "$ROOT_PASSWORD" | sudo passwd --stdin root
	else
		echo "$installOwnerPwd" | sudo passwd --stdin $INSTALL_OWNER
		echo "$rootPwd" | sudo passwd --stdin root
	fi
	if [ "$onlyDocbroker" != "true" ] && [ "$DB_TYPE" = "postgres" ]
	then
		if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
		then
			echo "$DATABASE_PASSWORD" | sudo passwd --stdin postgres
		else
			echo "$databasePwd" | sudo passwd --stdin postgres
		fi
	fi
}

handle_start_docbroker()
{
    log "---------------------------------------------------------------------------------------"
    log "handle_start_docbroker"   
	
	if [ $NEWRELIC_ENABLE ]
    then
      log "Trapping the signal for Docbroker"
      trap '' SIGUSR1
    fi
                
    if [ "$alreadyInstalled" = "TRUE" ]
    then
        log "Starting Docbroker"
        ${DOCUMENTUM}/dba/dm_launch_Docbroker
        log "Docbroker Started"	
    else
		if [ "${IS_VAULT_ENABLED}" = "true" ]
        then
                if [ -n "$DOCBROKER_USE_CERTIFICATES" ] && [ "$DOCBROKER_USE_CERTIFICATES" == "true" ]
                then
                        sed -i -e "s/IS_VAULT_ENABLED=.*/IS_VAULT_ENABLED=$IS_VAULT_ENABLED/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
                        sed -i -e "s;DSIS_URL=.*;DSIS_URL=$DSIS_URL;"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
                fi
        fi
        sed -i -e "s;SERVER.SECURE.ROOT_PASSWORD=.*;SERVER.SECURE.ROOT_PASSWORD=$ROOT_PASSWORD;"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
        sed -i -e "s/SERVER.DOCBROKER_PORT=.*/SERVER.DOCBROKER_PORT=$DOCBROKER_PORT/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
        sed -i -e "s/SERVER.PROJECTED_DOCBROKER_PORT=.*/SERVER.PROJECTED_DOCBROKER_PORT=$DOCBROKER_PORT/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
        sed -i -e "s/SERVER.DOCBROKER_NAME=.*/SERVER.DOCBROKER_NAME=Docbroker/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
        sed -i -e "s/SERVER.PROJECTED_DOCBROKER_HOST=.*/SERVER.PROJECTED_DOCBROKER_HOST=$hostname/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties		
        sed -i -e "s/SERVER.DOCBROKER_CONNECT_MODE=.*/SERVER.DOCBROKER_CONNECT_MODE=$DOCBROKER_CONNECT_MODE/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
        log "Docbroker installation Started...."
        ${DM_HOME}/install/dm_launch_server_config_program.sh -f ${DM_DOCKER_HOME}/config/configDocbroker.properties -i silent
        if [ $? != $SUCCESS ]
        then
            log "ERROR: The installation has failed. Please check install logs at container's ${DM_HOME}/install/logs/install.log"
            exitProgram
        fi
        log "Docbroker installation Completed"

        echo dfc.docbroker.host[0]= $hostname >> ${DOCUMENTUM}/config/dfc.properties
        echo dfc.docbroker.port[0]= $DOCBROKER_PORT >> ${DOCUMENTUM}/config/dfc.properties
        chown $INSTALL_OWNER:$INSTALL_OWNER ${DOCUMENTUM}/config/dfc.properties						
    fi	   
}

handle_start_ext_docbroker()
{
    log "---------------------------------------------------------------------------------------"
    log "handle_start_ext_docbroker"   
	
	if [ $NEWRELIC_ENABLE ]
    then
      log "Trapping the signal for external Docbroker"
      trap '' SIGUSR1
    fi
            
    if [ "$alreadyInstalled" = "TRUE" ]
    then
        log "Starting External Docbroker"
        ${DOCUMENTUM}/dba/dm_launch_extDocbroker
        log "Docbroker Started"	
    else
		if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
		then
			sed -i -e "s;SERVER.SECURE.ROOT_PASSWORD=.*;SERVER.SECURE.ROOT_PASSWORD=$ROOT_PASSWORD;"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
		elif [ -n "$DOCBROKER_USE_CERTIFICATES" ] && [ "$DOCBROKER_USE_CERTIFICATES" == "true" ]
		then
			sed -i -e "s/IS_VAULT_ENABLED=.*/IS_VAULT_ENABLED=$IS_VAULT_ENABLED/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
			sed -i -e "s;DSIS_URL=.*;DSIS_URL=$DSIS_URL;"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
		fi
        sed -i -e "s/SERVER.DOCBROKER_PORT=.*/SERVER.DOCBROKER_PORT=$ExtDocbrokerPort/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
        sed -i -e "s/SERVER.PROJECTED_DOCBROKER_PORT=.*/SERVER.PROJECTED_DOCBROKER_PORT=$ExtDocbrokerPort/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
        sed -i -e "s/SERVER.DOCBROKER_NAME=.*/SERVER.DOCBROKER_NAME=extDocbroker/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
        sed -i -e "s/SERVER.PROJECTED_DOCBROKER_HOST=.*/SERVER.PROJECTED_DOCBROKER_HOST=$hostname/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties		
        sed -i -e "s/SERVER.DOCBROKER_CONNECT_MODE=.*/SERVER.DOCBROKER_CONNECT_MODE=$DOCBROKER_CONNECT_MODE/"  ${DM_DOCKER_HOME}/config/configDocbroker.properties
        log "Docbroker installation Started...."
        ${DM_HOME}/install/dm_launch_server_config_program.sh -f ${DM_DOCKER_HOME}/config/configDocbroker.properties -i silent
        if [ $? != $SUCCESS ]
        then
            log "ERROR: The installation has failed. Please check install logs at container's ${DM_HOME}/install/logs/install.log"
            exitProgram

        fi
        log "External Docbroker installation Completed"		
        
        #--- backing dba to kube as we do not want to mount log folder in pvc ---
        copy_dba_files_to_kube_backup
    fi	   
}

updateGlobalRepositoryDetailsInConfigFile()
{
    log "---------------------------------------------------------------------------------------"
    log "Global Repository: $GLOBAL_REPOSITORY_NAME"
    GRDocbrokerPort=$GLOBAL_REPOSITORY_DOCBROKER_PORT
    GRDocbrokerHost=$GLOBAL_REPOSITORY_DOCBROKER_HOST
    if [ "$GRDocbrokerPort" = "" ]
    then
            GRDocbrokerPort=$DOCBROKER_PORT
    fi
    if [ "$GRDocbrokerHost" = "" ]
    then
            GRDocbrokerHost=$ext_docbroker
    fi
	log "Global Repository Docbroker Host: $GRDocbrokerHost"
	log "Global Repository Docbroker Port: $GRDocbrokerPort"
	log "Global Repository Validation"

	if [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
    then
		#adding truststore details in dfc.properties
		# Now encrypt the password using the password encryption utility
		if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
		then	
            encryptedPasswd=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config EncryptPasswordUtil ${DFC_SSL_TRUSTSTORE_PASSWORD})			
			if [ `grep security.ssl.truststore $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
			then 
				echo "dfc.security.ssl.truststore=$DOCUMENTUM/certificate/dfc.keystore" >> $DOCUMENTUM/config/dfc.properties
				if [ -z "$encryptedPasswd" ]
				then
					log "[updateGlobalRepositoryDetailsInConfigFile] -->> Truststore password encryption failed. Using plain password"
					echo "dfc.security.ssl.truststore_password=${DFC_SSL_TRUSTSTORE_PASSWORD}" >> $DOCUMENTUM/config/dfc.properties
				else
					log "[updateGlobalRepositoryDetailsInConfigFile] -->> Truststore password encryption passed."
					echo "dfc.security.ssl.truststore_password=$encryptedPasswd" >> $DOCUMENTUM/config/dfc.properties
				fi  
			
				log "Added truststore details in $DOCUMENTUM/config/dfc.properties"
			else
				#Check the password present in dfc.properties. If it matches with the encrypted password.
				#The no need to change trust store password
				dfcPropPasswd=$( sed -n -e '/dfc.security.ssl.truststore_password/ s/.*\= *//p' $DOCUMENTUM/config/dfc.properties)
			
				if [  "$encryptedPasswd" = "$dfcPropPasswd" ]
				then
					log "[updateGlobalRepositoryDetailsInConfigFile] -->> Encrypted password [$encryptedPasswd] matches the password [$dfcPropPasswd] stored in dfc.properties."
				else
					log "[updateGlobalRepositoryDetailsInConfigFile] -->> Encrypted password [$encryptedPasswd] doesn't matches the password [$dfcPropPasswd] stored in dfc.properties."
					sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$encryptedPasswd;" $DOCUMENTUM/config/dfc.properties
					log "[updateGlobalRepositoryDetailsInConfigFile] -->> dfc.properties updated with new encrypted password $encryptedPasswd."
				fi
			fi
		else
			if [ `grep dfc.dsis.enabled $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
			then
				echo "dfc.dsis.enabled=$IS_VAULT_ENABLED" >> $DOCUMENTUM/config/dfc.properties
				echo "dfc.dsis.daemon.url=$DSIS_URL" >> $DOCUMENTUM/config/dfc.properties
		
				hostname=`hostname -f`
				echo "dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname" >> $DOCUMENTUM/config/dfc.properties
			else
				sed -i -e "s;dfc.dsis.enabled=.*;dfc.dsis.enabled=$IS_VAULT_ENABLED;" $DOCUMENTUM/config/dfc.properties
				sed -i -e "s;dfc.dsis.daemon.url=.*;dfc.dsis.daemon.url=$DSIS_URL;" $DOCUMENTUM/config/dfc.properties
		
				hostname=`hostname -f`
				sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname;" $DOCUMENTUM/config/dfc.properties
			fi
		fi
		java -cp $DM_DOCKER_HOME:$DOCUMENTUM/dfc/dfc.jar:$DOCUMENTUM/config TestDocbaseConnection dm_bof_registry $GLOBAL_REGISTRY_PASSWORD $GRDocbrokerHost $GRDocbrokerPort $GLOBAL_REPOSITORY_NAME $DSIS_URL
	fi
   
	if [ $? != $SUCCESS ]
	then
		log "Global Repository is not valid"
		exitProgram
	else
		log "Global Repository is valid"
	fi
    log "updateGlobalRepositoryDetailsInConfigFile"
    configFileName=$1	
    sed -i -e "s/SERVER.GLOBAL_REGISTRY_SPECIFY_OPTION=USE_THIS_REPOSITORY/SERVER.GLOBAL_REGISTRY_SPECIFY_OPTION=SPECIFY_DIFFERENT_REPOSITORY/g" $DM_DOCKER_HOME/config/$configFileName
    echo "SERVER.GLOBAL_REGISTRY_REPOSITORY=$GLOBAL_REPOSITORY_NAME" >> $DM_DOCKER_HOME/config/$configFileName
    echo "SERVER.PROJECTED_DOCBROKER_PORT_OTHER=$GRDocbrokerPort" >> $DM_DOCKER_HOME/config/$configFileName
    echo "SERVER.PROJECTED_DOCBROKER_HOST_OTHER=$GRDocbrokerHost" >> $DM_DOCKER_HOME/config/$configFileName
}			

updateodbcini()
{
    if [ "$DB_TYPE" != "oracle" ]
	then
     log "Updating odbc.ini"
     sudo sed -i -e "s/Servername = .*/Servername = $DATABASE_HOST/"  /etc/odbc.ini
     sudo sed -i -e "s/Port = .*/Port = $DATABASE_SERVER_PORT/"  /etc/odbc.ini
     if [ $DATABASE_SERVICE_NAME ]
     then
        sudo sed -i -e "s/MyPostgres/$DATABASE_SERVICE_NAME/I"  /etc/odbc.ini
     fi
        
     if [ -n "$DATABASE_SSL_SUPPORT" ] && [ "$DATABASE_SSL_SUPPORT" == "true" ]
     then
        sudo sed -i -e "s/SSLmode=.*/SSLmode=$DATABASE_SSL_MODE/" /etc/odbc.ini
        if [ -n "$DATABASE_SSL_CERTIFICATE" ] && [ -n "$DATABASE_SSL_CERT_PATH" ]
        then
             mkdir -p /opt/dctm/.postgresql/
             sudo echo "$DATABASE_SSL_CERTIFICATE" > /opt/dctm/$DATABASE_SSL_CERT_PATH
             sudo sed -i -e "s|SSLCertPath=.*|SSLCertPath=/opt/dctm/$DATABASE_SSL_CERT_PATH|" /etc/odbc.ini
             mkdir -p /home/$INSTALL_OWNER/.postgresql/
             sudo echo "$DATABASE_SSL_CERTIFICATE" > /home/$INSTALL_OWNER/$DATABASE_SSL_CERT_PATH
        fi
     fi	
     sudo chmod -R 664 /etc/odbc.ini	
   fi
}		

handle_CS_statuscheck()
{
  cs_status_check_iapi=/tmp/cs_status_check_iapi.txt
  if [ ! -f $cs_status_check_iapi ];
  then
   echo "retrieve,c,dm_server_config" > $cs_status_check_iapi
   echo "disconnect,c" >> $cs_status_check_iapi
   echo "exit" >> $cs_status_check_iapi 
  fi
  COUNTER=0
  while [  $COUNTER -lt 12 ]; do
    log "checking CS status..."
    source $DM_HOME/bin/dm_set_server_env.sh; iapi $DOCBASE_NAME@$HOSTNAME -U$INSTALL_OWNER -P"" -R$cs_status_check_iapi >> /tmp/cs_status_check.log
    if [ $? -eq $SUCCESS ];
    then
     log "CS status succeeded"	
     break
    fi
	log "waiting for CS to come up..."
    let COUNTER=COUNTER+1         
    sleep 10	
  done
   
}

handle_JMS_statuscheck()
{
  COUNTER=0
  while [  $COUNTER -lt 18 ]; do
    JMS_URL="http://localhost:9080/DmMethods/servlet/DoMethod"
	ACS_URL="http://localhost:9080/ACS/servlet/ACS"
	log "Checking DmMethods response..."
	urlstatus=$(curl -o /dev/null --silent --head --write-out '%{http_code}' $JMS_URL)
	if [ $urlstatus -eq '200' ]
	then
	  log "Checking ACS response..."
      urlstatus=$(curl -o /dev/null --silent --head --write-out '%{http_code}' $ACS_URL)	
      if [ $urlstatus -eq '200' ]
      then
       log "JMS and ACS status succeeded"	  
       break
      fi
	fi
	log "waiting for JMS and ACS to come up..."
    let COUNTER=COUNTER+1         
    sleep 10	
  done
}


configure_csai_config()
{
	log "Verifying the configuration of CSAI Configuration required at this stage."
	hostname=`hostname -f`		
	containername=$CONTAINER_NAME
	containerlength=${#containername}	
	index=`expr $containerlength + 2`
	host_index=`expr substr $hostname $index 1`
	## During upgrade all the dar upgrade happens only in primary pod hence the dm_csai_object may not
	## be created hence the csai configuration should be done only in primary pod eigther of install & upgrade scenario  
	if [ $host_index = 0 ]
	then
		log "Configuring the csai_config object"
		
		if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
		then
			password=$INSTALL_OWNER_PASSWORD
		else
			password=$installOwnerPwd
		fi

		## Invoking configuration utility which interanlly to create or update the objects based on the values passed. 
		java -cp $DM_DOCKER_HOME:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config/: -DsrcDocbaseName=$GLOBAL_REPOSITORY_NAME -DtargetDocbaseName=$DOCBASE_NAME -DdocbaseUser=$INSTALL_OWNER -DdocbasePwd=$password  -Ddfc.properties.file=${DOCUMENTUM}/config/dfc.properties csaiconfigutil
		
		if [ $? != $SUCCESS ]
		then
			log "CSAI Configuration  failed"
		else
			
			log "CSAI Configuration successful"
		fi
	fi
}



handle_start_docbase()
{
    log "---------------------------------------------------------------------------------------"
	log "handle_start_docbase"		
	
	docbase=$DOCBASE_NAME
	serverport=$CONTENTSERVER_PORT
	server_secure_port=`expr $serverport + 1`
	serverini=${DOCUMENTUM}/dba/config/$docbase/server.ini
	
	echo dm_${docbase} $serverport/tcp | sudo tee -a /etc/services
	echo dm_${docbase}_s $server_secure_port/tcp | sudo tee -a /etc/services
    
	if [ "$alreadyInstalled" = "TRUE" ]
    then	
	  if [ "$EXT_DBR_PROJECTION_ENABLE" = "true" ]
	  then
		grep -i "${EXT_DBR_DOCBROKER_PORT}" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini > /dev/null
	    if [ $? -eq 1 ]
		then
		  count=$DOCBROKERS_COUNT
		  newcount=0
		  while [ $newcount -lt $DOCBROKERS_COUNT ]
		  do
			client_docbroker_host=$DOCBROKER_SERVICE_NAME-$newcount.$DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE			
			
			log "client_docbroker_host $client_docbroker_host"
			echo "[DOCBROKER_PROJECTION_TARGET_$count]" >> ${DOCUMENTUM}/dba/config/$docbase/server.ini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a proximity = 1"  ${DOCUMENTUM}/dba/config/$docbase/server.ini			
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a port = $EXT_DBR_DOCBROKER_PORT"  ${DOCUMENTUM}/dba/config/$docbase/server.ini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a host = $client_docbroker_host"  ${DOCUMENTUM}/dba/config/$docbase/server.ini
			count=`expr $count + 1`
			newcount=`expr $newcount + 1`
		  done		  
		fi
	  fi
		if [ "$DB_TYPE" = "oracle" ]
		then		
            if [ -n "$DATABASE_SERVICE_NAME" ]
			then        
				sed -i -e "s/SERVER.DATABASE_CONNECTION=.*/SERVER.DATABASE_CONNECTION=$DATABASE_SERVICE_NAME/"  ${DM_DOCKER_HOME}/config/linux_config.properties
            else
				sed -i -e "s/SERVER.DATABASE_CONNECTION=.*/SERVER.DATABASE_CONNECTION=orcl/"  ${DM_DOCKER_HOME}/config/linux_config.properties
            fi			
        fi
		if [ "$DB_TYPE" != "oracle" ]
		then
	      if [ -n "$DATABASE_SSL_SUPPORT" ] && [ "$DATABASE_SSL_SUPPORT" == "true" ]
          then
              sudo sed -i -e "s/SSLmode=.*/SSLmode=$DATABASE_SSL_MODE/" /etc/odbc.ini
              if [ -n "$DATABASE_SSL_CERTIFICATE" ] && [ -n "$DATABASE_SSL_CERT_PATH" ]
              then
                  mkdir -p /opt/dctm/.postgresql/
                  sudo echo "$DATABASE_SSL_CERTIFICATE" > /opt/dctm/$DATABASE_SSL_CERT_PATH
                  sudo sed -i -e "s|SSLCertPath=.*|SSLCertPath=/opt/dctm/$DATABASE_SSL_CERT_PATH|" /etc/odbc.ini
                  mkdir -p /home/$INSTALL_OWNER/.postgresql/
                  sudo echo "$DATABASE_SSL_CERTIFICATE" > /home/$INSTALL_OWNER/$DATABASE_SSL_CERT_PATH
              fi
          fi
		fi

      if [ -n "$CONCURRENT_SESSIONS" ]
      then
		sed -i -e "s/concurrent_sessions = .*/concurrent_sessions = $CONCURRENT_SESSIONS/"  ${DOCUMENTUM}/dba/config/$docbase/server.ini
      fi		  
  
      if [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
        then
            encryptedPasswd=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config EncryptPasswordUtil ${DFC_SSL_TRUSTSTORE_PASSWORD})
            certDocbase
            #For primary cs upgrade scenario,adding cert details in server.ini
            if [ `grep keystore_file $DOCUMENTUM/dba/config/$DOCBASE_NAME/server.ini | wc -l` -eq 0 ]
            then			
				sed -i -e '/^\[DOCBROKER_PROJECTION_TARGET_0/i \keystore_file=server.p12' $DOCUMENTUM/dba/config/$DOCBASE_NAME/server.ini
				sed -i -e '/keystore_file=server.p12/a cipherlist=ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256' $DOCUMENTUM/dba/config/$DOCBASE_NAME/server.ini
				sed -i -e '/keystore_file=server.p12/a truststore_file=server-trust.p7b' $DOCUMENTUM/dba/config/$DOCBASE_NAME/server.ini
				sed -i -e '/keystore_file=server.p12/a keystore_pwd_file=server.pwd' $DOCUMENTUM/dba/config/$DOCBASE_NAME/server.ini
				log "Added cert details in $DOCUMENTUM/dba/config/$DOCBASE_NAME/server.ini"
            fi
 
            #adding truststore details in dfc.properties
			# Now encrypt the password using the password encryption utility
			
			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				if [ `grep security.ssl.truststore $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
				then 
					echo "dfc.security.ssl.truststore=$DOCUMENTUM/certificate/dfc.keystore" >> $DOCUMENTUM/config/dfc.properties									
					if [ -z "$encryptedPasswd" ]
					then
						log "[handle_start_docbase] -->> Truststore password encryption failed. Using plain password"
						echo "dfc.security.ssl.truststore_password=${DFC_SSL_TRUSTSTORE_PASSWORD}" >> $DOCUMENTUM/config/dfc.properties
					else
						log "[handle_start_docbase] -->> Truststore password encryption passed."
						echo "dfc.security.ssl.truststore_password=$encryptedPasswd" >> $DOCUMENTUM/config/dfc.properties
					fi
                							
					log "Added truststore details in $DOCUMENTUM/config/dfc.properties"
				else
					#Check the password present in dfc.properties. If it matches with the encrypted password.
					#The no need to change trust store password
					dfcPropPasswd=$( sed -n -e '/dfc.security.ssl.truststore_password/ s/.*\= *//p' $DOCUMENTUM/config/dfc.properties)
				
					if [  "$encryptedPasswd" = "$dfcPropPasswd" ]
					then
						log "[handle_start_docbase] -->> Encrypted password [$encryptedPasswd] matches the password [$dfcPropPasswd] stored in dfc.properties."
					else
						log "[handle_start_docbase] -->> Encrypted password [$encryptedPasswd] doesn't matches the password [$dfcPropPasswd] stored in dfc.properties."
						sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$encryptedPasswd;" $DOCUMENTUM/config/dfc.properties
						log "[handle_start_docbase] -->> dfc.properties updated with new encrypted password $encryptedPasswd."
					fi
				
				fi
			else
		
				hostname=`hostname -f`
				sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname;" $DOCUMENTUM/config/dfc.properties
			fi

            if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				if [ `grep security.ssl.truststore ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties | wc -l` -eq 0 ]
				then 
					echo "dfc.security.ssl.truststore=$DOCUMENTUM/certificate/dfc.keystore" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
				
						if [ -z "$encryptedPasswd" ]
						then
							log "[handle_start_docbase] -->> Truststore password encryption failed. Using plain password"
							echo "dfc.security.ssl.truststore_password=${DFC_SSL_TRUSTSTORE_PASSWORD}" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
						else
							log "[handle_start_docbase] -->> Truststore password encryption passed."
							echo "dfc.security.ssl.truststore_password=$encryptedPasswd" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
						fi
                							
					log "Added truststore details in ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties"
				else
					#Check the password present in dfc.properties. If it matches with the encrypted password.
					#The no need to change trust store password
					dfcPropPasswd=$( sed -n -e '/dfc.security.ssl.truststore_password/ s/.*\= *//p' ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties)
				
					if [  "$encryptedPasswd" = "$dfcPropPasswd" ]
					then
						log "[handle_start_docbase] -->> Encrypted password [$encryptedPasswd] matches the password [$dfcPropPasswd] stored in dfc.properties."
					else
						log "[handle_start_docbase] -->> Encrypted password [$encryptedPasswd] doesn't matches the password [$dfcPropPasswd] stored in dfc.properties."
						sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$encryptedPasswd;" ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
						log "[handle_start_docbase] -->> dfc.properties updated with new encrypted password $encryptedPasswd."
					fi
			    
				fi
			else
				echo "dfc.dsis.enabled=$IS_VAULT_ENABLED" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
				echo "dfc.dsis.daemon.url=$DSIS_URL" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
		
				hostname=`hostname -f`
				echo "dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
			fi

			sed -i -e "s/dfc.session.secure_connect_default=.*/dfc.session.secure_connect_default=try_secure_first/" ${DOCUMENTUM}/config/dfc.properties
			sed -i -e "s/dfc.session.secure_connect_default=.*/dfc.session.secure_connect_default=try_secure_first/" ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
			log "Updated dfc.session.secure_connect_default=try_secure_first"
      fi
	  
	  set_event_hub_dfc_properties
	  
	  sed -i -e "s/upd_last_chg_time_from_db =.*/upd_last_chg_time_from_db = T/"  ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server.ini
	  log "[handle_start_docbase] -->> upd_last_chg_time_from_db with vlaue T."	

	  # Check if AEK details have been changed if yest upgrade it.
      # Check if AEK details have been changed if yest upgrade it.
	  # Check if we are creating AEK key here, then we need to start docbase.
	  # Get old AEK name from server.ini
	  oldAEKName=$( sed -n -e '/crypto_keyname/ s/.*\= *//p' ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server.ini)
	  # Get the key location from server.ini
	  oldAEKLocation=$( sed -n -e '/crypto_keystore/ s/.*\= *//p' ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server.ini)
	
	  if  [ "${oldAEKName}" != "${AEK_NAME}" ]
	  then
		log "[handle_start_docbase] -->> AEK details changed upgrading AEK key"

		if [ ! -f ${DOCUMENTUM}/data/aek_upgrade_files/${AEK_NAME} ]
		then
			aekKeyCreated="true"
			# If the current AEK key is local. Run dm_crypto_boot.
			if [ "${oldAEKLocation}" = "Local" ]
			then
				# In case of vault pull old aek password from vault.
				if [ "${IS_VAULT_ENABLED}" = "true" ]
				then
					oldaekPwd=$(curl $DSIS_URL/secret/$OLD_AEK_PASSPHRASE)
					source $DM_HOME/bin/dm_set_server_env.sh; dm_crypto_boot -passphrase $oldaekPwd -all
				else
					source $DM_HOME/bin/dm_set_server_env.sh; dm_crypto_boot -passphrase $OLD_AEK_PASSPHRASE -all
				fi
			fi		
		
			log "[handle_start_docbase] -->> Start Docbase"
			source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/dba/dm_start_${docbase}
			#CS perf: Modifying this to status check
			handle_CS_statuscheck
			log "[handle_start_docbase] -->> Docbase Started"
		fi
		
		handle_aek_upgrade	

		if [ "$aekKeyCreated" = "true" ]
		then
			log "[handle_start_docbase] -->> Stop Docbase after AEK upgrade"
			kill -9 `ps -ef | grep ${DOCBASE_NAME} |grep -v grep | awk '{print $2}'`
			check_cs_shutdown_status "server.ini"
			aekKeyCreated="false"
		fi	
	  fi

	  update_mail_notification_flag $serverini
	  initUpgrade=${DOCUMENTUM}/kube/upgradeInitiated$PRODUCT_MAJOR_VERSION
	  if [ -f "$initUpgrade" ]
	  then
		locupgadefile="${DOCUMENTUM}/data/locations-upgraded$PRODUCT_MAJOR_VERSION"
		if [ -f "$locupgadefile" ]
		then
			log "Locationobjects already Upgraded for CS $PRODUCT_MAJOR_VERSION"
		else
			upgradeLocationObjects true
			touch -f ${DOCUMENTUM}/data/locations-upgraded$PRODUCT_MAJOR_VERSION
		fi	  
	  fi
	  log "Starting Docbase"
	  
	  if [ "${AEK_LOCATION}" = "Local" ]
	  then
		source $DM_HOME/bin/dm_set_server_env.sh; dm_crypto_boot -passphrase $AEK_PASSPHRASE -all
	  fi
	  source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/dba/dm_start_${docbase}
	  #CS Perf: Modifying this to status check call
	  handle_CS_statuscheck
	  log "Docbase Started"
	  log "Executing the dm_acs_install.ebs script."
	  source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f ${DM_HOME}/install/admin/dm_acs_install.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" -e Upgrade > ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dm_acs_install.out;
	  validateEBSError dm_acs_install
	  updateAcsConfigLocalBaseUrl

	  restart_method_server
	  if [ -f "$initUpgrade" ]
	  then
		## Upgrading the dar files
		docbaseupgadefile="${DOCUMENTUM}/kube/Docbase-Upgraded$PRODUCT_MAJOR_VERSION"		
		if [ -f "$docbaseupgadefile" ]
		then
			log "Docbase already Upgraded"
		else
			upgradeDocbase
			log "Restarting the docbase after upgrade Docbase"
			log "stop content server"
			kill -9 `ps -ef | grep ${DOCBASE_NAME} |grep -v grep | awk '{print $2}'`
			check_cs_shutdown_status "server.ini"

			# Check if AEK details have been changed if yest upgrade it.
			handle_aek_upgrade

			log "Start content server"
			 			
			if [ "${AEK_LOCATION}" = "Local" ]
			then
				source $DM_HOME/bin/dm_set_server_env.sh; dm_crypto_boot -passphrase $AEK_PASSPHRASE -all
			fi
			source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/dba/dm_start_${docbase} 
			#CS Perf: Modifying this to status check call
			handle_CS_statuscheck
			log "Docbase Started"
			touch -f ${DOCUMENTUM}/kube/Docbase-Upgraded$PRODUCT_MAJOR_VERSION
			
		fi		
	  else
		dd_Populate
	  fi
      #restore the method sever and odbc config files
	  #$DM_DOCKER_HOME/scripts/methodserver_restore_backup_changes.sh restore
    else
		if [ "$MIGRATECS" = "true" ]
		then
			migratecsfile="${DOCUMENTUM}/kube/MigrateCS"		
			if [ -f "$migratecsfile" ]
			then
				log "Migration already completed"
			else
				rm -rf ${DOCUMENTUM}/dba/dm_start_$DOCBASE_NAME
				if [ "$MIGRATECS_FROM_WINDOWS" = "true" ]
				then
					migrateSysObjects
				fi
				migrateLocationObjects
				touch -f ${DOCUMENTUM}/kube/MigrateCS
				
			fi
		fi
		
		if [ "$ROOT_SQUASH_ENABLED" != "true" ]
		then
		 chmod -R 775 $DM_DOCKER_HOME
		fi
		
		if [ "$FILESTORE_COMPRESSION" = "true" ]
		then
				log "Enabling compression for default filestore"
				#sed -i -e "s/set,c,l,name\", fsName)/&\n    status=dmAPISet(\"set,c,l,content_dupl_pref\", \"4\")/" $DM_HOME/install/admin/headstart.ebs
				sed -i -e "s/set,c,l,name\", fsName)/&\n    status=dmAPISet(\"set,c,l,compression_mode\", \"1\")/" $DM_HOME/install/admin/headstart.ebs
		fi
		if [ "$FILESTORE_ENCRYPTION" = "true" ]
		then
				log "Enabling encryption for default filestore"
				sed -i -e "s/set,c,l,name\", fsName)/&\n    status=dmAPISet(\"set,c,l,crypto_mode\", \"1\")/" $DM_HOME/install/admin/headstart.ebs
		fi
			
		chmod -R 775 $DM_DOCKER_HOME/config
		log Setting values in odbc
		log DATABASE_HOST : $DATABASE_HOST
		log DATABASE_USER : $DATABASE_USER
		
		dbuser=$DATABASE_USER
		if [ "$DB_TYPE" = "oracle" ]
		then
		        log "DB_TYPE oracle"				
				if [ $DATABASE_SERVICE_NAME ]
				then                 
					sed -i -e "s/SERVER.DATABASE_CONNECTION=.*/SERVER.DATABASE_CONNECTION=$DATABASE_SERVICE_NAME/"  ${DM_DOCKER_HOME}/config/linux_config.properties
				else
					sed -i -e "s/SERVER.DATABASE_CONNECTION=.*/SERVER.DATABASE_CONNECTION=orcl/"  ${DM_DOCKER_HOME}/config/linux_config.properties
				fi				
		else
				updateodbcini
				if [ $DATABASE_SERVICE_NAME ]
				then
                        sed -i -e "s/SERVER.DATABASE_CONNECTION=.*/SERVER.DATABASE_CONNECTION=$DATABASE_SERVICE_NAME/"  ${DM_DOCKER_HOME}/config/linux_config.properties
				else
					sed -i -e "s/SERVER.DATABASE_CONNECTION=.*/SERVER.DATABASE_CONNECTION=MyPostgres/"  ${DM_DOCKER_HOME}/config/linux_config.properties
				fi		
		fi
		
		
		log "Setting values in $DM_DOCKER_HOME/config/linux_config.properties"
		
		sed -i -e "s/SERVER.PROJECTED_DOCBROKER_HOST=.*/SERVER.PROJECTED_DOCBROKER_HOST=$ext_docbroker/"  $DM_DOCKER_HOME/config/linux_config.properties
		sed -i -e "s;SERVER.SECURE.ROOT_PASSWORD=.*;SERVER.SECURE.ROOT_PASSWORD=$ROOT_PASSWORD;"  $DM_DOCKER_HOME/config/linux_config.properties
		sed -i -e "s/SERVER.PROJECTED_DOCBROKER_PORT=.*/SERVER.PROJECTED_DOCBROKER_PORT=$DOCBROKER_PORT/"  $DM_DOCKER_HOME/config/linux_config.properties
	   
		#AEK Alogorithm changes

		sed -i -e "s/common.aek.algorithm=.*/common.aek.algorithm=$AEK_ALGORITHM/"  $DM_DOCKER_HOME/config/linux_config.properties
		
		sed -i -e "s;common.aek.passphrase.password=.*;common.aek.passphrase.password=$AEK_PASSPHRASE;"  $DM_DOCKER_HOME/config/linux_config.properties
		
		sed -i -e "s/common.aek.key.name=.*/common.aek.key.name=$AEK_NAME/"  $DM_DOCKER_HOME/config/linux_config.properties
		# kms changes
		if [ "${AEK_LOCATION}" = "Remote" ]
		then			
			sed -i -e "s;common.aek.otkms.url=.*;common.aek.otkms.url=$KMS_URL;"  $DM_DOCKER_HOME/config/linux_config.properties
			sed -i -e "s;common.aek.credential.key=.*;common.aek.credential.key=$KMS_API_KEY;"  $DM_DOCKER_HOME/config/linux_config.properties
			sed -i -e "s/common.aek.masterkey.id=.*/common.aek.masterkey.id=$KMS_MASTER_KEY_ID/"  $DM_DOCKER_HOME/config/linux_config.properties
		fi
		if [ "${IS_VAULT_ENABLED}" = "true" ]
		then
			sed -i -e "s;IS_VAULT_ENABLED=.*;IS_VAULT_ENABLED=$IS_VAULT_ENABLED;" $DM_DOCKER_HOME/config/linux_config.properties
			sed -i -e "s;DSIS_URL=.*;DSIS_URL=$DSIS_URL;" $DM_DOCKER_HOME/config/linux_config.properties
		fi
		if [ "${AEK_LOCATION}" = "Remote_Vault" ]
		then
			sed -i -e "s/common.aek.key.type=.*/common.aek.key.type=Local/"  $DM_DOCKER_HOME/config/linux_config.properties
		else
			sed -i -e "s/common.aek.key.type=.*/common.aek.key.type=$AEK_LOCATION/"  $DM_DOCKER_HOME/config/linux_config.properties
		fi
        
		sed -i -e "s;SERVER.SECURE.DOCBASE_OWNER_PASSWORD=.*;SERVER.SECURE.DOCBASE_OWNER_PASSWORD=$DOCBASE_PASSWORD;"  $DM_DOCKER_HOME/config/linux_config.properties
		sed -i -e "s;SERVER.SECURE.BOF_REGISTRY_USER_PASSWORD=.*;SERVER.SECURE.BOF_REGISTRY_USER_PASSWORD=$GLOBAL_REGISTRY_PASSWORD;"  $DM_DOCKER_HOME/config/linux_config.properties
		
		if [ "$GLOBAL_REPOSITORY_NAME" != "" ] && [ "$GLOBAL_REPOSITORY_NAME" != "$DOCBASE_NAME" ]
		then
			updateGlobalRepositoryDetailsInConfigFile "linux_config.properties"
		fi
				
		sed -i -e "s/SERVER.FQDN=.*/SERVER.FQDN=$hostname/"  $DM_DOCKER_HOME/config/linux_config.properties
		sed -i -e "s/SERVER.AUTH_DOMAIN=.*/SERVER.AUTH_DOMAIN=$hostname/"  $DM_DOCKER_HOME/config/linux_config.properties
		sed -i -e "s/SERVER.DOCBASE_OWNER_NAME=.*/SERVER.DOCBASE_OWNER_NAME=$DOCBASE_OWNER_NAME/"  ${DM_DOCKER_HOME}/config/linux_config.properties
		sed -i -e "s/SERVER.DOCBASE_NAME=.*/SERVER.DOCBASE_NAME=$docbase/"  ${DM_DOCKER_HOME}/config/linux_config.properties
		sed -i -e "s/SERVER.DOCBASE_DESCRIPTION=.*/SERVER.DOCBASE_DESCRIPTION=$docbase/"  ${DM_DOCKER_HOME}/config/linux_config.properties
		if [ "$DATABASE_NAME" != "" ]
		then
			sed -i -e "s/SERVER.DATABASE_NAME=.*/SERVER.DATABASE_NAME=$DATABASE_NAME/"  ${DM_DOCKER_HOME}/config/linux_config.properties
		else
			sed -i -e "s/SERVER.DATABASE_NAME=.*/SERVER.DATABASE_NAME=dm_${docbase}_docbase/"  ${DM_DOCKER_HOME}/config/linux_config.properties
		fi
		sed -i -e "s/SERVER.DOCBASE_SERVICE_NAME=.*/SERVER.DOCBASE_SERVICE_NAME=dm_${docbase}/"  ${DM_DOCKER_HOME}/config/linux_config.properties
		
		sed -i -e "s;SERVER.SECURE.DATABASE_ADMIN_PASSWORD=.*;SERVER.SECURE.DATABASE_ADMIN_PASSWORD=$DATABASE_PASSWORD;"  ${DM_DOCKER_HOME}/config/linux_config.properties
		
		sed -i -e "s/SERVER.DATABASE_ADMIN_NAME=.*/SERVER.DATABASE_ADMIN_NAME=$dbuser/"  ${DM_DOCKER_HOME}/config/linux_config.properties
		
		sed -i -e "s;DFC.SECURE.GR_PASSWORD=.*;DFC.SECURE.GR_PASSWORD=$GLOBAL_REGISTRY_PASSWORD;"  ${DM_DOCKER_HOME}/config/linux_config.properties
		
		sed -i -e "s/SERVER.DOCBASE_ID=.*/SERVER.DOCBASE_ID=$DOCBASE_ID/"  ${DM_DOCKER_HOME}/config/linux_config.properties
		sed -i -e "s#SERVER.DOCUMENTUM_DATA=.*#SERVER.DOCUMENTUM_DATA=${DOCUMENTUM}/data#"  ${DM_DOCKER_HOME}/config/linux_config.properties
		sed -i -e "s#SERVER.DOCUMENTUM_SHARE=.*#SERVER.DOCUMENTUM_SHARE=${DOCUMENTUM}/share#"  ${DM_DOCKER_HOME}/config/linux_config.properties
		sed -i -e "s/SERVER.CONNECT_MODE=.*/SERVER.CONNECT_MODE=$DOCBASE_CONNECT_MODE/" ${DM_DOCKER_HOME}/config/linux_config.properties
		 if [ -n $USE_DEFAULT_SPACE ] && [ "$USE_DEFAULT_SPACE" = "true" ]
        then
            log "USE_DEFAULT_SPACE"
            sed -i -e "s/SERVER.POSTGRES_USE_DEFAULT_SPACE=.*/SERVER.POSTGRES_USE_DEFAULT_SPACE=$USE_DEFAULT_SPACE/"  ${DM_DOCKER_HOME}/config/linux_config.properties
        fi
		if [ -n $DATABASE_PAAS_ENV ] && [ "$DATABASE_PAAS_ENV" = "true" ]
        then
            log "DATABASE_PAAS_ENV"
            sed -i -e "s/SERVER.DB_IN_PAAS_ENVIRONMENT=.*/SERVER.DB_IN_PAAS_ENVIRONMENT=$DATABASE_PAAS_ENV/"  ${DM_DOCKER_HOME}/config/linux_config.properties
            if [ -z $USE_DEFAULT_SPACE ] || [ "$USE_DEFAULT_SPACE" = "false" ]
            then
                sed -i -e "s/SERVER.POSTGRES_USE_DEFAULT_SPACE=.*/SERVER.POSTGRES_USE_DEFAULT_SPACE=true/"  ${DM_DOCKER_HOME}/config/linux_config.properties
            fi
        fi
		#sed -i -e "s/START_METHOD_SERVER=.*/START_METHOD_SERVER=true/"  ${DM_DOCKER_HOME}/config/linux_config.properties
		
		
		if [ "$USE_EXISTING_DATABASE_ACCOUNT" = "true" ]
		then 
			chown -R $INSTALL_OWNER:$INSTALL_OWNER ${DOCUMENTUM}/dba
			if [ -d  "${DOCUMENTUM}/dba/log" ]
			then
					log "$DOCUMENTUM/dba/log folder already exists"
			else
					log "Creating $DOCUMENTUM/dba/log folder"
					mkdir ${DOCUMENTUM}/dba/log
			fi
			log USE_EXISTING_DATABASE_ACCOUNT : $USE_EXISTING_DATABASE_ACCOUNT
			log INDEXSPACE_NAME : $INDEXSPACE_NAME
			if [ "$INDEXSPACE_NAME" = "" ]
			then 
					log "IndexSpace name is missing. Please check INDEXSPACE_NAME env variable and try again."
					exitProgram
			fi
			sed -i -e "s/SERVER.USE_EXISTING_DATABASE_ACCOUNT=.*/SERVER.USE_EXISTING_DATABASE_ACCOUNT=$USE_EXISTING_DATABASE_ACCOUNT/"  ${DM_DOCKER_HOME}/config/linux_config.properties
			sed -i -e "s/##SERVER.INDEXSPACE_NAME=.*/SERVER.INDEXSPACE_NAME=$INDEXSPACE_NAME/"  ${DM_DOCKER_HOME}/config/linux_config.properties
			
		fi
		if [ -f $DOCUMENTUM/shared_key/$AEK_NAME ]
		then
			log "Use existing shared AEK from PVC"
			cp $DOCUMENTUM/shared_key/$AEK_NAME $DOCUMENTUM/dba/secure/$AEK_NAME
		fi
		if [ "$MIGRATECS" = "true" ] || [ -f $DOCUMENTUM/dba/secure/$AEK_NAME ]
		then
			log "Updating USE_EXISTING_AEK"
			sed -i -e "s/common.use.existing.aek.*/common.use.existing.aek=common.use.existing/"  ${DM_DOCKER_HOME}/config/linux_config.properties
		fi
		
        if [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
        then
		    sed -i -e "s/common.use.existing.aek.*/common.use.existing.aek=common.use.existing/"  ${DM_DOCKER_HOME}/config/linux_config.properties
            sed -i -e "s/SERVER.CONNECT_MODE=.*/SERVER.CONNECT_MODE=$DOCBASE_CONNECT_MODE/" ${DM_DOCKER_HOME}/config/linux_config.properties
            certDocbase
            sed -i -e "s/#SERVER.USE_CERTIFICATES=.*/SERVER.USE_CERTIFICATES=$DOCBASE_USE_CERTIFICATES/"  ${DM_DOCKER_HOME}/config/linux_config.properties
            sed -i -e "s/#SERVER.KEYSTORE_FILE_NAME=.*/SERVER.KEYSTORE_FILE_NAME=server.p12/"  ${DM_DOCKER_HOME}/config/linux_config.properties
            sed -i -e "s/#SERVER.KEYSTORE_PASSWORD_FILE_NAME=.*/SERVER.KEYSTORE_PASSWORD_FILE_NAME=server.pwd/"  \
                                        ${DM_DOCKER_HOME}/config/linux_config.properties
            sed -i -e "s/#SERVER.TRUST_STORE_FILE_NAME=.*/SERVER.TRUST_STORE_FILE_NAME=server-trust.p7b/" ${DM_DOCKER_HOME}/config/linux_config.properties
            sed -i -e "s/#SERVER.CIPHER_LIST=.*/SERVER.CIPHER_LIST=ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256/" ${DM_DOCKER_HOME}/config/linux_config.properties
            sed -i -e "s|#SERVER.DFC_SSL_TRUSTSTORE=.*|SERVER.DFC_SSL_TRUSTSTORE=$DOCUMENTUM/certificate/dfc.keystore|"  ${DM_DOCKER_HOME}/config/linux_config.properties
			
			sed -i -e "s;#SERVER.DFC_SSL_TRUSTSTORE_PASSWORD=.*;SERVER.DFC_SSL_TRUSTSTORE_PASSWORD=${DFC_SSL_TRUSTSTORE_PASSWORD};"  ${DM_DOCKER_HOME}/config/linux_config.properties
			
            sed -i -e "s/#SERVER.DFC_SSL_USE_EXISTING_TRUSTSTORE=.*/SERVER.DFC_SSL_USE_EXISTING_TRUSTSTORE=false/" ${DM_DOCKER_HOME}/config/linux_config.properties
        fi
		if [ -n "$IS_EXTERNAL_USER_ENABLED" ] && [ "$IS_EXTERNAL_USER_ENABLED" == "true" ]
        then
			sed -i -e "s|SERVER.EXTERNAL_USER_METRICS=.*|SERVER.EXTERNAL_USER_METRICS=true|"  ${DM_DOCKER_HOME}/config/linux_config.properties
		fi
		log "Docbase Installation Started..."
		${DM_HOME}/install/dm_launch_server_config_program.sh -f ${DM_DOCKER_HOME}/config/linux_config.properties
		if [ $? != $SUCCESS ]
		then        
			log "ERROR: The installation has failed. Please check install logs at container's ${DM_HOME}/install/logs/install.log"
			exitProgram
		
		fi
		log "Docbase installation Completed...."
		
		if [ "$SHARE_KEY" == "true" ]
		then
			log "Creating shared AEK in PVC"
			cp $DOCUMENTUM/dba/secure/$AEK_NAME $DOCUMENTUM/shared_key/$AEK_NAME
		fi
		#update the data_dictionary.ini according to the language packs selected during the installation.
		dd_Populate

		sed -i -e '/\[DOCBROKER_PROJECTION_TARGET/d' $serverini
        sed -i -e '/proximity=/d' $serverini
        sed -i -e '/proximity =/d' $serverini
        sed -i -e '/host=/d' $serverini
        sed -i -e '/host =/d' $serverini
        sed -i -e '/port=/d' $serverini
        sed -i -e '/port =/d' $serverini
		if [ -n "$CONCURRENT_SESSIONS" ]
        then
		   sed -i -e "s/concurrent_sessions = .*/concurrent_sessions = $CONCURRENT_SESSIONS/"  $serverini
        fi
		
		add_docbroker_to_serverini			
		
		if [ "$EXT_DBR_PROJECTION_ENABLE" = "true" ]
		then
		 newcount=0
		 while [ $newcount -lt $DOCBROKERS_COUNT ]
		 do
			client_docbroker_host=$DOCBROKER_SERVICE_NAME-$newcount.$DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE			
			
			log "client_docbroker_host $client_docbroker_host"
			echo "[DOCBROKER_PROJECTION_TARGET_$count]" >> $serverini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a proximity = 1"  $serverini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a port = $EXT_DBR_DOCBROKER_PORT" $serverini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a host = $client_docbroker_host" $serverini
			count=`expr $count + 1`
			newcount=`expr $newcount + 1`
		 done		  
		fi
		
		chown -R $INSTALL_OWNER:$INSTALL_OWNER $serverini
		log "Stop Docbase"
		kill -9 `ps -ef | grep ${DOCBASE_NAME} |grep -v grep | awk '{print $2}'`
		
		
		check_cs_shutdown_status "server.ini"
		update_mail_notification_flag $serverini
		set_event_hub_dfc_properties
		log "Start Docbase"
		# Check if AEK details have been changed if yest upgrade it.
		handle_aek_upgrade

		source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/dba/dm_start_${docbase}
		#CS perf: Modifying this to status check
        handle_CS_statuscheck

		#--- backing dba files to kube as we do not want to mount log folder in pvc ---
		copy_dba_files_to_kube_backup		
	fi
}

add_docbroker_to_serverini()
{
	count=0		
	while [ $count -lt $DOCBROKERS_COUNT ]
	do
		client_docbroker_host=$DOCBROKER_SERVICE_NAME-$count.$DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE			
		log "client_docbroker_host $client_docbroker_host"
		echo "[DOCBROKER_PROJECTION_TARGET_$count]" >> ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server.ini
		sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a proximity = 1"  ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server.ini			
		sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a port = $DOCBROKER_PORT"  ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server.ini
		sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a host = $client_docbroker_host"  ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server.ini
		count=`expr $count + 1`
	done
}

handle_start_HA_docbase()
{
    log "---------------------------------------------------------------------------------------"
	log "handle_start_HA_docbase"	
	
	docbase=$DOCBASE_NAME		 
	serverport=$CONTENTSERVER_PORT
	server_secure_port=`expr $serverport + 1`	
	serverini=${DOCUMENTUM}/dba/config/$docbase/server_${SERVER_CONFIG_NAME}.ini
		
	echo dm_${docbase} $serverport/tcp | sudo tee -a /etc/services
	echo dm_${docbase}_s $server_secure_port/tcp | sudo tee -a /etc/services	
		
	if [ "$alreadyInstalled" = "TRUE" ]
	then
          if [ "$EXT_DBR_PROJECTION_ENABLE" = "true" ]
	  then
		grep -i "${EXT_DBR_DOCBROKER_PORT}" ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server_${SERVER_CONFIG_NAME}.ini > /dev/null
	    if [ $? -eq 1 ]
		then
		  count=$DOCBROKERS_COUNT
		  newcount=0
		  while [ $newcount -lt $DOCBROKERS_COUNT ]
		  do
			client_docbroker_host=$DOCBROKER_SERVICE_NAME-$newcount.$DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE			
			
			log "client_docbroker_host $client_docbroker_host"
			echo "[DOCBROKER_PROJECTION_TARGET_$count]" >> ${DOCUMENTUM}/dba/config/$docbase/server_${SERVER_CONFIG_NAME}.ini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a proximity = 1"  ${DOCUMENTUM}/dba/config/$docbase/server_${SERVER_CONFIG_NAME}.ini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a port = $EXT_DBR_DOCBROKER_PORT"  ${DOCUMENTUM}/dba/config/$docbase/server_${SERVER_CONFIG_NAME}.ini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a host = $client_docbroker_host"  ${DOCUMENTUM}/dba/config/$docbase/server_${SERVER_CONFIG_NAME}.ini
			count=`expr $count + 1`
			newcount=`expr $newcount + 1`
		  done		  
		fi
	 fi
	 
	   if [ "$DB_TYPE" != "oracle" ]
	   then
         if [ -n "$DATABASE_SSL_SUPPORT" ] && [ "$DATABASE_SSL_SUPPORT" == "true" ]
         then
             sudo sed -i -e "s/SSLmode=.*/SSLmode=$DATABASE_SSL_MODE/" /etc/odbc.ini
             if [ -n "$DATABASE_SSL_CERTIFICATE" ] && [ -n "$DATABASE_SSL_CERT_PATH" ]
             then
                 mkdir -p /opt/dctm/.postgresql/
                 sudo echo "$DATABASE_SSL_CERTIFICATE" > /opt/dctm/$DATABASE_SSL_CERT_PATH
                 sudo sed -i -e "s|SSLCertPath=.*|SSLCertPath=/opt/dctm/$DATABASE_SSL_CERT_PATH|" /etc/odbc.ini
                 mkdir -p /home/$INSTALL_OWNER/.postgresql/
                 sudo echo "$DATABASE_SSL_CERTIFICATE" > /home/$INSTALL_OWNER/$DATABASE_SSL_CERT_PATH
             fi
         fi
	   fi
		 
		if [ -n "$CONCURRENT_SESSIONS" ]
        then
            sed -i -e "s/concurrent_sessions = .*/concurrent_sessions = $CONCURRENT_SESSIONS/"  ${DOCUMENTUM}/dba/config/$docbase/server_${SERVER_CONFIG_NAME}.ini
        fi
        
		if [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
        then
            encryptedPasswd=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config EncryptPasswordUtil ${DFC_SSL_TRUSTSTORE_PASSWORD})
            certDocbase
            #for HA upgrade scenario, updating server_HA*docabse.ini
            if [ `grep keystore_file ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server_${SERVER_CONFIG_NAME}.ini | wc -l` -eq 0 ]
            then
                sed -i -e '/^\[DOCBROKER_PROJECTION_TARGET_0/i \keystore_file=server.p12' ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server_${SERVER_CONFIG_NAME}.ini
                sed -i -e '/keystore_file=server.p12/a cipherlist=ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256' ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server_${SERVER_CONFIG_NAME}.ini
                sed -i -e '/keystore_file=server.p12/a truststore_file=server-trust.p7b' ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server_${SERVER_CONFIG_NAME}.ini
                sed -i -e '/keystore_file=server.p12/a keystore_pwd_file=server.pwd' ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server_${SERVER_CONFIG_NAME}.ini
                log "Added cert details in ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server_${SERVER_CONFIG_NAME}.ini"
            fi

            #adding truststore details in dfc.properties
			# Now encrypt the password using the password encryption utility
			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then			
				if [ `grep security.ssl.truststore $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
				then 
					echo "dfc.security.ssl.truststore=$DOCUMENTUM/certificate/dfc.keystore" >> $DOCUMENTUM/config/dfc.properties
					
						if [ -z "$encryptedPasswd" ]
						then
							log "[handle_start_HA_docbase] -->> Truststore password encryption failed. Using plain password"
							echo "dfc.security.ssl.truststore_password=${DFC_SSL_TRUSTSTORE_PASSWORD}" >> $DOCUMENTUM/config/dfc.properties
						else
							log "[handle_start_HA_docbase] -->> Truststore password encryption passed."
							echo "dfc.security.ssl.truststore_password=$encryptedPasswd" >> $DOCUMENTUM/config/dfc.properties
						fi
					               
					log "Added truststore details in $DOCUMENTUM/config/dfc.properties"
				else
					#Check the password present in dfc.properties. If it matches with the encrypted password.
					#The no need to change trust store password
					dfcPropPasswd=$( sed -n -e '/dfc.security.ssl.truststore_password/ s/.*\= *//p' $DOCUMENTUM/config/dfc.properties)
				
					if [  "$encryptedPasswd" = "$dfcPropPasswd" ]
					then
						log "[handle_start_HA_docbase] -->> Encrypted password [$encryptedPasswd] matches the password [$dfcPropPasswd] stored in dfc.properties."
					else
						log "[handle_start_HA_docbase] -->> Encrypted password [$encryptedPasswd] doesn't matches the password [$dfcPropPasswd] stored in dfc.properties."
						sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$encryptedPasswd;" $DOCUMENTUM/config/dfc.properties
						log "[handle_start_HA_docbase] -->> dfc.properties updated with new encrypted password $encryptedPasswd."
					fi
				fi
		    else
				if [ `grep dfc.security.ssl.truststore_password $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
				then
			
					hostname=`hostname -f`
				    echo "dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname" >> $DOCUMENTUM/config/dfc.properties
				else
			
					hostname=`hostname -f`
				    sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname;" $DOCUMENTUM/config/dfc.properties
				fi
			fi 

			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				if [ `grep security.ssl.truststore ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties | wc -l` -eq 0 ]
				then 
					echo "dfc.security.ssl.truststore=$DOCUMENTUM/certificate/dfc.keystore" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
				
					if [ -z "$encryptedPasswd" ]
					then
						log "[handle_start_HA_docbase] -->> Truststore password encryption failed. Using plain password"
						echo "dfc.security.ssl.truststore_password=${DFC_SSL_TRUSTSTORE_PASSWORD}" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
					else
						log "[handle_start_HA_docbase] -->> Truststore password encryption passed."
						echo "dfc.security.ssl.truststore_password=$encryptedPasswd" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
					fi
               
					log "Added truststore details in ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties"
				else
					#Check the password present in dfc.properties. If it matches with the encrypted password.
					#The no need to change trust store password
					dfcPropPasswd=$( sed -n -e '/dfc.security.ssl.truststore_password/ s/.*\= *//p' 	${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties)
				
					if [  "$encryptedPasswd" = "$dfcPropPasswd" ]
					then
						log "[handle_start_HA_docbase] -->> Encrypted password [$encryptedPasswd] matches the password [$dfcPropPasswd] stored in dfc.properties."
					else
						log "[handle_start_HA_docbase] -->> Encrypted password [$encryptedPasswd] doesn't matches the password [$dfcPropPasswd] stored in dfc.properties."
						sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$encryptedPasswd;" ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
						log "[handle_start_HA_docbase] -->> dfc.properties updated with new encrypted password $encryptedPasswd."
					fi
				fi
				log "Added truststore details in ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties"
			 else
				if [ `grep dfc.dsis.enabled ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties | wc -l` -eq 0 ]
				then
					echo "dfc.dsis.enabled=$IS_VAULT_ENABLED" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
					echo "dfc.dsis.daemon.url=$DSIS_URL" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
			
					hostname=`hostname -f`
					echo "dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname" >> ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
				else
					sed -i -e "s;dfc.dsis.enabled=.*;dfc.dsis.enabled=$IS_VAULT_ENABLED;" ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
					sed -i -e "s;dfc.dsis.daemon.url=.*;dfc.dsis.daemon.url=$DSIS_URL;" ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
			
					hostname=`hostname -f`
					sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname;" ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
				fi
             fi
	
            sed -i -e "s/dfc.session.secure_connect_default=.*/dfc.session.secure_connect_default=try_secure_first/" ${DOCUMENTUM}/config/dfc.properties
			sed -i -e "s/dfc.session.secure_connect_default=.*/dfc.session.secure_connect_default=try_secure_first/" ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
            log "Updated dfc.session.secure_connect_default=try_secure_first"
        fi
		
		sed -i -e "s/upd_last_chg_time_from_db =.*/upd_last_chg_time_from_db = T/"  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server_${SERVER_CONFIG_NAME}.ini
		log "[handle_start_HA_docbase] -->> upd_last_chg_time_from_db with vlaue T."

		## Upgrading the location objects
		initUpgrade=${DOCUMENTUM}/kube/upgradeInitiated$PRODUCT_MAJOR_VERSION
		if [ -f "$initUpgrade" ]
		then
			locupgadefile="${DOCUMENTUM}/data/locations-upgraded$PRODUCT_MAJOR_VERSION"		
			if [ -f "$locupgadefile" ]
			then
				log "Locationobjects already Upgraded for CS $PRODUCT_MAJOR_VERSION"				
			else
				upgradeLocationObjects
				touch -f ${DOCUMENTUM}/data/locations-upgraded$PRODUCT_MAJOR_VERSION
			
			fi
		fi
		set_event_hub_dfc_properties
		
		if [ "${AEK_LOCATION}" = "Local" ]
		then
			source $DM_HOME/bin/dm_set_server_env.sh; dm_crypto_boot -passphrase $AEK_PASSPHRASE -all
		fi
	else		
		log "AEK_ALGORITHM : $AEK_ALGORITHM"
		log "DOCBROKER_HOST : $DOCBROKER_HOST"
		log "SERVER_CONFIG_NAME : $SERVER_CONFIG_NAME"	
        if [ "$DB_TYPE" != "oracle" ]
        then		
		  log "Setting values in odbc.ini"
		fi
		log "DATABASE_HOST : $DATABASE_HOST"
		log "DATABASE_USER : $DATABASE_USER"
		
		if [ "$DB_TYPE" = "oracle" ]
		then
		        log "DB_TYPE oracle"				
				if [ $DATABASE_SERVICE_NAME ]
                then                
					sed -i -e "s/SERVER.DATABASE_CONNECTION=.*/SERVER.DATABASE_CONNECTION=$DATABASE_SERVICE_NAME/"  ${DM_DOCKER_HOME}/config/linux_config.properties
                else
					sed -i -e "s/SERVER.DATABASE_CONNECTION=.*/SERVER.DATABASE_CONNECTION=orcl/"  ${DM_DOCKER_HOME}/config/linux_config.properties
                fi				
		else
				updateodbcini

		fi
		
		log "Setting values in cfs_linux_config.properties"

		if [ "${IS_VAULT_ENABLED}" = "true" ]
		then
			sed -i -e "s;IS_VAULT_ENABLED=.*;IS_VAULT_ENABLED=$IS_VAULT_ENABLED;" $DM_DOCKER_HOME/config/cfs_linux_config.properties
			sed -i -e "s;DSIS_URL=.*;DSIS_URL=$DSIS_URL;" $DM_DOCKER_HOME/config/cfs_linux_config.properties
		fi
		
		#AEK Alogorithm changes

		# AEK related ?? If aek will be used from the primary(AEK_ALGORITHM, AEK_PASSPHRASE, AEK_NAME)
		sed -i -e "s/common.aek.algorithm=.*/common.aek.algorithm=$AEK_ALGORITHM/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		sed -i -e "s;common.aek.passphrase.password=.*;common.aek.passphrase.password=$AEK_PASSPHRASE;"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		sed -i -e "s/common.aek.key.name=.*/common.aek.key.name=$AEK_NAME/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties

		# kms changes
		sed -i -e "s;common.aek.otkms.url=.*;common.aek.otkms.url=$KMS_URL;"  $DM_DOCKER_HOME/config/cfs_linux_config.properties
		sed -i -e "s;common.aek.credential.key=.*;common.aek.credential.key=$KMS_API_KEY;"  $DM_DOCKER_HOME/config/cfs_linux_config.properties
		sed -i -e "s/common.aek.masterkey.id=.*/common.aek.masterkey.id=$KMS_MASTER_KEY_ID/"  $DM_DOCKER_HOME/config/cfs_linux_config.properties
		if [ "${AEK_LOCATION}" = "Remote_Vault" ]
		then
			sed -i -e "s/common.aek.key.type=.*/common.aek.key.type=Local/"  $DM_DOCKER_HOME/config/cfs_linux_config.properties
		else
			sed -i -e "s/common.aek.key.type=.*/common.aek.key.type=$AEK_LOCATION/"  $DM_DOCKER_HOME/config/cfs_linux_config.properties
		fi

		sed -i -e "s/SERVER.PROJECTED_CONNECTION_BROKER_PORT=.*/SERVER.PROJECTED_CONNECTION_BROKER_PORT=$DOCBROKER_PORT/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.CONNECTION_BROKER_PORT=.*/SERVER.CONNECTION_BROKER_PORT=$DOCBROKER_PORT/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.CONNECTION_BROKER_NAME=.*/SERVER.CONNECTION_BROKER_NAME=Docbroker/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.VALIDATE_FQDN=.*/SERVER.VALIDATE_FQDN=$VALIDATE_FQDN/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties		
		
		sed -i -e "s/SERVER.PRIMARY_CONNECTION_BROKER_HOST=.*/SERVER.PRIMARY_CONNECTION_BROKER_HOST=$ext_docbroker/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.PRIMARY_CONNECTION_BROKER_PORT=.*/SERVER.PRIMARY_CONNECTION_BROKER_PORT=$DOCBROKER_PORT/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		# Give internal Docbroker host name(hostname)
		sed -i -e "s/SERVER.PROJECTED_CONNECTION_BROKER_HOST=.*/SERVER.PROJECTED_CONNECTION_BROKER_HOST=$ext_docbroker/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		# Give the service name ?? should the service be configure in  etc(DOCBASE_NAME)
		sed -i -e "s/SERVER.DOCBASE_SERVICE_NAME=.*/SERVER.DOCBASE_SERVICE_NAME=dm_${docbase}/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		# Give the hostname as server fqdn(hostname)
		sed -i -e "s/SERVER.FQDN=.*/SERVER.FQDN=$hostname/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		# Docbase name and server config name, both are docbase name only(DOCBASE_NAME)
		sed -i -e "s/SERVER.DOCBASE_NAME=.*/SERVER.DOCBASE_NAME=$docbase/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.PRIMARY_SERVER_CONFIG_NAME=.*/SERVER.PRIMARY_SERVER_CONFIG_NAME=$docbase/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		# Repository username, password and repo domain(INSTALL_OWNER, INSTALL_OWNER_PASSWORD)
		sed -i -e "s/SERVER.REPOSITORY_USERNAME=.*/SERVER.REPOSITORY_USERNAME=$INSTALL_OWNER/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		sed -i -e "s;SERVER.SECURE.REPOSITORY_PASSWORD=.*;SERVER.SECURE.REPOSITORY_PASSWORD=$INSTALL_OWNER_PASSWORD;"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		sed -i -e "s/SERVER.REPOSITORY_USERNAME_WITH_DOMAIN=.*/SERVER.REPOSITORY_USERNAME_WITH_DOMAIN=$INSTALL_OWNER/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		# Server repo local hostname, new server config name(hostname)--changed
		sed -i -e "s/SERVER.REPOSITORY_HOSTNAME.*/SERVER.REPOSITORY_HOSTNAME=$PRIMARY_HOSTNAME/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/CFS_SERVER_CONFIG_NAME=.*/CFS_SERVER_CONFIG_NAME=$SERVER_CONFIG_NAME/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties	
		if [ "$GLOBAL_REPOSITORY_NAME" != "" ] && [ "$GLOBAL_REPOSITORY_NAME" != "$DOCBASE_NAME" ]	
		then
			updateGlobalRepositoryDetailsInConfigFile "cfs_linux_config.properties"
		else 
			sed -i -e "s/SERVER.GLOBAL_REGISTRY_REPOSITORY=.*/SERVER.GLOBAL_REGISTRY_REPOSITORY=$docbase/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		fi
        
		sed -i -e "s;SERVER.SECURE.BOF_REGISTRY_USER_PASSWORD=.*;SERVER.SECURE.BOF_REGISTRY_USER_PASSWORD=$GLOBAL_REGISTRY_PASSWORD;"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		sed -i -e "s#SERVER.DOCUMENTUM_DATA=.*#SERVER.DOCUMENTUM_DATA=$DOCUMENTUM_DATA_PATH#"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s#SERVER.DOCUMENTUM_SHARE=.*#SERVER.DOCUMENTUM_SHARE=$DOCUMENTUM_SHARE_PATH#"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		sed -i -e "s/SERVER.PROJECTED_DOCBROKER_PORT_OTHER=.*/SERVER.PROJECTED_DOCBROKER_PORT_OTHER=$DOCBROKER_PORT/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
        sed -i -e "s/SERVER.PROJECTED_DOCBROKER_HOST_OTHER=.*/SERVER.PROJECTED_DOCBROKER_HOST_OTHER=$ext_docbroker/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		sed -i -e "s/SERVER.CONNECT_MODE=.*/SERVER.CONNECT_MODE=$DOCBASE_CONNECT_MODE/" ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		
		if [ $USE_DEFAULT_SPACE ] && [ "$USE_DEFAULT_SPACE" = "true" ]
        then
            log "USE_DEFAULT_SPACE"
            sed -i -e "s/SERVER.POSTGRES_USE_DEFAULT_SPACE=.*/SERVER.POSTGRES_USE_DEFAULT_SPACE=$USE_DEFAULT_SPACE/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
        fi
        if [ -n $DATABASE_PAAS_ENV ] && [ "$DATABASE_PAAS_ENV" = "true" ]
        then
            log "DATABASE_PAAS_ENV"
            sed -i -e "s/SERVER.DB_IN_PAAS_ENVIRONMENT=.*/SERVER.DB_IN_PAAS_ENVIRONMENT=$DATABASE_PAAS_ENV/"  ${DM_DOCKER_HOME}/config/linux_config.properties
            if [ -z $USE_DEFAULT_SPACE ] || [ "$USE_DEFAULT_SPACE" = "false" ]
            then
                sed -i -e "s/SERVER.POSTGRES_USE_DEFAULT_SPACE=.*/SERVER.POSTGRES_USE_DEFAULT_SPACE=true/"  ${DM_DOCKER_HOME}/config/linux_config.properties
            fi
        fi				

        if [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
        then
            certDocbase
			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				encryptedPasswd=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config EncryptPasswordUtil ${DFC_SSL_TRUSTSTORE_PASSWORD})
			fi
            sed -i -e "s/SERVER.CONNECT_MODE=.*/SERVER.CONNECT_MODE=$DOCBASE_CONNECT_MODE/" ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
            sed -i -e "s/#SERVER.USE_CERTIFICATES=.*/SERVER.USE_CERTIFICATES=$DOCBASE_USE_CERTIFICATES/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
            sed -i -e "s/#SERVER.KEYSTORE_FILE_NAME=.*/SERVER.KEYSTORE_FILE_NAME=server.p12/"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
            sed -i -e "s/#SERVER.KEYSTORE_PASSWORD_FILE_NAME=.*/SERVER.KEYSTORE_PASSWORD_FILE_NAME=server.pwd/"  \
                                                ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
            sed -i -e "s/#SERVER.TRUST_STORE_FILE_NAME=.*/SERVER.TRUST_STORE_FILE_NAME=server-trust.p7b/" ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
            sed -i -e "s/#SERVER.CIPHER_LIST=.*/SERVER.CIPHER_LIST=ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256/" ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
            sed -i -e "s|#SERVER.DFC_SSL_TRUSTSTORE=.*|SERVER.DFC_SSL_TRUSTSTORE=$DOCUMENTUM/certificate/dfc.keystore|"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
			
			sed -i -e "s;#SERVER.DFC_SSL_TRUSTSTORE_PASSWORD=.*;SERVER.DFC_SSL_TRUSTSTORE_PASSWORD=${DFC_SSL_TRUSTSTORE_PASSWORD};"  ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
			
			sed -i -e "s/#SERVER.DFC_SSL_USE_EXISTING_TRUSTSTORE=.*/SERVER.DFC_SSL_USE_EXISTING_TRUSTSTORE=false/" ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
            echo "dfc.security.ssl.truststore=$DOCUMENTUM/certificate/dfc.keystore" >> $DOCUMENTUM/config/dfc.properties
			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				if [ -z "$encryptedPasswd" ]
				then
					log "[handle_start_HA_docbase] -->> Truststore password encryption failed. Using plain password"
					echo "dfc.security.ssl.truststore_password=${DFC_SSL_TRUSTSTORE_PASSWORD}" >> $DOCUMENTUM/config/dfc.properties
				else
					log "[handle_start_HA_docbase] -->> Truststore password encryption passed."
					echo "dfc.security.ssl.truststore_password=$encryptedPasswd" >> $DOCUMENTUM/config/dfc.properties
				fi
			else
				if [ `grep dfc.security.ssl.truststore_password $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
				then
			
					hostname=`hostname -f`
					echo "dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname" >> $DOCUMENTUM/config/dfc.properties
				else
			
					hostname=`hostname -f`
					sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname;" $DOCUMENTUM/config/dfc.properties
				fi
			fi	
        fi
		log "Installing Docbase..."

		$DM_HOME/install/dm_launch_cfs_server_config_program.sh -f ${DM_DOCKER_HOME}/config/cfs_linux_config.properties
		if [ $? != $SUCCESS ]
		then        
				log "ERROR : The installation has failed. Please check install logs at container's ${DM_HOME}/install/logs/install.log"
				exitProgram
		
		fi

		log "Docbase installation Completed...."	  
		
		if [ "${IS_VAULT_ENABLED}" = "true" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
		then
	
			hostname=`hostname -f`
			sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$docbasetrustStorePasswordPrefix/$hostname;" $DOCUMENTUM/config/dfc.properties
		fi
		log "set the Docbrokers in server.ini"		
		sed -i -e '/\[DOCBROKER_PROJECTION_TARGET/d' $serverini
        sed -i -e '/proximity=/d' $serverini
        sed -i -e '/proximity =/d' $serverini
        sed -i -e '/host=/d' $serverini
        sed -i -e '/host =/d' $serverini
        sed -i -e '/port=/d' $serverini
        sed -i -e '/port =/d' $serverini
		if [ -n "$CONCURRENT_SESSIONS" ]
        then
		   sed -i -e "s/concurrent_sessions = .*/concurrent_sessions = $CONCURRENT_SESSIONS/"  $serverini
        fi
		
		count=0		
		while [ $count -lt $DOCBROKERS_COUNT ]
		do
			client_docbroker_host=$DOCBROKER_SERVICE_NAME-$count.$DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE			
			
			log "client_docbroker_host $client_docbroker_host"
			echo "[DOCBROKER_PROJECTION_TARGET_$count]" >> $serverini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a proximity = 1"  $serverini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a port = $DOCBROKER_PORT"  $serverini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a host = $client_docbroker_host"  $serverini
			count=`expr $count + 1`
		done		
		
		if [ "$EXT_DBR_PROJECTION_ENABLE" = "true" ]
		then
		 newcount=0
		 while [ $newcount -lt $DOCBROKERS_COUNT ]
		 do
			client_docbroker_host=$DOCBROKER_SERVICE_NAME-$newcount.$DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE			
			
			log "client_docbroker_host $client_docbroker_host"
			echo "[DOCBROKER_PROJECTION_TARGET_$count]" >> $serverini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a proximity = 1"  $serverini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a port = $EXT_DBR_DOCBROKER_PORT"  $serverini
			sed -i -e "/DOCBROKER_PROJECTION_TARGET_$count/ a host = $client_docbroker_host"  $serverini
			count=`expr $count + 1`
			newcount=`expr $newcount + 1`
		 done		  
		fi
		chown -R $INSTALL_OWNER:$INSTALL_OWNER $serverini
		
		log "Stop Docbase"
		kill -9 `ps -ef | grep ${DOCBASE_NAME} |grep -v grep | awk '{print $2}'`
	
		check_cs_shutdown_status "server_${SERVER_CONFIG_NAME}.ini"

		#--- backing dba files to kube as we do not want to mount log folder in pvc ---
		copy_dba_files_to_kube_backup
    fi	
	update_mail_notification_flag $serverini	
	set_event_hub_dfc_properties

    # Check if AEK details have been changed, if yes upgrade it.
	# Get old AEK name from server.ini
	oldAEKName=$( sed -n -e '/crypto_keyname/ s/.*\= *//p' ${serverini})
	# Get the key location from server.ini
	oldAEKLocation=$( sed -n -e '/crypto_keystore/ s/.*\= *//p' ${serverini})
	
	if  [ "${oldAEKName}" != "${AEK_NAME}" ]
	then
		log "[handle_start_HA_docbase] -->> AEK details changed upgrading AEK key"

		if [ ! -f ${DOCUMENTUM}/data/aek_upgrade_files/${AEK_NAME} ]
		then
			aekKeyCreatedHA="true"
			# If the current AEK key is local. Run dm_crypto_boot.
			if [ "${oldAEKLocation}" = "Local" ]
			then
				# In case of vault pull old aek password from vault.
				if [ "${IS_VAULT_ENABLED}" = "true" ]
				then
					oldaekPwd=$(curl $DSIS_URL/secret/$OLD_AEK_PASSPHRASE)
					source $DM_HOME/bin/dm_set_server_env.sh; dm_crypto_boot -passphrase $oldaekPwd -all
				else
					source $DM_HOME/bin/dm_set_server_env.sh; dm_crypto_boot -passphrase $OLD_AEK_PASSPHRASE -all
				fi
			fi		
		
			log "[handle_start_HA_docbase] -->> Start Docbase before AEK upgrade"
			source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/dba/dm_start_${docbase}_dm_${docbase}
			#CS perf: Modifying this to status check
			handle_CS_statuscheck
			log "[handle_start_HA_docbase] -->> Docbase Started before AEK upgrade"
		fi
		
		handle_aek_upgrade	

		if [ "$aekKeyCreatedHA" = "true" ]
		then
			log "[handle_start_HA_docbase] -->> Stop Docbase after AEK upgrade"
			kill -9 `ps -ef | grep ${DOCBASE_NAME} |grep -v grep | awk '{print $2}'`
			check_cs_shutdown_status "server_${SERVER_CONFIG_NAME}.ini"
			aekKeyCreatedHA="false"
		fi			
	fi
	log "[handle_start_HA_docbase] -->> Start Docbase"

	if [ "${AEK_LOCATION}" = "Local" ]
	then
		source $DM_HOME/bin/dm_set_server_env.sh; dm_crypto_boot -passphrase $AEK_PASSPHRASE -all
	fi

	source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/dba/dm_start_${docbase}_dm_${docbase}
	#CS perf: Modifying this to status check
	handle_CS_statuscheck
	log "[handle_start_HA_docbase] -->> Docbase Started"		
}

add_hosts_aliases()
{
    log "---------------------------------------------------------------------------------------"
    log "add_hosts_aliases"
   
    containername=$CONTAINER_NAME
	containerlength=${#containername}
	index=`expr $containerlength + 2`
	currenthostname=`hostname`
	
	log "MAX_REPLICA: $MAX_REPLICA"
	
	count=0

	while [ $count -lt $MAX_REPLICA ]
	do
	  temphostname=`echo $currenthostname | sed s/./$count/$index`
	  if [ "$temphostname"  = "$currenthostname" ]
	  then
		 log "Current Host"
		 count=`expr $count + 1`
		 continue
	  fi	  
	  
	  tempfqdn=`echo $PRIMARY_HOSTNAME | sed s/./$count/$index`
	  echo "$temphostname $tempfqdn" | sudo tee -a /etc/host.aliases 
	  
	  count=`expr $count + 1`
	done
	sudo chmod 777 /etc/bashrc
	sudo echo "export HOSTALIASES=/etc/host.aliases" >> /etc/bashrc
	source /etc/bashrc	
}


prepare_start_method_server()
{
	log "---------------------------------------------------------------------------------------"
    log "prepare_start_method_server"
	fixACSLog4jProperties  
	importSMTPSSLCert
	importS3sslCert
	importAzureStoresslCert
	importGcpStoresslCert		
	# Handle multipart upload settings
	handle_s3multipart
	add_hosts_aliases
	sed -i -e "s/tcp:.*9084/tcp:\/\/${HOSTNAME}:9084/" $DOCUMENTUM/$TOMCAT/conf/server.xml
	sed -i -e "s/jms.url=.*/jms.url=tcp\\\:\/\/${HOSTNAME}\\\:9084/" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	
	if [ ! -f ${DOCUMENTUM}/${TOMCAT}/lib/logback.xml ]
    then
	   cat > ${DOCUMENTUM}/${TOMCAT}/lib/logback.xml<<'EOF'
		<configuration debug="true">
		<appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
		<encoder>
		<pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
		</encoder>
		</appender>

		<root level="warn">
		<appender-ref ref="STDOUT" />
		</root>
		</configuration>
EOF
    fi

	if [ "$URL_VALIDATION_FILTER" = "true" ]
	then
		log "Enabling ACS URL validation filter configuration"
		mv -f ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/web.xml ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/web.xml.bak
		mv -f ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/web.xml_urlvalidation ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/web.xml
	fi
	
	if [ "$isCORSAllowed" = "true" ]			
	then
		sed -i '/<param-name>CORSAllowed<\/param-name>/{n;s/<param-value>false<\/param-value>/<param-value>true<\/param-value>/}' ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/web.xml
				 
	else 
		sed -i '/<param-name>CORSAllowed<\/param-name>/{n;s/<param-value>true<\/param-value>/<param-value>false<\/param-value>/}' ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/web.xml
	fi

   if [ "$S3_STORE_ENABLE" = "true" ]
   then
      s3updatedone=${DOCUMENTUM}/kube/s3_acs_update_success
	  if [ -f $s3updatedone ]
	  then	  
	    log "Removing s3 acs_supported_protocol from dm_acs_config object"
		isACSConfigS3Removed=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config JMSHAConfigUtil $DOCBASE_NAME $INSTALL_OWNER "" dm_acs_config_remove_s3 $CONTAINER_NAME)
		if [ "$isACSConfigS3Removed" = "REMOVED_S3_FROM_ACS_CONFIG" ]
        then		
		  rm -f ${DOCUMENTUM}/kube/s3_acs_update_success
		fi
	  fi
   fi
   
   ##update acs S3.Properties file.
   if [ $S3_STORE_ENABLE ]
   then
	 s3PropertiesFile=${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties    
	 sed -i -e "s/enable-md5=.*/enable-md5=${S3_MD5_ENABLE}/" $s3PropertiesFile
	 sed -i -e "s/enable-v4signing=.*/enable-v4signing=${S3_V4SIGNING_ENABLE}/" $s3PropertiesFile	
   fi
   ##update acs Rest.Properties file with proxy host & port.
   if [ $REST_STORE_ENABLE ]
   then
	 restPropertiesFile=$DM_JMS_HOME/webapps/ACS/WEB-INF/classes/rest.properties
	 if [ "$REST_STORE_PROXY_HOST" != "" ]
	 then
	   sed -i -e "s/.*PROXY_HOST.*/PROXY_HOST=${REST_STORE_PROXY_HOST}/" $restPropertiesFile
	 else 
	   sed -i -e "s/.*PROXY_HOST.*/#PROXY_HOST=${REST_STORE_PROXY_HOST}/" $restPropertiesFile
	 fi
	 if [ "$REST_STORE_PROXY_PORT" != "" ]
	 then
	   sed -i -e "s/.*PROXY_PORT.*/PROXY_PORT=${REST_STORE_PROXY_PORT}/" $restPropertiesFile
	 else
	   sed -i -e "s/.*PROXY_PORT.*/#PROXY_PORT=${REST_STORE_PROXY_PORT}/" $restPropertiesFile
	 fi
	 log "Updating the Rest properties file with proxy_host"
   fi
   ##Done updating the Rest properties file## 

   ## configuring the newrelic java agent for jms/tomcat.
   if [ $NEWRELIC_ENABLE ]
   then
	 log "configuring the newrelic java agent for JMS/tomcat"
	 handle_newrelic_java_agent_config_forJMS
	 log "Successfully completed configuring the newrelic java agent for JMS/tomcat"
   elif [ "$JMS_MEM_SETTING" != "" ]
   then
	 `sed -i -e "s/CATALINA_OPTS=.*/CATALINA_OPTS=\"$JMS_MEM_SETTING\"/" ${DOCUMENTUM}/$TOMCAT/bin/startMethodServer.sh`
   fi
   ##Done, configuring  newrelic java agent for jms/tomcat.## 
}

restart_method_server()
{
	if [ -f ${DOCUMENTUM}/$TOMCAT/bin/pid.txt ]
	then
		${DOCUMENTUM}/$TOMCAT/bin/dctmServerStatus.sh 9080
		if [ $? = 0 ]
		then
			#Tomcat running
			kill -9 `ps -ef | grep $DM_JMS_HOME | grep -v grep | awk '{print($2)}' | tr '\n' ' '`
			log "Method Server stopped"
		fi
		rm -rf $DM_JMS_HOME/bin/pid.txt
	fi
	rm -rf $NEW_TOMCAT_LOGS_DIR/*
	source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/$TOMCAT/bin/startMethodServer.sh &
	#CS Perf: Modifying this to status check
    handle_JMS_statuscheck
	log "Method Server started"
}

handle_start_method_server()
{
    log "---------------------------------------------------------------------------------------"
    log "handle_start_method_server"       
	if [ "$alreadyInstalled" = "FALSE" ]
	then		
		sed -i -e '/dfc.docbroker.host/d' ${DOCUMENTUM}/config/dfc.properties
		sed -i -e '/dfc.docbroker.port/d' ${DOCUMENTUM}/config/dfc.properties
		echo "dfc.security.keystore.file = $DOCUMENTUM/config/dfc.keystore" >> $DOCUMENTUM/config/dfc.properties
		
		count=0		
		while [ $count -lt $DOCBROKERS_COUNT ]
		do
		  client_docbroker_host=$DOCBROKER_SERVICE_NAME-$count.$DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE			  
		  echo "dfc.docbroker.host[$count]=$client_docbroker_host" >> $DOCUMENTUM/config/dfc.properties
		  echo "dfc.docbroker.port[$count]=$DOCBROKER_PORT" >> $DOCUMENTUM/config/dfc.properties
		  count=`expr $count + 1`
		done
		
		log "enable JMS HA feature"
		isDocbaseConfigObjUpdated=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config JMSHAConfigUtil $DOCBASE_NAME $INSTALL_OWNER "" dm_docbase_config)
		
		if [ "$isDocbaseConfigObjUpdated" = "JMS_HA_Feature_Enabled" ]	
		then
			log "enabled JMS HA feature successfully"
			log "JMSHAConfigUtil, update 'app_server_uri' in server amd  'base_uri' in JMS config objects"
			hostnameshort=`hostname -s`
			hostnamefqdn=`hostname -f`
			isServerJMSConfigObjUpdated=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config JMSHAConfigUtil $DOCBASE_NAME $INSTALL_OWNER "" dm_jms_config $hostnameshort $hostnamefqdn)		  
		  
			if [ "$isServerJMSConfigObjUpdated" = "updatedAttrURIinCSandJMSConfigObjs" ]
			then
				log "JMSHAConfigUtil, updated 'app_server_uri' in server and 'base_uri' in JMS config objects successfully"		  
				log "configure the JMS config object ids in server config objects"
				isServerConfigObjUpdated=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config JMSHAConfigUtil $DOCBASE_NAME $INSTALL_OWNER "" dm_server_config)						  
			    
				if [ "$isServerConfigObjUpdated" = "AddedJMSConfigIDsToServerConfig" ]			
				then
					log "Successfully configured the JMS config object ids in all server config objects of docbase ${DOCBASE_NAME}"
					log "JMS HA configuration is completed."
				else 
					log "JMSHAConfigUtil failed to update serverconfig objects of docbase ${DOCBASE_NAME} ";				 
				fi					 
			else 
				log "JMSHAConfigUtil, failed to update 'app_server_uri' in server and 'base_uri' in JMS config objects";			  
			fi	  
		else
			log "JMSHAConfigUtil failed to update docbase ${DOCBASE_NAME} dm_docbase_config object";
		fi

		if [ "$isHA" != "TRUE" ]
		then
			log "stop content server"
			kill -9 `ps -ef | grep ${DOCBASE_NAME} |grep -v grep | awk '{print $2}'`
			log "Start content server"
			check_cs_shutdown_status "server.ini"
			source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}
			#CS Perf: Modifying this to status check
			handle_CS_statuscheck	 
		fi	  
	fi  

	restart_method_server
   
   log "Taking backup of the methodserver files"
   cp -r ${DOCUMENTUM}/$TOMCAT/webapps/DmMethods/WEB-INF/web.xml  ${DOCUMENTUM}/mdserver_conf/web.xml
   if [[ $hostname == $CONTAINER_NAME-0* ]];
   then
		cp -r ${DOCUMENTUM}/$TOMCAT/webapps/DmMethods/WEB-INF/web.xml ${DOCUMENTUM}/share/mdserver_conf/web.xml
   fi
		
   if [ "$alreadyInstalled" != "TRUE" ]
   then			
        cp -r ${DOCUMENTUM}/config/dfc.properties  ${DOCUMENTUM}/mdserver_conf/dfc.properties
		cp -r ${DOCUMENTUM}/mdserver_conf/dfc.properties ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
		cp -r ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties ${DOCUMENTUM}/mdserver_conf/acs.properties
        cp -r ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties ${DOCUMENTUM}/mdserver_conf/s3.properties
		if [ "${IS_VAULT_ENABLED}" = "true" ]
		then
			acsAdminPasswordPrefix=$(echo $APP_SERVER_PASSWORD | cut -d'/' -f1)
			sed -i -e "s;user.acsAdmin=.*;user.acsAdmin=$acsAdminPasswordPrefix/$hostname,Administrators;" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/jmx.properties
		fi
		cp -r ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/jmx.properties ${DOCUMENTUM}/mdserver_conf/jmx.properties
   fi
}

handle_start_thumbnail_server()
{
   log "---------------------------------------------------------------------------------------"
   log "handle_start_thumbnail_server"
   if [ "$CONFIGURE_THUMBNAIL_SERVER" = "true" ]
   then
        chown $INSTALL_OWNER:$INSTALL_OWNER ${DM_DOCKER_HOME}/thumbserverbuild/configure-thumbnail-server.sh
        chmod +x ${DM_DOCKER_HOME}/thumbserverbuild/configure-thumbnail-server.sh
		
		log "configuring thumbnail server..."
       		
		if [ "${IS_VAULT_ENABLED}" = "true" ]
        then
            if [ "${AEK_LOCATION}" = "Remote" ]
            then
                ${DM_DOCKER_HOME}/thumbserverbuild/configure-thumbnail-server.sh $DOCBASE_NAME $INSTALL_OWNER $INSTALL_OWNER_PASSWORD $KMS_URL $KMS_API_KEY $hostname $DSIS_URL
            else
                ${DM_DOCKER_HOME}/thumbserverbuild/configure-thumbnail-server.sh $DOCBASE_NAME $INSTALL_OWNER $INSTALL_OWNER_PASSWORD $AEK_PASSPHRASE $hostname $DSIS_URL
            fi
        else
            if [ "${AEK_LOCATION}" = "Remote" ]
            then
                ${DM_DOCKER_HOME}/thumbserverbuild/configure-thumbnail-server.sh $DOCBASE_NAME $INSTALL_OWNER $INSTALL_OWNER_PASSWORD $KMS_URL $KMS_API_KEY $hostname
            else
                ${DM_DOCKER_HOME}/thumbserverbuild/configure-thumbnail-server.sh $DOCBASE_NAME $INSTALL_OWNER $INSTALL_OWNER_PASSWORD $AEK_PASSPHRASE $hostname
            fi
    	fi
				
		if [ $? != $SUCCESS ]
		then
			log "ERROR: The ${DM_DOCKER_HOME}/thumbserverbuild/configure-thumbnail-server.sh has failed"
		else
		    log "Thumbnail server configuration succeeded"
		fi
   fi
}

handle_otds_config()
{
   log "---------------------------------------------------------------------------------------"
   log "handle_otds_config"
   
   if [ "$CONFIGURE_OTDS" = "true" ]
   then
      if [ "$CERT_AUTO_REFRESH" = "true" ]
	  then	 
		 grep "auto_cert_refresh" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		 
		 if [ $? -eq $SUCCESS ];
		 then
		   sed -i -e "s:auto_cert_refresh=.*:auto_cert_refresh=true:" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		   sed -i -e "s;cert_jwks_url=.*;cert_jwks_url=$CERT_JWKS_URL;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties		 
		 else
		   echo -e "" >> ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		   echo -e "auto_cert_refresh=true" >> ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		   echo -e "cert_jwks_url=$CERT_JWKS_URL" >> ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties		 
		 fi  
		  
	  fi
	  
	  if [[ ! -z $OTDS_USER_RENAME_ENABLED ]]
	  then
	    sed -i -e "s:user_rename_enabled=.*:user_rename_enabled=$OTDS_USER_RENAME_ENABLED:" ${DOCUMENTUM}/$TOMCAT/webapps/dmotdsrest/WEB-INF/classes/usermappings.properties
      fi
	  if [[ ! -z $OTDS_USER_RENAME_UNLOCK_LOCKEDOBJ ]]
	  then
	    sed -i -e "s:user_rename_unlock_locked_obj=.*:user_rename_unlock_locked_obj=$OTDS_USER_RENAME_UNLOCK_LOCKEDOBJ:" ${DOCUMENTUM}/$TOMCAT/webapps/dmotdsrest/WEB-INF/classes/usermappings.properties
	  fi
	  if [[ ! -z $OTDS_GROUP_RENAME_ENABLED ]]
	  then
        sed -i -e "s:group_rename_enabled=.*:group_rename_enabled=$OTDS_GROUP_RENAME_ENABLED:" ${DOCUMENTUM}/$TOMCAT/webapps/dmotdsrest/WEB-INF/classes/groupmappings.properties
	  fi
	  
	  sed -i -e "s;is_hybrid=.*;is_hybrid=$IS_HYBRID;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
	  
      if [ "$alreadyInstalled" != "TRUE" ]
	  then
	      authurl="http://$OTDS_API_SVC/rest/authentication/credentials"
		  certurl="http://$OTDS_API_SVC/rest/systemconfig/certificate_content"
		  if [ "$OTDS_SSL" = "true" ]
		  then
		    authurl="https://$OTDS_API_SVC/rest/authentication/credentials"
		    certurl="https://$OTDS_API_SVC/rest/systemconfig/certificate_content"
		  fi		  
		  curl --insecure $certurl > /tmp/otdscert
		  sed -i -e '/BEGIN CERTIFICATE/d' /tmp/otdscert
		  sed -i -e '/END CERTIFICATE/d' /tmp/otdscert
		  cert=`sed ':a;N;$!ba;s/\n//g' /tmp/otdscert`
		  log "certificate is: $cert"
		  sed -i -e "s:certificate=.*:certificate=$cert:" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  sed -i -e "s;otds_rest_credential_url=.*;otds_rest_credential_url=$authurl;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties		  		  
		  		  
		  log "client capability: $OTDS_USERS_CLIENT_CAPABILITY, privilege: $OTDS_USERS_PRIVILEGES, xprivilege: $OTDS_USERS_XPRIVILEGES"
		  
		  sed -i -e "s:client_capability=.*:client_capability=$OTDS_USERS_CLIENT_CAPABILITY:" ${DOCUMENTUM}/$TOMCAT/webapps/dmotdsrest/WEB-INF/classes/usermappings.properties
		  sed -i -e "s:user_privileges=.*:user_privileges=$OTDS_USERS_PRIVILEGES:" ${DOCUMENTUM}/$TOMCAT/webapps/dmotdsrest/WEB-INF/classes/usermappings.properties
		  sed -i -e "s:user_xprivileges=.*:user_xprivileges=$OTDS_USERS_XPRIVILEGES:" ${DOCUMENTUM}/$TOMCAT/webapps/dmotdsrest/WEB-INF/classes/usermappings.properties
		  
		  sed -i -e "s:user_rename_enabled=.*:user_rename_enabled=$OTDS_USER_RENAME_ENABLED:" ${DOCUMENTUM}/$TOMCAT/webapps/dmotdsrest/WEB-INF/classes/usermappings.properties
		  sed -i -e "s:user_rename_unlock_locked_obj=.*:user_rename_unlock_locked_obj=$OTDS_USER_RENAME_UNLOCK_LOCKEDOBJ:" ${DOCUMENTUM}/$TOMCAT/webapps/dmotdsrest/WEB-INF/classes/usermappings.properties
		  sed -i -e "s:group_rename_enabled=.*:group_rename_enabled=$OTDS_GROUP_RENAME_ENABLED:" ${DOCUMENTUM}/$TOMCAT/webapps/dmotdsrest/WEB-INF/classes/groupmappings.properties
		  
		  otds_iapi='/tmp/otdsiapi'		  
		  echo "retrieve,c,dm_server_config where object_name='$SERVER_CONFIG_NAME'" > $otds_iapi
		  echo "append,c,l,app_server_name" >> $otds_iapi
		  echo "OTDSAuthentication" >> $otds_iapi
		  echo "append,c,l,app_server_uri" >> $otds_iapi
		  echo "http://`hostname -f`:9080/OTDSAuthentication/servlet/authenticate" >> $otds_iapi
		  echo "save,c,l" >> $otds_iapi
		  
		  echo "retrieve,c,dm_jms_config where object_name like '%`hostname -s`%'" >> $otds_iapi
		  echo "append,c,l,servlet_name" >> $otds_iapi
		  echo "OTDSAuthentication" >> $otds_iapi
		  echo "append,c,l,base_uri" >> $otds_iapi
		  echo "http://`hostname -f`:9080/OTDSAuthentication/servlet/authenticate" >> $otds_iapi
		  echo "append,c,l,supported_protocol" >> $otds_iapi
		  echo "http" >> $otds_iapi
		  echo "save,c,l" >> $otds_iapi
		  
		  source $DM_HOME/bin/dm_set_server_env.sh; iapi $DOCBASE_NAME -U$INSTALL_OWNER -P"" -R$otds_iapi > /tmp/otdsiapi.out
		  log "otds configuration completed"
      else
	      authurl="http://$OTDS_API_SVC/rest/authentication/credentials"
		  if [ "$OTDS_SSL" = "true" ]
		  then
		    authurl="https://$OTDS_API_SVC/rest/authentication/credentials"		    
		  fi
		  sed -i -e "s;otds_rest_credential_url=.*;otds_rest_credential_url=$authurl;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties		  
		  
		  if [ "$UPDATE_OTDSCERT_RESTART" = "true" ]
		  then
            certurl="http://$OTDS_API_SVC/rest/systemconfig/certificate_content"
			if [ "$OTDS_SSL" = "true" ]
			then
			  certurl="https://$OTDS_API_SVC/rest/systemconfig/certificate_content"
			fi
			curl --insecure $certurl > /tmp/otdscert
			grep "BEGIN CERTIFICATE" /tmp/otdscert
			
			if [ $? -eq $SUCCESS ];
			then			
			  sed -i -e '/BEGIN CERTIFICATE/d' /tmp/otdscert
			  sed -i -e '/END CERTIFICATE/d' /tmp/otdscert
			  cert=`sed ':a;N;$!ba;s/\n//g' /tmp/otdscert`
			  log "certificate on restart is: $cert"
			  sed -i -e "s:certificate=.*:certificate=$cert:" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties			  
			fi
		  fi          		  
	  fi
	  
	  grep "synced_user_login_name" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
	  
	  if [ $? -eq $SUCCESS ];
	  then
	    sed -i -e "s;synced_user_login_name=.*;synced_user_login_name=$SYNCED_USER_LOGIN_NAME;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
	  else
	    echo -e "" >> ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
	    echo -e "synced_user_login_name=$SYNCED_USER_LOGIN_NAME" >> ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
	  fi
	    
	    
	  
	  if [ "$PASSAUTH_USE_OAUTH2_TOKEN" = "true" ]
	  then
		grep "passauth_use_oauth2_token" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		if [ $? -eq $SUCCESS ];
		then
		  sed -i -e "s;passauth_use_oauth2_token=.*;passauth_use_oauth2_token=$PASSAUTH_USE_OAUTH2_TOKEN;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  sed -i -e "s;client_id=.*;client_id=$CLIENT_ID;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  sed -i -e "s;client_secret=.*;client_secret=$CLIENT_SECRET;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  sed -i -e "s;otds_rest_oauth2_url=.*;otds_rest_oauth2_url=$OTDS_REST_OAUTH2_URL;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties 
		  sed -i -e "s;is_vault_enabled=.*;is_vault_enabled=$IS_VAULT_ENABLED;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties 
		  sed -i -e "s;dsis_url=.*;dsis_url=$DSIS_URL;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		else
		  echo -e "" >> ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  echo -e "passauth_use_oauth2_token=$PASSAUTH_USE_OAUTH2_TOKEN" >> ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  echo -e "client_id=$CLIENT_ID" >> ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  echo -e "client_secret=$CLIENT_SECRET" >> ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  echo -e "otds_rest_oauth2_url=$OTDS_REST_OAUTH2_URL" >> ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  echo -e "is_vault_enabled=$IS_VAULT_ENABLED;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties 
		  echo -e "dsis_url=$DSIS_URL;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties		  
		fi
	  elif [ "$PASSAUTH_USE_OAUTH2_TOKEN" = "false" ]
      then
        grep "passauth_use_oauth2_token" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
        if [ $? -eq $SUCCESS ];
        then
          sed -i -e "s;passauth_use_oauth2_token=.*;passauth_use_oauth2_token=$PASSAUTH_USE_OAUTH2_TOKEN;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
          sed -i -e "s;client_id=.*;client_id=$CLIENT_ID;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  sed -i -e "s;client_secret=.*;client_secret=$CLIENT_SECRET;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
		  sed -i -e "s;otds_rest_oauth2_url=.*;otds_rest_oauth2_url=$OTDS_REST_OAUTH2_URL;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties 
		  sed -i -e "s;is_vault_enabled=.*;is_vault_enabled=$IS_VAULT_ENABLED;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties 
		  sed -i -e "s;dsis_url=.*;dsis_url=$DSIS_URL;" ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties
        fi
	  fi
	  cp -r ${DOCUMENTUM}/$TOMCAT/webapps/OTDSAuthentication/WEB-INF/classes/otdsauth.properties  ${DOCUMENTUM}/mdserver_conf/otdsauth.properties
   fi
}

handle_dar_install_config()
{
   log "---------------------------------------------------------------------------------------"
   log "handle_dar_install_config"
   if [ "$CONFIGURE_DAR_INSTALL" = "true" ]
   then
      if [ "$alreadyInstalled" != "TRUE" ]
	  then
		dar_install_iapi='/tmp/darinstalliapi'		  
		echo "retrieve,c,dm_server_config where object_name='$SERVER_CONFIG_NAME'" > $dar_install_iapi
		echo "append,c,l,app_server_name" >> $dar_install_iapi
		echo "install_dar" >> $dar_install_iapi
		echo "append,c,l,app_server_uri" >> $dar_install_iapi
		echo "http://`hostname -f`:9080/DmMethods/servlet/InstallDar" >> $dar_install_iapi
		echo "save,c,l" >> $dar_install_iapi
		source $DM_HOME/bin/dm_set_server_env.sh; iapi $DOCBASE_NAME -U$INSTALL_OWNER -P"" -R$dar_install_iapi > /tmp/darinstalliapi.out
		log "dar install configuration completed"
	  fi
   fi
}

ready()
{
   log "---------------------------------------------------------------------------------------"
   log "prepare readiness"
   
   if [ "$onlyDocbroker" = "true" ]
   then
     if [ "$alreadyInstalled" != "TRUE" ]
	 then
       touch -f ${DOCUMENTUM}/kube/Docbroker-installed
	   log "Docbroker-installed file created"
	 fi
   else
     if [ "$EXT_DBR_PROJECTION_ENABLE" = "true" ]
	 then
	   externalprojectedfile="${DOCUMENTUM}/kube/cs-external-projected"
	   if [ -f "$externalprojectedfile" ]
	   then
			log "cs-external-projected file already created"
		else
			touch -f ${DOCUMENTUM}/kube/cs-external-projected
		fi
	 fi
     if [ "$alreadyInstalled" != "TRUE" ]
	 then
		 touch -f ${DOCUMENTUM}/kube/${DOCBASE_NAME}-installed		 
		 log "$DOCBASE_NAME-installed file created"
		 if [ "$isHA" != "TRUE" ]
		 then
		   touch -f ${DOCUMENTUM}/data/primary-installed
		   log "primary-installed file created"
		 fi
	 fi	 
   fi
}
#Migrate config objects  
migarteConfigObjects()
{
    log "Migrating ACS config object base URL"
	acs_protocol=http;
	jms_protocol=http;
	jmsHost=`echo $JMS_HOST`
	acsPort=""
	jmsPort=9080
    #If no JMS_HOST value provided then use hostname with FQDN
    if [ -z $jmsHost ];
    then
       jmsHost=`hostname -f`
       acsPort=:$jmsPort
    fi;
   
    log "Updating ACS config object base URL to jmsHost $jmsHost"
	  acs_protocol=`echo $INGRESS_PROTOCOL`
	  jms_protocol=`echo $JMS_PROTOCOL`
	  if [ -z $acs_protocol ];
	  then
			 acs_protocol=`echo $JMS_PROTOCOL`
	  fi
	  if [ -z $acs_protocol ];
	  then
			 acs_protocol=http;
	  fi
	  if [ -z $jms_protocol ];
	  then
			 jms_protocol=http;
	  fi

	acs_url=$acs_protocol://$jmsHost$acsPort/ACS/servlet/ACS
	  
	  fullhostname=`hostname -f`
	  jms_url=$jms_protocol://$fullhostname:$jmsPort
	  rm -rf /tmp/acs.sql
	  rm -rf /tmp/config_objects.out
	  echo "update dm_acs_config_r set acs_base_url = '${acs_url}' where acs_base_url like '%${OLD_MIG_HOSTNAME}%';" >> /tmp/acs.sql
	  echo "update dm_sysobject_s set object_name = '${fullhostname}ACS1' where r_object_type ='dm_acs_config' and  object_name like '%ACS1%';" >> /tmp/acs.sql
	  echo "update dm_sysprocess_config_r set base_uri='${jms_url}/DmMail/servlet/DoMail' from (select r_object_id from dm_sysobject_s where object_name like '%${OLD_MIG_HOSTNAME}%') as jms where dm_sysprocess_config_r.r_object_id =jms.r_object_id and dm_sysprocess_config_r.servlet_name='do_mail';" >> /tmp/acs.sql
	  echo "update dm_sysprocess_config_r set base_uri='${jms_url}/DmMethods/servlet/DoMethod' from (select r_object_id from dm_sysobject_s where object_name like '%${OLD_MIG_HOSTNAME}%') as jms where dm_sysprocess_config_r.r_object_id =jms.r_object_id and dm_sysprocess_config_r.servlet_name='do_method';" >> /tmp/acs.sql
	  echo "update dm_sysprocess_config_r set base_uri='${jms_url}/SAMLAuthentication/servlet/ValidateSAMLResponse' from (select r_object_id from dm_sysobject_s where object_name like '%${OLD_MIG_HOSTNAME}%') as jms where dm_sysprocess_config_r.r_object_id =jms.r_object_id and dm_sysprocess_config_r.servlet_name='SAMLAuthentication';" >> /tmp/acs.sql
	  echo "update dm_sysprocess_config_r set base_uri='${jms_url}/XhiveConnector/servlet/XhiveConnectorServlet' from (select r_object_id from dm_sysobject_s where object_name like '%${OLD_MIG_HOSTNAME}%') as jms where dm_sysprocess_config_r.r_object_id =jms.r_object_id and dm_sysprocess_config_r.servlet_name='XhiveConnector';" >> /tmp/acs.sql
	  echo "update dm_sysobject_s set object_name='JMS ${fullhostname}${jmsPort} for ${DOCBASE_NAME}.${DOCBASE_NAME}' where object_name like '%${OLD_MIG_HOSTNAME}%';" >> /tmp/acs.sql
	  chmod 775 /tmp/acs.sql
	  DOCBASE_OWNER_EX=`cat  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini |grep database_owner| awk '{print $3}'`
	  #####psql "host=$DATABASE_HOST  dbname=dm_${DOCBASE_NAME}_docbase user=$DOCBASE_OWNER_EX password=$DOCBASE_PASSWORD" -a -f /tmp/acs.sql >> /tmp/config_objects.out
	  if [ "$DB_TYPE" == "oracle" ]
	  then
			sqlplus ${DOCBASE_NAME}/$DOCBASE_PASSWORD@${DATABASE_HOST}/${DATABASE_SERVICE_NAME} @/tmp/acs.sql >> /tmp/config_objects.out
	  else
			PGPASSWORD=$DOCBASE_PASSWORD psql -h ${DATABASE_HOST} -d dm_${DOCBASE_NAME}_docbase -U ${DOCBASE_OWNER_EX} -a -f /tmp/acs.sql >> /tmp/config_objects.out
			
	  fi
	  
	  if [ $? -eq $SUCCESS ];
	  then
		 log "JMS and ACS config object updated successfully: $acs_url"
	  else
		 log "JMS and ACS config object update failed for docbase : $DOCBASE_NAME ";
		 log "log file is /tmp/config_objects.out"
		 exit $FAILURE     
	  fi;
   
}

migrateSysObjects()
{
	if [ "$MIGRATECS" = "true" ]
	  then
		log "Upgrading dm_sysobjects objects for migration"
		rm -rf /tmp/migratesys.sql
		rm -rf /tmp/migrate_sys_objects.out
		echo "delete from dm_location_s where r_object_id in ( select r_object_id from dm_sysobject_s where object_name ='change_password' );" >> /tmp/migratesys.sql
		echo "delete from dm_sysobject_s where object_name ='change_password';" >> /tmp/migratesys.sql
		echo "delete from dm_outputdevice_s where r_object_id in ( select r_object_id from dm_sysobject_s where object_name='%Printer on%' ) ;" >> /tmp/migratesys.sql
		echo "delete from dm_sysobject_s where object_name='%Printer on%' ;" >> /tmp/migratesys.sql
		echo "delete from dm_method_s where r_object_id in ( select r_object_id from dm_sysobject_s where object_name='print_nt' ) ;" >> /tmp/migratesys.sql
		echo "delete from dm_sysobject_s where object_name='print_nt' ;" >> /tmp/migratesys.sql
		echo "delete from dm_method_s where r_object_id in ( select r_object_id from dm_sysobject_s where object_name='replicate_setup_methods' ) ;" >> /tmp/migratesys.sql
		echo "delete from dm_sysobject_s where object_name='replicate_setup_methods' ;" >> /tmp/migratesys.sql
		echo "UPDATE dm_method_s SET method_verb = REPLACE(method_verb,  '\', '/');" >> /tmp/migratesys.sql
		
		echo "update dm_type_s set views_valid=0;" >> /tmp/migratesys.sql
		echo "CREATE SEQUENCE ${DOCBASE_NAME}.dm_audittrail_s_r_object_sequence_seq INCREMENT 1 START 423 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1;" >> /tmp/migratesys.sql
		echo "ALTER SEQUENCE ${DOCBASE_NAME}.dm_audittrail_s_r_object_sequence_seq OWNER TO ${DOCBASE_NAME};" >> /tmp/migratesys.sql

		
		
		chmod 775 /tmp/migratesys.sql
		DOCBASE_OWNER_EX=`cat  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini |grep database_owner| awk '{print $3}'`
		#####psql "host=$DATABASE_HOST  dbname=dm_${DOCBASE_NAME}_docbase user=$DOCBASE_OWNER_EX password=$DOCBASE_PASSWORD" -a -f /tmp/migratesys.sql >> /tmp/migrate_sys_objects.out
		if [ "$DB_TYPE" == "oracle" ]
		then
			sqlplus ${DOCBASE_NAME}/$DOCBASE_PASSWORD@${DATABASE_HOST}/${DATABASE_SERVICE_NAME} @/tmp/migratesys.sql >> /tmp/migrate_sys_objects.out
		else
			PGPASSWORD=$DOCBASE_PASSWORD psql -h ${DATABASE_HOST} -d dm_${DOCBASE_NAME}_docbase -U ${DOCBASE_OWNER_EX} -a -f /tmp/migratesys.sql >> /tmp/migrate_sys_objects.out
		
		fi
		
		if [ $? -eq $SUCCESS ];
		then
			log "Method  objects migrated successfully"
		else
			log "Method objects migrated failed for docbase  : $DOCBASE_NAME ";
			log "log file is /tmp/migrate_sys_objects.out"
			exit $FAILURE
		fi
	fi
}

#Migrate Location objects   
migrateLocationObjects()
{
	if [ "$MIGRATECS" = "true" ]
	  then
		log "Upgrading location objects for migration"
		rm -rf /tmp/migrateloc.sql
		rm -rf /tmp/migrate_loc_objects.out
		echo "update dm_location_s set file_system_path = 'data/events' from (select r_object_id from dm_sysobject_s where object_name ='events') as location where dm_location_s.r_object_id =location.r_object_id;" >> /tmp/migrateloc.sql
		echo "update dm_location_s set file_system_path = 'data/common' from (select r_object_id from dm_sysobject_s where object_name ='common') as location where dm_location_s.r_object_id =location.r_object_id;" >> /tmp/migrateloc.sql

		echo "UPDATE dm_location_s set file_system_path = REPLACE(file_system_path,'${OLD_DOCUMENTUM}','${DOCUMENTUM}');" >> /tmp/migrateloc.sql
		
		echo "update dm_location_s set file_system_path = '/opt/dctm/product/${PRODUCT_MAJOR_VERSION}/convert' from (select r_object_id from dm_sysobject_s where object_name ='convert') as location where dm_location_s.r_object_id =location.r_object_id;" >> /tmp/migrateloc.sql
		echo "update dm_location_s set file_system_path = '/opt/dctm/product/${PRODUCT_MAJOR_VERSION}/install/external_apps/nls_chartrans' from (select r_object_id from dm_sysobject_s where object_name ='nls_chartrans') as location where dm_location_s.r_object_id =location.r_object_id;" >> /tmp/migrateloc.sql

		echo "update dm_mount_point_s set file_system_path = '/opt/dctm/share' from (select r_object_id from dm_sysobject_s where object_name ='share') as location where dm_mount_point_s.r_object_id =location.r_object_id;" >> /tmp/migrateloc.sql

		chmod 775 /tmp/migrateloc.sql
		#psql -U ${DOCBASE_OWNER_NAME} -d dm_${DOCBASE_NAME}_docbase -h $DATABASE_HOST -p$DATABASE_SERVER_PORT -P$DOCBASE_PASSWORD -a -f /tmp/migrateloc.sql >> /tmp/migrate_loc_objects.out
		DOCBASE_OWNER_EX=`cat  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini |grep database_owner| awk '{print $3}'`
		####psql "host=$DATABASE_HOST  dbname=dm_${DOCBASE_NAME}_docbase user=$DOCBASE_OWNER_EX password=$DOCBASE_PASSWORD" -a -f /tmp/migrateloc.sql >> /tmp/migrate_loc_objects.out
		if [ "$DB_TYPE" == "oracle" ]
		then
			sqlplus ${DOCBASE_NAME}/$DOCBASE_PASSWORD@${DATABASE_HOST}/${DATABASE_SERVICE_NAME} @/tmp/migrateloc.sql >> /tmp/migrate_loc_objects.out
		else
			PGPASSWORD=$DOCBASE_PASSWORD psql -h ${DATABASE_HOST} -d dm_${DOCBASE_NAME}_docbase -U ${DOCBASE_OWNER_EX} -a -f /tmp/migrateloc.sql >> /tmp/migrate_loc_objects.out
		
		fi
		
	  	if [ $? -eq $SUCCESS ];
		then
			log "Location  objects migrated successfully"
		else
			log "Location objects migrated failed for docbase  : $DOCBASE_NAME ";
			log "log file is /tmp/migrate_loc_objects.out"
			exit $FAILURE
		fi;
		
		migarteConfigObjects
			
	  fi
}
exitProgram()
{
   log "---------------------------------------------------------------------------------------"
   log "exitProgram"
   exit $FAILURE     
}

#Logging method
log()
{
   echo "$(date) $1"
   echo "$(date) $1" >> $logfile
}

certDocbroker()
{
    source $DM_HOME/bin/dm_set_server_env.sh;${DOCUMENTUM}/dba/dm_stop_Docbroker
    if [ $? -ne $SUCCESS ] 
    then
        log "Error:Docbroker is not down.Please check why the Docbroker is not going down. "
        exitProgram
    fi 
    
    source $DM_HOME/bin/dm_set_server_env.sh;${DOCUMENTUM}/dba/dm_stop_extDocbroker
    if [ $? -ne $SUCCESS ] 
    then
        log "Error: External Docbroker is not down.Please check why the Docbroker is not going down. "      
        exitProgram
    fi 
	sudo mkdir -p ${DOCUMENTUM}/certificate/docbroker_keys
    if [ ! -f  $DOCUMENTUM/dba/secure/broker.pwd ]
    then 
        export OPENSSL_CONF=$DM_HOME/bin/openssl.cnf;
		if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
		then
        	if [ ! -f $DOCUMENTUM/dba/secure/$DOCBROKER_AEK_NAME ]; then
				if [ ! -f $DOCUMENTUM/certificate/docbroker_keys/$DOCBROKER_AEK_NAME ]; then
			    	if [ "${AEK_LOCATION}" = "Remote" ]
					then
						source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_crypto_create -keyname $DOCBROKER_AEK_NAME -algorithm $AEK_ALGORITHM -key_id ${KMS_MASTER_KEY_ID} -kms_url ${KMS_URL} -kms_api_key $KMS_API_KEY -remote
					elif [ "${AEK_LOCATION}" = "Local" ]
					then
						source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_crypto_create -keyname $DOCBROKER_AEK_NAME -passphrase $DOCBROKER_AEK_PASSPHRASE -algorithm $AEK_ALGORITHM
					fi
					if [ $? -ne $SUCCESS ]; then
						log "Error while creating docbroker aek key."      
						exitProgram
					fi 
					log "Created $DOCUMENTUM/dba/secure/$DOCBROKER_AEK_NAME"
					cp $DOCUMENTUM/dba/secure/$DOCBROKER_AEK_NAME $DOCUMENTUM/certificate/docbroker_keys/
					log "Copied $DOCBROKER_AEK_NAME to $DOCUMENTUM/certificate/docbroker_keys/"
				else
					cp $DOCUMENTUM/certificate/docbroker_keys/$DOCBROKER_AEK_NAME $DOCUMENTUM/dba/secure/
					log "Copied existing $DOCUMENTUM/certificate/docbroker_keys/$DOCBROKER_AEK_NAME to $DOCUMENTUM/dba/secure/"
				fi
			else
				log "Using existing key $DOCUMENTUM/dba/secure/$DOCBROKER_AEK_NAME"
				if [ ! -f $DOCUMENTUM/certificate/docbroker_keys/$DOCBROKER_AEK_NAME ]; then
					cp $DOCUMENTUM/dba/secure/$DOCBROKER_AEK_NAME $DOCUMENTUM/certificate/docbroker_keys/
					log "Backing up $DOCBROKER_AEK_NAME to $DOCUMENTUM/certificate/docbroker_keys/"
				fi
        	fi
		fi
        
        if [ -z "$DOCBROKER_PEM_CERTIFICATE" ] || [ -z "$DOCBROKER_PEM_CERT_PRIVATE_KEY" ]
        then
            touch $DOCUMENTUM/dba/secure/self_signed_cert_used
            openssl req -newkey rsa:2048 -x509 -nodes -sha256 -keyout $DOCUMENTUM/dba/secure/brokerkey.pem -out $DOCUMENTUM/dba/secure/brokercrt.pem -days 365 -subj "/C=IN/ST=Kar/L=BLR/O=emc/OU=iig/CN=broker.com/emailAddress=broker@dctm.com"
			log "Created self signed certificate."
        else
            touch $DOCUMENTUM/dba/secure/provided_cert_used
			log "Using provided certificate."
            echo "$DOCBROKER_PEM_CERTIFICATE" > $DOCUMENTUM/dba/secure/brokercrt.pem
            echo "$DOCBROKER_PEM_CERT_PRIVATE_KEY" > $DOCUMENTUM/dba/secure/brokerkey.pem
            crthash=$(openssl x509 -noout -modulus -in "$DOCUMENTUM/dba/secure/brokercrt.pem" | openssl md5)
            keyhash=$(openssl rsa -noout -modulus -in "$DOCUMENTUM/dba/secure/brokerkey.pem" | openssl md5)
            if [ "$keyhash" != "$crthash" ]
            then
                log "Error: Invalid certificate/key provided."
                exitProgram
            fi
        fi
		if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
		then
			openssl pkcs12 -export -out $DOCUMENTUM/dba/secure/broker.p12 -inkey $DOCUMENTUM/dba/secure/brokerkey.pem -in $DOCUMENTUM/dba/secure/brokercrt.pem -name broker -password pass:$DOCBROKER_CERT_PASSWORD -descert
		else
			openssl pkcs12 -export -out $DOCUMENTUM/dba/secure/broker.p12 -inkey $DOCUMENTUM/dba/secure/brokerkey.pem -in $DOCUMENTUM/dba/secure/brokercrt.pem -name broker -password pass:$docbrokerCertPwd -descert
		fi
		
        if [ "${IS_VAULT_ENABLED}" = "true" ]; 
		then
			echo $DOCBROKER_CERT_PASSWORD >> $DOCUMENTUM/dba/secure/broker.pwd
		
		else
			if [ "${AEK_LOCATION}" = "Remote" ];
			then
				source $DM_HOME/bin/dm_set_server_env.sh; dm_encrypt_password -encrypt $DOCBROKER_CERT_PASSWORD -file $DOCUMENTUM/dba/secure/broker.pwd -keyname $DOCBROKER_AEK_NAME -kms_url ${KMS_URL} -kms_api_key $KMS_API_KEY
			elif [ "${AEK_LOCATION}" = "Local" ];
			then
        		source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_encrypt_password -encrypt $DOCBROKER_CERT_PASSWORD -file $DOCUMENTUM/dba/secure/broker.pwd -keyname $DOCBROKER_AEK_NAME -passphrase $DOCBROKER_AEK_PASSPHRASE
			fi
		fi
        openssl x509 -outform der -in $DOCUMENTUM/dba/secure/brokercrt.pem -out $DOCUMENTUM/dba/secure/brokercrt.der
		if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
		then
			sudo keytool -importcert -keystore $DOCUMENTUM/certificate/dfc.keystore -file $DOCUMENTUM/dba/secure/brokercrt.der -alias broker.`hostname` -storepass $DOCBROKER_TRUST_PASSWORD -noprompt
		else
			sudo keytool -importcert -keystore $DOCUMENTUM/certificate/dfc.keystore -file $DOCUMENTUM/dba/secure/brokercrt.der -alias broker.`hostname` -storepass $docbrokerTrustPwd -noprompt
		fi
		if [ "${AEK_LOCATION}" = "Remote" ]
		then
			sudo keytool -importcert -keystore $JAVA_HOME/lib/security/cacerts -file $DOCUMENTUM/dba/secure/brokercrt.der -alias broker.`hostname` -storepass changeit -noprompt
		fi
		sudo cat $DOCUMENTUM/dba/secure/brokercrt.pem >> $DOCUMENTUM/certificate/server-trust.pem
		sudo cp $DOCUMENTUM/dba/secure/brokercrt.der $DOCUMENTUM/certificate/brokercrt.`hostname`.der
	else
		sudo mv -f $DOCUMENTUM/dba/secure/broker.pwd $DOCUMENTUM/dba/secure/broker_back.pwd
		if [ "${IS_VAULT_ENABLED}" = "true" ]; 
		then
			echo $DOCBROKER_CERT_PASSWORD >> $DOCUMENTUM/dba/secure/broker.pwd
		fi

		if [ "${AEK_LOCATION}" = "Remote" ]; 
		then
			source $DM_HOME/bin/dm_set_server_env.sh; dm_encrypt_password -encrypt $DOCBROKER_CERT_PASSWORD -file $DOCUMENTUM/dba/secure/broker.pwd -keyname $DOCBROKER_AEK_NAME -kms_url ${KMS_URL} -kms_api_key $KMS_API_KEY
		elif [ "${AEK_LOCATION}" = "Local" ];
		then
        	source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_encrypt_password -encrypt $DOCBROKER_CERT_PASSWORD -file $DOCUMENTUM/dba/secure/broker.pwd -keyname $DOCBROKER_AEK_NAME -passphrase $DOCBROKER_AEK_PASSPHRASE
		fi			
    fi
 	if [ "${AEK_LOCATION}" = "Local" ]
	then
		source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_crypto_boot -keyname $DOCBROKER_AEK_NAME -passphrase $DOCBROKER_AEK_PASSPHRASE
	fi
   
    ls $DOCUMENTUM/dba/*Docbroker.ini | while read line ;
    do
        if [ `grep keystore_file $line | wc -l` -eq 0 ]
        then 
            echo "keystore_file=broker.p12" >> $line
            echo "keystore_pwd_file=broker.pwd" >> $line
            echo "cipherlist=ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256" >> $line
            echo "crypto_keyname=$DOCBROKER_AEK_NAME" >> $line
			if [ "${AEK_LOCATION}" = "Remote" ]; then
				echo "kms_url=$KMS_URL" >> $line
				echo "kms_api_key=$KMS_API_KEY" >> $line
			fi
        fi
    done
    echo "dfc.security.ssl.truststore=$DOCUMENTUM/certificate/dfc.keystore" >> $DOCUMENTUM/config/dfc.properties
    encryptedPasswd=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config EncryptPasswordUtil $DOCBROKER_TRUST_PASSWORD)
	if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
	then
		#Encrypt dfc trust store password
		if [ `grep security.ssl.truststore_password $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
		then 		
			if [ -z "$encryptedPasswd" ]
			then
				log "[certDocbroker] -->> Docbroker DFC trust store password encryption failed. Using plain password"
				echo "dfc.security.ssl.truststore_password=$DOCBROKER_TRUST_PASSWORD" >> $DOCUMENTUM/config/dfc.properties
			else
				log "[certDocbroker] -->> Docbroker DFC trust store password encryption passed."
				echo "dfc.security.ssl.truststore_password=$encryptedPasswd" >> $DOCUMENTUM/config/dfc.properties
			fi
		
			log "[certDocbroker] -->> Added truststore details in $DOCUMENTUM/config/dfc.properties"		
		else
			#Check the password present in dfc.properties. If it matches with the encrypted password.
			#The no need to change trust store password
			dfcPropPasswd=$( sed -n -e '/dfc.security.ssl.truststore_password/ s/.*\= *//p' $DOCUMENTUM/config/dfc.properties)
		
			if [  "$encryptedPasswd" = "$dfcPropPasswd" ]
			then
				log "[certDocbroker] -->> Encrypted password [$encryptedPasswd] matches the password [$dfcPropPasswd] stored in dfc.properties."
			else
				log "[certDocbroker] -->> Encrypted password [$encryptedPasswd] doesn't matches the password [$dfcPropPasswd] stored in dfc.properties."
				sed -i -e "s;dfc.security.ssl.truststore_password=.*;dfc.security.ssl.truststore_password=$encryptedPasswd;" $DOCUMENTUM/config/dfc.properties
				log "[certDocbroker] -->> dfc.properties updated with new encrypted password $encryptedPasswd."
			fi
		fi
		log "[certDocbroker] -->> Added truststore details in $DOCUMENTUM/config/dfc.properties"
	else
		hostname=`hostname -f`
		echo "dfc.security.ssl.truststore_password=$docbrokertrustStorePasswordPrefix/$hostname" >> $DOCUMENTUM/config/dfc.properties
	fi
    source $DM_HOME/bin/dm_set_server_env.sh;${DOCUMENTUM}/dba/dm_launch_Docbroker
    if [ $? -ne $SUCCESS ] 
    then
        log "Error:Docbroker is not starting. Check why the Docbroker is not going down. "      
        exitProgram
    fi 
    
    source $DM_HOME/bin/dm_set_server_env.sh;${DOCUMENTUM}/dba/dm_launch_extDocbroker
    if [ $? -ne $SUCCESS ] 
    then
        log "Error: External Docbroker is not starting. Check why the Docbroker is not going down. "      
        exitProgram
    fi 
}

certDocbase()
{
	if [ ! -f $DOCUMENTUM/certificate/server-trust.pem ]
	then
		log "Error: $DOCUMENTUM/certificate/server-trust.pem file not found. Check why server-trust.pem was not created from docbroker."      
        exitProgram
	fi

	openssl crl2pkcs7 -nocrl -certfile $DOCUMENTUM/certificate/server-trust.pem -outform der -out $DOCUMENTUM/dba/secure/server-trust.p7b

    if [ ! -f $DOCUMENTUM/dba/secure/server.pwd ]
    then 
        export OPENSSL_CONF=$DM_HOME/bin/openssl.cnf;

		if [ ! -f $DOCUMENTUM/dba/secure/$AEK_NAME ]; then
			if [ "${IS_VAULT_ENABLED}" = "true" ]
			then
				if [ "${AEK_LOCATION}" = "Remote_Vault" ]
				then
					source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_crypto_create -keyname $AEK_NAME -dsis_url $DSIS_URL -secret_id $AEK_PASSPHRASE -algorithm $AEK_ALGORITHM -vault
				elif [ "${AEK_LOCATION}" = "Remote" ]
				then
					source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_crypto_create -keyname $AEK_NAME -algorithm $AEK_ALGORITHM -key_id ${KMS_MASTER_KEY_ID} -kms_url ${KMS_URL} -kms_api_key $KMS_API_KEY -dsis_url $DSIS_URL -remote -vault
				fi
			else
				if [ "${AEK_LOCATION}" = "Remote" ]
				then
					source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_crypto_create -keyname $AEK_NAME -algorithm $AEK_ALGORITHM -key_id ${KMS_MASTER_KEY_ID} -kms_url ${KMS_URL} -kms_api_key $KMS_API_KEY -remote
				elif [ "${AEK_LOCATION}" = "Local" ]
				then
					source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_crypto_create -keyname $AEK_NAME -passphrase $AEK_PASSPHRASE -algorithm $AEK_ALGORITHM
				fi
			fi
			if [ $? -ne $SUCCESS ]; then
					log "Error while creating remote docbase key. "      
					exitProgram
			fi
			log "Created $DOCUMENTUM/dba/secure/$AEK_NAME"
			# Create a marker file indicating that AEK has been created
			touch -f ${DOCUMENTUM}/dba/secure/${AEK_NAME}_created
			log "Created AEK marker file ${DOCUMENTUM}/dba/secure/${AEK_NAME}_created"
		else
			log "Using existing key $DOCUMENTUM/dba/secure/$AEK_NAME"
		fi
		
		# Check if we have p12 (primary docbase certificate) file on shared location (/opt/dctm/certificate)
		if [ -f $DOCUMENTUM/certificate/server.p12 ] && [ -f $DOCUMENTUM/certificate/dfc.keystore ] && [ -f $DOCUMENTUM/certificate/server.pwd ]
		then
			# If yes the use that don't create certificate for secondary docbase
			cp $DOCUMENTUM/certificate/server.p12 $DOCUMENTUM/dba/secure/.
			cp $DOCUMENTUM/certificate/server.pwd $DOCUMENTUM/dba/secure/.	
		else
			if [ -z "$DOCBASE_PEM_CERTIFICATE" ] || [ -z "$DOCBASE_PEM_CERT_PRIVATE_KEY" ]
			then
				source $DM_HOME/bin/dm_set_server_env.sh; touch $DOCUMENTUM/dba/secure/self_signed_cert_used
				openssl req -newkey rsa:2048 -x509 -nodes -sha256 -keyout $DOCUMENTUM/dba/secure/serverkey.pem -out $DOCUMENTUM/dba/secure/servercrt.pem -days 365 -subj "/C=IN/ST=Kar/L=BLR/O=emc/OU=iig/CN=server.com/emailAddress=server@dctm.com"
			else
				source $DM_HOME/bin/dm_set_server_env.sh; touch $DOCUMENTUM/dba/secure/provided_cert_used
				source $DM_HOME/bin/dm_set_server_env.sh; echo "$DOCBASE_PEM_CERTIFICATE" > $DOCUMENTUM/dba/secure/servercrt.pem
				source $DM_HOME/bin/dm_set_server_env.sh; echo "$DOCBASE_PEM_CERT_PRIVATE_KEY" > $DOCUMENTUM/dba/secure/serverkey.pem
				crthash=$(openssl x509 -noout -modulus -in "$DOCUMENTUM/dba/secure/servercrt.pem" | openssl md5)
				keyhash=$(openssl rsa -noout -modulus -in "$DOCUMENTUM/dba/secure/serverkey.pem" | openssl md5)
				if [ "$keyhash" != "$crthash" ]
				then
					log "Error: Invalid certificate/key provided."
					exitProgram
				fi
			fi
			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				openssl pkcs12 -export -out $DOCUMENTUM/dba/secure/server.p12 -inkey $DOCUMENTUM/dba/secure/serverkey.pem -in $DOCUMENTUM/dba/secure/servercrt.pem -name server -password pass:$DOCBASE_CERT_PASSWORD -descert
			else
				openssl pkcs12 -export -out $DOCUMENTUM/dba/secure/server.p12 -inkey $DOCUMENTUM/dba/secure/serverkey.pem -in $DOCUMENTUM/dba/secure/servercrt.pem -name server -password pass:$docbaseCertPwd -descert
			fi
			if [ "${IS_VAULT_ENABLED}" = "true" ];
			then
				echo $DOCBASE_CERT_PASSWORD >> $DOCUMENTUM/dba/secure/server.pwd
			else
				if [ "${AEK_LOCATION}" = "Remote" ]; 
				then
					source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_encrypt_password -encrypt $DOCBASE_CERT_PASSWORD -file $DOCUMENTUM/dba/secure/server.pwd -keyname $AEK_NAME -kms_url ${KMS_URL} -kms_api_key $KMS_API_KEY
				elif [ "${AEK_LOCATION}" = "Local" ];
				then
					source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_encrypt_password -encrypt $DOCBASE_CERT_PASSWORD -file $DOCUMENTUM/dba/secure/server.pwd -keyname $AEK_NAME -passphrase $AEK_PASSPHRASE
				fi
			fi
			openssl x509 -outform der -in  $DOCUMENTUM/dba/secure/servercrt.pem -out $DOCUMENTUM/dba/secure/servercrt.der
			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				sudo keytool -importcert -keystore $DOCUMENTUM/certificate/dfc.keystore -file $DOCUMENTUM/dba/secure/servercrt.der -alias server.`hostname` -storepass $DFC_SSL_TRUSTSTORE_PASSWORD -noprompt
			else
				sudo keytool -importcert -keystore $DOCUMENTUM/certificate/dfc.keystore -file $DOCUMENTUM/dba/secure/servercrt.der -alias server.`hostname` -storepass $dfcTrustStorePwd -noprompt
			fi
			if [ "${AEK_LOCATION}" = "Remote" ]
			then
				sudo keytool -importcert -keystore $JAVA_HOME/lib/security/cacerts -file $DOCUMENTUM/dba/secure/servercrt.der -alias server.`hostname` -storepass changeit -noprompt
			fi
			sudo cp $DOCUMENTUM/dba/secure/servercrt.der $DOCUMENTUM/certificate/servercrt.`hostname`.der
			sudo cp $DOCUMENTUM/dba/secure/server.p12 $DOCUMENTUM/certificate/.
			sudo cp $DOCUMENTUM/dba/secure/server.pwd $DOCUMENTUM/certificate/.
		fi
	else
		# Rename the original server.pwd file
		sudo mv -f $DOCUMENTUM/dba/secure/server.pwd $DOCUMENTUM/dba/secure/server_back.pwd
		# Regenarate the server.pwd file
		if [ "${IS_VAULT_ENABLED}" = "true" ];
		then
			echo $DOCBASE_CERT_PASSWORD >> $DOCUMENTUM/dba/secure/server.pwd
		else
			if [ "${AEK_LOCATION}" = "Remote" ]; 
			then
				source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_encrypt_password -encrypt $DOCBASE_CERT_PASSWORD -file $DOCUMENTUM/dba/secure/server.pwd -keyname $AEK_NAME -kms_url ${KMS_URL} -kms_api_key $KMS_API_KEY
			elif [ "${AEK_LOCATION}" = "Local" ];
			then
				source $DM_HOME/bin/dm_set_server_env.sh; $DM_HOME/bin/dm_encrypt_password -encrypt $DOCBASE_CERT_PASSWORD -file $DOCUMENTUM/dba/secure/server.pwd -keyname $AEK_NAME -passphrase $AEK_PASSPHRASE
			fi
		fi
    fi
}

importSMTPSSLCert()
{
	if [ -n "$SMTP_SSL_CERTIFICATE" ]
	then
	# save certificate.
	echo "$SMTP_SSL_CERTIFICATE" > $DOCUMENTUM/dba/secure/smtp.pem
	# import certificate to appropriate trust store.
		if [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
		then
			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				sudo keytool -importcert -keystore $DOCUMENTUM/certificate/dfc.keystore -file $DOCUMENTUM/dba/secure/smtp.pem -alias smtp.`hostname` -storepass $DFC_SSL_TRUSTSTORE_PASSWORD -noprompt
			else
				sudo keytool -importcert -keystore $DOCUMENTUM/certificate/dfc.keystore -file $DOCUMENTUM/dba/secure/smtp.pem -alias smtp.`hostname` -storepass $dfcTrustStorePwd -noprompt
			fi
		else
			sudo keytool -importcert -keystore $JAVA_HOME/lib/security/cacerts -file $DOCUMENTUM/dba/secure/smtp.pem -alias smtp -storepass changeit -noprompt
		fi
	fi
}

importS3sslCert()
{
	if [ -n "$S3_SSL_CERTIFICATE" ]
	then
		# save certificate.
		if [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
		then
			KEYSTORE=$DOCUMENTUM/certificate/dfc.keystore
			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				PASSWORD=$DFC_SSL_TRUSTSTORE_PASSWORD
			else
				PASSWORD=$dfcTrustStorePwd
			fi
		else
			KEYSTORE=$JAVA_HOME/lib/security/cacerts
			PASSWORD=changeit
		fi
		PEM_FILE=$DOCUMENTUM/dba/secure/s3.pem
		echo "$S3_SSL_CERTIFICATE" > $PEM_FILE
		# number of certs in the PEM file
		CERTS=$(grep 'END CERTIFICATE' $PEM_FILE| wc -l)
		# For every cert in the PEM file, extract it and import into java truststore
		for N in $(seq 0 $(($CERTS - 1))); do
			ALIAS="s3-$N"
			cat $PEM_FILE |
				awk "n==$N { print }; /END CERTIFICATE/ { n++ }" |
				sudo keytool -noprompt -importcert -alias $ALIAS -keystore $KEYSTORE -storepass $PASSWORD
		done
	fi
}

importAzureStoresslCert()
{
	if [ $REST_STORE_ENABLE ] && [ -n "$REST_AZURE_STORE_SSL_CERT" ] && [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
	then
		# import certificate to appropriate trust store.
		# save certificate only in certificate based setup.
		log "[importAzureStoresslCert] ==>> Getting public certificate for Azure store"
		echo -n "$REST_AZURE_STORE_SSL_CERT" > $DOCUMENTUM/dba/secure/restazurestorecertchain.pem
		cd $DOCUMENTUM/dba/secure
		awk '
		split_after == 1 {n++;split_after=0}
		/-----END CERTIFICATE-----/ {split_after=1}
		{print > "rest_azure_store_cert_" n ".pem"}' < $DOCUMENTUM/dba/secure/restazurestorecertchain.pem
		
		n=0
		for i in $(ls rest_azure_store_cert_*.pem)
		do
			if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				sudo keytool -importcert -keystore $DOCUMENTUM/certificate/dfc.keystore -file $i -alias azureblob_$n.`hostname` -storepass $DFC_SSL_TRUSTSTORE_PASSWORD -noprompt
			else
				sudo keytool -importcert -keystore $DOCUMENTUM/certificate/dfc.keystore -file $i -alias azureblob_$n.`hostname` -storepass $dfcTrustStorePwd -noprompt
			fi
			((n=n+1))
		done
		log "[importAzureStoresslCert] ==>> Imported Azure Blob store certificate to $DOCUMENTUM/certificate/dfc.keystore"
		cd -
	fi
}

importGcpStoresslCert()
{
	if [ $REST_STORE_ENABLE ] && [ -n "$REST_GCP_STORE_SSL_CERT" ] && [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
	then
		# import certificate to appropriate trust store.
		# save certificate only in certificate based setup.
		log "[importGcpStoresslCert] ==>> Getting public certificate for GCP store"
		echo -n "$REST_GCP_STORE_SSL_CERT" > $DOCUMENTUM/dba/secure/restgcpstorecertchain.pem
		cd $DOCUMENTUM/dba/secure
		awk '
		split_after == 1 {n++;split_after=0}
		/-----END CERTIFICATE-----/ {split_after=1}
		{print > "rest_gcp_store_cert_" n ".pem"}' < $DOCUMENTUM/dba/secure/restgcpstorecertchain.pem
	
		n=0
		for i in $(ls rest_gcp_store_cert_*.pem)
		do
		    if [ -z "${IS_VAULT_ENABLED}" ] || [ "${IS_VAULT_ENABLED}" = "false" ]
			then
				sudo keytool -importcert -keystore $DOCUMENTUM/certificate/dfc.keystore -file $i -alias gcpstore_$n.`hostname` -storepass $DFC_SSL_TRUSTSTORE_PASSWORD -noprompt
			else
				sudo keytool -importcert -keystore $DOCUMENTUM/certificate/dfc.keystore -file $i -alias gcpstore_$n.`hostname` -storepass $dfcTrustStorePwd -noprompt
			fi
			((n=n+1))
		done
		log "[importAzureStoresslCert] ==>> Imported GCP store certificate to $DOCUMENTUM/certificate/dfc.keystore"
		
		cd -
	fi
}

#Fix for updating (overriding) log4j2.properties without helm configmap changes
fixACSLog4jProperties()
{
	sed -i '/log4j.additivity.tracing/d;/log4j.category.tracing/d' ${DM_JMS_HOME}/webapps/ACS/WEB-INF/classes/log4j2.properties
	log "fixACSLog4jProperties: removed 2 older properties from webapps/ACS/WEB-INF/classes/log4j2.properties"
}

onlyDocbroker()
{
   if [ "$alreadyInstalled" != "FALSE" ]
   then
        CURRENT_CS_VERSION=`cat  ${DOCUMENTUM}/dba/dm_launch_Docbroker |grep DM_HOME_CURRENT=| awk 'BEGIN{FS="/"} {print $5}'`
        if [ "$CURRENT_CS_VERSION" != "$PRODUCT_MAJOR_VERSION" ]
        then
            upgradeDbr
        fi
    fi
   if [ $NEWRELIC_ENABLE ]
   then
	 handle_start_newrelic_c_agent
   fi
   handle_start_docbroker
   handle_start_ext_docbroker
   if [ "${IS_VAULT_ENABLED}" = "true" ]
   then
		# First we Docbroker.ini
		if [ `grep isDSISEnabled $DOCUMENTUM/dba/Docbroker.ini | wc -l` -eq 0 ]
		then
			# Entry not there add new entry
			echo "isDSISEnabled=T" >> $DOCUMENTUM/dba/Docbroker.ini
		else
			# Replace existing entry
			sed -i -e "s;isDSISEnabled.*;isDSISEnabled = T;" $DOCUMENTUM/dba/Docbroker.ini
		fi
			
		if [ `grep dsis_url $DOCUMENTUM/dba/Docbroker.ini | wc -l` -eq 0 ]
		then
			# Entry not there add new entry
			echo "dsis_url=$DSIS_URL" >> $DOCUMENTUM/dba/Docbroker.ini
		else
			# Replace existing entry
			sed -i -e "s;dsis_url.*;dsis_url = $DSIS_URL;" $DOCUMENTUM/dba/Docbroker.ini
		fi
		
		# First we extDocbroker.ini
		if [ `grep isDSISEnabled $DOCUMENTUM/dba/extDocbroker.ini | wc -l` -eq 0 ]
		then
			# Entry not there add new entry
			echo "isDSISEnabled=T" >> $DOCUMENTUM/dba/extDocbroker.ini
		else
			# Replace existing entry
			sed -i -e "s;isDSISEnabled.*;isDSISEnabled = T;" $DOCUMENTUM/dba/extDocbroker.ini
		fi
			
		if [ `grep dsis_url $DOCUMENTUM/dba/extDocbroker.ini | wc -l` -eq 0 ]
		then
			# Entry not there add new entry
			echo "dsis_url=$DSIS_URL" >> $DOCUMENTUM/dba/extDocbroker.ini
		else
			# Replace existing entry
			sed -i -e "s;dsis_url.*;dsis_url = $DSIS_URL;" $DOCUMENTUM/dba/extDocbroker.ini
		fi
		
		# Now update dfc.properties
		if [ `grep dfc.dsis.enabled $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
		then
			# Entry not there add new entry
			echo "dfc.dsis.enabled=$IS_VAULT_ENABLED" >> $DOCUMENTUM/config/dfc.properties
		else
			# Replace existing entry
			sed -i -e "s;dfc.dsis.enabled.*;dfc.dsis.enabled=$IS_VAULT_ENABLED;" $DOCUMENTUM/config/dfc.properties
		fi
			
		if [ `grep dfc.dsis.daemon.url $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
		then
			# Entry not there add new entry
			echo "dfc.dsis.daemon.url=$DSIS_URL" >> $DOCUMENTUM/config/dfc.properties
		else
			# Replace existing entry
			sed -i -e "s;dfc.dsis.daemon.url.*;dfc.dsis.daemon.url=$DSIS_URL;" $DOCUMENTUM/config/dfc.properties
		fi

		#update jmx.properties
		sed -i -e "s;user.acsAdmin=.*;user.acsAdmin=SECRET_NOT_SUPPORTED,Administrators;" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/jmx.properties
		
   fi   
   if [ -n "$DOCBROKER_USE_CERTIFICATES" ] && [ "$DOCBROKER_USE_CERTIFICATES" == "true" ]
   then
       certDocbroker
   fi
   ready
}
#Regression testing code
launchCSTests()
{
 
   log "---------------------------------------------------------------------------------------"

  log "start cstest regression" 
  if [ -d "$DM_DOCKER_HOME/cstests/cstests" ]
  then
   log "$DM_DOCKER_HOME/cstests/cstests already exists"
  else
   log "creating dir $DM_DOCKER_HOME/cstests/cstests"
   mkdir $DM_DOCKER_HOME/cstests/cstests
  fi
   #chmod -R 777 $DM_DOCKER_HOME
   #chmod -R 777 $DM_DOCKER_HOME/cstests/cstests/results
   hname=`hostname`
			
   if [[ $hname = $CONTAINER_NAME-0* ]];
   then
		cp $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr.xml $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr0.xml
			
		sed -i -e 's/name="cluster" value="false"/name="cluster" value="true"/g' $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr0.xml
		sed -i -e "s/docbase1/$DOCBASE_NAME/g" $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr0.xml
		controller=${CONTAINER_NAME}-0.${CONTAINER_NAME}.${DOCBROKER_CLUSTER_SPACE}
		log "Setting cluster and controller parameters in Masterconfig$host_index"  
		sed -i -e "s/10.31.70.135/$controller/g" $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr0.xml
		
		log "Setting isController is true"  
		
		sed -i -e 's/name="isController" value="false"/name="isController" value="true"/g' $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr0.xml
		masterConfig=MasterConfigServerRegr0.xml
		sleep 10m	
   else
		cp $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr.xml $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr$host_index.xml
		sed -i -e 's/name="cluster" value="false"/name="cluster" value="true"/g' $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr$host_index.xml
		sed -i -e "s/docbase1/$DOCBASE_NAME/g" $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr$host_index.xml
		controller=${CONTAINER_NAME}-0.${CONTAINER_NAME}.${DOCBROKER_CLUSTER_SPACE}
		log "Setting cluster and controller parameters in Masterconfig$host_index"  
		sed -i -e "s/10.31.70.135/$controller/g" $DM_DOCKER_HOME/cstests/cstests/configs/MasterConfigServerRegr$host_index.xml
	
		log "rename the startup and shutdoun scripts"
		sed -i -e "s/${CONFIG_NAME_OPTION}${host_index}${DOCBASE_NAME}.log/${DOCBASE_NAME}.log/g" $DOCUMENTUM/dba/dm_start_${DOCBASE_NAME}_dm_${DOCBASE_NAME}
	
		cp $DOCUMENTUM/dba/dm_shutdown_${DOCBASE_NAME}_dm_${DOCBASE_NAME}  $DOCUMENTUM/dba/dm_shutdown_${DOCBASE_NAME}
		cp $DOCUMENTUM/dba/dm_start_${DOCBASE_NAME}_dm_${DOCBASE_NAME}  $DOCUMENTUM/dba/dm_start_${DOCBASE_NAME}
		sed -i -e "s/server_${CONFIG_NAME_OPTION}${host_index}${DOCBASE_NAME}/server/g" $DOCUMENTUM/dba/dm_start_${DOCBASE_NAME}
		
		
		
		masterConfig=MasterConfigServerRegr${host_index}.xml
		cp $DOCUMENTUM/dba/config/$DOCBASE_NAME/server_$CONFIG_NAME_OPTION$host_index${DOCBASE_NAME}.ini  $DOCUMENTUM/dba/config/$DOCBASE_NAME/server.ini
		
   fi
		log "Stop Docbase"
		kill -9 `ps -ef | grep ${DOCBASE_NAME} |grep -v grep | awk '{print $2}'`
		
		log "Start Docbase"
		source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}
		#Modifying this to status check
        sleep 2m		
		source $DM_HOME/bin/dm_set_server_env.sh; source $DM_DOCKER_HOME/cstests/cstests/dm_regr_setup_env.sh; ant -f $DM_DOCKER_HOME/cstests/cstests/scripts/build.xml server.run.group -Dgroup Core -DmasterConfig $masterConfig;
  
     
   log "Regression completed" 
   touch -f $DM_DOCKER_HOME/cstests/cstests/regression-completed
   exit $SUCCESS     
    
}

#During pod upgrade, ingress URL will not be accessible
#Update current pod's ACS config object base URL with localhost value
updateAcsConfigLocalBaseUrl()
{
	acs_url=http://`hostname -f`:9080/ACS/servlet/ACS
	log "Updating ACS config object base URL to $acs_url"
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f $DM_DOCKER_HOME/update_config_objects.ebs -e updateACSConfigLocalBaseUrl -- $DOCBASE_NAME $INSTALL_OWNER "" `hostname` $acs_url >> /tmp/update_config_objects_dmbasic.out;
	if [ $? -eq $SUCCESS ];
	then
		log "ACS config object updated successfully: $acs_url"
	else
		log "ACS config object update failed for docbase: $DOCBASE_NAME and url: $acs_url";
		log "log file is /tmp/update_config_objects_dmbasic.out"
	fi
}

#Update ACS config object base URL with ingress host value
updateAcsConfigBaseUrl()
{
   if [ "$DISABLE_UPDATE_ACS_URL" != "true" ]
   then
   
	   jmsHost=`echo $JMS_HOST`
	   log "updateAcsConfigBaseUrl called Jms host:  $jmsHost"
	   jmsPort=""
	   #If no JMS_HOST value provided then use hostname with FQDN
	   if [ -z "$jmsHost" ];
	   then
		  jmsHost=`hostname -f`
		  jmsPort=:9080
	   fi;
	   
	  log "Updating ACS config object base URL to jmsHost $jmsHost"
	  acs_protocol=`echo $INGRESS_PROTOCOL`
	  if [ -z "$acs_protocol" ];
	  then
			 acs_protocol=`echo $JMS_PROTOCOL`
	  fi
	  if [ -z "$acs_protocol" ];
	  then
			 acs_protocol=http;
	  fi

	  acs_url=$acs_protocol://$jmsHost$jmsPort/ACS/servlet/ACS
	  source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f $DM_DOCKER_HOME/update_config_objects.ebs -e updateACSConfigBaseUrl -- $DOCBASE_NAME $INSTALL_OWNER "" $acs_url >> /tmp/update_config_objects_dmbasic.out;
	  if [ $? -eq $SUCCESS ];
	  then
			 log "ACS config object updated successfully: $acs_url"
	  else
			 log "ACS config object update failed for docbase : $DOCBASE_NAME and url: $acs_url";
			 log "log file is /tmp/update_config_objects_dmbasic.out"
	  fi;
  fi;
}

#Update Thumbnail server base URL with ingress host value 
updateThumbnailServerBaseUrl()
{
   log "updateThumbnailServerBaseUrl called Tns host:  $TNS_HOST"
   tnsHost=`echo $TNS_HOST`
   if [ ! -z "$tnsHost" ]
   then
      log "Updating Thumbnail server base URL"
	  tns_protocol=`echo $TNS_PROTOCOL`
	  if [ -z $tns_protocol ];
	  then
         tns_protocol=http;
	  fi
	  tns_url=$tns_protocol://$tnsHost/thumbsrv/getThumbnail?
	  source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f $DM_DOCKER_HOME/update_config_objects.ebs -e updateThumbnailServerBaseUrl -- $DOCBASE_NAME $INSTALL_OWNER "" $tns_url >> /tmp/update_config_objects_dmbasic.out;
	  if [ $? -eq $SUCCESS ];
	  then
         log "Thumbnail server base URL updated successfully: $tns_url"
	  else
         log "Thumbnail server base URL: $tns_url update failed for docbase : $DOCBASE_NAME";
		 log "log file is /tmp/update_config_objects_dmbasic.out"
	  fi;
   fi
}

#Due to some reason the proximity value in dm_server_config object is changing to 2. 
#We have to set it back to 1 for loadbalancer. This is a workaround until this issue is fixed in CS code.
#Once it is fixed in CS code, we have to remove this code
#set server config object proximity value to 1 
updateServerConfigProximityValue()
{
   if [ "$alreadyInstalled" != "TRUE" ]
   then
      log "Updating server config object proximity value from 2 to 1"
	  source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f $DM_DOCKER_HOME/update_config_objects.ebs -e updateServerConfigProximityValue -- $DOCBASE_NAME $INSTALL_OWNER "" >> /tmp/update_config_objects_dmbasic.out;
	  if [ $? -eq $SUCCESS ];
	  then
		 log "Server config object proximity value updated successfully"
	  else
		 log "Server config object proximity value update failed for docbase :  $DOCBASE_NAME";
		 log "log file is /tmp/update_config_objects_dmbasic.out"
	  fi;
   fi
}
#Upgrade the convert and nls_chartrans location objects to latest version
upgradeLocationObjects()
{
	log "==============================================================================================="
	log "[upgradeLocationObjects] ==>> upgradeLocationObjects function called to update location objects"
	log "==============================================================================================="
	  rm -rf /tmp/sha3.sql
	  rm -rf /tmp/upgrade_loc_objects.out
	  primary=$1
	  if [ "$primary" != "true" ]
	  then
		cryptoALg=`expr substr $AEK_ALGORITHM 1 3`
		cryptoKeySize=`expr substr $AEK_ALGORITHM 5 3`
		cryptomode=${cryptoALg}${cryptoKeySize}_RSA2048_SHA3_384
		echo "update dm_docbase_config_s set r_crypto_mode = '${cryptomode}';" >> /tmp/sha3.sql
	  fi
	  echo "update dm_location_s set file_system_path ='/opt/dctm/product/${PRODUCT_MAJOR_VERSION}/convert' where dm_location_s.r_object_id in (select r_object_id from dm_sysobject_s where object_name ='convert');" >> /tmp/sha3.sql
	  echo "update dm_location_s set file_system_path = '/opt/dctm/product/${PRODUCT_MAJOR_VERSION}/install/external_apps/nls_chartrans' where dm_location_s.r_object_id in (select r_object_id from dm_sysobject_s where object_name ='nls_chartrans');" >> /tmp/sha3.sql
	  
	  chmod 775 /tmp/sha3.sql
	  if [ "$primary" == "true" ]
	  then
		DOCBASE_OWNER_EX=`cat  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini |grep database_owner| awk '{print $3}'`
	  else
		DOCBASE_OWNER_EX=`cat  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server_${SERVER_CONFIG_NAME}.ini |grep database_owner| awk '{print $3}'`
	  fi
	  #####psql "host=$DATABASE_HOST  dbname=dm_${DOCBASE_NAME}_docbase user=$DOCBASE_OWNER_EX password=$DOCBASE_PASSWORD" -a -f /tmp/sha3.sql >> /tmp/upgrade_loc_objects.out
	  if [ "${IS_VAULT_ENABLED}" = "true" ]; 
	  then		
			DOCBASE_PASSWORD=$(curl "$DSIS_URL/secret/$DOCBASE_PASSWORD")  
			if [ -z "$DOCBASE_PASSWORD" ]; 
			then  
				log "DOCBASE_PASSWORD is empty"
			fi
	  fi

	  if [ "$DB_TYPE" == "oracle" ]
	  then
		sqlplus "${DOCBASE_NAME}/${DOCBASE_PASSWORD}@${DATABASE_HOST}/${DATABASE_SERVICE_NAME}" @/tmp/sha3.sql >> /tmp/upgrade_loc_objects.out
	  else
		PGPASSWORD="${DOCBASE_PASSWORD}" psql -h "${DATABASE_HOST}" -d "dm_${DOCBASE_NAME}_docbase" -U "${DOCBASE_OWNER_EX}" -a -f /tmp/sha3.sql >> /tmp/upgrade_loc_objects.out
	  fi	  
	  
	  if [ $? -eq $SUCCESS ];
	  then
		 log "Location objects  and SHA3 algorithm  successfully upgraded"
	  else
		 log "Location objects  and SHA3 algorithm is not upgraded in docbase";
		 log "log file is /tmp/upgrade_loc_objects.out"
		 cat /tmp/upgrade_loc_objects.out
	  fi
	log "==============================================================================================="
	log "[upgradeLocationObjects] ==>> upgradeLocationObjects function exited"
	log "==============================================================================================="
}
migration_util()
{
    migration=false
    hostname=`hostname`
	if [ "$isHA" != "TRUE" ]
	then
		if [ "$MIGRATECS" = "true" ]
		then
			migratecsfile="${DOCUMENTUM}/kube/MigrateCS"		
			if [ -f "$migratecsfile" ]
			then
				log "Migration already complted"
			else
				oldhostname=$OLD_MIG_HOSTNAME
			fi
		fi
	else
		oldhostname=`cat ${DOCUMENTUM}/uninstall/dfc/installvariables.properties | grep NATIVE_ENVIRONMENT.HOSTNAME | awk '{print substr($1,index($1,"=")+1)}'`
	fi
	if [ -f /opt/dctm/dba/config/${DOCBASE_NAME}/*server*.ini ]
    then
        olddocbaseid=`grep -i "docbase_id" /opt/dctm/dba/config/${DOCBASE_NAME}/*server*.ini | awk '{print $3}'`
    fi

    if [ "$oldhostname" != "$hostname" ]
    then
        log "Old hostname is : $oldhostname"
        sed -i -e '/ChangeHostName/s/no/yes/' ${DM_DOCKER_HOME}/config/config.xml
        sed -i -e "s/OldHostname/$oldhostname/"  ${DM_DOCKER_HOME}/config/config.xml
        sed -i -e "s/NewHostname/$hostname/"  ${DM_DOCKER_HOME}/config/config.xml
        migration=true
    fi

    if [[ ! -z "$olddocbaseid" && "$olddocbaseid" != "$DOCBASE_ID" ]]
    then
         log "Old docbase id is : $olddocbaseid"
        sed -i -e '/ChangeDocbaseID/s/no/yes/' ${DM_DOCKER_HOME}/config/config.xml
        
        sed -i -e "s/Docbase name/$DOCBASE_NAME/" ${DM_DOCKER_HOME}/config/config.xml
        sed -i -e "s/Target Docbase ID/$DOCBASE_ID/"  ${DM_DOCKER_HOME}/config/config.xml
        migration=true
        
    fi

    if [ $migration == "true" ]
    then	
		sed -i -e "/tgt_database_server/s/localhost/$DATABASE_HOST/" ${DM_DOCKER_HOME}/config/config.xml
        sed -i -e "/DocbaseName.1/s/centdb/$DOCBASE_NAME/" ${DM_DOCKER_HOME}/config/config.xml
		sed -i -e "s;<entry key=\"DocbasePassword.1\">.*;<entry key=\"DocbasePassword.1\">$DOCBASE_PASSWORD</entry>;" ${DM_DOCKER_HOME}/config/config.xml
		if [ "${IS_VAULT_ENABLED}" = "true" ]
		then
			sed -i -e "s;<entry key=\"vaultEnabled\">.*;<entry key=\"vaultEnabled\">yes</entry>;" ${DM_DOCKER_HOME}/config/config.xml
			sed -i -e "s;<entry key=\"dsis_url\">.*;<entry key=\"dsis_url\">$DSIS_URL</entry>;" ${DM_DOCKER_HOME}/config/config.xml
		fi		
        cp  ${DM_HOME}/install/external_apps/MigrationUtil/config.xml ${DM_HOME}/install/external_apps/MigrationUtil/config.xml.bak
        cp  ${DM_DOCKER_HOME}/config/config.xml ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
        chmod 775 ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
        cd ${DM_HOME}/install/external_apps/MigrationUtil; source $DM_HOME/bin/dm_set_server_env.sh; java $JVM_OPTS -cp ${CLASSPATH}:${DM_HOME}/install/external_apps/MigrationUtil/MigrationUtil.jar:${DM_HOME}/install/external_apps/MigrationUtil/postgresql.jar MigrationUtil
        if [ $? != $SUCCESS ]
        then
            log "ERROR: The Hostname change Utility has failed. Please check install logs at container's ${DM_HOME}/install/external_apps/MigrationUtil/MigrationUtilLogs"
            log "Revert ${DM_HOME}/install/external_apps/MigrationUtil/config.xml"
            cp  ${DM_HOME}/install/external_apps/MigrationUtil/config.xml.bak ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
            exit $FAILURE
        fi
        log "Revert ${DM_HOME}/install/external_apps/MigrationUtil/config.xml"
        cp  ${DM_HOME}/install/external_apps/MigrationUtil/config.xml.bak ${DM_HOME}/install/external_apps/MigrationUtil/config.xml
    fi
	
}

handle_logs_cleanup()
{
   log "---------------------------------------------------------------------------------------"
   log "handle_logs_cleanup"
}

custom_script_execution()
{
    log "custom_script_execution"
    if [ -x ${DM_DOCKER_HOME}/custom_script/script_from_external.sh ]
    then
        /bin/sh ${DM_DOCKER_HOME}/custom_script/script_from_external.sh
    else
        log "File custom_script/script_from_external.sh doesn't execute or not available"
    fi
}

custom_script_pvc_execution()
{
    log "custom_script_execution"
	for i in `ls /opt/dctm_docker/custom_script_pvc/*deploy.sh | sort -V`; do
     $i $1
     if [ $? != $SUCCESS ]
     then
       log "Failed Custom Script $i"	   
       exitProgram
     fi
	 log "custom script succeeded: $i"
    done
	log "All custom scripts passed"		
}

###Configure S3 Store if S3 store is enabled###
configure_S3_Store()
{
  if [ $S3_STORE_ENABLE ]
   then	
    log "create S3 Store Type Object"
    isS3StoreTypeObjectCreated=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config CreateS3StoreTypeObject $DOCBASE_NAME.$SERVER_CONFIG_NAME $INSTALL_OWNER "" $S3_STORE_NAME $S3_STORE_BASE_URL $S3_STORE_CREDENTIAL_ID $S3_STORE_CREDENTIAL_KEY $S3_STORE_DEFAULT $S3_STORE_PROXY_HOST $S3_STORE_PROXY_PORT $S3_STORE_ISWORM $S3_STORE_VENDOR  $S3_STORE_REGION $S3_STORE_UPDATE $S3_STORE_PROXY_HOST_UPDATE $S3_STORE_PROXY_PORT_UPDATE $S3_STORE_LIST_UPDATE ) 
                                                                                                                                            
    if [[ "$isS3StoreTypeObjectCreated" = *"S3StoreTypeObjectCreated"* ]]	
	   then
		log "The Utility CreateS3StoreTypeObjectS3 Store Type dm_s3_store Object created Successfully"
    else
        log "The Utility CreateS3StoreTypeObjectS3 failed to create S3 Store Type Object."
    fi  
  fi
}


###Configure rest Store if rest store is enabled###
configure_rest_Store()
{
	
	if [ $REST_STORE_ENABLE ]
	then
		log "create REST Store Type Object"
		
		if [ $GCP_STORE_ENABLE = "true" ]
		then
			if [ "${IS_VAULT_ENABLED}" = "true" ]
			then
				isRestStoreTypeObjectCreated=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config CreateRestStoreTypeObject $DOCBASE_NAME.$SERVER_CONFIG_NAME $INSTALL_OWNER "" $REST_STORE_NAME $REST_STORE_BASE_URL $GCP_STORE_CREDENTIALS $DSIS_URL 'GCPStore' $REST_STORE_DEFAULT  )
			else
				rest_store_file_loc='/tmp/'
				jsonfileext='.json'			
				rest_store_file_loc="${rest_store_file_loc}${REST_STORE_NAME}${jsonfileext}"

				log "$rest_store_file_loc"
				echo $GCP_STORE_CREDENTIALS > $rest_store_file_loc			
				
				isRestStoreTypeObjectCreated=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config CreateRestStoreTypeObject $DOCBASE_NAME $INSTALL_OWNER "" $REST_STORE_NAME $REST_STORE_BASE_URL 'OBJECT_ID' $rest_store_file_loc 'GCPStore' $REST_STORE_DEFAULT  )
			fi
		else
			isRestStoreTypeObjectCreated=$( java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config CreateRestStoreTypeObject $DOCBASE_NAME $INSTALL_OWNER "" $REST_STORE_NAME $REST_STORE_BASE_URL $REST_STORE_CREDENTIAL_ID $REST_STORE_CREDENTIAL_KEY 'AzureBlob' $REST_STORE_DEFAULT $DSIS_URL )
		fi

		if [[ "$isRestStoreTypeObjectCreated" = *"RestStoreTypeObjectCreated"* ]]	
		then
			log "The Utility CreateRestStoreTypeObject Store Type dm_Rest_store Object created Successfully"
		else
			if [[ "$isRestStoreTypeObjectCreated" = *"RestStoreTypeObjectCreatedWithWarn"* ]]
			then
				log "The Utility CreateRestStoreTypeObject Store Type dm_Rest_store Object created with WARNINGS"
			else				
				log "The Utility CreateRestStoreTypeObject failed to create REST Store Type Object."
			fi
		fi
	fi
}

###Configure email ###
configure_email()
{
  if [ $CONFIGURE_EMAIL ]
		then
		#create DQL query and save to temporary file.
		email_config="emailconfig.txt"
		echo -e "update dm_server_config object set smtp_server = '$SMTP_SERVER'\ngo" >> $email_config
		echo -e "update dm_user object set user_address='$EMAIL_ADDRESS' where user_name='$INSTALL_OWNER'\ngo" >> $email_config
		#execute DQL query.
		exit_status=$($DM_HOME/bin/idql $DOCBASE_NAME -U$INSTALL_OWNER -P"" -R$email_config)
		if [[ $exit_status == *"objects_updated"* ]]	
			then
				log "email configuration updated succesfully."
			else
				log "email configuration update failed."
		fi
		#remove temp file  
		rm $email_config
		log "Executing the SMTPConfig.ebs script."
		source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f ${DM_HOME}/install/admin/SMTPConfig.ebs -e Install -P ${DOCBASE_NAME}.${SERVER_CONFIG_NAME} ${INSTALL_OWNER} ""  "${SMTP_SERVER}" "${SMTP_PORT}" "${SMTP_AUTH}" "${SMTP_USER}" "${SMTP_PASS}" "${SMTP_SSL}" > ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/SMTPConfig.out; 
		log "Updating SMTP Server in config file"
		echo "set mta=smtp://$SMTP_SERVER" | sudo tee -a /etc/s-nail.rc
		echo "set from=$EMAIL_ADDRESS" | sudo tee -a /etc/s-nail.rc
  fi
}

check_cs_shutdown_status()
{
	init_file=$1
	count=1	
	while true
	 do
		ps -ef | grep "documentum -docbase_name $DOCBASE_NAME" | grep -i "init_file ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/$init_file" |grep -v grep > /dev/null
		status=$?
		if [  $status = 1 ]; then
			 ### repository and all child processes have been shutdown
			 break
		fi
		log "Waiting for shutdown of repository ....."
		count=`expr $count + 1`
		if [ $count -gt 300 ]
         then
          log "failed to shutdown the repository"
		  exitProgram
        fi
		sleep 1
	  done
}

upgradeCS()
{
	containername=$CONTAINER_NAME
	containerlength=${#containername}
	index=`expr $containerlength + 2`
	host_index=`expr substr $hostname $index 1`
	cryptoALg=`expr substr $AEK_ALGORITHM 1 3`
	cryptoKeySize=`expr substr $AEK_ALGORITHM 5 3`
	cryptomode=${cryptoALg}${cryptoKeySize}_RSA2048_SHA3_384
	
	log "==============================================================================================="
	log "[upgradeCS] ==>> upgradeCS function called to CS"
	log "[upgradeCS] ==>> Container name ${CONTAINER_NAME}"
	log "==============================================================================================="
    if [ $host_index = 0 ]
	then
		CURRENT_CS_VERSION=`cat  ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME} |grep DM_HOME_CURRENT=| awk 'BEGIN{FS="/"} {print $5}'`
		log "[upgradeCS] ==>> Current CS version ${CURRENT_CS_VERSION}"
		log "[upgradeCS] ==>> Upgraded CS version ${PRODUCT_MAJOR_VERSION}"

		if [ "$CURRENT_CS_VERSION" != "$PRODUCT_MAJOR_VERSION" ]
		then
		    rm -f ${DOCUMENTUM}/kube/custom-script-success
			rm -rf ${DOCUMENTUM}/kube/Docbase-Upgraded$PRODUCT_MAJOR_VERSION
			touch -f ${DOCUMENTUM}/kube/upgradeInitiated$PRODUCT_MAJOR_VERSION
			sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}
			sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_shutdown_${DOCBASE_NAME}
			sed -i -e "s/DM_SERVER_VERSION=.*/DM_SERVER_VERSION=$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}
			sed -i -e "s/crypto_mode =.*/crypto_mode = $cryptomode/"  ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server.ini
			sed -i -e "s/crypto_lockbox = lockbox.lb//"  ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server.ini
			\cp -f ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME} ${DOCUMENTUM}/kube/dba/dm_start_${DOCBASE_NAME} 
			\cp -f ${DOCUMENTUM}/dba/dm_shutdown_${DOCBASE_NAME} ${DOCUMENTUM}/kube/dba/dm_shutdown_${DOCBASE_NAME}
			if [ "$CONFIGURE_THUMBNAIL_SERVER" = "true" ]
			then
				sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"  ${DM_HOME}/thumbsrv/container/webapps/thumbsrv/WEB-INF/web.xml
				sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"   ${DM_HOME}/thumbsrv/conf/user.dat
			fi
			#remove old keystore
	        #rm -rf ${DOCUMENTUM}/config/dfc.keystore
		fi
	else
		CURRENT_CS_VERSION=`cat ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}_dm_$DOCBASE_NAME |grep DM_HOME_CURRENT=| awk 'BEGIN{FS="/"} {print $5}'`
		log "[upgradeCS] ==>> Current CS version ${CURRENT_CS_VERSION}"
		log "[upgradeCS] ==>> Upgraded CS version ${PRODUCT_MAJOR_VERSION}"

		if [ "$CURRENT_CS_VERSION" != "$PRODUCT_MAJOR_VERSION" ]
		then
			touch -f ${DOCUMENTUM}/kube/upgradeInitiated$PRODUCT_MAJOR_VERSION
			rm -f ${DOCUMENTUM}/kube/custom-script-success
			sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}_dm_${DOCBASE_NAME}
			sed -i -e "s/DM_SERVER_VERSION=.*/DM_SERVER_VERSION=$PRODUCT_MAJOR_VERSION/"   ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}_dm_${DOCBASE_NAME}
			sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_shutdown_${DOCBASE_NAME}_dm_${DOCBASE_NAME}
			sed -i -e "s/crypto_lockbox = lockbox.lb//"  ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server_${SERVER_CONFIG_NAME}.ini
			sed -i -e "s/crypto_mode =.*/crypto_mode = $cryptomode/"  ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server_${SERVER_CONFIG_NAME}.ini
			\cp -f ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}_dm_${DOCBASE_NAME} ${DOCUMENTUM}/kube/dba/dm_start_${DOCBASE_NAME}_dm_${DOCBASE_NAME}
			\cp -f ${DOCUMENTUM}/dba/dm_shutdown_${DOCBASE_NAME}_dm_${DOCBASE_NAME} ${DOCUMENTUM}/kube/dba/dm_shutdown_${DOCBASE_NAME}_dm_${DOCBASE_NAME}
			if [ "$CONFIGURE_THUMBNAIL_SERVER" = "true" ]
			then
				sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"  ${DM_HOME}/thumbsrv/container/webapps/thumbsrv/WEB-INF/web.xml
				sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"   ${DM_HOME}/thumbsrv/conf/user.dat
			fi
			#remove old keystore
	        #rm -rf ${DOCUMENTUM}/config/dfc.keystore
		fi
	fi
	log "==============================================================================================="
	log "[upgradeCS] ==>> Container name ${CONTAINER_NAME}"
	log "[upgradeCS] ==>> CS upgrade finished"
	log "==============================================================================================="
}

prepareCertUpgrade()
{
	#update dfc.properties to set dfc.session.secure_connect_default to try_native_first
	if [ -n "$SET_TRY_NATIVE_FIRST" ] && [ "$SET_TRY_NATIVE_FIRST" == "true" ]
	then		
		sed -i -e "s/dfc.session.secure_connect_default=.*/dfc.session.secure_connect_default=try_native_first/" ${DOCUMENTUM}/config/dfc.properties
		log "setting dfc.session.secure_connect_default to try_native_first"
	fi
}

upgradeDbr()
{
	sed -i -e "s/DM_SERVER_VERSION=.*/DM_SERVER_VERSION=$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_launch_Docbroker
	sed -i -e "s/DM_SERVER_VERSION=.*/DM_SERVER_VERSION=$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_launch_extDocbroker
	sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_launch_Docbroker
	sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_launch_extDocbroker
	sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_stop_Docbroker
	sed -i -e "s/$CURRENT_CS_VERSION/$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_stop_extDocbroker
	\cp -f ${DOCUMENTUM}/dba/dm_stop_extDocbroker ${DOCUMENTUM}/kube/dba/dm_stop_extDocbroker
	\cp -f  ${DOCUMENTUM}/dba/dm_stop_Docbroker ${DOCUMENTUM}/kube/dba/dm_stop_Docbroker
	\cp -f ${DOCUMENTUM}/dba/dm_launch_extDocbroker ${DOCUMENTUM}/kube/dba/dm_launch_extDocbroker
	\cp -f  ${DOCUMENTUM}/dba/dm_launch_Docbroker ${DOCUMENTUM}/kube/dba/dm_launch_Docbroker
	
}

#Migration of data and dba
migrateDBA()
{
	log "Copying dba files" 
	rm -rf  /opt/dctm/migdba/dba/config/${DOCBASE_NAME}/*.ebs
	cp -R /opt/dctm/migdba/dba/* ${DOCUMENTUM}/dba/
	
	log "Changing permissions"
	
	chown -R ${INSTALL_OWNER}:${INSTALL_OWNER} ${DOCUMENTUM}/dba/*
	chmod -R 775 ${DOCUMENTUM}/dba/*
	
	log " copy dfc.properties"
	add_docbroker_to_dfcproperties
	log "Generate method server files"
    generate_method_server_config
	
	
    
	
}

#Start docbase
startDocbase()
{
	log "Start docbase" 
	
	if [ "${AEK_LOCATION}" = "Local" ]
	then
		source $DM_HOME/bin/dm_set_server_env.sh; dm_crypto_boot -passphrase $AEK_PASSPHRASE -all
	fi
	
	cd $DM_HOME_CURRENT/bin/; source $DM_HOME/bin/dm_set_server_env.sh; documentum -docbase_name $DOCBASE_NAME -security acl -init_file /opt/dctm/dba/config/${DOCBASE_NAME}/server.ini &
	
}
#Stop docbase
stopDocbase()
{
	log "Stop docbase" 
	cd $DM_HOME_CURRENT/bin/; source $DM_HOME/bin/dm_set_server_env.sh;echo \"shutdown,c,T,T\nexit\" | iapi ${DOCBASE_NAME} -U${INSTALL_OWNER} -P -e
	sleep 2m
	
}
#Adding dfc.properties
add_docbroker_to_dfcproperties()
{
	cp -R /opt/dctm/migdba/config/* ${DOCUMENTUM}/config/
	
	sed -i -e '/dfc.docbroker.host/d' ${DOCUMENTUM}/config/dfc.properties
	sed -i -e '/dfc.docbroker.port/d' ${DOCUMENTUM}/config/dfc.properties
	sed -i -e "s/dfc.session.secure_connect_default=.*/dfc.session.secure_connect_default=try_secure_first/"  ${DOCUMENTUM}/config/dfc.properties
	sed -i -e "s/dfc.crypto.repository=.*/dfc.crypto.repository=$DOCBASE_NAME/"  ${DOCUMENTUM}/config/dfc.properties
	sed -i -e "s/dfc.globalregistry.repository=.*/dfc.globalregistry.repository=$DOCBASE_NAME/"  ${DOCUMENTUM}/config/dfc.properties
	sed -i -e "s/dfc.data.dir=.*/dfc.data.dir=\/opt\/dctm/"  ${DOCUMENTUM}/config/dfc.properties
	sed -i -e "s/dfc.tokenstorage.dir=.*/dfc.tokenstorage.dir=\/opt\/dctm\/apptocken/"  ${DOCUMENTUM}/config/dfc.properties
	
	log "Adding all docbroker hosts in dfc.properties"
	count=0		
	while [ $count -lt $DOCBROKERS_COUNT ]
	do
		client_docbroker_host=$DOCBROKER_SERVICE_NAME-$count.$DOCBROKER_SERVICE_NAME.$DOCBROKER_CLUSTER_SPACE			
		log "client_docbroker_host $client_docbroker_host"
		echo dfc.docbroker.host[$count]= $client_docbroker_host >> ${DOCUMENTUM}/config/dfc.properties
		echo dfc.docbroker.port[$count]= $DOCBROKER_PORT >> ${DOCUMENTUM}/config/dfc.properties
		count=`expr $count + 1`
	done
	
	chown -R ${INSTALL_OWNER}:${INSTALL_OWNER} ${DOCUMENTUM}/config/*
	chmod -R 775 ${DOCUMENTUM}/config/*
	
	sed -i -e "s/appender.F1.fileName=.*/appender.F1.fileName=\/opt\/dctm\/logs\/log4j.log/" ${DOCUMENTUM}/config/log4j2.properties
	sed -i -e "s/appender.FILE_TRACE.fileName=.*/appender.FILE_TRACE.fileName=\/opt\/dctm\/logs\/trace.log/" ${DOCUMENTUM}/config/log4j2.properties
	sed -i -e "s/property.filename=.*/property.filename=\/opt\/dctm/" ${DOCUMENTUM}/config/log4j2.properties
	chown -R ${INSTALL_OWNER}:${INSTALL_OWNER} ${DOCUMENTUM}/config/log4j2.properties
	chmod -R 775 ${DOCUMENTUM}/config/log4j2.properties
}

generate_method_server_config()
{   
	log "Generating acs.properties"
	echo "repository.name=${DOCBASE_NAME}.${DOCBASE_NAME}" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	echo "repository.login=$INSTALL_OWNER" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	echo "primary.content.store.root=/opt/dctm/acsCache" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	
	echo "primary.content.store.quota=1000M" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	echo "jms.url=tcp\://${HOSTNAME}\:9084" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	echo "repository.acsconfig=${CONTAINER_NAME}-0.${CONTAINER_NAME}.${DOCBROKER_CLUSTER_SPACE}ACS1" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	chown $INSTALL_OWNER:$INSTALL_OWNER ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	chmod 6640 ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/config/acs.properties
	log "Copy dfc.properties"
	cp ${DOCUMENTUM}/config/dfc.properties ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/dfc.properties
	cp ${DOCUMENTUM}/config/log4j2.properties ${DM_HOME}/install/composer/ComposerHeadless/plugins/com.emc.ide.external.dfc_1.0.0/documentum.config/log4j2.properties
	
	log "Updating web.xml with docbase"
	sed -i -e "s/<load-on-startup>/<init-param>\n\t<param-name>docbase-$DOCBASE_NAME<\/param-name>\n\t<param-value>$DOCBASE_NAME<\/param-value>\n<\/init-param>\n<load-on-startup>/"  ${DOCUMENTUM}/$TOMCAT/webapps/DmMethods/WEB-INF/web.xml
	chown $INSTALL_OWNER:$INSTALL_OWNER ${DOCUMENTUM}/$TOMCAT/webapps/DmMethods/WEB-INF/web.xml
	chmod 6640 ${DOCUMENTUM}/$TOMCAT/webapps/DmMethods/WEB-INF/web.xml
	
}
#Update server.ini, startup and shutdown scripts for migration
migrateScripts()
{
	log "Update server.ini files"
	sed -i -e "s/service =.*/service = dm_$DOCBASE_NAME/"  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini
	sed -i -e "s/database_conn =.*/database_conn = $DATABASE_SERVICE_NAME/"  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini
	sed -i -e "s/database_password_file =.*/database_password_file = \/opt\/dctm\/dba\/config\/$DOCBASE_NAME\/dbpasswd.txt/"  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini
	sed -i -e "s/root_secure_validator =.*/root_secure_validator = \/opt\/dctm\/dba\/dm_check_password/"  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini
	sed -i -e "s/install_owner =.*/install_owner = $INSTALL_OWNER/"  ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini
	#need to clear the old entires of dbr
	sed -i -e '/DOCBROKER_PROJECTION_TARGET/,$d' ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini
	
	sed -i -e "s/source_database_connection=.*/source_database_connection=jdbc:postgresql:\/\/hostname\/database/"  $DOCUMENTUM/dba/config/${DOCBASE_NAME}/webcache.ini
	sed -i -e "s/JDBC_DRIVER=.*/JDBC_DRIVER=org.postgresql.Driver/"  $DOCUMENTUM/dba/config/${DOCBASE_NAME}/webcache.ini
	chmod 775  $DOCUMENTUM/dba/config/${DOCBASE_NAME}/webcache.ini	
	chown $INSTALL_OWNER:$INSTALL_OWNER   $DOCUMENTUM/dba/config/${DOCBASE_NAME}/webcache.ini		
	add_docbroker_to_serverini
	#rm -rf ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}
	
	startupfile="${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}"		
	if [ -f "$startupfile" ]
	then
		log "Startup file already exist"
		#updating the old env paths to docker paths
		sed -i -e "s/init_file .*server.ini/init_file \/opt\/dctm\/dba\/config\/$DOCBASE_NAME\/server.ini/"  ${DOCUMENTUM}/dba/dm_start_$DOCBASE_NAME
		sed -i -e "s/DM_HOME_CURRENT=.*/DM_HOME_CURRENT=\/opt\/dctm\/product\/$PRODUCT_MAJOR_VERSION/"  ${DOCUMENTUM}/dba/dm_start_$DOCBASE_NAME
		sed -i -e "s/DM_DBA=.*/DM_DBA=\/opt\/dctm\/dba/"  ${DOCUMENTUM}/dba/dm_start_$DOCBASE_NAME

	else
		echo "cd $DM_HOME/bin" >> ${DOCUMENTUM}/dba/dm_start_$DOCBASE_NAME
		echo "source $DM_HOME/bin/dm_set_server_env.sh" >> ${DOCUMENTUM}/dba/dm_start_$DOCBASE_NAME
		echo "./documentum -docbase_name $DOCBASE_NAME -security acl -init_file $DOCUMENTUM/dba/config/${DOCBASE_NAME}/server.ini $@ >> $DOCUMENTUM/dba/log/${DOCBASE_NAME}.log 2>&1 &" >> ${DOCUMENTUM}/dba/dm_start_$DOCBASE_NAME
	fi
	touch -f ${DOCUMENTUM}/dba/dm_shutdown_$DOCBASE_NAME
	chmod 775 ${DOCUMENTUM}/dba/dm_start_$DOCBASE_NAME
	chmod 775 ${DOCUMENTUM}/dba/dm_shutdown_$DOCBASE_NAME
	log "Changing permistions to modified files"
	chmod 775 ${DOCUMENTUM}/dba/config/$DOCBASE_NAME/server.ini
}


upgradeDars()
{
    log "==========================Upgrading  Dars initiated=========================================="

	# Mark the DAR Script upgrade process completion. Readiness scripts relies on this file to mark the rediness of the environment
	# If the file is not present which means the DAR upgrade is completed successfully 
	darUpgradeInitiated=${DOCUMENTUM}/kube/darUpgradeInitiated$PRODUCT_MAJOR_VERSION
	touch -f $darUpgradeInitiated

	touch -f ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/tempdar.log
	mv ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dars.log ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dars.log.bck
	tempdarlogs=${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/tempdar.log
	
	passwordForDar=$INSTALL_OWNER_PASSWORD
	if [ "${IS_VAULT_ENABLED}" = "true" ]
	then
		passwordForDar=$installOwnerPwd
	fi

	log "Creating temp dfc.properties with dfc.bof.cache.enable_preload=false for dar installation"
	echo "#include ${DOCUMENTUM}/config/dfc.properties" >> ${DM_DOCKER_HOME}/dfc.properties
	echo "dfc.bof.cache.enable_preload=false" >> ${DM_DOCKER_HOME}/dfc.properties
	for darFile in ${DOCUMENTUM}/product/${PRODUCT_MAJOR_VERSION}/install/DARsInternal/*; do
		log "...................................................................................."
		log "Upgrading  Dar $darFile started..."

		java $JVM_OPTS -Ddfc.properties.file=${DM_DOCKER_HOME}/dfc.properties -Ddar="$darFile" -Dlogpath=$tempdarlogs -Ddocbase=$DOCBASE_NAME -Duser=$INSTALL_OWNER -Dpassword=$passwordForDar -Ddomain= -cp $DM_HOME/install/composer/ComposerHeadless/startup.jar org.eclipse.equinox.launcher.Main -data $DM_HOME/install/composer/workspace -application org.eclipse.ant.core.antRunner -buildfile $DM_HOME/install/composer/deploy.xml > $tempdarlogs

		# Based on the DAR file execution status, the upgrade process will be continued or terminated. In case of failure, the installation is terminated and execution log is printed to the console/container's log to show the cause of failure. This will help in avoiding the futher scripts failures and prevent to provide an unstable environment.
		if [ $? -eq $SUCCESS ];
		then
			cat $tempdarlogs >> ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dars.log
			log "$darFile upgrade completed....................................."
			log "................................................................................."
		else
			log "ERROR: $darFile failed. Please check the log file at container's ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dars.log and install failed dars manually"
			cat $tempdarlogs >> ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/dars.log
			#printing the errored dar file output stream to console
			log "................................................................................."
			log "Upgrading $darFile.dar failed...."
			cat $tempdarlogs
			rm -f $tempdarlogs
			log "................................................................................."
			exitProgram
		fi
	done

	# Removing the file as the all the DARs are upgraded successfully
	rm -f ${DM_DOCKER_HOME}/dfc.properties
	rm -f $darUpgradeInitiated
	rm -f $tempdarlogs
    log "All Dar files upgrade completed"
    log "............................................................................."
}

upgradeDocbase()
{
	log "Upgrading Docbase initiated...."

    log "Licensing: Enabling privilege for OTDSAuthentication"
	cd /opt/dctm_docker; javac -encoding UTF-8 -cp .:$DM_JMS_HOME/webapps/DmMethods/WEB-INF/lib/dfc.jar com/documentum/ijms/IJMSConfigurator.java

	approve_privilege=$( java $JVM_OPTS -cp $DM_JMS_HOME/webapps/OTDSAuthentication/WEB-INF/classes/:$DM_JMS_HOME/webapps/DmMethods/WEB-INF/lib/*:. com/documentum/ijms/IJMSConfigurator approve_privilege $DOCBASE_NAME $INSTALL_OWNER_USER $INSTALL_OWNER_PASSWORD $DM_JMS_HOME/webapps/OTDSAuthentication/WEB-INF/classes/)
	log "approve privilege for OTDSAuthentication $approve_privilege"
	if [ $? != $SUCCESS ]
	then
		log "Failed to approve OTDSAuthentication as privileged client"	
	fi

	cshostname=`hostname`
	logPath=${DOCUMENTUM}/dba/config/${DOCBASE_NAME}

	# File helps to determine the EBS Script upgrade completion and is used by the readiness script. 
	ebsUpgradeInitiated=${DOCUMENTUM}/kube/ebsUpgradeInitiated$PRODUCT_MAJOR_VERSION
	touch -f $ebsUpgradeInitiated

	log "Executing the headstart.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/headstart.ebs ${DM_HOME}/install/admin/headstart2.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" "" "${DM_HOME}" "${DOCUMENTUM}/data" "${DOCUMENTUM}/dba" "${DM_HOME}/install" "${DOCUMENTUM}/share" "${DOCUMENTUM}/fulltext" ${cshostname} Linux en "localhost" "test@localhost.com" "${INSTALL_OWNER}" "dual" 9080 "" FALSE dsearch -e Install >${logPath}/headstart.out; 
	validateEBSError headstart
	
	log "Executing the dm_apply_formats.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/bin/dm_apply_formats.ebs -P noreport ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" "${DM_HOME}/install/tools/formats.csv" trace -e testmain > ${logPath}/dm_apply_formats.out; 
	validateEBSError dm_apply_formats
	log "Executing the dm_cas_install.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dm_cas_install.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" "${DM_HOME}" Linux -e Entry_Point > ${logPath}/dm_cas_install.out; 
	validateEBSError dm_cas_install
	log "Executing the csec_plugin.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/csec_plugin.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ""  "${DM_HOME}" Linux -e Install > ${logPath}/csec_plugin.out; 
	validateEBSError csec_plugin
	log "Executing the dm_routerConv_install.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dm_routerConv_install.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ""  NONE -e Install > ${logPath}/dm_routerConv_install.out; 
	validateEBSError dm_routerConv_install
	log "Executing the templates.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/templates.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" "${DM_HOME}" "${DM_HOME}/install" -e Install > ${logPath}/templates.out; 
	validateEBSError templates
	log "Executing the replicate_bootstrap.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/bin/replicate_bootstrap.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME}  "${DM_HOME}/bin" FALSE -e rmain > ${logPath}/replicate_bootstrap.out; 
	validateEBSError replicate_bootstrap
	log "Executing the desktop_client.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/desktop_client/desktop_client.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" "${DM_HOME}" -e EntryPoint > ${logPath}/desktop_client.out; 
	validateEBSError desktop_client
	log "Executing the disable_fulltext_jobs.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/disable_fulltext_jobs.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" -e Install > ${logPath}/disable_fulltext_jobs.out; 
	validateEBSError disable_fulltext_jobs
	log "Executing the dfc.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dfc.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" -e Install > ${logPath}/dfc.out; 
	validateEBSError dfc
	log "Executing the dfc_javadbexpr.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dfc_javadbexpr.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" -e EntryPoint > ${logPath}/dfc_javadbexpr.out; 
	validateEBSError dfc_javadbexpr
	log "Executing the dm_bpmmodules_install.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dm_bpmmodules_install.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" ${DM_HOME}/lib -e Install > ${logPath}/dm_bpmmodules_install.out;
	validateEBSError dm_bpmmodules_install
	log "Executing the createMethodServerObject.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/createMethodServerObject.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" -e EntryPoint > ${logPath}/createMethodServerObject.out; 
	validateEBSError createMethodServerObject
	log "Executing the csec_plugin_upgrade_53.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/csec_plugin_upgrade_53.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" "${DM_HOME}" Linux -e Install > ${logPath}/csec_plugin_upgrade_53.out; 
	validateEBSError csec_plugin_upgrade_53
	log "Executing the toolset.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/toolset.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} "${DM_HOME}/install/admin" ${cshostname}  -e ToolSetup > ${logPath}/applyadmin.out; 
	validateEBSError applyadmin
	log "Executing the dm_bpm_install.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dm_bpm_install.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ""  -e Install > ${logPath}/dm_bpm_install.out; 
	validateEBSError dm_bpm_install
	log "Executing the dm_wfTimer_upgrade.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dm_wfTimer_upgrade.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ""  -e Install > ${logPath}/dm_wfTimer_upgrade.out; 
	validateEBSError dm_wfTimer_upgrade
	log "Executing the create_fulltext_objects.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/create_fulltext_objects.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ""  dsearch -e Install > ${logPath}/create_fulltext_objects.out; 
	validateEBSError create_fulltext_objects
	log "Executing the dm_ldap_install.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dm_ldap_install.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} "${DM_HOME}/bin"  -e Install > ${logPath}/dm_ldap_install.out; 
	validateEBSError dm_ldap_install
	log "Executing the dm_storageservices_install.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dm_storageservices_install.ebs -e Install -- ${DOCBASE_NAME}.${DOCBASE_NAME} "${DM_HOME}/bin"  T > ${logPath}/dm_storageservices_install.out; 
	validateEBSError dm_storageservices_install
	log "Executing the dm_emailTemplate_install.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dm_emailTemplate_install.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ""  -e Install > ${logPath}/dm_emailTemplate_install.out;
	validateEBSError dm_emailTemplate_install
	log "Executing the dm_xml_install.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/admin/dm_xml_install.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ""  -e Install > ${logPath}/dm_xml_install.out;
	validateEBSError dm_xml_install
	log "Executing the dm_gwm_install.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic    -f ${DM_HOME}/bin/dm_gwm_install.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} "${INSTALL_OWNER}" "${DM_HOME}/bin" -e Install > ${logPath}/dm_gwm_install.out;
	validateEBSError dm_gwm_install
	log "Executing the upgrade_java_methods_51.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic    -f ${DM_HOME}/install/tools/upgrade_java_methods_51.ebs  -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ""  -e UpgradeMethods > ${logPath}/dm_java_methods.out;
	validateEBSError dm_java_methods
	log "Executing the ci_schema_install.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic    -f ${DM_HOME}/install/tools/ci_schema_install.ebs  -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ""  -e EntryPoint > ${logPath}/ci_schema_install.out;
	validateEBSError ci_schema_install
	log "Executing the display_config_setup.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/tools/display_config_setup.ebs   -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" -e EntryPoint > ${logPath}/display_config_setup.out;
	validateEBSError display_config_setup
	log "Executing the offline_config_setup.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic     -f ${DM_HOME}/install/tools/offline_config_setup.ebs   -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} ""  -e EntryPoint > ${logPath}/offline_config_setup.out;
	validateEBSError offline_config_setup
	log "Executing the dm_archiveserver_upgrade.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic   -f ${DM_HOME}/install/admin/dm_archiveserver_upgrade.ebs  -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" -e Entry_Point > ${logPath}/dm_archiveserver_upgrade.out;
	validateEBSError dm_archiveserver_upgrade
	
	localefile="$DOCUMENTUM/data/available_locales"	
		
	if [ -f "$localefile" ]
	then
	  log "localefile already present"
	else
	  log "localefile not present. So assuming pre 22.1 upgrade scenario"
	  echo "en" >> $DOCUMENTUM/data/available_locales
	fi
	
	upgradeDars
	dd_Populate
	
	log "Executing the dm_defaultevent_set.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f ${DM_HOME}/install/admin/dm_defaultevent_set.ebs -P ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" -e Install > ${logPath}/dm_defaultevent_set.out;
	validateEBSError dm_defaultevent_set
	#log "Executing the dm_jms_config_setup.ebs script."
	#source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f ${DM_HOME}/install/admin/dm_jms_config_setup.ebs -e install -- ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" ${hostname} 9080 > ${logPath}/dm_jms_config_setup.out;
	#validateEBSError dm_jms_config_setup
	log "Executing the dm_gr_config.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f ${DM_HOME}/install/admin/dm_gr_config.ebs -e Install -- ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" > ${logPath}/dm_gr_config.out
	validateEBSError dm_gr_config
	log "Executing the javaAdminMethodInstall.ebs script."
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic  -f ${DM_HOME}/install/admin/javaAdminMethodInstall.ebs -e EntryPoint -- ${DOCBASE_NAME}.${DOCBASE_NAME} ${INSTALL_OWNER} "" > ${logPath}/javaAdminMethodInstall.out;
	validateEBSError javaAdminMethodInstall
	# Run the ebs script for external user
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f dm_extuser_table.ebs -p${DOCBASE_NAME}.${DOCBASE_NAME} -p${INSTALL_OWNER} -p"" -eCreateExtTable > ${logPath}/dm_extuser_table_create_table.out;
	source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f dm_extuser_table.ebs -p${DOCBASE_NAME}.${DOCBASE_NAME} -p${INSTALL_OWNER} -p"" -eRegisterExtTable  > ${logPath}/dm_extuser_table_register_table.out;

	# Removing the ${DOCUMENTUM}/kube/ebsUpgradeInitiated$PRODUCT_MAJOR_VERSION file, so that readiness script 
	# undesrtands the EBS upgrade is completed
	rm -f $ebsUpgradeInitiated
}

validateEBSError()
{
	# For replicate_bootstrap.ebs script the SUCCESSFUL status is determined by exit code "1" and for others "0". Even Installer handles this manner
	# The script can be fixed later to formalize the exit codes

	execStatus=$?

	if [ $execStatus -eq $SUCCESS ] && [ "$1" != "replicate_bootstrap" ]
    then
		log "The {$1} script has completed successfully"
           
    elif [ $execStatus -eq $FAILURE ] && [ "$1" = "replicate_bootstrap" ]
    then
		log "The {$1} script has completed successfully"
    else
		log "=================================================================================="
        log "ERROR: The $1 script has failed. Please check $1.out file at container's ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/$1.out. and run it manually"
		cat ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/$1.out
		log "=================================================================================="
		exitProgram
    fi
	log "............................................................................."
}

dd_Populate_opr()
{
      CS_Locale_Name=$(echo $CS_LOCALE_NAME | tr '[:upper:]' '[:lower:]')
	  log "The data dictionary populate for the locale $CS_Locale_Name"
	  #checking whether the locale is specified during the invocation, else we make use of en as default.
	if [ "x$CS_Locale_Name" !=  "x" ] 
        then
		 # Section 1: Run SQL query to populate data
		rm -rf /tmp/mip_dd_populate.sql
		rm -rf /tmp/mip_dd_populate_objects.out

		echo "select i_attr_def from dmc_aspect_type_sv where object_name='miplabelinfo';" >> /tmp/mip_dd_populate.sql
		chmod 775 /tmp/mip_dd_populate.sql

		# Determine the correct database owner
		DOCBASE_OWNER_EX=`cat ${DOCUMENTUM}/dba/config/${DOCBASE_NAME}/server.ini | grep database_owner | awk '{print $3}'`
		echo $DOCBASE_OWNER_EX

		if [ "${IS_VAULT_ENABLED}" = "true" ]; 
		then		
			DOCBASE_PASSWORD=$(curl "$DSIS_URL/secret/$DOCBASE_PASSWORD")  
			if [ -z "$DOCBASE_PASSWORD" ]; 
			then  
				log "DATABASE_PASSWORD is empty,cannot extract mip aspect and populate data dictionary for mip "
				return  
			fi
		fi

		# Execute SQL command based on DB_TYPE (oracle or postgres)
		if [ "$DB_TYPE" = "oracle" ]; then
			sqlplus "${DOCBASE_NAME}/$DOCBASE_PASSWORD@${DATABASE_HOST}/${DATABASE_SERVICE_NAME}" @/tmp/mip_dd_populate.sql >> /tmp/mip_dd_populate_objects.out
		else
			PGPASSWORD="$DOCBASE_PASSWORD" psql -h "${DATABASE_HOST}" -d "dm_${DOCBASE_NAME}_docbase" -U "${DOCBASE_OWNER_EX}" -a -f /tmp/mip_dd_populate.sql >> /tmp/mip_dd_populate_objects.out
		fi

		if [ $? -eq $SUCCESS ]; then
			log "Extracted mip aspect type successfully"
		else
			log "Extraction of mip aspect type failed for docbase: $DOCBASE_NAME"
			log "Log file is /tmp/mip_dd_populate_objects.out"
		fi

		# Extracting the i_attr_def value from the SQL output
		TYPE=$(grep -o 'dmi_[0-9a-f]*' /tmp/mip_dd_populate_objects.out)

		# Set flag to check if TYPE was successfully extracted
		TYPE_EXTRACTED=false
		if [ -n "$TYPE" ]; then
			log "MIP Aspect type extracted: $TYPE"
			TYPE_EXTRACTED=true
			cp $DM_HOME/bin/data_dictionary_mip.ini $DOCUMENTUM/kube/data_dictionary_$DOCBASE_NAME.ini
			sed -i "s/data_dictionary_mip_en.txt/#data_dictionary_mip_en.txt/" $DOCUMENTUM/kube/data_dictionary_$DOCBASE_NAME.ini
		else
			cp $DOCUMENTUM/dba/config/$DOCBASE_NAME/data_dictionary.ini $DOCUMENTUM/kube/data_dictionary_$DOCBASE_NAME.ini
			sed -i "s/data_dictionary_en.txt/#data_dictionary_en.txt/" $DOCUMENTUM/kube/data_dictionary_$DOCBASE_NAME.ini
			log "MIP types/attributes will not be published in the data dictionary tables, as type retrieval failed"
		fi


		# Iterate through locales
		for locale in $(echo ${CS_Locale_Name} | sed "s/,/ /g")
		do
			if [ "$locale" = 'zh' ]; then
				chineseLocPresent='true'
			fi
			# Only perform TYPE replacement if TYPE was successfully extracted
			if [ "$TYPE_EXTRACTED" = "true" ]; then
				sed -i "s/#data_dictionary_mip_$locale.txt/data_dictionary_mip_$locale.txt/" $DOCUMENTUM/kube/data_dictionary_$DOCBASE_NAME.ini
				sed -i '/TYPE = miplabelinfo/s/TYPE = miplabelinfo/TYPE = '"$TYPE"'/' $DM_HOME/bin/data_dictionary_mip_$locale.txt
			else
				sed -i "s/#data_dictionary_$locale.txt/data_dictionary_$locale.txt/" $DOCUMENTUM/kube/data_dictionary_$DOCBASE_NAME.ini
			fi
		done

		 log "--------------------------------------------------------------------------------------"
		 log "Updated data dictionary file. Dumping the updated data dictionary file."
		 log "--------------------------------------------------------------------------------------"
		 cat $DOCUMENTUM/kube/data_dictionary_$DOCBASE_NAME.ini
		 log "--------------------------------------------------------------------------------------"
		 log "The data dictionary population script is running for the locale $CS_Locale_Name"
		 source $DM_HOME/bin/dm_set_server_env.sh; dmbasic -f $DM_HOME/bin/dd_populate.ebs -e Entry_Point -- $DOCBASE_NAME $INSTALL_OWNER "" $DOCUMENTUM/kube/data_dictionary_$DOCBASE_NAME.ini > $DOCUMENTUM/dba/config/$DOCBASE_NAME/dd_populate.out;
		 touch -f ${DOCUMENTUM}/data/available_locales_mip
         echo $CS_Locale_Name > $DOCUMENTUM/data/available_locales_mip
         if [ "$chineseLocPresent" != 'true' ]
		 then
			# Do validation only when chinese locale is not specified
			validateEBSError dd_populate
		 fi
		 rm -f $DOCUMENTUM/kube/data_dictionary_$DOCBASE_NAME.ini
	fi

}

dd_Populate()
{
	CS_Locale_Name=$(echo $CS_LOCALE_NAME | tr '[:upper:]' '[:lower:]')
	log "Invoking data dictionary populate script for locale $CS_Locale_Name"
	locale_installed="${DOCUMENTUM}/data/available_locales"
	mip_locale_installed="${DOCUMENTUM}/data/available_locales_mip"

	if [ ! -f "$mip_locale_installed" ] && [ -f "$locale_installed" ]; then
	    rm -rf $locale_installed
	fi
	if [ ! -f "$locale_installed" ]; 
	then
		dd_Populate_opr
		echo $CS_Locale_Name >> $DOCUMENTUM/data/available_locales
	else
		avail_locale=$(<$locale_installed)
		if [[ "$avail_locale" != "$CS_Locale_Name" ]]; then
			resultant_locale=""
			for locale in $(echo ${CS_Locale_Name} | sed "s/,/ /g")
			do
				exists=$(echo $avail_locale | grep -wc $locale)
				if [ $exists -eq 0 ]; then
					if [ "x$resultant_locale" != "x" ]; then
						resultant_locale="$resultant_locale,$locale"
					else
						resultant_locale="$locale"
					fi
				fi
			done
			if [ "x$resultant_locale" != "x" ]; then
				rm -f $locale_installed
				echo $avail_locale,$resultant_locale >> $DOCUMENTUM/data/available_locales
				CS_LOCALE_NAME=$resultant_locale
				dd_Populate_opr
			else
				log "Provided Locales $CS_LOCALE_NAME are already available in the docbase"
			fi
		fi
	fi
	#creating the marker file for having readiness and liveliness alive during data dictionary job
	touch -f ${DOCUMENTUM}/kube/available_locales 
}

handle_newrelic_java_agent_config_forJMS()
{
#echo "JAVA_OPTS=\"\$JAVA_OPTS -javaagent:${DM_DOCKER_HOME}/${NEWRELIC_JAVA_AGENT}/newrelic/newrelic.jar -Djboss.modules.system.pkgs=$JBOSS_MODULES_SYSTEM_PKGS,com.newrelic\"" >> ${DOCUMENTUM}/$TOMCAT/bin/standalone.conf
## update the newrelic.yml file with app_name, proxy and license key details
sed -i '$H;x;1,/  app_name: My Application/s/  app_name: My Application/OT_DCS_NEWRELIC_APP_NAME/;1d' ${DM_DOCKER_HOME}/${NEWRELIC_JAVA_AGENT}/newrelic/newrelic.yml
sed -i "s@OT_DCS_NEWRELIC_APP_NAME@  app_name: $NEWRELIC_APP_NAME@1g" ${DM_DOCKER_HOME}/${NEWRELIC_JAVA_AGENT}/newrelic/newrelic.yml
sed -i "s@license_key: '<%= license_key %>'@license_key: '$NEWRELIC_LICENSE_KEY'@" ${DM_DOCKER_HOME}/${NEWRELIC_JAVA_AGENT}/newrelic/newrelic.yml
sed -i "s@#proxy_host: hostname@proxy_host: $NEWRELIC_PROXY_HOST@" ${DM_DOCKER_HOME}/${NEWRELIC_JAVA_AGENT}/newrelic/newrelic.yml
sed -i "s@#proxy_port: 8080@proxy_port: $NEWRELIC_PROXY_PORT@" ${DM_DOCKER_HOME}/${NEWRELIC_JAVA_AGENT}/newrelic/newrelic.yml
#setting CATALINA_OPTS at begining of startMethodServer.sh with javaagent option.
JAVAAGENT_OPTION="-javaagent:${DM_DOCKER_HOME}/${NEWRELIC_JAVA_AGENT}/newrelic/newrelic.jar"
if [ "$JMS_MEM_SETTING" != "" ]
then
sed -i -e "s;CATALINA_OPTS=.*;CATALINA_OPTS=\"$JMS_MEM_SETTING $JAVAAGENT_OPTION\";" ${DOCUMENTUM}/$TOMCAT/bin/startMethodServer.sh
else
sed -i -e "s;CATALINA_OPTS=.*;CATALINA_OPTS=\"-Xms1024m -Xmx2048m $JAVAAGENT_OPTION\";" ${DOCUMENTUM}/$TOMCAT/bin/startMethodServer.sh
fi
}

handle_start_newrelic_c_agent()
{
   ##./newrelic-daemon -f -logfile daemon.log -loglevel debug --proxy http://bp2-prox01-l001.otxlab.net:3128 &
    log "Starting newrelic c agent" 
	log "Trapping the signal"
    trap '' SIGUSR1
	cd ${NEWRELIC_C_AGENT} ; ./newrelic-daemon -f -logfile daemon.log -loglevel debug --proxy $NEWRELIC_PROXY_PROTOCOL://$NEWRELIC_PROXY_HOST:$NEWRELIC_PROXY_PORT -c newrelic.ini &
	
	if [ $? == 0 ]
    then
	  log "Successfully started the newrelic c agent"
    fi
	  
}

handle_removeprojection()
{
  log "------------- handle_removeprojection ---------------"
  removeprojection_iapi='/tmp/removeprojection'
  echo "retrieve,c,dm_server_config where object_name='$DOCBASE_NAME'" > $removeprojection_iapi
  echo "remove,c,l,projection_targets" >> $removeprojection_iapi
  echo "remove,c,l,projection_ports" >> $removeprojection_iapi
  echo "remove,c,l,projection_proxval" >> $removeprojection_iapi
  echo "remove,c,l,projection_notes" >> $removeprojection_iapi
  echo "remove,c,l,projection_enable" >> $removeprojection_iapi
  echo "save,c,l" >> $removeprojection_iapi
  source $DM_HOME/bin/dm_set_server_env.sh; iapi $DOCBASE_NAME -U$INSTALL_OWNER -P"" -R$removeprojection_iapi > /tmp/removeprojectioniapi.out
}

handle_s3multipart() {
	log "------------- handle_s3multipart ---------------"
	# Check whether multipart is enabled or not.
	# If enabled then add value for number of threads
	if [ "$MULTIPART_ENABLE" = "true" ]
	then
		if [ `grep "#multipart-parallel-processing" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties | wc -l` -gt 0 ]
		then
			sed -i -e "s;#multipart-parallel-processing.*;multipart-parallel-processing=$MULTIPART_ENABLE;" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties
		elif [ `grep "multipart-parallel-processing" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties | wc -l` -gt 0 ]
		then
			sed -i -e "s;multipart-parallel-processing.*;multipart-parallel-processing=$MULTIPART_ENABLE;" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties
		else
			echo "multipart-parallel-processing=$MULTIPART_ENABLE" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties
		fi

		# Now set the thread count
		if [ `grep "#multipart-processing-thread.pool-size" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties | wc -l` -gt 0 ]
		then
			sed -i -e "s;#multipart-processing-thread.pool-size.*;multipart-processing-thread.pool-size=$MULTIPART_THREAD_NUM;" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties
		elif [ `grep "multipart-processing-thread.pool-size" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties | wc -l` -gt 0 ]
		then
			sed -i -e "s;multipart-processing-thread.pool-size.*;multipart-processing-thread.pool-size=$MULTIPART_THREAD_NUM;" ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties
		else
			echo "multipart-processing-thread.pool-size=$MULTIPART_THREAD_NUM" >> ${DOCUMENTUM}/$TOMCAT/webapps/ACS/WEB-INF/classes/s3.properties
		fi
	fi
}

mkdir_sysadmin() {
	printf -v hexDocbaseId '%x' $DOCBASE_ID
	id_len=${#hexDocbaseId}
	len_diff="$((8-${id_len}))"	
	character="0"
	strZero=""
	for(( i = 0; i < "$len_diff"; ++i ))
	do 
		strZero="${strZero}${character}"
	done
	hexDocbaseIdWith0=${strZero}${hexDocbaseId}
	LOG_DIR=${DOCUMENTUM}/dba/log/${hexDocbaseIdWith0}/sysadmin

	if [ ! -d "$LOG_DIR" ]
	then  
		mkdir $LOG_DIR
	fi
}

getSecretsFromVault()
{
	if [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
	then
		docbaseCertPwd=$(curl $DSIS_URL/secret/$DOCBASE_CERT_PASSWORD)
		dfcTrustStorePwd=$(curl $DSIS_URL/secret/$DFC_SSL_TRUSTSTORE_PASSWORD)
		if [ -z $docbaseCertPwd ] || [ -z $dfcTrustStorePwd ]
		then
	    	log "DOCBASE_CERT_PASSWORD or DFC_SSL_TRUSTSTORE_PASSWORD is empty"
			exitProgram
		fi
	fi
	if [ -n "$DOCBROKER_USE_CERTIFICATES" ] && [ "$DOCBROKER_USE_CERTIFICATES" == "true" ]
	then
   		docbrokerCertPwd=$(curl $DSIS_URL/secret/$DOCBROKER_CERT_PASSWORD)
		docbrokerTrustPwd=$(curl $DSIS_URL/secret/$DOCBROKER_TRUST_PASSWORD)
		if [ -z $docbrokerCertPwd ] || [ -z $docbrokerTrustPwd ]
		then
			log "DOCBROKER_CERT_PASSWORD or DOCBROKER_TRUST_PASSWORD is empty"
			exitProgram
		fi
	fi

	if [ -n "$SMTP_AUTH" ] && [ "$SMTP_AUTH" == "true" ]
	then
		SMTP_PASS=$(curl $DSIS_URL/secret/$SMTP_PASS)
		if [ -z $SMTP_PASS ]
		then
			log "SMTP_PASS is empty"
			exitProgram
		fi
	fi
	if [ "$onlyDocbroker" != "true" ]
	then
		databasePwd=$(curl $DSIS_URL/secret/$DATABASE_PASSWORD)
		oldaekPwd=$(curl $DSIS_URL/secret/$OLD_AEK_PASSPHRASE)
		if [ -z $databasePwd ]
		then
			log "DATABASE_PASSWORD is empty"
			exitProgram
		fi
	fi
	
	installOwnerPwd=$(curl $DSIS_URL/secret/$INSTALL_OWNER_PASSWORD)
	rootPwd=$(curl $DSIS_URL/secret/$ROOT_PASSWORD)
	if [ -z $installOwnerPwd ] || [ -z $rootPwd ]
	then
		log "INSTALL_OWNER_PASSWORD or ROOT_PASSWORD is empty"
		exitProgram
	fi
}

main()
{
   export JVM_OPTS="-Djava.locale.providers=COMPAT,SPI --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-exports=java.base/sun.security.provider=ALL-UNNAMED --add-exports=java.base/sun.security.pkcs=ALL-UNNAMED --add-exports=java.base/sun.security.x509=ALL-UNNAMED --add-exports=java.base/sun.security.util=ALL-UNNAMED --add-exports=java.base/sun.security.tools.keytool=ALL-UNNAMED"
	echo "export JAVA_TOOL_OPTIONS=\"$JAVA_TOOL_OPTIONS $JVM_OPTS\"">>${DM_HOME}/bin/dm_set_server_env.sh
	echo "export JAVA_TOOL_OPTIONS=\"$JAVA_TOOL_OPTIONS $JVM_OPTS\"">>${DM_HOME}/bin/dm_set_server_env.sh_oracle
	if [ "${IS_VAULT_ENABLED}" = "true" ]
	then
		getSecretsFromVault
	fi
	
	initialize
	handle_password_change
	if [ "$onlyDocbroker" = "true" ]
    then	
		onlyDocbroker	
	else	    
		if [ "$alreadyInstalled" != "FALSE" ]
		then
		    upgradeCS
			prepareCertUpgrade
			tomcatLogs="${NEW_TOMCAT_LOGS_DIR}"
			if [ -d "$tomcatLogs" ] && [ $(ls "$tomcatLogs" | wc -l) -gt 0 ] 
			then
				tar zcf "${DOCUMENTUM}/kube/tomcatLogs/tomcatLogs-$(hostname)-$(date +"%d-%b-%Y-%H_%M_%S")_restart".gz -C "${tomcatLogs}" .
				log "Tomcat logs after restart archived under ${DOCUMENTUM}/kube/tomcatLogs"
			fi
		fi
		update_app_server_credential
		if [ "$MIGRATECS" = "true" ]
		then
			migratecsfile="${DOCUMENTUM}/kube/MigrateCS"		
			if [ -f "$migratecsfile" ]
			then
				log "Migration already completed"
			else
				if [ "$isHA" != "TRUE" ]
				then
					migrateScripts
					if [ "$DB_TYPE" != "oracle" ]
					then
					  updateodbcini
					fi
				else
					handle_kube_pvc
				fi
				
			fi
		else
			handle_kube_pvc
		fi
		if [ "$alreadyInstalled" = "FALSE" ] && [ "$isHA" = "FALSE" ] && [ "$MIGRATECS" = "false" ]
		then
			#validate only for fresh deployment, primary CS, non-migration
			validate_passwords
		fi
        migration_util        
		copy_dba_scripts
		prepare_start_method_server
		if [ $NEWRELIC_ENABLE ]
        then
		  handle_start_newrelic_c_agent
		fi
		
		if [ -f $DOCUMENTUM/config/dfc.properties ]
        then
            if [ `grep dfc.dsis.enabled $DOCUMENTUM/config/dfc.properties | wc -l` -eq 0 ]
            then
                echo "dfc.dsis.enabled=$IS_VAULT_ENABLED" >> $DOCUMENTUM/config/dfc.properties
                echo "dfc.dsis.daemon.url=$DSIS_URL" >> $DOCUMENTUM/config/dfc.properties
            else
                sed -i -e "s;dfc.dsis.enabled=.*;dfc.dsis.enabled=$IS_VAULT_ENABLED;" $DOCUMENTUM/config/dfc.properties
                sed -i -e "s;dfc.dsis.daemon.url=.*;dfc.dsis.daemon.url=$DSIS_URL;" $DOCUMENTUM/config/dfc.properties
            fi
		fi		
		if [ "$isHA" != "TRUE" ]
		then
			handle_start_docbase
		else
			handle_start_HA_docbase
			handle_removeprojection
		fi	
		
		
		#update proximity value in server config object to 1
		updateServerConfigProximityValue	
		configure_email		
		handle_start_method_server
		upgradeInitFile=${DOCUMENTUM}/kube/upgradeInitiated$PRODUCT_MAJOR_VERSION
		if [ -f "$upgradeInitFile" ]
		then
			rm -f $upgradeInitFile
		fi	
		handle_start_thumbnail_server
		handle_otds_config
		handle_dar_install_config
		## In case of mutlti docbase  with Aviator deployment scenario, the secondary and other docbases has to be configured with dm_csai_config object
		## The DCIS, AMQ & Aviator services will be shared across docbases, hence create/update the secondary and others by obtaining the configuration from
		## primary docbase 
		if [ "$GLOBAL_REPOSITORY_NAME" != "" ] && [ "$GLOBAL_REPOSITORY_NAME" != "$DOCBASE_NAME" ]
		then
	  		configure_csai_config
		fi
		updateThumbnailServerBaseUrl
		if [ -n "$CUST_SCRIPT_EXE" ] && [ "$CUST_SCRIPT_EXE" == "true" ]
        then
            custom_script_execution
        fi
		
        if [ "$CUST_SCRIPT_IN_PVC" = "true" ] || [ "$USE_INITCONTAINERS" = "true" ]
		then
			# in some cases it takes a lot of time for custom scripts to complete causing pod restart issues.
			# therefore creating marker files for docbase and primary installed here itself - CS-132722
			if [ "$alreadyInstalled" != "TRUE" ]
	 		then 
		 		touch -f ${DOCUMENTUM}/kube/${DOCBASE_NAME}-installed		 
		 		log "$DOCBASE_NAME-installed file created"
		 		if [ "$isHA" != "TRUE" ]
		 		then
		   			touch -f ${DOCUMENTUM}/data/primary-installed
		   			log "primary-installed file created"
		 		fi
	 		fi

			if [ "$alreadyInstalled" = "FALSE" ]
			then
			  log "Copying custom script from PVC to local"
			  cp -R ${DM_DOCKER_HOME}/customscriptpvc/. ${DM_DOCKER_HOME}/custom_script_pvc
			  chown -R -f $INSTALL_OWNER:$INSTALL_OWNER ${DM_DOCKER_HOME}/custom_script_pvc
			  chmod +x ${DM_DOCKER_HOME}/custom_script_pvc/*.sh
			fi

			if [ "$isHA" != "TRUE" ]
			then
			  log "Restart Content Server"
			  kill -9 `ps -ef | grep ${DOCBASE_NAME} |grep -v grep | awk '{print $2}'`
			  check_cs_shutdown_status "server.ini"
			  source $DM_HOME/bin/dm_set_server_env.sh; ${DOCUMENTUM}/dba/dm_start_${DOCBASE_NAME}
			  handle_CS_statuscheck	 
			fi			
			restart_method_server
			custom_script_pvc_execution "posthook"
			touch -f ${DOCUMENTUM}/kube/custom-script-success
        fi
		java $JVM_OPTS -cp $DM_DOCKER_HOME/:${DOCUMENTUM}/dfc/*:${DOCUMENTUM}/config MIPTrustedClients "/opt/dctm/config/"
		exit_code=$?

		# Check the exit code
		if [ $exit_code -eq 0 ]; then
			echo "MIPTrustedClients was successful, or the clients are already present."
		else
			echo "Failed to register MIPTrustedClients"
		fi
		configure_S3_Store
		configure_rest_Store		
		updateAcsConfigBaseUrl
		ready
		log "-------------------Invoking the Logging Service.---------------------------------"
		${DM_DOCKER_HOME}/cs_logging_config/CS_Logging_Config_monitoring_Service.sh &
		mkdir_sysadmin
	fi
	
	if [ "${AEK_LOCATION}" = "Remote" ]
	then
		if [ -n "$DOCBROKER_USE_CERTIFICATES" ] && [ "$DOCBROKER_USE_CERTIFICATES" == "true" ] 
		then
			sudo keytool -delete -keystore $JAVA_HOME/lib/security/cacerts -alias broker.`hostname` -storepass changeit -noprompt
		fi
		if [ -n "$DOCBASE_USE_CERTIFICATES" ] && [ "$DOCBASE_USE_CERTIFICATES" == "true" ]
        then
			sudo keytool -delete -keystore $JAVA_HOME/lib/security/cacerts -alias server.`hostname` -storepass changeit -noprompt
		fi
	fi
	
	handle_logs_cleanup	
	log "Documentum Content Server Installation Completed"
	#Regression test call
	if [ "$LAUNCH_CSREGR" = "true" ]
    then	
		launchCSTests	
	fi
	log "-------------------SCRIPT COMPLETED---------------------------------"
	
}
main
