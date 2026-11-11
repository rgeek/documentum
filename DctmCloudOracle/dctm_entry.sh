#!/bin/bash
# Entry point for ot-dctm-server (Docker mode, Oracle) - primary (cs) and additional servers (cs2).
#  1. additional server only (PRIMARY_DBA_DIR set): copy the primary's AEK before first install
#  2. run OpenText's cs_startup.sh unchanged (install or restart)
#  3. once it has finished and the docbase accepts logins, apply idempotent post-config:
#       - peer docbroker in dfc.properties                       (PEER_HOST)
#       - normalise server.ini projection targets + add peer     (PEER_HOST) + reinit if changed
#       - this server's JMS config (dm_jms_admin.sh) if missing, with retries + verification
#       - Process Engine custom scripts (ENABLE_PE=true), like kube_cs.sh custom_script_pvc_execution
#       - backup tnsnames.ora + method server config to the volumes
#  Log: stdout and $DOCUMENTUM/dba/log/dctm_entry.log (survives docker compose down)
DOCUMENTUM=${DOCUMENTUM:-/opt/dctm}
DM_DOCKER_HOME=${DM_DOCKER_HOME:-/opt/dctm_docker}
DM_HOME=${DM_HOME:-$(ls -d $DOCUMENTUM/product/*/ 2>/dev/null | head -1)}; DM_HOME=${DM_HOME%/}
HOST=$(hostname)
PEER_PORT=${PEER_DOCBROKER_PORT:-1489}
JMS_PORT=${JMS_PORT:-9080}
PE_DIR=${PE_SCRIPTS_DIR:-$DM_DOCKER_HOME/custom_script_pvc}
LOGF=$DOCUMENTUM/dba/log/dctm_entry.log
log() { local m; m="$(date) [entry] $*"; echo "$m"; { mkdir -p "$(dirname "$LOGF")" && echo "$m" >> "$LOGF"; } 2>/dev/null; }

if [ -n "$SERVER_CONFIG_NAME" ]; then
  SRVCFG="${HOST}_${DOCBASE_NAME}"; SERVER_INI="$DOCUMENTUM/dba/config/$DOCBASE_NAME/server_${HOST}_${DOCBASE_NAME}.ini"; IS_HA=true
else
  SRVCFG="$DOCBASE_NAME";           SERVER_INI="$DOCUMENTUM/dba/config/$DOCBASE_NAME/server.ini"; IS_HA=false
fi
DFC_PROPS="$DOCUMENTUM/config/dfc.properties"

# ---------------- helpers (testable via: source dctm_entry.sh --lib) ----------------
add_dfc_docbroker() {   # $1 file, $2 host, $3 port
  local f=$1 h=$2 p=$3
  [ -f "$f" ] || { log "dfc: $f not found"; return 1; }
  if grep -qE "^dfc\.docbroker\.host\[[0-9]+\]=${h}[[:space:]]*$" "$f"; then log "dfc: $h already in $f"; return 0; fi
  local n; n=$(grep -oE '^dfc\.docbroker\.host\[[0-9]+\]' "$f" | grep -oE '[0-9]+' | sort -n | tail -1)
  n=$(( ${n:--1} + 1 ))
  printf 'dfc.docbroker.host[%s]=%s\ndfc.docbroker.port[%s]=%s\n' "$n" "$h" "$n" "$p" >> "$f"
  log "dfc: added docbroker[$n]=$h:$p to $f"
}

# Rewrites all [DOCBROKER_PROJECTION_TARGET*] sections: collects every host/port/proximity entry
# (also several per section, as create_ha_server.sh produces), drops placeholders + duplicates,
# appends the peer if missing. Returns 10 if the file changed.
normalize_projection_targets() {   # $1 server.ini, $2 peer host, $3 peer port, $4 peer proximity
  local f=$1 tmp
  [ -f "$f" ] || { log "ini: $f not found"; return 1; }
  tmp=$(mktemp)
  awk -v PH="$2" -v PP="$3" -v PX="$4" '
    function flush() { if (h != "") { n++; H[n]=h; P[n]=(p==""?"1489":p); X[n]=(x==""?"1":x) } h=""; p=""; x="" }
    function val(s) { sub(/^[^=]*=[[:space:]]*/, "", s); gsub(/[[:space:]]/, "", s); return s }
    BEGIN { inproj=0; n=0; nb=0 }
    /^\[DOCBROKER_PROJECTION_TARGET(_[0-9]+)?\][[:space:]]*$/ { flush(); inproj=1; next }
    /^\[/ { if (inproj) flush(); inproj=0 }
    {
      if (inproj) {
        if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) next
        if ($0 ~ /^[[:space:]]*host[[:space:]]*=/)      { if (h != "") flush(); h=val($0); next }
        if ($0 ~ /^[[:space:]]*port[[:space:]]*=/)      { p=val($0); next }
        if ($0 ~ /^[[:space:]]*proximity[[:space:]]*=/) { x=val($0); next }
        next
      }
      B[++nb]=$0
    }
    END {
      flush()
      while (nb > 0 && B[nb] ~ /^[[:space:]]*$/) nb--
      for (i=1; i<=nb; i++) print B[i]
      m=0
      for (i=1; i<=n; i++) { k=H[i] ":" P[i]; if (k in seen) continue; seen[k]=1; m++; OH[m]=H[i]; OP[m]=P[i]; OX[m]=X[i] }
      if (PH != "" && !((PH ":" PP) in seen)) { m++; OH[m]=PH; OP[m]=PP; OX[m]=PX }
      for (i=1; i<=m; i++)
        printf "\n[DOCBROKER_PROJECTION_TARGET%s]\nhost = %s\nport = %s\nproximity = %s\n", (i==1?"":"_" (i-1)), OH[i], OP[i], OX[i]
    }' "$f" > "$tmp"
  if cmp -s "$f" "$tmp"; then rm -f "$tmp"; log "ini: projection targets already clean in $f"; return 0; fi
  cp -p "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
  cat "$tmp" > "$f"; rm -f "$tmp"
  log "ini: projection targets normalised in $f (backup kept)"
  return 10
}
[ "${1:-}" = "--lib" ] && return 0 2>/dev/null

