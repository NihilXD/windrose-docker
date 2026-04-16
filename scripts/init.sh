#!/bin/bash
# shellcheck source=scripts/functions.sh
source "/home/steam/server/functions.sh"

# ─── PUID / PGID ───────────────────────────────────────────────────────────────
if [ -z "${PUID}" ] || [ -z "${PGID}" ]; then
    LogError "PUID and PGID must be set as environment variables"
    exit 1
fi

usermod  -o -u "${PUID}" steam
groupmod -o -g "${PGID}" steam
chown -R steam:steam /home/steam/

cat /branding

# ─── Update / install server files ────────────────────────────────────────────
if [ "${UPDATE_ON_START:-true}" = "true" ]; then
    install
else
    LogWarn "UPDATE_ON_START=false — skipping server update"
fi

chown -R steam:steam /home/steam/server-files

# ─── Signal handler (for clean container shutdown) ────────────────────────────
term_handler() {
    LogInfo "SIGTERM received — shutting down server..."
    if ! shutdown_server; then
        local pid
        pid=$(pgrep -f "WindroseServer-Win64-Shipping" | head -1)
        [ -n "$pid" ] && kill -SIGTERM "$pid"
    fi
    sleep 2
    tail --pid="$killpid" -f 2>/dev/null
}

trap 'term_handler' SIGTERM

# ─── Run server as steam user ─────────────────────────────────────────────────
su - steam -c "
    INVITE_CODE='${INVITE_CODE}' \
    SERVER_NAME='${SERVER_NAME}' \
    SERVER_PASSWORD='${SERVER_PASSWORD}' \
    MAX_PLAYERS='${MAX_PLAYERS:-4}' \
    P2P_PROXY_ADDRESS='${P2P_PROXY_ADDRESS}' \
    GENERATE_SETTINGS='${GENERATE_SETTINGS:-true}' \
    /home/steam/server/start.sh
" &

killpid="$!"
wait "$killpid"
