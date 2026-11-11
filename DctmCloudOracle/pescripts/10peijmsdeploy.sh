#!/bin/bash
hostname=`hostname -f`
hostname_short=`hostname`

mkdir -p $DM_DOCKER_HOME/logs/
logfile=$DM_DOCKER_HOME/logs/${hostname}.log

bpmwebappsfolder=$DM_JMS_HOME/webapps/bpm
peinstallfolder=$DM_DOCKER_HOME/custom_script_pvc/pe_installer
peinstalllibfolder=$peinstallfolder/lib

host_fqdn=`hostname -f`
ijms_port="$JMS_PORT"
ijms_protocol="$JMS_PROTOCOL"
BPM_URL="$JMS_PROTOCOL://localhost:$JMS_PORT/bpm/servlet/DoMethod"

log()
{
   echo "$(date) $1"
   echo "$(date) $1" >> $logfile
}

log "In 10peijmsdeploy.sh"

handle_war_deployment()
{
   log "----------------handle_war_deployment---------------------"
   unzip -q $peinstallfolder/bpm.zip -d $bpmwebappsfolder
   unzip -q $bpmwebappsfolder/bpm.war -d $bpmwebappsfolder
   rm $bpmwebappsfolder/bpm.war
}

check_docbase_connection()
{
    count=0

	while [ $count -lt 10 ]
	do
        test_docbase_connection=$( java $JDK_OPTIONS -cp .:$DM_JMS_HOME/webapps/DmMethods/WEB-INF/lib/* com/documentum/ijms/IJMSConfigurator test_docbase_connection $DOCBASE_NAME $INSTALL_OWNER_USER $INSTALL_OWNER_PASSWORD)
	    log "test_docbase_connection $test_docbase_connection"
        if [ $? -eq 0 ]
        then
          log "Docbase is up and running."
          break
        else
          log "Docbase is down.Hence waiting for the docbase to come up...."
          sleep 30
          count=`expr $count + 1`
          if [ $count -eq 10 ]
          then
            log "Finshed maximum wait for the docbase connection. Hence exiting.Please run the $DM_DOCKER_HOME/jms/configure-ijms script manually once the docbase is up."
            rm $DM_DOCKER_HOME/jms/dummy.txt
            exit
          fi
        fi
	done     
}

handle_backup()
{
    log "---------------handle_backup------------------------------"
	
	log "backing up dfc.keystore files"
	cp -f $bpmwebappsfolder/WEB-INF/classes/dfc.keystore  ${DM_DOCKER_HOME}/mdserver_conf/bpm.dfc.keystore
	
	log "backing up dfc.properties files"
	cp -f $bpmwebappsfolder/WEB-INF/classes/dfc.properties  ${DM_DOCKER_HOME}/mdserver_conf/bpm.dfc.properties
}

handle_backup_restore()
{
   log "------------------handle_backup_restore---------------------"
   
   log "Restoring dfc.keystore files"
   cp -f ${DM_DOCKER_HOME}/mdserver_conf/bpm.dfc.keystore $bpmwebappsfolder/WEB-INF/classes/dfc.keystore
	
   log "Restoring dfc.properties files"
   cp -f ${DM_DOCKER_HOME}/mdserver_conf/bpm.dfc.properties $bpmwebappsfolder/WEB-INF/classes/dfc.properties
}

handle_configurations()
{
	log "------------------handle_configurations---------------------"

	log "Modifying log4j2.properties"
	sed -i -e "s:\$H(SERVER_INSTANCE_DIR):/opt/tomcat:" $bpmwebappsfolder/WEB-INF/classes/log4j2.properties
    sed -i -e "s:\$H(APP_NAME):bpm:" $bpmwebappsfolder/WEB-INF/classes/log4j2.properties
}

handle_firsttime_scenario()
{
    log "----------------handle_firsttime_scenario------------------"
	handle_war_deployment
	
	sudo chown $INSTALL_OWNER_USER:$INSTALL_OWNER_USER -Rf $bpmwebappsfolder
	
	#update dfc.properties
	sed -i '/#include/c\#include '"$DM_DOCKER_HOME"'/dfc.properties' $bpmwebappsfolder/WEB-INF/classes/dfc.properties
	
	check_docbase_connection
		
	handle_configurations
	
	log "Updating config and approving privilege"
	java $JDK_OPTIONS -cp .:$peinstalllibfolder/xcp_ijms_pe.jar:$DM_JMS_HOME/webapps/DmMethods/WEB-INF/lib/*:$peinstalllibfolder/pe_shared.jar com.documentum.docker.pe.PeConfigureForIJMSInitContainer $bpmwebappsfolder/WEB-INF/classes/dfc.properties $DOCBASE_NAME $INSTALL_OWNER_USER $INSTALL_OWNER_PASSWORD $ijms_protocol $host_fqdn $ijms_port $bpmwebappsfolder/WEB-INF/classes/ $DOCBASE_DOMAIN

	handle_backup
}

handle_restart_scenario()
{
   log "----------------handle_restart_scenario---------------------"
   handle_war_deployment
   handle_backup_restore
   handle_configurations     
}

stopMethodServer(){
    log "----------------stop_method_server---------------------"
	kill -9 `ps -ef | grep $DM_JMS_HOME | awk '{print($2)}' | tr '\n' ' '`
}

startMethodServer(){
    log "----------------start_method_server---------------------"
	sh $DM_JMS_HOME/bin/startup.sh
}

installpe()
{
   log "------------------------------ installpe ------------------------"
   
   export JDK_OPTIONS="-Djava.locale.providers=COMPAT,SPI --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-exports=java.base/sun.security.provider=ALL-UNNAMED --add-exports=java.base/sun.security.pkcs=ALL-UNNAMED --add-exports=java.base/sun.security.x509=ALL-UNNAMED --add-exports=java.base/sun.security.util=ALL-UNNAMED --add-exports=java.base/sun.security.tools.keytool=ALL-UNNAMED"
   cd /opt/dctm_docker; javac -encoding UTF-8 -cp .:$DM_JMS_HOME/webapps/DmMethods/WEB-INF/lib/dfc.jar com/documentum/ijms/IJMSConfigurator.java
   
   if [ "$INGRESS_ENABLED" = "true" ]
   then
	host_fqdn="$INGRESS_HOST"		
	ijms_port="$INGRESS_PORT"
	ijms_protocol="$INGRESS_PROTOCOL"		
   fi
   
   already_deployed="${DM_DOCKER_HOME}/mdserver_conf/ijms-pe-deployed"
   if [ -f "$already_deployed" ]
   then
     handle_restart_scenario
   else	 
     handle_firsttime_scenario	 
   fi   
}

probeBPM()
{
	WAIT=0
	urlstatus=400
	while [ "$WAIT" -lt 300 ]
	do
		urlstatus=$(curl -o /dev/null --silent --head --write-out '%{http_code}' $BPM_URL)
		echo Waiting for $BPM_URL to be up
		if [ $urlstatus -eq '200' ]
		then
			log "BPM probe passed for URL $BPM_URL. Status=$urlstatus. WaitTime=${WAIT}s"
			touch -f /opt/dctm_docker/mdserver_conf/ijms-pe-deployed
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

if [ "$1" = "posthook" ]
then
	log "-------------------------------In posthook-------------------------"
	if [ ! -d "$bpmwebappsfolder" ]
	then
		stopMethodServer
		installpe
		startMethodServer
	else
		log "$bpmwebappsfolder folder exists. pe is already installed."
	fi
	probeBPM
fi

if [ "$1" = "prehook" ]
then
	log "-------------------------------In prehook-------------------------"
	installpe
fi
