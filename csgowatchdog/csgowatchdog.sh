#!/bin/bash

set -ueEo pipefail

PINNED_FILE="/watchdog/pinned.txt"

# Read the pinned version for a layer, or nothing if it isn't pinned.
read_pin() {
    local name="$1" pin
    [ -f "$PINNED_FILE" ] || return 0
    pin=$(tr -d '\r' < "$PINNED_FILE" | awk -v n="$name" '{ sub(/#.*/, "") } $1 == n { print $2; exit }')
    [ -n "$pin" ] || return 0
    # The version ends up as a directory name, so keep it to safe characters.
    if ! [[ "$pin" =~ ^[[:alnum:]._+-]+$ ]]; then
        echo "ERROR: Ignoring invalid pin for $name: '$pin'" >&2
        return 0
    fi
    echo "$pin"
}

# Point a layer at a version.
write_layer_version() {
    local latest_file="$1" ver="$2"
    if [ -f "$latest_file" ] && [ "$(cat "$latest_file")" = "$ver" ]; then
        return 0
    fi
    echo "$ver" > "/tmp/layer_latest.txt"
    mv -f "/tmp/layer_latest.txt" "$latest_file"
}

install_git_release() {
    local owner="$1"
    local repo="$2"
    local asset_pattern="$3"
    local name="$4"  # layer name (key for builds dir)
    local builds_dir="/watchdog/layers/$name/builds"
    local latest_file="/watchdog/layers/$name/latest.txt"
    local tmp_dir="/watchdog/layers/.tmp"

    # A pinned layer stays on its version: newer releases are ignored entirely and latest.txt is left alone
    local pin
    pin=$(read_pin "$name")
    if [ -n "$pin" ] && [ -d "$builds_dir/$pin" ] && [ -n "$(ls -A "$builds_dir/$pin")" ]; then
        write_layer_version "$latest_file" "$pin"
        return 0
    fi

    local api_url="https://api.github.com/repos/$owner/$repo/releases?per_page=1"
    if [ -n "$pin" ]; then
        api_url="https://api.github.com/repos/$owner/$repo/releases/tags/$pin"
    fi

    local release_json
    release_json=$(curl -sSL \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "$api_url")

    if [ -n "$pin" ]; then
        if ! echo "$release_json" | jq -e 'has("tag_name")' > /dev/null 2>&1; then
            echo "ERROR: No release tagged '$pin' for $owner/$repo (pinned):"
            echo "$release_json" | jq -r '.message // .'
            return 1
        fi
    else
        if ! echo "$release_json" | jq -e 'type == "array"' > /dev/null 2>&1; then
            echo "ERROR: GitHub API error for $owner/$repo:"
            echo "$release_json" | jq -r '.message // .'
            return 1
        fi

        release_json=$(echo "$release_json" | jq '.[0]')

        if echo "$release_json" | jq -e '. == null' > /dev/null 2>&1; then
            echo "ERROR: No releases found for $owner/$repo (empty or rate-limited response)"
            return 1
        fi
    fi

    local latest
    latest=$(echo "$release_json" | jq -r '.tag_name')

    if [ -d "$builds_dir/$latest" ] && [ -n "$(ls -A "$builds_dir/$latest")" ]; then
        return 0
    fi

    echo "Installing $name: $latest"
    local asset_url
    asset_url=$(echo "$release_json" | jq -r --arg pat "$asset_pattern" \
        '[.assets[] | select((.name | test($pat)) and (.name | test("upgrade") | not) and (.name | test("Website") | not))][0].browser_download_url // empty')

    if [[ -z "$asset_url" ]]; then
        echo "ERROR: No asset matched pattern '$asset_pattern' for $owner/$repo"
        echo "Available assets:"
        echo "$release_json" | jq -r '.assets[].name'
        return 1
    fi

    local tmp_archive="/tmp/${name}_${latest}"
    rm -f "$tmp_archive"
    if ! curl -fsSL "$asset_url" -o "$tmp_archive"; then
        echo "ERROR: Failed to download asset for $name: $asset_url"
        rm -f "$tmp_archive"
        return 1
    fi

    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"

    case "$asset_url" in
        *.zip)
            unzip -o -q "$tmp_archive" -d "$tmp_dir"
            ;;
        *.tar.gz|*.tgz|*.tar.xz|*.tar)
            tar -x --no-same-permissions -f "$tmp_archive" -C "$tmp_dir"
            ;;
        *.smx)
            # Bare plugin binary: build the layer tree the release is missing
            mkdir -p "$tmp_dir/addons/sourcemod/plugins"
            mv "$tmp_archive" "$tmp_dir/addons/sourcemod/plugins/${asset_url##*/}"
            ;;
        *)
            echo "ERROR: Unknown file extension for $name: $asset_url"
            rm -f "$tmp_archive"
            rm -rf "$tmp_dir"
            return 1
            ;;
    esac || { rm -f "$tmp_archive"; rm -rf "$tmp_dir"; return 1; }

    rm -f "$tmp_archive"
    mkdir -p "$builds_dir"
    mv -f "$tmp_dir" "$builds_dir/$latest"

    write_layer_version "$latest_file" "$latest"
}

