#!/bin/bash
# shellcheck source=scripts/functions.sh
source "/home/steam/server/functions.sh"

SERVER_FILES="/home/steam/server-files"
SERVER_DESC="${SERVER_FILES}/R5/ServerDescription.json"
# Use the root wrapper exe (mirrors StartServerForeground.bat behaviour)
# which may initialise Steam differently from calling the shipping exe directly
if [ -f "${SERVER_FILES}/WindroseServer.exe" ]; then
    SERVER_EXEC="${SERVER_FILES}/WindroseServer.exe"
else
    SERVER_EXEC="${SERVER_FILES}/R5/Binaries/Win64/WindroseServer-Win64-Shipping.exe"
fi

cd "$SERVER_FILES" || exit 1

LogAction "Starting Windrose Dedicated Server"

# ─── Sanity check ─────────────────────────────────────────────────────────────
if [ ! -f "$SERVER_EXEC" ]; then
    LogError "Server binary not found: $SERVER_EXEC"
    LogError "Server files directory contents:"
    ls -laR "$SERVER_FILES/"
    exit 1
fi

# ─── Wine environment ─────────────────────────────────────────────────────────
export WINEPREFIX="${WINEPREFIX:-${HOME}/.wine}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:-fixme-all}"

# Bootstrap Wine prefix on first run
if [ ! -f "${WINEPREFIX}/system.reg" ]; then
    LogInfo "Initialising Wine prefix (first run — this may take a minute)..."
    xvfb-run -a wineboot --init
    LogSuccess "Wine prefix initialised"
fi

# ─── First-boot config generation ─────────────────────────────────────────────
if [ "${GENERATE_SETTINGS:-true}" = "false" ]; then
    LogInfo "GENERATE_SETTINGS=false — skipping config generation"
elif [ ! -f "$SERVER_DESC" ]; then
    LogAction "First boot detected — generating ServerDescription.json"
    LogInfo "Running server briefly to create default config files..."

    xvfb-run -a wine "$SERVER_EXEC" -log &
    firstrun_pid=$!

    WORLD_DESC="${SERVER_FILES}/R5/WorldDescription.json"

    count=0
    while [ "$count" -lt 120 ]; do
        [ -f "$SERVER_DESC" ] && [ -f "$WORLD_DESC" ] && break
        sleep 1
        count=$((count + 1))
    done

    if [ ! -f "$SERVER_DESC" ]; then
        LogError "ServerDescription.json was not generated after ${count}s"
        LogError "The server may have failed to start or the path has changed"
        kill "$firstrun_pid" 2>/dev/null
        wait "$firstrun_pid" 2>/dev/null
        wineserver -k 2>/dev/null
        exit 1
    fi

    if [ ! -f "$WORLD_DESC" ]; then
        LogWarn "WorldDescription.json was not generated after ${count}s — continuing anyway"
    fi

    LogSuccess "Config files generated — stopping first-run instance"
    kill "$firstrun_pid" 2>/dev/null
    wait "$firstrun_pid" 2>/dev/null
    wineserver -k 2>/dev/null
    sleep 2
fi

# ─── Resolve P2P proxy address ────────────────────────────────────────────────
if [ -z "${P2P_PROXY_ADDRESS}" ]; then
    LogInfo "P2P_PROXY_ADDRESS not set — auto-detecting public IP..."
    P2P_PROXY_ADDRESS=$(curl -sf --max-time 10 https://api.ipify.org)
    if [ -z "${P2P_PROXY_ADDRESS}" ]; then
        LogWarn "Could not detect public IP — falling back to 0.0.0.0"
        P2P_PROXY_ADDRESS="0.0.0.0"
    else
        LogSuccess "Public IP detected: ${P2P_PROXY_ADDRESS}"
    fi
else
    LogInfo "Using P2P_PROXY_ADDRESS: ${P2P_PROXY_ADDRESS}"
fi

# ─── Patch ServerDescription.json with env vars ───────────────────────────────
if [ -f "$SERVER_DESC" ]; then
    LogInfo "Patching ServerDescription.json with environment variables..."
    tmp=$(mktemp)

    jq \
        --arg      proxy       "${P2P_PROXY_ADDRESS}" \
        --arg      invite      "${INVITE_CODE:-}" \
        --arg      name        "${SERVER_NAME:-}" \
        --arg      password    "${SERVER_PASSWORD:-}" \
        --argjson  maxplayers  "${MAX_PLAYERS:-4}" \
        '
        .ServerDescription_Persistent.P2pProxyAddress = $proxy |
        if $invite != ""
            then .ServerDescription_Persistent.InviteCode = $invite
            else . end |
        if $name != ""
            then .ServerDescription_Persistent.ServerName = $name
            else . end |
        if $password != "" then
            .ServerDescription_Persistent.IsPasswordProtected = true |
            .ServerDescription_Persistent.Password = $password
        else
            .ServerDescription_Persistent.IsPasswordProtected = false |
            .ServerDescription_Persistent.Password = ""
        end |
        .ServerDescription_Persistent.MaxPlayers = $maxplayers
        ' < "$SERVER_DESC" > "$tmp" && mv "$tmp" "$SERVER_DESC"

    LogSuccess "ServerDescription.json patched"
fi

# ─── Launch server ────────────────────────────────────────────────────────────
LogAction "Launching $(basename "$SERVER_EXEC")"
exec xvfb-run -a wine "$SERVER_EXEC" -log
