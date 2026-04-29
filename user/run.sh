#!/bin/bash
trap '' SIGINT
set -ueEo pipefail

# initialize variables
databases_cfg=""
actual_gslt=""

# helper functions
append_database() {
    databases_cfg+="\n\"$1\"\n{\ndriver \"$2\"\nhost \"$3\"\nport \"$4\"\ndatabase \"$5\"\nuser \"$6\"\npass \"$7\"\ntimeout \"$8\"\n}\n"
}

install_layer() {
    cp -rf "$root/layers/$1"/* "$server_dir/csgo"
}

install_mount() {
    rm -rf "$server_dir/csgo/$2"
    ln -s "$root/mounts/$1" "$server_dir/csgo/$2"
}

# wrapper for admin mounts
install_mount_admins() {
    install_mount "$1/cfg/admins_simple.ini" "addons/sourcemod/configs/admins_simple.ini"
    install_mount "$1/cfg/admins.cfg" "addons/sourcemod/configs/admins.cfg"
    install_mount "$1/cfg/admin_groups.cfg" "addons/sourcemod/configs/admin_groups.cfg"
    install_mount "$1/cfg/admin_overrides.cfg" "addons/sourcemod/configs/admin_overrides.cfg"
}

# make sure necessary directories exist and copy base game files
mkdir -p "$server_dir/csgo/cfg" "$server_dir/csgo/maps" "$server_dir/csgo/materials" "$server_dir/csgo/models" "$server_dir/csgo/sound" "$server_dir/csgo/addons"
cp -rs "$build_dir"/* "$server_dir"

mkdir -p "mounts/replays" "mounts/maps" "mounts/$ID/sqlite" "mounts/$ID/cfg" "mounts/$ID/logs/sourcemod" "mounts/$ID/logs/csgo" "mounts/$ID/logs/GlobalAPI" "mounts/$ID/logs/GlobalAPI-Retrying"
mkdir -p "mounts/fkz-1/sqlite" "mounts/fkz-1/cfg" "mounts/fkz-1/logs/sourcemod" "mounts/fkz-1/logs/csgo" "mounts/fkz-1/logs/GlobalAPI" "mounts/fkz-1/logs/GlobalAPI-Retrying"

# create server.cfg
cat <<EOF > "$server_dir/csgo/cfg/server.cfg"
    hostname "$HOSTNAME"
    sv_contact "$CONTACT"
    sv_steamgroup "$STEAMGROUP"
    sv_password "$PASSWORD"
    rcon_password "$RCON_PASSWORD"

    host_name_store 1
    host_info_show 1
    host_players_show 2
    sv_lan 0
    sv_region -1
    sv_tags "$TAGS"

    sv_downloadurl "$FASTDL_URL"
    //sv_allowdownload 1
    //sv_allowupload 1
    //sv_workshop_allow_other_maps 1
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

    exec banned_user.cfg
    exec banned_ip.cfg
    writeid
    writeip

    sm_updatemappool

    exec fkz-print.cfg
    mp_restartgame 1
EOF

# Set webapi authkey
rm -f "$server_dir/csgo/webapi_authkey.txt"
echo "$WS_APIKEY" > "$server_dir/csgo/webapi_authkey.txt"

# Install MM & SM
install_layer "MetaMod"
install_layer "SourceMod"

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

# Install KZ plugins and set API key
install_layer "MovementAPI"
install_layer "GOKZ"
echo "$KZ_APIKEY" > "$server_dir/csgo/cfg/sourcemod/globalapi-key.cfg"

# Install misc plugins and disable FollowCSGOServerGuidelines to allow plugins that modify gameplay
install_layer "MiscPlugins"
sed -i -E "s/(\"FollowCSGOServerGuidelines\"[[:space:]]+)\"[^\"]+\"/\1\"no\"/" "$server_dir/csgo/addons/sourcemod/configs/core.cfg"

# Install SBPP and set serverid, also remove basebans
install_layer "SBPP"
sed -i "s/\"ServerID\"\s*\"[^\"]*\"/\"ServerID\"\t\t\"${SBPP_SERVERID}\"/" "$server_dir/csgo/addons/sourcemod/configs/sourcebans/sourcebans.cfg"
rm "$server_dir/csgo/addons/sourcemod/plugins/basebans.smx"

# Install AutoRestart layer
#install_layer "AutoRestart"

# Config general databases
append_database "default" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "0"
append_database "storage-local" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "0"
append_database "clientprefs" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "30"
append_database "no_dupe_account" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "0"
append_database "sourcebans" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_SHARED_NAME" "$DB_USER" "$DB_PASS" "0"

# Config tickrate specific databases
append_database "gokz" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_TICKRATE_NAME" "$DB_USER" "$DB_PASS" "0"
append_database "more-stats" "$DB_DRIVER" "$DB_HOST" "$DB_PORT" "$DB_TICKRATE_NAME" "$DB_USER" "$DB_PASS" "0"

# Install CowAC and AntiDLL if AC is enabled
if [[ "$AC" == "true" ]]; then
    install_layer "CowAC"
fi

# Install whitelist layer if whitelist is enabled
if [[ "$WHITELIST" == "true" ]]; then
    install_layer "whitelist"
    mkdir -p "mounts/$ID/whitelist"
    install_mount "$ID/whitelist" "addons/sourcemod/configs/whitelist"
fi

# Install KZ mapchooser (whitelist modifies normal mapchooser stuff so can't be used together)
if [[ "$WHITELIST" != "true" && "$KZ_MAPTIERS" == "true" ]]; then
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/mapchooser.smx"
    install_layer "KZTierMapchooser"
fi

# Install server-specific layers and mounts
if [[ "$MODE" == "fkz-maptest" ]]; then
    install_layer "fkz-maptest"
    install_mount_admins "$ID"
elif [[ "$MODE" == "fkz" ]]; then
    install_layer "fkz"
    install_mount_admins "fkz-1"
elif [[ "$MODE" == "boakz" ]]; then
    install_layer "boakz"
    install_mount_admins "$ID"
else 
    install_mount_admins "$ID"
fi

# Install realtime stats layer if enabled
if [[ "$RTS" == "true" ]]; then
    install_layer "gokz-rts"

    install_mount "$ID/cfg/gokz-rts.cfg" "addons/sourcemod/configs/gokz-rts.cfg"
fi

# Install 64tick layer if tickrate is 64, and disable incompatible plugins
if [[ "$TICKRATE" == "64" ]]; then
    install_layer "64t"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/gokz-mode-simplekz.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/gokz-mode-kztimer.smx"
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/gokz-global.smx"
fi

# Enable auto bunnyhopping if ABH is enabled, also remove incompatible global plugin
if [[ "$ABH" == "true" ]]; then
    rm -f "$server_dir/csgo/addons/sourcemod/plugins/gokz-global.smx"
    cat <<EOF >> "$server_dir/csgo/cfg/server.cfg"

    sv_cheats 1
    sv_autobunnyhopping 1
    sv_cheats 0
EOF
fi

# Mount mapcycle
install_mount "mapcycle.txt" "mapcycle.txt"
install_mount "mapcycle.txt" "cfg/sourcemod/gokz/gokz-localranks-mappool.cfg"

# Only mount custom maps folder if it has content, otherwise keep base game maps
if [ "$(ls -A /mounts/maps 2>/dev/null)" ]; then
    install_mount "maps" "maps"
fi

# Mount ban cfg files
install_mount "banned_user.cfg" "cfg/banned_user.cfg"
install_mount "banned_ip.cfg" "cfg/banned_ip.cfg"

# Mount appid kickmsg config
install_mount "csgo_appid_kickmsg.txt" "addons/sourcemod/configs/csgo_appid_kickmsg.txt"

# Mount replays and sqlite databases
install_mount "replays/$TICKRATE" "addons/sourcemod/data/gokz-replays"
install_mount "$ID/sqlite" "addons/sourcemod/data/sqlite"

# Mount logs
install_mount "$ID/logs/csgo" "logs"
install_mount "$ID/logs/sourcemod" "addons/sourcemod/logs"
install_mount "$ID/logs/GlobalAPI" "addons/sourcemod/data/GlobalAPI"
install_mount "$ID/logs/GlobalAPI-Retrying" "addons/sourcemod/data/GlobalAPI-Retrying"

# Generate databases.cfg with earlier configured database credentials
cat <<EOF > "$server_dir/csgo/addons/sourcemod/configs/databases.cfg"
"Databases"
{
    "driver_default"		"mysql"
    $(echo -e "$databases_cfg")
}
EOF

# Whether to use new CS:GO appid (4465480)
if [[ "$NEW_APPID" == "true" ]]; then
    if [[ "$GSLT_NEW" != "" ]]; then
        actual_gslt="$GSLT_NEW"
    else
        echo "WARNING: NEW_APPID is true but GSLT_NEW is empty, using old GSLT."
        actual_gslt="$GSLT"
    fi

    sed -i 's/appID=730/appID=4465480/' "$server_dir/csgo/steam.inf"
else 
    actual_gslt="$GSLT"

    sed -i 's/appID=4465480/appID=730/' "$server_dir/csgo/steam.inf"
fi

# Finally, launch the server
"$server_dir/srcds_linux" -game csgo -usercon -strictportbind -ip "$IP" -port "$PORT" -nobreakpad -nowatchdog -nohltv -noautoupdate -tickrate $TICKRATE $EXTRA_LAUNCH_OPTS -apikey "$WS_APIKEY" -maxplayers_override 64 +sv_setsteamaccount "$actual_gslt" +map "$MAP" +exec "server.cfg"
