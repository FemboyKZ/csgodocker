#!/bin/bash

set -ueEo pipefail

server_dir="/tmp/csgoserver"
mkdir -p "$server_dir"

for (( first=1;; first=0 )); do
    [ $first -eq 0 ] && sleep 10

    build_ver="0"
    build_dir="/csgo"
    [ -d "$build_dir" ] || exit 1

    rm -rf "$server_dir"/*
    LD_LIBRARY_PATH="$server_dir:$server_dir/bin" HOME="/tmp/csgohome" root="" build_ver="$build_ver" build_dir="$build_dir" server_dir="$server_dir" /bin/bash /user/run.sh
done
