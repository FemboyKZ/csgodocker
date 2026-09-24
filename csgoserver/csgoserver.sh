#!/bin/bash

set -ueEo pipefail

# Fix steamclient.so ... Why is this such a mess?
mkdir -p "/tmp/csgohome/.steam/sdk64" "/tmp/csgohome/.steam/sdk32"
cp "/watchdog/steamcmd/linux64/steamclient.so" "/tmp/csgohome/.steam/sdk64/"
cp "/watchdog/steamcmd/linux32/steamclient.so" "/tmp/csgohome/.steam/sdk32/"

server_dir="/tmp/csgoserver"
mkdir -p "$server_dir"

read_layer_ver() {
    local file="/watchdog/layers/$1/latest.txt"
    [ -f "$file" ] && cat "$file" || echo ""
}

# Mirrors the watchdog's layer list: the server waits until every layer has a build
required_layers=(
    "mm" "sm"
    "movementapi" "gokz" "mhud" "autorestart" "fkz-api" "miss" "bsppeek" "steamworks" "sbpp"
    "kzserveradvisor"
    "mapcrashfixer" "smjansson" "gokz-lead"
    "globalapi" "itemcrashfix" "itstoodark" "antifun"
    "whitelist" "morestats" "gokzdiscord" "json" "websocket"
    "nolobbyreservation" "showpos" "demofix" "multiappid" "scoreboardtimer" "nms" "nightvision"
    "ztopwatch" "distbug" "vanillatier"
    "ptah" "weapons" "gloves"
    "cfg"
)

for (( first=1;; first=0 )); do
    [ $first -eq 0 ] && sleep 10

    # Wait for watchdog to provide latest version
    [ -f "/watchdog/csgo/latest.txt" ] || continue
    build_ver="$(cat /watchdog/csgo/latest.txt)"
    build_dir="/watchdog/csgo/builds/$build_ver"
    [ -d "$build_dir" ] || continue

    # Verify all plugin layers have a build ready
    layers_ok=1
    for layer_name in "${required_layers[@]}"; do
        ver="$(read_layer_ver "$layer_name")"
        if [ -z "$ver" ] || [ ! -d "/watchdog/layers/$layer_name/builds/$ver" ]; then
            layers_ok=0
            break
        fi
    done
    [ $layers_ok -eq 1 ] || continue

    rm -rf "$server_dir"/*
    # Hold shared lock on layers (blocks cleanup) and shared lock on csgo build dir
    (
        flock -s 200
        flock -ns "$build_dir/.lockfile" --command "LD_LIBRARY_PATH=\"$server_dir:$server_dir/bin\" HOME=\"/tmp/csgohome\" build_ver=\"$build_ver\" build_dir=\"$build_dir\" server_dir=\"$server_dir\" /bin/bash /user/run.sh"
    ) 200>/watchdog/layers/.lockfile
done
