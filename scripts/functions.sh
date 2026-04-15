#!/bin/bash

# ─── Colour codes ──────────────────────────────────────────────────────────────
export RESET='\033[0m'
export WHITE='\033[0;37m'
export RED_BOLD='\033[1;31m'
export GREEN_BOLD='\033[1;32m'
export YELLOW_BOLD='\033[1;33m'
export CYAN_BOLD='\033[1;36m'

# ─── Logging ───────────────────────────────────────────────────────────────────
Log()        { printf "${2}%s%s%s${RESET}\n" "${3}" "${1}" "${4}"; }
LogInfo()    { Log "$1" "$WHITE"       "" ""; }
LogWarn()    { Log "$1" "$YELLOW_BOLD" "" ""; }
LogError()   { Log "$1" "$RED_BOLD"    "" ""; }
LogSuccess() { Log "$1" "$GREEN_BOLD"  "" ""; }
LogAction()  { Log "$1" "$CYAN_BOLD"   "==== " " ===="; }

# ─── Install / update server via DepotDownloader ──────────────────────────────
install() {
    LogAction "Downloading Windrose Dedicated Server (App 4129620)"
    /depotdownloader/DepotDownloader \
        -app 4129620 \
        -dir /home/steam/server-files \
        -validate
    LogSuccess "Server download complete"
}

# ─── Graceful shutdown ─────────────────────────────────────────────────────────
# Returns 0 on clean shutdown, 1 if forced kill was needed
shutdown_server() {
    local pid
    pid=$(pgrep -f "WindroseServer-Win64-Shipping" | head -1)

    if [ -z "$pid" ]; then
        return 0
    fi

    LogInfo "Sending SIGTERM to server (pid $pid)..."
    kill -SIGTERM "$pid"

    local count=0
    while [ "$count" -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        count=$((count + 1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        LogWarn "Server did not shut down gracefully — forcing kill"
        kill -SIGKILL "$pid" 2>/dev/null
        return 1
    fi

    LogSuccess "Server shut down gracefully"
    return 0
}