dql() {   # $1 query ; prints idql output
  local q; q=$(mktemp); printf '%s\ngo\nquit\n' "$1" > "$q"
  ( source "$DM_HOME/bin/dm_set_server_env.sh" >/dev/null 2>&1
    idql "$DOCBASE_NAME.$SRVCFG" -Udmadmin -P"$INSTALL_OWNER_PASSWORD" -R"$q" 2>/dev/null )
  rm -f "$q"
}
api() {   # $1 api command
  local q; q=$(mktemp); printf '%s\nquit\n' "$1" > "$q"
  ( source "$DM_HOME/bin/dm_set_server_env.sh" >/dev/null 2>&1
    iapi "$DOCBASE_NAME.$SRVCFG" -Udmadmin -P"$INSTALL_OWNER_PASSWORD" -R"$q" 2>/dev/null )
  rm -f "$q"
}
port_open()   { (echo > /dev/tcp/$1/$2) >/dev/null 2>&1; }
server_id()   { dql "select r_object_id from dm_server_config where object_name = '$SRVCFG'" | grep -oE '3d[0-9a-f]{14}' | head -1; }
jms_count()   { dql "select count(*) as c from dm_jms_config where object_name like 'JMS $HOST:$JMS_PORT for %'" | grep -E '^[[:space:]]*[0-9]+[[:space:]]*$' | tr -d ' ' | head -1; }
jms_up()      { curl -s -o /dev/null -w '%{http_code}' "http://$HOST:$JMS_PORT/DmMethods/servlet/DoMethod" | grep -q 200; }