install_git_release_once() {
    # <owner> <repo> <asset_pattern> <name>
    # For plugins that don't need updating: if the layer is already installed this returns immediately.
    local name="$4"
    local builds_dir="/watchdog/layers/$name/builds"
    local latest_file="/watchdog/layers/$name/latest.txt"

    # A pin overrides whatever happens to be installed.
    if [ -z "$(read_pin "$name")" ] && [ -f "$latest_file" ]; then
        local current
        current=$(cat "$latest_file")
        if [ -n "$current" ] && [ -d "$builds_dir/$current" ] && [ -n "$(ls -A "$builds_dir/$current")" ]; then
            return 0
        fi
    fi

    install_git_release "$@"
}

install_git_repo() {
    # <owner> <repo> <name>: snapshots the default branch as a layer versioned by commit sha
    local owner="$1"
    local repo="$2"
    local name="$3"
    local builds_dir="/watchdog/layers/$name/builds"
    local latest_file="/watchdog/layers/$name/latest.txt"
    local tmp_dir="/watchdog/layers/.tmp"

    local ver
    ver=$(read_pin "$name")
    if [ -z "$ver" ]; then
        ver=$(curl -fsSL \
            ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
            -H "Accept: application/vnd.github.sha" \
            "https://api.github.com/repos/$owner/$repo/commits/HEAD") || ver=""
        if ! [[ "$ver" =~ ^[[:alnum:]]+$ ]]; then
            echo "ERROR: Could not get latest commit for $owner/$repo (got: '$ver')"
            return 1
        fi
    fi

    if [ -d "$builds_dir/$ver" ] && [ -n "$(ls -A "$builds_dir/$ver")" ]; then
        write_layer_version "$latest_file" "$ver"
        return 0
    fi

    echo "Installing $name: $ver"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"
    # The tarball wraps everything in a single <owner>-<repo>-<sha> directory
    if ! curl -fsSL \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "https://api.github.com/repos/$owner/$repo/tarball/$ver" \
        | tar -xz --no-same-permissions --strip-components=1 -C "$tmp_dir"; then
        echo "ERROR: Failed to download $owner/$repo at $ver"
        rm -rf "$tmp_dir"
        return 1
    fi

    mkdir -p "$builds_dir"
    mv -f "$tmp_dir" "$builds_dir/$ver"

    write_layer_version "$latest_file" "$ver"
}


install_metamod() {
    local name="mm"
    local builds_dir="/watchdog/layers/$name/builds"
    local latest_file="/watchdog/layers/$name/latest.txt"
    local tmp_dir="/watchdog/layers/.tmp"
    local url="https://www.metamodsource.net/latest.php?os=linux&version=1.12"

    # Use Content-Disposition header from a HEAD request to get the versioned filename
    local filename
    filename=$(curl -sSLI "$url" | grep -i 'content-disposition' | grep -oP 'filename=\K[^\s;\r]+' | tr -d '"')
    local latest="${filename%.tar.gz}"

    if ! [[ "$latest" =~ ^[[:alnum:]._+-]+$ ]]; then
        echo "ERROR: Could not determine metamod version (got: '$latest')"
        return 1
    fi

    if [ -d "$builds_dir/$latest" ] && [ -n "$(ls -A "$builds_dir/$latest")" ]; then
        return 0
    fi

    echo "Installing metamod: $latest"
    local tmp_archive="/tmp/${name}_${latest}.tar.gz"
    rm -f "$tmp_archive"
    if ! curl -fsSL "$url" -o "$tmp_archive"; then
        echo "ERROR: Failed to download metamod"
        rm -f "$tmp_archive"
        return 1
    fi

    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"
    tar -xz --no-same-permissions -f "$tmp_archive" -C "$tmp_dir" || { rm -f "$tmp_archive"; rm -rf "$tmp_dir"; return 1; }
    rm -f "$tmp_archive"

    mkdir -p "$builds_dir"
    mv -f "$tmp_dir" "$builds_dir/$latest"

    echo "$latest" > "/tmp/layer_latest.txt"
    mv -f "/tmp/layer_latest.txt" "$latest_file"
}

