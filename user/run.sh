#!/bin/bash
trap '' SIGINT
set -ueEo pipefail

printf -v log_date '%(%Y-%m-%d_%H-%M-%S)T' -1

echo "Build version: $build_ver"
echo "Restart time: $RESTART_TIME"
echo "Build dir: $build_dir"
echo "Server name: ${HOSTNAME:-}"
echo "Server ID: ${ID:-}"
echo "Date: $log_date"

export daily_restart_time="$RESTART_TIME"
export discord_webhook="$DC_RESTART_WEBHOOK"
export server_name="${HOSTNAME:-}"

# Symlink all the server files.
cp -rs "$build_dir"/* "$server_dir"

# Cleanup old addons to prevent stale files from previous versions.
rm -rf "$server_dir/csgo/addons" "$server_dir/csgo/cfg/sourcemod"

# Make sure necessary directories exist
mkdir -p "$server_dir/csgo/cfg" "$server_dir/csgo/maps" "$server_dir/csgo/materials" "$server_dir/csgo/models" "$server_dir/csgo/sound" "$server_dir/csgo/addons"
mkdir -p "mounts/replays" "mounts/replays/gotas" "mounts/replays/$TICKRATE" "mounts/maps" "mounts/$ID/dumps" "mounts/$ID/sqlite"
mkdir -p "mounts/$ID/logs/sourcemod" "mounts/$ID/logs/console" "mounts/$ID/logs/csgo" "mounts/$ID/logs/global" "mounts/$ID/logs/global-retry"

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
        cp -rf "$base"/. "$server_dir/csgo${out_subdir:+/$out_subdir}"
    fi
}

install_mount() {
    rm -rf "$server_dir/csgo/$2"
    ln -s "/mounts/$1" "$server_dir/csgo/$2"
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
    local section="${4:-}"
    local escaped_value=$(printf '%s' "$value" | sed -e 's/[\x00-\x1F\x7F]/\\&/g' -e 's/[\/&]/\\&/g')
    local range=""
    [[ -n "$section" ]] && range="/^[[:space:]]*\"?$section\"?[[:space:]]*$/,/^[[:space:]]*}/"
    if grep -Eq "^[[:space:]]*\"?$key\"?[[:space:]]" "$file"; then
        sed -Ei "${range}s/^([[:space:]]*\"?$key\"?[[:space:]]+)\"[^\"]*\"/\1\"$escaped_value\"/" "$file"
    else
        echo "Warning: Key '$key' not found in $file"
    fi
}

append_database() {
    local args=() a entry
    for a in "$@"; do
        a="${a//\\/\\\\}"
        args+=("${a//\"/\\\"}")
    done
    printf -v entry '\n"%s"\n{\ndriver "%s"\nhost "%s"\nport "%s"\ndatabase "%s"\nuser "%s"\npass "%s"\ntimeout "%s"\n}\n' "${args[@]}"
    databases_cfg+="$entry"
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
install_layer "routecalc-ext"

# Install SM Plugins

# KZ
install_layer "movementapi"
install_layer "gokz"
#install_layer "gokz-lead"
install_layer "gokzdiscord"
install_layer "globalapi"
install_layer "morestats"
install_layer "mhud"
install_layer "miss"
install_layer "antifun"
install_layer "showpos"
install_layer "showtriggers"
install_layer "scoreboardtimer"
install_layer "ztopwatch"
install_layer "distbug"
install_layer "vanillatier"
install_layer "gpb"
install_layer "kzserveradvisor"
install_layer "routecalc"

# Fixes
install_layer "nolobbyreservation"
install_layer "mapcrashfixer"
install_layer "itemcrashfix"

# Misc
install_layer "nms" "" "addons/sourcemod/plugins"
install_layer "itstoodark"
install_layer "nightvision"
install_layer "gunmenu"
install_layer "redacted"
install_layer "fkz-api"

# Skins
install_layer "weapons"
install_layer "gloves"

# Whitelist
if [[ "${WHITELIST,,}" == "true" ]]; then
    install_layer "whitelist"
fi

# FKZ specific
if [[ "${MODE,,}" == "fkz" ]]; then
    install_layer "sbpp" "sourcebans-pp-*/common"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/basebans.smx"