wait_docbase_login() {   # port open is not enough; wait until a session works (max ~15 min)
  local i=0 sid
  while [ $i -lt 90 ]; do
    sid=$(server_id); [ -n "$sid" ] && { log "docbase accepts logins (server config $SRVCFG = $sid)"; return 0; }
    i=$((i+1)); sleep 10
  done
  log "WARNING: no docbase session possible after 15 min"; return 1
}

ensure_jms_config() {
  local i=0
  until jms_up; do
    i=$((i+1))
    if [ $i -eq 6 ] && ! pgrep -f catalina >/dev/null; then
      log "JMS not running - starting it"
      ( source "$DM_HOME/bin/dm_set_server_env.sh" >/dev/null 2>&1; "$DM_JMS_HOME/bin/startMethodServer.sh" ) >/tmp/jms_start.log 2>&1 &
    fi
    [ $i -ge 90 ] && { log "WARNING: JMS not answering on $HOST:$JMS_PORT after 15 min - JMS config skipped"; return 1; }
    sleep 10
  done
  log "JMS answering on $HOST:$JMS_PORT"
  local attempt cnt sid out="$DOCUMENTUM/dba/config/$DOCBASE_NAME/dm_jms_config_setup_entry.out"
  for attempt in 1 2 3; do
    cnt=$(jms_count)
    if [ -n "$cnt" ] && [ "$cnt" != "0" ]; then log "JMS config for $HOST:$JMS_PORT present"; return 0; fi
    sid=$(server_id)
    if [ -z "$sid" ]; then log "attempt $attempt: server config id not found yet - retrying"; sleep 60; continue; fi
    log "attempt $attempt: creating JMS config for $SRVCFG ($sid)"
    ( source "$DM_HOME/bin/dm_set_server_env.sh" >/dev/null 2>&1
      "$DM_HOME/bin/dm_jms_admin.sh" -docbase "$DOCBASE_NAME.$SRVCFG" -username dmadmin \
        -action add,enableDFC,testDFC,migrate,dumpServerCache,listAll \
        -jms_host_name "$HOST" -jms_port "$JMS_PORT" -jms_proximity 9000 \
        -webapps ServerApps -server_config_id "$sid" ) >> "$out" 2>&1
    sleep 10
  done
  cnt=$(jms_count)
  if [ -n "$cnt" ] && [ "$cnt" != "0" ]; then log "JMS config created"; return 0; fi
  log "WARNING: JMS config still missing after 3 attempts - see $out"; return 1
}

jms_restart() {
  log "restarting method server"
  pkill -9 -f "catalina.home=$DM_JMS_HOME" 2>/dev/null; pkill -9 -f catalina 2>/dev/null; sleep 5
  ( source "$DM_HOME/bin/dm_set_server_env.sh" >/dev/null 2>&1; "$DM_JMS_HOME/bin/startMethodServer.sh" ) >/tmp/jms_start.log 2>&1 &
  local i=0; until jms_up; do i=$((i+1)); [ $i -ge 60 ] && { log "WARNING: JMS not back after 10 min"; return 1; }; sleep 10; done
  log "method server back up"
}

