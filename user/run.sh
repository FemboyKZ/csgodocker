#!/bin/bash
trap '' SIGINT
set -ueEo pipefail

databases_cfg=""
append_database() {
    databases_cfg+="\n\"$1\"\n{\ndriver \"$2\"\nhost \"$3\"\nport \"$4\"\ndatabase \"$5\"\nuser \"$6\"\npass \"$7\"\n}\n"
}

install_layer() {
    cp -rf "$root/layers/$1"/* "$server_dir/csgo"
}

install_mount() {
    rm -rf "$server_dir/csgo/$2"
    ln -s "$root/mounts/$1" "$server_dir/csgo/$2"
}

install_mount_admins() {
    install_mount "$1/cfg/admins_simple.ini" "addons/sourcemod/configs/admins_simple.ini"
    install_mount "$1/cfg/admins.cfg" "addons/sourcemod/configs/admins.cfg"
    install_mount "$1/cfg/admin_groups.cfg" "addons/sourcemod/configs/admin_groups.cfg"
    install_mount "$1/cfg/admin_overrides.cfg" "addons/sourcemod/configs/admin_overrides.cfg"
}

mkdir -p "$server_dir/csgo/cfg" "$server_dir/csgo/maps" "$server_dir/csgo/materials" "$server_dir/csgo/models" "$server_dir/csgo/sound" "$server_dir/csgo/addons"
cp -rs "$build_dir"/* "$server_dir"

mkdir -p "mounts/replays" "mounts/maps" "mounts/$ID/sqlite" "mounts/$ID/cfg" "mounts/$ID/logs/sourcemod" "mounts/$ID/logs/csgo" "mounts/$ID/logs/GlobalAPI" "mounts/$ID/logs/GlobalAPI-Retrying"
mkdir -p "mounts/fkz-1/sqlite" "mounts/fkz-1/cfg" "mounts/fkz-1/logs/sourcemod" "mounts/fkz-1/logs/csgo" "mounts/fkz-1/logs/GlobalAPI" "mounts/fkz-1/logs/GlobalAPI-Retrying"

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
    sv_allowdownload 1
    sv_allowupload 1
    sv_workshop_allow_other_maps 1
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

    exec fkz-print.cfg
    mp_restartgame 1
EOF

install_layer "MetaMod"
install_layer "SourceMod"

rm "$server_dir/csgo/addons/sourcemod/extensions/updater.ext.so"
rm "$server_dir/csgo/addons/sourcemod/plugins/funvotes.smx"
rm "$server_dir/csgo/addons/sourcemod/plugins/funcommands.smx"
rm "$server_dir/csgo/addons/sourcemod/plugins/playercommands.smx"

cp "$server_dir/csgo/addons/sourcemod/plugins/disabled/mapchooser.smx" "$server_dir/csgo/addons/sourcemod/plugins/mapchooser.smx"
cp "$server_dir/csgo/addons/sourcemod/plugins/disabled/rockthevote.smx" "$server_dir/csgo/addons/sourcemod/plugins/rockthevote.smx"
cp "$server_dir/csgo/addons/sourcemod/plugins/disabled/nominations.smx" "$server_dir/csgo/addons/sourcemod/plugins/nominations.smx"

append_database "clientprefs" "$DB_CLIENTPREFS_DRIVER" "$DB_CLIENTPREFS_HOST" "$DB_CLIENTPREFS_PORT" "$DB_CLIENTPREFS_NAME" "$DB_CLIENTPREFS_USER" "$DB_CLIENTPREFS_PASS"

install_layer "MovementAPI"
install_layer "GOKZ"
append_database "gokz" "$DB_GOKZ_DRIVER" "$DB_GOKZ_HOST" "$DB_GOKZ_PORT" "$DB_GOKZ_NAME" "$DB_GOKZ_USER" "$DB_GOKZ_PASS"
echo $KZ_APIKEY > "$server_dir/csgo/cfg/sourcemod/globalapi-key.cfg"

install_layer "MiscPlugins"
append_database "more-stats" "$DB_MORESTATS_DRIVER" "$DB_MORESTATS_HOST" "$DB_MORESTATS_PORT" "$DB_MORESTATS_NAME" "$DB_MORESTATS_USER" "$DB_MORESTATS_PASS"
append_database "no_dupe_account" "$DB_NODUPE_DRIVER" "$DB_NODUPE_HOST" "$DB_NODUPE_PORT" "$DB_NODUPE_NAME" "$DB_NODUPE_USER" "$DB_NODUPE_PASS"
sed -i -E "s/(\"FollowCSGOServerGuidelines\"[[:space:]]+)\"[^\"]+\"/\1\"no\"/" "$server_dir/csgo/addons/sourcemod/configs/core.cfg"

install_layer "SBPP"
append_database "sourcebans" "$DB_SBPP_DRIVER" "$DB_SBPP_HOST" "$DB_SBPP_PORT" "$DB_SBPP_NAME" "$DB_SBPP_USER" "$DB_SBPP_PASS"
sed -i "s/\"ServerID\"\s*\"[^\"]*\"/\"ServerID\"\t\t\"${SBPP_SERVERID}\"/" "$server_dir/csgo/addons/sourcemod/configs/sourcebans/sourcebans.cfg"
rm "$server_dir/csgo/addons/sourcemod/plugins/basebans.smx"

if [[ "$AC" == "true" ]]; then
    install_layer "CowAC"
fi

if [[ "$WHITELIST" == "true" ]]; then
    install_layer "whitelist"
    mkdir -p "mounts/$ID/whitelist"
    install_mount "$ID/whitelist" "addons/sourcemod/configs/whitelist"
fi

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

if [[ "$TICKRATE" == "64" ]]; then
    install_layer "64t"
fi

if [[ "ABH" == "true" ]]; then
    cat <<EOF >> "$server_dir/csgo/cfg/server.cfg"

    sv_cheats 1
    sv_autobunnyhopping 1
    sv_cheats 0
EOF
fi

install_mount "mapcycle.txt" "mapcycle.txt"
install_mount "maps" "maps"

install_mount "replays/$TICKRATE" "addons/sourcemod/data/gokz-replays"
install_mount "$ID/sqlite" "addons/sourcemod/data/sqlite"

install_mount "$ID/logs/csgo" "logs"
install_mount "$ID/logs/sourcemod" "addons/sourcemod/logs"
install_mount "$ID/logs/GlobalAPI" "addons/sourcemod/data/GlobalAPI"
install_mount "$ID/logs/GlobalAPI-Retrying" "addons/sourcemod/data/GlobalAPI-Retrying"

cat <<EOF > "$server_dir/csgo/addons/sourcemod/configs/databases.cfg"
    "Databases"
    {
        "driver_default"		"mysql"
        "default"
	    {
		    "driver"			"default"
		    "host"				"localhost"
		    "database"			"sourcemod"
		    "user"				"root"
		    "pass"				""
		    //"timeout"			"0"
		    //"port"			"0"
	    }
        "storage-local"
	    {
		    "driver"			"sqlite"
		    "database"			"sourcemod-local"
	    }
        $(echo -e "$databases_cfg")
    }
EOF

"$server_dir/srcds_linux" -game csgo -usercon -strictportbind -ip "$IP" -port "$PORT" -nobreakpad -nowatchdog -nohltv -noautoupdate -tickrate $TICKRATE "$EXTRA_LAUNCH_OPTS" -apikey "$WS_APIKEY" -maxplayers_override 64 +sv_setsteamaccount "$GSLT" +map "$MAP" +exec "server.cfg"
