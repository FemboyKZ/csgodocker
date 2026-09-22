#!/bin/bash

set -ueEo pipefail

echo "Build version: $build_ver"
echo "Restart time: $RESTART_TIME"
echo "Build dir: $build_dir"
echo "Server name: ${HOSTNAME:-}"

export daily_restart_time="$RESTART_TIME"
export discord_webhook="$DC_RESTART_WEBHOOK"
export server_name="${HOSTNAME:-}"

# Symlink all the server files.
cp -rs "$build_dir"/* "$server_dir"

# Run the server.
"$server_dir/srcds_linux" -game csgo -strictportbind -port "$PORT" -nobreakpad -noautoupdate +sv_setsteamaccount "$GSLT" +map de_dust2