# Mirrors kube_cs.sh custom_script_pvc_execution for 10pedeploy.sh, with the env the k8s pod would have.
#  - prehook: only when the bpm webapp is missing but a PE backup exists (recreated container);
#             then restart JMS so Tomcat loads the redeployed webapp
#  - posthook: every start (installs on first run; on later runs only probes /bpm)
#  - additional server waits until the primary's PE (DARs) is done
run_pe_scripts() {
  [ "$ENABLE_PE" = "true" ] || return 0
  ls "$PE_DIR"/*deploy.sh >/dev/null 2>&1 || { log "PE: ENABLE_PE=true but no *deploy.sh in $PE_DIR"; return 1; }
  local pe_primary=true; [ "$IS_HA" = "true" ] && pe_primary=false
  local pelog="$DOCUMENTUM/dba/log/pe_scripts.log" bpmdir="$DM_JMS_HOME/webapps/bpm" s rc i

  if [ "$pe_primary" = "false" ] && [ -n "$PRIMARY_DBA_DIR" ]; then
    i=0; until [ -f "$PRIMARY_DBA_DIR/pe-posthook-done" ]; do
      [ $i -eq 0 ] && log "PE: waiting for the primary's Process Engine install to finish"
      i=$((i+1)); [ $i -ge 270 ] && { log "WARNING: primary PE not done after 45 min - continuing"; break; }; sleep 10
    done
  fi

  pe_run() {   # $1 phase
    for s in $(ls "$PE_DIR"/*deploy.sh | sort -V); do
      log "PE: $1 $(basename "$s") (PE_PRIMARY=$pe_primary)"
      ( source "$DM_HOME/bin/dm_set_server_env.sh" >/dev/null 2>&1
        cd "$PE_DIR"
        KUBERNETES=false PE_PRIMARY=$pe_primary PE_FQDN="$HOST" CONFIG_NAME_OPTION=HOSTNAME \
        JMS_PROTOCOL=${JMS_PROTOCOL:-http} CONTAINER_NAME="$HOST" "$s" "$1" ) >> "$pelog" 2>&1
      rc=$?
      [ $rc -eq 0 ] || { log "PE: FAILED $(basename "$s") $1 (rc=$rc) - see $pelog"; return 1; }
    done
  }

  if [ ! -d "$bpmdir" ] && [ -f "$DOCUMENTUM/kube/bpm/web.xml" ]; then
    pe_run prehook || return 1
    jms_restart
  fi
  pe_run posthook || return 1
  touch "$DOCUMENTUM/dba/pe-posthook-done"; log "PE: done"
}

post_config() {
  log "post-config for server $SRVCFG (HA: $IS_HA, peer: ${PEER_HOST:-none})"
  wait_docbase_login || return 1

  if [ -n "$PEER_HOST" ]; then
    add_dfc_docbroker "$DFC_PROPS" "$PEER_HOST" "$PEER_PORT"
    normalize_projection_targets "$SERVER_INI" "$PEER_HOST" "$PEER_PORT" 2
    if [ $? -eq 10 ]; then log "reinit docbase to pick up projection targets"; api "reinit,c" >/dev/null; fi
  fi

  ensure_jms_config
  run_pe_scripts

  cp -f "$TNS_ADMIN/tnsnames.ora" "$DOCUMENTUM/odbc/tnsnames.ora" 2>/dev/null && log "saved tnsnames.ora to odbc volume"
  sudo -E "$DM_DOCKER_HOME/scripts/methodserver_restore_backup_changes.sh" backup >/dev/null 2>&1 \
    && log "method server config backed up" || log "WARNING: method server backup failed"
  log "post-config done"
}

# ---------------- main ----------------
trap 'log "stop signal"; kill $STARTUP_PID 2>/dev/null; exit 0' SIGTERM SIGINT

if [ -n "$PRIMARY_DBA_DIR" ] && [ -d "$PRIMARY_DBA_DIR/secure" ]; then
  mkdir -p "$DOCUMENTUM/dba/secure"
  for f in "$PRIMARY_DBA_DIR"/secure/*; do
    [ -e "$f" ] || continue; b=$(basename "$f")
    [ -e "$DOCUMENTUM/dba/secure/$b" ] || { cp -rp "$f" "$DOCUMENTUM/dba/secure/" && log "copied $b from primary"; }
  done
fi

"$DM_DOCKER_HOME/cs_startup.sh" &
STARTUP_PID=$!

sleep 15
while pgrep -f configure-stateless-server >/dev/null; do sleep 10; done
log "OpenText startup finished"
i=0; until port_open "$HOST" "${CONTENTSERVER_PORT:-50000}"; do i=$((i+1)); [ $i -ge 60 ] && break; sleep 10; done
if port_open "$HOST" "${CONTENTSERVER_PORT:-50000}"; then post_config; else log "WARNING: docbase not listening - post-config skipped"; fi

wait $STARTUP_PID