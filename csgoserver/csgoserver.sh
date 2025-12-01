#!/bin/bash

set -ueEo pipefail

server_dir="/tmp/csgoserver"
mkdir -p "$server_dir"

for (( first=1;; first=0 )); do
    [ $first -eq 0 ] && sleep 10

    # Wait for watchdog to provide latest version
    [ -f "/watchdog/csgo/latest.txt" ] || continue
    build_ver="$(cat /watchdog/csgo/latest.txt)"
    build_dir="/watchdog/csgo/builds/$build_ver"
    [ -d "$build_dir" ] || continue

    rm -rf "$server_dir"/*
    LD_LIBRARY_PATH="$server_dir:$server_dir/bin" HOME="/tmp/csgohome" root="" build_ver="$build_ver" build_dir="$build_dir" server_dir="$server_dir" /bin/bash /user/run.sh
done