install_sourcemod() {
    local name="sm"
    local builds_dir="/watchdog/layers/$name/builds"
    local latest_file="/watchdog/layers/$name/latest.txt"
    local tmp_dir="/watchdog/layers/.tmp"
    local url="https://www.sourcemod.net/latest.php?os=linux&version=1.12"

    # Use Content-Disposition header from a HEAD request to get the versioned filename
    local filename
    filename=$(curl -sSLI "$url" | grep -i 'content-disposition' | grep -oP 'filename=\K[^\s;\r]+' | tr -d '"')
    local latest="${filename%.tar.gz}"

    if ! [[ "$latest" =~ ^[[:alnum:]._+-]+$ ]]; then
        echo "ERROR: Could not determine sourcemod version (got: '$latest')"
        return 1
    fi

    if [ -d "$builds_dir/$latest" ] && [ -n "$(ls -A "$builds_dir/$latest")" ]; then
        return 0
    fi

    echo "Installing sourcemod: $latest"
    local tmp_archive="/tmp/${name}_${latest}.tar.gz"
    rm -f "$tmp_archive"
    if ! curl -fsSL "$url" -o "$tmp_archive"; then
        echo "ERROR: Failed to download sourcemod"
        rm -f "$tmp_archive"
        return 1
    fi

    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"
    tar -xz --no-same-permissions -f "$tmp_archive" -C "$tmp_dir" || { rm -f "$tmp_archive"; rm -rf "$tmp_dir"; return 1; }
    rm -f "$tmp_archive"

    mkdir -p "$builds_dir"
    mv -f "$tmp_dir" "$builds_dir/$latest"

    echo "$latest" > "/tmp/layer_latest.txt"
    mv -f "/tmp/layer_latest.txt" "$latest_file"
}