fi

# Anticheat
if [[ "${AC,,}" == "true" ]]; then
    echo "TODO: AC"
fi

# Disable unused plugins
if [[ "${ABH,,}" == "true" || "${TICKRATE,,}" != "128" ]]; then
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/gokz-global.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/GlobalAPI.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/GlobalAPI-Logging-Flatfile.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/GlobalAPI-Retrying-Binary.smx"
fi

if [[ "${TICKRATE,,}" != "128" ]]; then
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/gokz-mode-simplekz.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/gokz-mode-kztimer.smx"
fi

if [[ "${ID,,}" == boa-* || "${ID,,}" == test-* ]]; then
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/gokz-autoreplay.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/fkz-api.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/sbpp_admcfg.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/sbpp_checker.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/sbpp_comms.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/sbpp_main.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/sbpp_report.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/sbpp_sleuth.smx"
fi

# Only mount custom maps folder if it has content, otherwise keep base game maps
if [ "$(ls -A /mounts/maps 2>/dev/null)" ]; then
    install_mount "maps" "maps"
fi

# Mount data
install_mount "replays/$TICKRATE" "addons/sourcemod/data/gokz-replays"
install_mount "replays/gotas" "addons/sourcemod/data/gotas"
install_mount "$ID/sqlite" "addons/sourcemod/data/sqlite"

# Mount logs
install_mount "$ID/logs/console/$log_date.log" "console.log"
install_mount "$ID/logs/csgo" "logs"
install_mount "$ID/logs/sourcemod" "addons/sourcemod/logs"
install_mount "$ID/logs/global" "addons/sourcemod/data/GlobalAPI"
install_mount "$ID/logs/global-retry" "addons/sourcemod/data/GlobalAPI-Retrying"

# Mount dumps
rm -rf "/tmp/dumps"
ln -s "/mounts/$ID/dumps" "/tmp/dumps"

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
append_database "routecalc" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_TICKRATE_NAME" "$DB_USER" "$DB_PASS" "0"

# Generate databases.cfg with earlier configured database credentials
cat <<EOF > "$server_dir/csgo/addons/sourcemod/configs/databases.cfg"
"Databases"
{
    "driver_default"		"mysql"
    $databases_cfg
}
EOF

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

# Auto-bunnyhopping configs
if [[ "${ABH,,}" == "true" ]]; then
    cat <<EOF >> "$server_dir/csgo/cfg/server.cfg"
sv_cheats 1
sv_autobunnyhopping 1
sv_cheats 0
EOF
fi

if [[ "${ID,,}" == test-* ]]; then
    cat <<EOF >> "$server_dir/csgo/cfg/server.cfg"

    sv_cheats 1
    sm_routecalc_debug 1
EOF
fi

# Clear ban cfg files
: > "$server_dir/csgo/cfg/banned_user.cfg"
: > "$server_dir/csgo/cfg/banned_ip.cfg"

# Install server specific configs
if [[ "${ID,,}" == fkz-* || "${ID,,}" == test-* ]]; then
    install_cfg "SHARED/whitelist.txt" "addons/sourcemod/configs/whitelist/whitelist.txt"

    install_cfg "SHARED/admin_groups.cfg" "addons/sourcemod/configs/admin_groups.cfg"
    install_cfg "SHARED/admins_simple.ini" "addons/sourcemod/configs/admins_simple.ini"
    install_cfg "CSGO/fkz/admin_overrides.cfg" "addons/sourcemod/configs/admin_overrides.cfg"

    install_cfg "CSGO/fkz/gokz-core.cfg" "cfg/sourcemod/gokz/gokz-core.cfg"

    install_cfg "CSGO/fkz/gloves.cfg" "cfg/sourcemod/gloves.cfg"
    install_cfg "CSGO/fkz/weapons.cfg" "cfg/sourcemod/weapons.cfg"
