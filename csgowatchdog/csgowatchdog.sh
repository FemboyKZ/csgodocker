#!/bin/bash

set -ueEo pipefail


update_csgo() {
    # Download CS:GO to /watchdog/csgo/install
    HOME="/watchdog/steamcmd" /watchdog/steamcmd/steamcmd.sh +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 +@bMetricsEnabled 0 +force_install_dir "/watchdog/csgo/install" +login anonymous +app_update 740 validate +quit 1>&2

    # Check which version we just installed
    local installed_version="$(grep PatchVersion= "/watchdog/csgo/install/csgo/steam.inf" | tr -cd "0-9")"

    # Return if we already have this version
    [ ! -d "/watchdog/csgo/builds/$installed_version" ]

    # Hard symlink the files from /watchdog/csgo/install to /watchdog/.tmp, then rename /watchdog/.tmp to /watchdog/csgo/builds/????? so it's atomic.
    # Must use a tmp directory inside of the /watchdog because symlinks don't work across filesystems.
    cp -rl "/watchdog/csgo/install" "/watchdog/.tmp"
    mv "/watchdog/.tmp" "/watchdog/csgo/builds/$installed_version"

    # Store the version in latest.txt so servers can detect an update
    rm "/tmp/latest.txt"
    echo "$installed_version" > "/tmp/latest.txt"
    mv "/tmp/latest.txt" "/watchdog/csgo/latest.txt"
}

# Download SteamCMD
if [ ! -d "/watchdog/steamcmd" ]; then
    mkdir -p "/tmp/steamcmd"
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C "/tmp/steamcmd"
    mv "/tmp/steamcmd" "/watchdog/steamcmd"
fi

mkdir -p "/watchdog/csgo/builds"
for (( first=1;; first=0 )); do
    [ $first -eq 0 ] && sleep 10

    # The temporary directory might exist if update_csgo fails
    rm -rf "/watchdog/.tmp"

    latest_version="13881" || continue

    # Remove outdated CS:GO builds that are not being used by any server
    find "/watchdog/csgo/builds" -mindepth 1 -maxdepth 1 -type d ! -name "$latest_version" -exec flock -nx "{}/.lockfile" --command "rm -rf \"{}\"" \; || true

    # Update CS:GO if we don't have the latest version
    if [ ! -d "/watchdog/csgo/builds/$latest_version" ]; then
        update_csgo || true
    fi
done