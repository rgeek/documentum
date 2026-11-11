#!/bin/bash
# Supervisor for ot-dctm-server in plain-Docker mode.
#  - runs OpenText's cs_startup.sh unchanged (first-time install or restart)
#  - once it has finished, starts the docbase + Java Method Server if they are not running
#    (the Docker-mode restart path only starts the docbrokers)
#  - on docker stop: shuts down docbase, JMS and docbrokers cleanly
DOCUMENTUM=${DOCUMENTUM:-/opt/dctm}
DM_DOCKER_HOME=${DM_DOCKER_HOME:-/opt/dctm_docker}
DBA=$DOCUMENTUM/dba
log() { echo "$(date) [supervise] $*"; }

jms_start() {
  if   [ -x "$DM_JMS_HOME/bin/startMethodServer.sh" ]; then "$DM_JMS_HOME/bin/startMethodServer.sh" >/dev/null 2>&1 &
  elif [ -x "$DM_JMS_HOME/bin/startup.sh" ];           then "$DM_JMS_HOME/bin/startup.sh" >/dev/null 2>&1
  else log "JMS start script not found under DM_JMS_HOME=$DM_JMS_HOME"; fi
}
jms_stop() {
  if   [ -x "$DM_JMS_HOME/bin/stopMethodServer.sh" ]; then "$DM_JMS_HOME/bin/stopMethodServer.sh" >/dev/null 2>&1
  elif [ -x "$DM_JMS_HOME/bin/shutdown.sh" ];         then "$DM_JMS_HOME/bin/shutdown.sh" >/dev/null 2>&1; fi
}
docbase_running() { pgrep -f "documentum -docbase_name $DOCBASE_NAME" >/dev/null; }
jms_running()     { pgrep -f "org.apache.catalina" >/dev/null; }

shutdown_all() {
  log "Stop signal received - shutting down cleanly"
  [ -x "$DBA/dm_shutdown_$DOCBASE_NAME" ] && "$DBA/dm_shutdown_$DOCBASE_NAME"
  jms_stop
  for s in "$DBA"/dm_stop_*; do [ -x "$s" ] && "$s"; done
  log "Shutdown complete"
  kill "$STARTUP_PID" 2>/dev/null
  exit 0
}
trap shutdown_all SIGTERM SIGINT

# 1) OpenText startup, unchanged. It ends in 'tail -f /dev/null & wait', so run it in the background.
"$DM_DOCKER_HOME/cs_startup.sh" &
STARTUP_PID=$!

# 2) Wait until configure-stateless-server has exited (covers the 20-40 min first install too)
sleep 15
while pgrep -f configure-stateless-server >/dev/null; do sleep 10; done
log "OpenText startup finished"

# 3) Start what the restart path skipped
# 3a) /etc/services entries for the docbase live in the container filesystem and are lost
#     when the container is recreated; the docbase resolves its ports by these names.
CS_PORT=${CONTENTSERVER_PORT:-50000}
CS_SSL_PORT=$((CS_PORT + 1))
if ! grep -qE "^dm_${DOCBASE_NAME}[[:space:]]" /etc/services; then
  log "Adding /etc/services entries dm_${DOCBASE_NAME}=${CS_PORT}, dm_${DOCBASE_NAME}_s=${CS_SSL_PORT}"
  printf 'dm_%s\t%s/tcp\t# Documentum docbase\ndm_%s_s\t%s/tcp\t# Documentum docbase (secure)\n' \
    "$DOCBASE_NAME" "$CS_PORT" "$DOCBASE_NAME" "$CS_SSL_PORT" | sudo tee -a /etc/services >/dev/null
fi

if [ -x "$DBA/dm_start_$DOCBASE_NAME" ]; then
  if ! docbase_running; then
    log "Docbase $DOCBASE_NAME not running - starting it"
    "$DBA/dm_start_$DOCBASE_NAME"
  else
    log "Docbase $DOCBASE_NAME already running"
  fi
  sleep 20
  if ! jms_running; then log "Starting Java Method Server"; jms_start; else log "JMS already running"; fi
else
  log "No $DBA/dm_start_$DOCBASE_NAME yet (install did not complete?) - not starting docbase"
fi

# 4) Stay in the foreground so the trap can fire on docker stop
while true; do sleep 3600 & wait $!; done