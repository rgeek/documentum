#!/bin/bash
# Adds DOCUMENTUM / DM_HOME / ORACLE_HOME / TNS_ADMIN to Documentum's $DM_HOME/bin/dm_set_server_env.sh,
# so it also works from login shells (su - dmadmin), where the container environment is wiped.
# Re-running replaces the previously added block. Run as root (build time or: docker exec -u root ...).
set -e
OH=${ORACLE_HOME_VALUE:-/usr/lib/oracle/21/client64/lib}
TA=${TNS_ADMIN_VALUE:-/opt/dctm_tns_admin}
DOCUMENTUM=${DOCUMENTUM:-/opt/dctm}
DMH="${DM_HOME:-$(ls -d $DOCUMENTUM/product/*/ 2>/dev/null | head -1)}"; DMH="${DMH%/}"
F="$DMH/bin/dm_set_server_env.sh"

if [ -z "$DMH" ] || [ ! -f "$F" ]; then
  echo "ERROR: dm_set_server_env.sh not found (DOCUMENTUM=$DOCUMENTUM, DM_HOME resolved to '$DMH')"; exit 1
fi
echo "DM_HOME resolved to: $DMH"

BLOCK="# >>> oracle env (added by add_oracle_env.sh)
DOCUMENTUM=\${DOCUMENTUM:-$DOCUMENTUM}; export DOCUMENTUM
DM_HOME=\${DM_HOME:-$DMH}; export DM_HOME
ORACLE_HOME=\${ORACLE_HOME:-$OH}; export ORACLE_HOME
TNS_ADMIN=\${TNS_ADMIN:-$TA}; export TNS_ADMIN
case \":\$LD_LIBRARY_PATH:\" in *\":\$ORACLE_HOME:\"*) ;; *) LD_LIBRARY_PATH=\$ORACLE_HOME:\$LD_LIBRARY_PATH; export LD_LIBRARY_PATH;; esac
case \":\$PATH:\" in *\":\$ORACLE_HOME/bin:\"*) ;; *) PATH=\$ORACLE_HOME/bin:\$ORACLE_HOME:\$PATH; export PATH;; esac
# <<< oracle env"

# remove an earlier version of the block, if present
sed -i '/^# >>> oracle env/,/^# <<< oracle env/d' "$F"

# insert right after the shebang (or at top) so it runs before the script's own checks
if head -1 "$F" | grep -q '^#!'; then
  { head -1 "$F"; echo "$BLOCK"; tail -n +2 "$F"; } > "$F.tmp"
else
  { echo "$BLOCK"; cat "$F"; } > "$F.tmp"
fi
cat "$F.tmp" > "$F"; rm -f "$F.tmp"; chmod 755 "$F"
echo "updated: $F"