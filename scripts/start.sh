#!/bin/bash
# shellcheck source=scripts/functions.sh
source "/home/steam/server/functions.sh"

SERVER_FILES="/home/steam/server-files"
SERVER_DESC="${SERVER_FILES}/R5/ServerDescription.json"
# Always use the shipping exe directly — WindroseServer.exe wrapper hangs under Wine
SERVER_EXEC="${SERVER_FILES}/R5/Binaries/Win64/WindroseServer-Win64-Shipping.exe"

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

# ─── Clean up incomplete world directories ────────────────────────────────────
# An aborted first-boot run can leave a partial RocksDB world directory that
# causes the server to crash with "data inconsistency". A complete directory
# always contains a CURRENT file; delete any that are missing it.
WORLDS_DIR="${SERVER_FILES}/R5/Saved/SaveProfiles/Default/RocksDB/0.10.0/Worlds"
if [ -d "$WORLDS_DIR" ]; then
    for world_dir in "$WORLDS_DIR"/*/; do
        [ -d "$world_dir" ] || continue
        if [ ! -f "${world_dir}CURRENT" ]; then
            LogWarn "Removing incomplete world directory: $(basename "$world_dir")"
            rm -rf "$world_dir"
        fi
    done
fi

# ─── First-boot config generation ─────────────────────────────────────────────
if [ "${GENERATE_SETTINGS:-true}" = "false" ]; then
    LogInfo "GENERATE_SETTINGS=false — skipping config generation"
elif [ ! -f "$SERVER_DESC" ]; then
    LogAction "First boot detected — generating ServerDescription.json"
    LogInfo "Running server briefly to create default config files..."

    xvfb-run -a wine "$SERVER_EXEC" -log &
    firstrun_pid=$!

    # WorldDescription.json lives at a UUID-based path deep under R5/Saved/
    # so we use `find` rather than a fixed path.
    WORLDS_SAVE_DIR="${SERVER_FILES}/R5/Saved/SaveProfiles/Default/RocksDB/0.10.0/Worlds"

    count=0
    world_desc=""
    while [ "$count" -lt 180 ]; do
        if [ -f "$SERVER_DESC" ]; then
            world_desc=$(find "$WORLDS_SAVE_DIR" -name "WorldDescription.json" -type f 2>/dev/null | head -1)
            [ -n "$world_desc" ] && break
        fi
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

    if [ -z "$world_desc" ]; then
        LogWarn "WorldDescription.json was not found after ${count}s — continuing anyway"
    else
        LogSuccess "WorldDescription.json found: $world_desc"
    fi

    # Give the server a moment to flush writes before we kill it
    sleep 3

    LogSuccess "Config files generated — stopping first-run instance"
    kill "$firstrun_pid" 2>/dev/null
    wait "$firstrun_pid" 2>/dev/null
    wineserver -k 2>/dev/null
    sleep 2
fi

# ─── Resolve P2P proxy address ────────────────────────────────────────────────
# P2pProxyAddress is registered with the Windrose backend so the P2PGate relay
# knows how to route player connections back to this server.  It must be the
# host's LAN IP, not 0.0.0.0 — the backend stores whatever value is here and
# hands it to P2PGate verbatim, so 0.0.0.0 is useless as a routing target.
#
# This container REQUIRES host networking (--network host / Network: host in
# Unraid).  In host-network mode the server process can bind directly to the
# LAN interface, which is what allows LAN IP detection to work correctly.
# Bridge networking will cause the P2P subsystem to fail to initialise.
if [ -n "${P2P_PROXY_ADDRESS}" ] && [ "${P2P_PROXY_ADDRESS}" != "0.0.0.0" ]; then
    LogInfo "Using P2P_PROXY_ADDRESS override: ${P2P_PROXY_ADDRESS}"
else
    P2P_PROXY_ADDRESS=$(ip route get 1.1.1.1 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
    if [ -n "${P2P_PROXY_ADDRESS}" ]; then
        LogInfo "Auto-detected LAN IP for P2P proxy: ${P2P_PROXY_ADDRESS}"
    else
        P2P_PROXY_ADDRESS="0.0.0.0"
        LogWarn "Could not auto-detect LAN IP — falling back to 0.0.0.0 (P2P connections will likely fail)"
    fi
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
        .ServerDescription_Persistent.MaxPlayerCount = $maxplayers
        ' < "$SERVER_DESC" > "$tmp" && mv "$tmp" "$SERVER_DESC"

    LogSuccess "ServerDescription.json patched"
fi

# ─── Launch server ────────────────────────────────────────────────────────────
LogAction "Launching $(basename "$SERVER_EXEC")"
exec xvfb-run -a wine "$SERVER_EXEC" -log