elif [[ "${ID,,}" == boa-* ]]; then
    mkdir -p "$server_dir/csgo/addons/sourcemod/configs/whitelist"
    install_mount "$ID/whitelist/whitelist.txt" "addons/sourcemod/configs/whitelist/whitelist.txt"

    install_cfg "CSGO/boa/admins_simple.ini" "addons/sourcemod/configs/admins_simple.ini"
    install_cfg "CSGO/boa/admin_overrides.cfg" "addons/sourcemod/configs/admin_overrides.cfg"

    install_cfg "CSGO/boa/gokz-core.cfg" "cfg/sourcemod/gokz/gokz-core.cfg"

    install_cfg "CSGO/boa/gloves.cfg" "cfg/sourcemod/gloves.cfg"
    install_cfg "CSGO/boa/weapons.cfg" "cfg/sourcemod/weapons.cfg"
fi

# Install shared configs
install_cfg "CSGO/mapcycle.txt" "mapcycle.txt"
install_cfg "CSGO/mapcycle.txt" "cfg/sourcemod/gokz/gokz-localranks-mappool.cfg"

install_cfg "CSGO/sourcemod/mapchooser.cfg" "cfg/sourcemod/mapchooser.cfg"
install_cfg "CSGO/sourcemod/rtv.cfg" "cfg/sourcemod/rtv.cfg"

install_cfg "CSGO/sourcemod/serverwhitelistadvanced.cfg" "cfg/sourcemod/serverwhitelistadvanced.cfg"
install_cfg "CSGO/sourcemod/sourcebans.cfg" "addons/sourcemod/configs/sourcebans.cfg"

install_cfg "CS2/fkz-print.cfg" "cfg/fkz-print.cfg"

if [[ "${TICKRATE,,}" == "64" ]]; then
    install_cfg "CSGO/sourcemod/gokz/gokz-jumpstats-tiers-64t.cfg" "cfg/sourcemod/gokz/gokz-jumpstats-tiers.cfg"
elif [[ "${TICKRATE,,}" == "102.4" ]]; then
    install_cfg "CSGO/sourcemod/gokz/gokz-jumpstats-tiers-102.4t.cfg" "cfg/sourcemod/gokz/gokz-jumpstats-tiers.cfg"
fi

# Insert secrets into configs
cfg="$server_dir/csgo/addons/sourcemod/configs/fkz-api.cfg"
modify_config "$cfg" "api_key" "$FKZ_APIKEY"
modify_config "$cfg" "server_ip" "$IP"
modify_config "$cfg" "server_port" "$PORT"

cfg="$server_dir/csgo/addons/sourcemod/configs/gokz-discord.cfg"
modify_config "$cfg" "Default" "$DC_GOKZ_WEBHOOK" "Webhook"

# Write KZT API key
rm -f "$server_dir/csgo/cfg/sourcemod/globalapi-key.cfg"
echo "$KZ_APIKEY" > "$server_dir/csgo/cfg/sourcemod/globalapi-key.cfg"

# Write WebAPI key
rm -f "$server_dir/csgo/webapi_authkey.txt"
echo "$WS_APIKEY" > "$server_dir/csgo/webapi_authkey.txt"

if [[ "${ID,,}" == test-* ]]; then
    install_layer "test"
fi

# Run the server.
"$server_dir/srcds_linux" -game csgo -usercon -console -condebug -strictportbind -ip "$IP" -port "$PORT" -nobreakpad -nowatchdog -nohltv -noautoupdate -tickrate $TICKRATE $EXTRA_LAUNCH_OPTS -apikey "$WS_APIKEY" -maxplayers_override 64 +sv_setsteamaccount "$GSLT" +map "$MAP" +exec "server.cfg"
