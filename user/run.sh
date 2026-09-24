#!/bin/bash
trap '' SIGINT
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

# Cleanup old addons to prevent stale files from previous versions.
rm -rf "$server_dir/csgo/addons"

# Make sure necessary directories exist
mkdir -p "$server_dir/csgo/cfg" "$server_dir/csgo/maps" "$server_dir/csgo/materials" "$server_dir/csgo/models" "$server_dir/csgo/sound" "$server_dir/csgo/addons"
mkdir -p "mounts/replays" "mounts/maps" "mounts/$ID/sqlite" "mounts/$ID/logs/sourcemod" "mounts/$ID/logs/csgo" "mounts/$ID/logs/GlobalAPI" "mounts/$ID/logs/GlobalAPI-Retrying"

# Make sure to use new CS:GO appid (4465480)
sed -i 's/appID=730/appID=4465480/' "$server_dir/csgo/steam.inf"

# Helper functions
install_layer() {
    local name="$1"
    local subdir="${2:-}"
    local out_subdir="${3:-}"
    local latest_file="/watchdog/layers/$name/latest.txt"
    local base
    if [[ -f "$latest_file" ]]; then
        local ver
        ver=$(cat "$latest_file")
        base="/watchdog/layers/$name/builds/$ver"
    else
        base="/layers/$name"
    fi
    if [[ -n "$subdir" ]]; then
        for src in "$base"/$subdir; do
            cp -rf "$src"/* "$server_dir/csgo${out_subdir:+/$out_subdir}"
        done
    else
        cp -rf "$base"/* "$server_dir/csgo${out_subdir:+/$out_subdir}"
    fi
}

install_mount() {
    rm -rf "$server_dir/csgo/$2"
    ln -s "/mounts/$1" "$server_dir/csgo/$2"
}

install_maplist() {
    local src="/watchdog/layers/cfg/builds/$(cat /watchdog/layers/cfg/latest.txt)/CSGO/maplists"
    rm -rf "$server_dir/csgo/mapcycle.txt"
    awk '{ sub(/\r$/, "") } NF' "${@/#/$src/}" | LC_ALL=C sort -u > "$server_dir/csgo/mapcycle.txt"
}

install_cfg() {
    rm -rf "$server_dir/csgo/$2"
    mkdir -p "$(dirname "$server_dir/csgo/$2")"
    cp "/watchdog/layers/cfg/builds/$(cat /watchdog/layers/cfg/latest.txt)/$1" "$server_dir/csgo/$2"
}

modify_config() {
    local file="$1"
    local key="$2"
    local value="$3"
    local escaped_value=$(printf '%s' "$value" | sed -e 's/[\x00-\x1F\x7F]/\\&/g' -e 's/[\/&]/\\&/g')
    if grep -Eq "^[[:space:]]*\"?$key\"?[[:space:]]" "$file"; then
        sed -Ei "s/^([[:space:]]*\"?$key\"?[[:space:]]+)\"[^\"]*\"/\1\"$escaped_value\"/" "$file"
    else
        echo "Warning: Key '$key' not found in $file"
    fi
}

append_database() {
    databases_cfg+="\n\"$1\"\n{\ndriver \"$2\"\nhost \"$3\"\nport \"$4\"\ndatabase \"$5\"\nuser \"$6\"\npass \"$7\"\ntimeout \"$8\"\n}\n"
}

# Install MM & SM
install_layer "mm"
install_layer "sm"

# Disable FollowCSGOServerGuidelines to allow plugins that modify gameplay
sed -i -E "s/(\"FollowCSGOServerGuidelines\"[[:space:]]+)\"[^\"]+\"/\1\"no\"/" "$server_dir/csgo/addons/sourcemod/configs/core.cfg"

# Remove default plugins that are not needed
rm -f "$server_dir/csgo/addons/sourcemod/extensions/updater.ext.so"
rm -f "$server_dir/csgo/addons/sourcemod/plugins/funvotes.smx"
rm -f "$server_dir/csgo/addons/sourcemod/plugins/funcommands.smx"
rm -f "$server_dir/csgo/addons/sourcemod/plugins/playercommands.smx"
rm -f "$server_dir/csgo/addons/sourcemod/plugins/nextmap.smx"

# Enable mapchooser
cp "$server_dir/csgo/addons/sourcemod/plugins/disabled/mapchooser.smx" "$server_dir/csgo/addons/sourcemod/plugins/mapchooser.smx"
cp "$server_dir/csgo/addons/sourcemod/plugins/disabled/rockthevote.smx" "$server_dir/csgo/addons/sourcemod/plugins/rockthevote.smx"
cp "$server_dir/csgo/addons/sourcemod/plugins/disabled/nominations.smx" "$server_dir/csgo/addons/sourcemod/plugins/nominations.smx"

# Install MM Plugins
install_layer "autorestart"
install_layer "multiappid"

# Install SM Extensions
install_layer "steamworks"
install_layer "bsppeek"
install_layer "smjansson"
install_layer "ptah"
install_layer "json"
install_layer "websocket"

# Install SM Plugins

# KZ
install_layer "movementapi"
install_layer "gokz"
install_layer "gokz-lead"
install_layer "gokzdiscord"
install_layer "globalapi"
install_layer "morestats"
install_layer "mhud"
install_layer "miss"
install_layer "antifun"
install_layer "showpos"
install_layer "scoreboardtimer"
install_layer "ztopwatch"
install_layer "distbug"
install_layer "vanillatier"
#install_layer "kzserveradvisor"

# Fixes
install_layer "nolobbyreservation"
install_layer "mapcrashfixer"
install_layer "itemcrashfix"

# Misc
install_layer "nms"
install_layer "itstoodark"
install_layer "nightvision"

# Skins
install_layer "weapons"
install_layer "gloves"

# Whitelist
if [[ "$WHITELIST" == "true" ]]; then
    install_layer "whitelist"
fi

# Sourcebans++
if [[ "$MODE" == "fkz" ]]; then
    install_layer "sbpp"
fi

# FKZ API
if [[ "$RTS" == "true" ]]; then
    install_layer "sbpp"
fi

# Create server.cfg
rm -rf "$server_dir/csgo/cfg/server.cfg"
cat <<EOF > "$server_dir/csgo/cfg/server.cfg"
hostname "$HOSTNAME"
sv_contact "admin@femboykz.com"
sv_steamgroup "$STEAMGROUP"
sv_password "$PASSWORD"
rcon_password "$RCON_PASSWORD"

host_name_store 1
host_info_show 2
host_players_show 2
sv_reliableavatardata 1
sv_lan 0
sv_region -1
sv_tags "$TAGS"

sv_downloadurl "$FASTDL_URL"
sv_pure 0
sv_pure_kick_clients 0

sv_hibernate_when_empty 1
sv_hibernate_ms 20
sv_hibernate_postgame_delay 20

sv_minrate 98304
sv_maxrate 0
mp_autokick 0

log on
sv_log_onefile 0
sv_logbans 1
sv_logecho 1
sv_logfile 1
sv_logflush 0

exec fkz-print.cfg
mp_restartgame 1
EOF

# Enable auto-bunnyhopping if enabled
if [[ "${ABH,,,}" == "true" ]]; then
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/gokz-global.smx"
    cat <<EOF >> "$server_dir/csgo/cfg/server.cfg"

sv_cheats 1
sv_autobunnyhopping 1
sv_cheats 0
EOF
fi

echo "$KZ_APIKEY" > "$server_dir/csgo/cfg/sourcemod/globalapi-key.cfg"

# Clear ban cfg files
: > "$server_dir/csgo/cfg/banned_user.cfg"
: > "$server_dir/csgo/cfg/banned_ip.cfg"

# Only mount custom maps folder if it has content, otherwise keep base game maps
if [ "$(ls -A /mounts/maps 2>/dev/null)" ]; then
    install_mount "maps" "maps"
fi

# Mount data
install_mount "replays/$TICKRATE" "addons/sourcemod/data/gokz-replays"
install_mount "$ID/sqlite" "addons/sourcemod/data/sqlite"

# Mount logs
install_mount "$ID/logs/csgo" "logs"
install_mount "$ID/logs/sourcemod" "addons/sourcemod/logs"
install_mount "$ID/logs/GlobalAPI" "addons/sourcemod/data/GlobalAPI"
install_mount "$ID/logs/GlobalAPI-Retrying" "addons/sourcemod/data/GlobalAPI-Retrying"

# Init databases
databases_cfg=""

# Config general databases
append_database "default" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "0"
append_database "storage-local" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "0"
append_database "clientprefs" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "30"
append_database "no_dupe_account" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "0"
append_database "sourcebans" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "0"
append_database "missedby" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "0"

# Config tickrate specific databases
append_database "gokz" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_TICKRATE_NAME" "$DB_USER" "$DB_PASS" "0"
append_database "more-stats" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_TICKRATE_NAME" "$DB_USER" "$DB_PASS" "0"

# Generate databases.cfg with earlier configured database credentials
cat <<EOF > "$server_dir/csgo/addons/sourcemod/configs/databases.cfg"
"Databases"
{
    "driver_default"		"mysql"
    $(echo -e "$databases_cfg")
}
EOF

# Write WebAPI key
rm -f "$server_dir/csgo/webapi_authkey.txt"
echo "$WS_APIKEY" > "$server_dir/csgo/webapi_authkey.txt"

# Run the server.
"$server_dir/srcds_linux" -game csgo -usercon -strictportbind -ip "$IP" -port "$PORT" -nobreakpad -nowatchdog -nohltv -noautoupdate -tickrate $TICKRATE $EXTRA_LAUNCH_OPTS -apikey "$WS_APIKEY" -maxplayers_override 64 +sv_setsteamaccount "$GSLT" +map "$MAP" +exec "server.cfg"