update_plugins() {
    local layer_names=(
        "mm" "sm"
        "movementapi" "gokz" "mhud" "autorestart" "fkz-api" "miss" "bsppeek" "steamworks" "sbpp"
        "kzserveradvisor"
        "smjansson" "gokz-lead"
        "mapcrashfixer" "globalapi" "itemcrashfix" "itstoodark" "antifun"
        "whitelist" "morestats" "gokzdiscord" "json" "websocket" "gpb"
        "nolobbyreservation" "showpos" "demofix" "multiappid" "scoreboardtimer" "nms" "nightvision"
        "ztopwatch" "distbug" "vanillatier"
        "ptah" "weapons" "gloves"
        "cfg"
    )

    rm -rf "/watchdog/layers/.tmp"

    install_metamod   # mm
    install_sourcemod # sm

    # SM Plugins
    install_git_release      "FemboyKZ"      "MovementAPI"                  "movementapi"                  "movementapi"
    install_git_release      "FemboyKZ"      "gokz"                         "gokz"                         "gokz"
    install_git_release      "FemboyKZ"      "movementhud"                  "movementhud"                  "mhud"
    install_git_release      "FemboyKZ"      "csgodocker-autorestart"       "linux-mm-1.12"                "autorestart"
    install_git_release      "FemboyKZ"      "sm-fkz-api"                   "fkz-api"                      "fkz-api"
    install_git_release      "FemboyKZ"      "sm-missedby"                  "missedby"                     "miss"
    install_git_release      "jvnipers"      "bsp-peek"                     "steamrt3--mm-1.12--sm-1.12"   "bsppeek"
    #install_git_release      "jvnipers"      "routecalc"                    "ext-steamrt3"                 "routecalc-ext"
    #install_git_release      "jvnipers"      "routecalc"                    "plugin"                       "routecalc"
    install_git_release      "BadServersNet" "SM-SteamWorks"                "linux"                        "steamworks"
    install_git_release      "sbpp"          "sourcebans-pp"                "plugin-only"                  "sbpp"

    # Stable, no updates expected SM plugins
    install_git_release_once "KZGlobalTeam"  "csgo-kz-server-advisor"       "KZServerAdvisor"              "kzserveradvisor"

    install_git_release_once "jvnipers"      "SMJansson"                    "smjansson"                    "smjansson"
    install_git_release_once "jvnipers"      "gokz-lead"                    "gokz-lead"                    "gokz-lead"

    install_git_release_once "misscatmint"   "csgo-fix-mapchange-crash-sm"  "fixcrash"                     "mapcrashfixer"
    install_git_release_once "misscatmint"   "csgo-sm-globalapi"            "GlobalAPI-latest"             "globalapi"
    install_git_release_once "misscatmint"   "itemcrashfix"                 "itemcrashfix"                 "itemcrashfix"
    install_git_release_once "misscatmint"   "its-too-dark"                 "its-too-dark"                 "itstoodark"
    install_git_release_once "misscatmint"   "gokz-nofun"                   "gokz-nofun"                   "antifun"

    install_git_release_once "FemboyKZ"      "sm-server-whitelist-advanced" "serverwhitelistadvanced"      "whitelist"
    install_git_release_once "FemboyKZ"      "more-stats"                   "more-stats"                   "morestats"
    install_git_release_once "FemboyKZ"      "gokz-discord"                 "gokz-discord"                 "gokzdiscord"
    install_git_release_once "FemboyKZ"      "sm-ext-json"                  "sm1.12-steamrt3"              "json"
    install_git_release_once "FemboyKZ"      "sm-ext-websocket"             "steamrt3-sm1.12"              "websocket"
    install_git_release_once "FemboyKZ"      "gokz-gpb-display"             "gokz-gpb-display"             "gpb"

    install_git_release_once "nuxencs"       "NoLobbyReservation"           "NoLobbyReservation"           "nolobbyreservation"
    install_git_release_once "zer0k-z"       "showpos"                      "showpos"                      "showpos"
    install_git_release_once "zer0k-z"       "demo-record-fix"              "demo-record-fix"              "demofix"
    install_git_release_once "zer0k-z"       "csgo-multi-appid"             "linux"                        "multiappid"
    install_git_release_once "DevRuto"       "GOKZ-Scoreboard-Timer"        "scoreboardtimer"              "scoreboardtimer"
    install_git_release_once "Szwagi"        "no-more-sounds"               "no-more-sounds"               "nms"
    install_git_release_once "GAMMACASE"     "NightVision"                  "nightvision"                  "nightvision"

    install_git_release_once "BadServersNet" "sm-zone-stopwatch"            "stopwatch"                    "ztopwatch"
    install_git_release_once "BadServersNet" "sm-distbug"                   "distbugfix"                   "distbug"
    install_git_release_once "BadServersNet" "sm-vanilla-tier"              "vanilla-tier"                 "vanillatier"

    install_git_release_once "komashchenko"  "PTaH"                         "linux"                        "ptah"
    install_git_release_once "kgns"          "weapons"                      "weapons"                      "weapons"
    install_git_release_once "kgns"          "gloves"                       "gloves"                       "gloves"

    # Plugin configs
    install_git_repo "FemboyKZ" "cfg" "cfg"

    # ? plugins, once every 10 minutes
    # ? x 600 = ? / 5000

    (
        flock -nx 200 || exit 0
        for _cleanup_name in "${layer_names[@]}"; do
            _cleanup_latest_file="/watchdog/layers/$_cleanup_name/latest.txt"
            [ -f "$_cleanup_latest_file" ] || continue
            _cleanup_latest=$(cat "$_cleanup_latest_file")
            find "/watchdog/layers/$_cleanup_name/builds" -mindepth 1 -maxdepth 1 -type d ! -name "$_cleanup_latest" \
                -exec rm -rf {} + 2>/dev/null || true
        done
    ) 200>/watchdog/layers/.lockfile || true
}

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
    [ $first -eq 0 ] && sleep 600

    # The temporary directory might exist if update_csgo fails
    rm -rf "/watchdog/.tmp"

    latest_version="13881" || continue

    # Remove outdated CS:GO builds that are not being used by any server
    find "/watchdog/csgo/builds" -mindepth 1 -maxdepth 1 -type d ! -name "$latest_version" -exec flock -nx "{}/.lockfile" --command "rm -rf \"{}\"" \; || true

    # Update CS:GO if we don't have the latest version
    if [ ! -d "/watchdog/csgo/builds/$latest_version" ]; then
        update_csgo || true
    fi

    update_plugins || true
done
