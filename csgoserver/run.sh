#!/bin/bash

set -ueEo pipefail

# Symlink all the server files.
cp -rs "$build_dir"/* "$server_dir"

# Run the server.
"$server_dir/srcds_linux" -game csgo -strictportbind -port "$PORT" -nobreakpad -noautoupdate +sv_setsteamaccount "$GSLT" +map de_dust2

