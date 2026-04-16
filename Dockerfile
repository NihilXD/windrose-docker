FROM --platform=linux/amd64 debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ─── Base dependencies ─────────────────────────────────────────────────────────
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates unzip procps iproute2 \
        wine wine32:i386 wine64 \
        winbind \
        xvfb xauth \
        jq \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── .NET 8 runtime (required by DepotDownloader) ─────────────────────────────
RUN curl -sL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    chmod +x /tmp/dotnet-install.sh && \
    /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share/dotnet && \
    ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet && \
    rm /tmp/dotnet-install.sh

# ─── DepotDownloader ───────────────────────────────────────────────────────────
ARG DEPOT_DOWNLOADER_VERSION=3.4.0
RUN curl -sL \
    "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOT_DOWNLOADER_VERSION}/DepotDownloader-linux-x64.zip" \
    -o /tmp/dd.zip && \
    mkdir -p /depotdownloader && \
    unzip /tmp/dd.zip -d /depotdownloader && \
    chmod +x /depotdownloader/DepotDownloader && \
    rm /tmp/dd.zip

# ─── Steam user ────────────────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash steam

# ─── Default environment ───────────────────────────────────────────────────────
ENV HOME=/home/steam \
    UPDATE_ON_START=true \
    GENERATE_SETTINGS=true \
    INVITE_CODE=windrose \
    SERVER_NAME="Windrose Server" \
    SERVER_PASSWORD="" \
    MAX_PLAYERS=4 \
    P2P_PROXY_ADDRESS="" \
    PUID=99 \
    PGID=100

# ─── Scripts & directories ─────────────────────────────────────────────────────
COPY scripts/ /home/steam/server/
COPY branding  /branding

RUN mkdir -p /home/steam/server-files && \
    chmod +x /home/steam/server/*.sh && \
    chown -R steam:steam /home/steam/

WORKDIR /home/steam/server

HEALTHCHECK --start-period=5m --interval=30s --timeout=10s \
    CMD pgrep -f "WindroseServer-Win64-Shipping" > /dev/null || exit 1

ENTRYPOINT ["/home/steam/server/init.sh"]
