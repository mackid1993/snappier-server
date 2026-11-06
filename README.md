# Snappier Server — Docker

A ready-to-run Docker setup for [Snappier Server](https://snappierserver.app),
the companion server for the **Snappier IPTV** app on Apple TV, iPhone and
iPad. Pre-built Linux images are published to GitHub Container Registry for
Intel/AMD (`amd64`) and ARM (`arm64`) — no building required.

> **Snappier Server is an add-on for the Snappier IPTV app, not a stand-alone
> player.** It records, gathers your channels, films and shows into one
> playlist, and supplies the TV guide. You watch everything in the Snappier
> IPTV app. Since CLI 2.0.4 the web dashboard no longer plays video in the
> browser; it is for setup and management only.

Runs the newest Snappier Server release (or the beta, or a release you pick)
with FFmpeg **9.0.1** on Ubuntu **26.04 LTS**.

- **Monthly rebuilds.** The image rebuilds on the 1st of each month with a
  fresh Ubuntu base and current packages, so security fixes and dependency
  updates arrive without waiting for a release. Pull `latest` to get them.
- **No image update needed for new Snappier releases.** The container
  installs the Snappier Server build you choose when it starts (see below),
  so a restart picks up a new release.

## Thank you, and credits

This image is built on
**[RyDizz214/snappier-server-docker](https://github.com/RyDizz214/snappier-server-docker)**.
The entrypoint, notification webhook, helper scripts, FFmpeg and Comskip
wrappers, compose files and nearly all of this documentation are his work,
used here with credit (the exact source commit is recorded in
[`UPSTREAM`](UPSTREAM)). A big thank you to RyDizz214 for all the hard work
that went into his container: it is the foundation of everything here. If
you prefer the original, please use his image.

Snappier IPTV and Snappier Server are made by the Snappier developer
([snappierserver.app](https://snappierserver.app),
[snappieriptv.app](https://snappieriptv.app)). This repository only packages
the server for Docker; Snappier Server itself is downloaded from its official
site and remains under its own license.

## How this differs from the original image

Everything works exactly as in RyDizz214's image, with these differences:

1. **You always get the developer's latest release, without waiting for a
   new image.** The original image has one Snappier Server version built in,
   so a new release only arrives with a new image. Here the image contains no
   Snappier Server at all. On every container start it checks
   snappierserver.app for the release you asked for:
   - If that build is already downloaded, it starts immediately with **no
     download**.
   - If there is a newer build, it downloads it **once**, verifies the
     publisher's minisign signature (an unsigned or altered download is never
     run), and keeps it for later starts.
   - If the site can't be reached, it starts the last verified build.

   Choose the build with one new variable, `SNAPPIER_VERSION`:

   | Value | Runs |
   |---|---|
   | `stable` (default) | the latest stable release |
   | `beta` | the latest beta |
   | `2.0.6-15` (any release) | exactly that release |

   To pick up a new release, just restart the container.

2. **New volume for the downloaded builds.** `docker-compose.yml` adds
   `${DATA_DIR:-./data}/snappier-cli:/root/SnappierServer/.snappier-cli`, so
   downloads survive container re-creates. If you use your own compose file,
   add an equivalent mount (or mount the whole `/root/SnappierServer` folder).
   Without it everything still works, but a build is downloaded again after
   each re-create.

3. **FFmpeg can be redistributed.** Same FFmpeg version and options, without
   `--enable-nonfree` and the Fraunhofer `libfdk_aac` encoder (a build with
   those may not be distributed). Where `libfdk_aac` is requested, the FFmpeg
   wrapper uses FFmpeg's built-in AAC encoder at the same bitrate and channel
   count. This and the GPU decoding in `scripts/comskip-wrapper.sh` are the
   only changes to RyDizz214's scripts; both are marked
   `[mackid1993/snappier-server]`.

4. **Reachable on your network out of the box.** The original publishes the
   web UI on `127.0.0.1:7429`, so the Snappier IPTV app can't reach it
   without editing the compose file. Here it is on port `8000` (Snappier's
   own port) on your network. With the VPN overlay, also set
   `PUBLIC_BASE_URL` (see [Add a VPN](#add-a-vpn-optional)).

5. **GPU acceleration for Intel, AMD and NVIDIA.** Comskip decodes on the
   GPU when one is passed in, and FFmpeg is built with VAAPI, Quick Sync and
   NVENC/NVDEC. Two optional variables, `GPU_DEVICE` and `DOCKER_RUNTIME`,
   turn it on; see [GPU acceleration](#gpu-acceleration). The original runs
   everything on the CPU.

6. **Smaller image** (about 540 MB instead of 750 MB), mostly from not
   shipping FFmpeg's build leftovers. Python packages are pinned to the
   versions in the original image.

Files that differ from the original are marked with `[mackid1993]` comments:
`docker-compose.yml` and `docker-compose.vpn.yml` (image name,
`SNAPPIER_VERSION`, the `snappier-cli` volume, the GPU lines, port `8000` on
your network; the unused `SNAPPIER_SERVER_VERSION` build argument is removed),
`example.env` (`SNAPPIER_VERSION` replaces `SNAPPIER_SERVER_VERSION`, plus
`GPU_DEVICE`, `DOCKER_RUNTIME`, `HOST_PORT=8000` and `PUBLIC_BASE_URL`), `ffmpeg-wrapper.sh`,
`scripts/comskip-wrapper.sh`, and the `Dockerfile`. New files: `snappier-select.sh`
(the build selector), `requirements.txt` and the GitHub workflows. Everything
else is byte-for-byte RyDizz214's.

### Switching from the original image

In your compose file, change the image and add the variable and the volume:

```yaml
services:
  snappier-server:
    image: ghcr.io/mackid1993/snappier-server:latest
    environment:
      SNAPPIER_VERSION: "stable"   # or "beta", or e.g. "2.0.6-15"
    volumes:
      - ./data/snappier-cli:/root/SnappierServer/.snappier-cli
```

Your data, settings and every other variable stay exactly as they are. For a
GPU, also add the lines from [GPU acceleration](#gpu-acceleration).

**Snappier is not affiliated with this package and will *not* provide support.**

---

## Install (5 minutes)

### 1. Install Docker on your Linux host

If you don't already have it: <https://docs.docker.com/engine/install/>

Docker Compose v2 is included with modern Docker installs.

### 2. Save the two files

Make a folder named `snappier-server`, save `docker-compose.yml` and `.env`
(below) in it, and keep `.env` private (`chmod 600 .env`). Both are copied
here in full, so there is nothing to download but the image. Every setting
has a default, so the compose file needs no editing.

<details>
<summary><code>docker-compose.yml</code></summary>

```yaml
########################################
# Snappier Server — Base Configuration
#
# Pulls the pre-built multi-arch image from GHCR by default. To build locally
# instead, run: `docker compose build` (uses the bundled Dockerfile).
#
# Usage (standalone, no VPN, built-in ffmpeg):
#   docker compose up -d
#
# Usage (with VPN):
#   docker compose -f docker-compose.yml -f docker-compose.vpn.yml up -d
#
# Usage (host ffmpeg, dev only, x86-64):
#   docker compose -f docker-compose.yml -f docker-compose.host-ffmpeg.yml up -d
#
# Or set COMPOSE_FILE in .env to combine overlays automatically.
########################################

services:
  snappier-server:
    image: ghcr.io/mackid1993/snappier-server:${SNAPPIER_IMAGE_TAG:-latest}
    container_name: snappier-server
    restart: unless-stopped

    # [mackid1993] GPU acceleration (see "GPU acceleration" in the README).
    runtime: ${DOCKER_RUNTIME:-runc} # NVIDIA only. Set DOCKER_RUNTIME=nvidia. Requires the NVIDIA driver and NVIDIA Container Toolkit on the host
    devices:
      - ${GPU_DEVICE:-/dev/null} # Intel or AMD only. Set GPU_DEVICE=/dev/dri. The default /dev/null always exists and does nothing

    build:
      context: .
      dockerfile: Dockerfile
      args:
        USE_HOST_FFMPEG: "${USE_HOST_FFMPEG:-false}"

    ports:
      # [mackid1993] On your network, so the Snappier IPTV app can reach it
      - "${HOST_PORT:-8000}:8000"
      - "127.0.0.1:${NOTIFICATION_HTTP_PORT:-9080}:${NOTIFICATION_HTTP_PORT:-9080}"

    env_file:
      - .env

    environment:
      # [mackid1993] Snappier Server build, installed at container start:
      #   stable (default), beta, or an exact release such as 2.0.6-15
      SNAPPIER_VERSION: "${SNAPPIER_VERSION:-stable}"
      # [mackid1993] NVIDIA only; does nothing unless DOCKER_RUNTIME=nvidia
      NVIDIA_VISIBLE_DEVICES: "${NVIDIA_VISIBLE_DEVICES:-all}"
      NVIDIA_DRIVER_CAPABILITIES: "${NVIDIA_DRIVER_CAPABILITIES:-compute,video,utility}"

      TZ: "${TZ:-UTC}"
      PORT: "8000"
      SNAPPIER_DOMAIN: "${SNAPPIER_DOMAIN:-snappier.local}"
      SNAPPIER_API_TOKEN: "${SNAPPIER_API_TOKEN:-}"
      LOG_ROTATE_ENABLED: "0"

      # EPG
      ENABLE_EPG: "${ENABLE_EPG:-1}"
      EPG_URLS_JSON: "${EPG_URLS_JSON:-}"
      EPG_INTERVAL_HOURS: "${EPG_INTERVAL_HOURS:-6}"

      # Recording / download
      ENABLE_REMUX: "${ENABLE_REMUX:-0}"
      USE_CURL_TO_DOWNLOAD: "${USE_CURL_TO_DOWNLOAD:-false}"
      DOWNLOAD_SPEED_LIMIT_MBS: "${DOWNLOAD_SPEED_LIMIT_MBS:-0}"
      RECORDING_NOTIFY_URL: "http://127.0.0.1:9080/notify"

      # Catch-up extension
      CATCHUP_EXTENSION_ENABLED: "${CATCHUP_EXTENSION_ENABLED:-1}"
      CATCHUP_BUFFER_MINUTES: "${CATCHUP_BUFFER_MINUTES:-5}"

      # Commercial detection on finished recordings (writes .edl sidecars).
      # The image builds its own comskip; these point Snappier at it.
      ENABLE_COMSKIP: "${ENABLE_COMSKIP:-false}"
      COMSKIP_PATH: "${COMSKIP_PATH:-/usr/local/bin/comskip}"
      COMSKIP_INI: "${COMSKIP_INI:-/usr/local/etc/comskip.ini}"

      # Node.js heap (for large EPG merges)
      PKG_NODE_OPTIONS: "--max-old-space-size=16384"
      NODE_OPTIONS: "--max-old-space-size=16384"

      # Notification webhook
      NOTIFICATION_HTTP_PORT: "${NOTIFICATION_HTTP_PORT:-9080}"
      NOTIFICATION_SSE_PATH: "${NOTIFICATION_SSE_PATH:-/events}"

      # Pushover
      PUSHOVER_USER_KEY: "${PUSHOVER_USER_KEY:-}"
      PUSHOVER_APP_TOKEN: "${PUSHOVER_APP_TOKEN:-}"

      # TMDB enrichment
      TMDB_ENABLED: "${TMDB_ENABLED:-1}"
      TMDB_API_KEY: "${TMDB_API_KEY:-}"
      TMDB_CACHE_MAX_SIZE: "${TMDB_CACHE_MAX_SIZE:-500}"
      TMDB_TIMEOUT: "${TMDB_TIMEOUT:-3}"

      # Health watcher
      HEALTH_INTERVAL_SEC: "${HEALTH_INTERVAL_SEC:-30}"
      HEALTH_FAIL_THRESHOLD: "${HEALTH_FAIL_THRESHOLD:-3}"
      HEALTH_WARN_COOLDOWN_SEC: "${HEALTH_WARN_COOLDOWN_SEC:-300}"
      HEALTH_HTTP_TIMEOUT: "${HEALTH_HTTP_TIMEOUT:-5}"
      HEALTH_EXPECT_MIN: "${HEALTH_EXPECT_MIN:-200}"
      HEALTH_EXPECT_MAX: "${HEALTH_EXPECT_MAX:-399}"
      HEALTH_WARN_ON_RECOVERY: "${HEALTH_WARN_ON_RECOVERY:-0}"
      HEALTH_NOTIFY_URL: "${HEALTH_NOTIFY_URL:-http://127.0.0.1:9080/notify}"
      HEALTH_ENDPOINT: "${HEALTH_ENDPOINT:-/serverStats}"
      SNAPPY_API_BASE: "${SNAPPY_API_BASE:-https://127.0.0.1:8000}"
      SNAPPY_API_TIMEOUT: "${SNAPPY_API_TIMEOUT:-5}"

      # Notification display
      NOTIFY_TITLE_PREFIX: "${NOTIFY_TITLE_PREFIX:-Snappier}"
      NOTIFY_DESC_LIMIT: "${NOTIFY_DESC_LIMIT:-900}"

      # FFmpeg wrapper log
      FFMPEG_WRAPPER_LOG: "/root/SnappierServer/logs/ffmpeg_wrapper.log"

    volumes:
      # Host path root for persistent data. Override DATA_DIR in .env
      # (defaults to ./data beside docker-compose.yml).
      - ${DATA_DIR:-./data}/Recordings:/root/SnappierServer/Recordings
      - ${DATA_DIR:-./data}/Movies:/root/SnappierServer/Movies
      - ${DATA_DIR:-./data}/TVSeries:/root/SnappierServer/TVSeries
      - ${DATA_DIR:-./data}/PVR:/root/SnappierServer/PVR
      - ${DATA_DIR:-./data}/epg:/root/SnappierServer/epg
      - ${DATA_DIR:-./data}/certs:/opt/SnappierServer/certs:ro
      - ${DATA_DIR:-./data}/logs:/root/SnappierServer/logs
      - ${DATA_DIR:-./data}/config.json:/root/SnappierServer/config.json
      # [mackid1993] Downloaded Snappier Server builds (selected by
      # SNAPPIER_VERSION). Keeps them across container re-creates so a build
      # is only downloaded once.
      - ${DATA_DIR:-./data}/snappier-cli:/root/SnappierServer/.snappier-cli

    extra_hosts:
      - "${SNAPPIER_DOMAIN:-snappier.local}:127.0.0.1"

    healthcheck:
      test:
        - CMD
        - bash
        - -c
        - timeout 2 bash -c 'echo > /dev/tcp/127.0.0.1/8000' 2>/dev/null
      interval: 30s
      timeout: 8s
      retries: 3
      start_period: 25s

networks:
  default:
    enable_ipv6: false
```

</details>

<details>
<summary><code>.env</code></summary>

```sh
# ============================================================
# Snappier Server — example.env
#
# Copy to .env and fill in your own values:
#   cp example.env .env
#
# Nothing in this file is strictly required for first boot — Snappier will
# come up with safe defaults. The VPN overlay has its own [REQUIRED] vars,
# marked below, which only matter if you include docker-compose.vpn.yml.
# ============================================================

# ---------- Image / build ----------
# Which pre-built image tag to pull from GHCR ("latest" for always-current).
SNAPPIER_IMAGE_TAG=latest

# [mackid1993] Snappier Server build, downloaded and signature-checked at
# container start. A build is downloaded once and cached in
# $DATA_DIR/snappier-cli; later starts only download when a newer release
# exists.
#   stable    latest stable release (default)
#   beta      latest beta
#   2.0.6-15  that exact release
SNAPPIER_VERSION=stable

# [mackid1993] GPU acceleration (Comskip decoding, FFmpeg). Leave both unset
# for CPU only.
#   Intel or AMD: GPU_DEVICE=/dev/dri
#   NVIDIA:       DOCKER_RUNTIME=nvidia  (needs the NVIDIA Container Toolkit)
GPU_DEVICE=
DOCKER_RUNTIME=

# Build FFmpeg from source (false, default) vs mount from host (true, dev only).
# Leave false for 99% of users. Published images ship with a static FFmpeg built
# from source (x264/x265/vpx/opus).
USE_HOST_FFMPEG=false

# ---------- Compose layering ----------
# Uncomment to auto-compose the overlays you want:
#COMPOSE_FILE=docker-compose.yml:docker-compose.vpn.yml
#COMPOSE_FILE=docker-compose.yml:docker-compose.vpn.yml:docker-compose.host-ffmpeg.yml

# ---------- Core ----------
# [mackid1993] Port for the web UI and the Snappier IPTV app, on your network
# (the container always listens on 8000).
HOST_PORT=8000

# [mackid1993] Address the Snappier IPTV app uses to reach this server, e.g.
# http://192.168.1.50:8000. Required with the VPN overlay: inside gluetun the
# server would otherwise give the app its internal Docker address and
# playback fails. Leave blank without a VPN.
PUBLIC_BASE_URL=

# IANA timezone. See: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
# Leave as UTC if unsure.
TZ=UTC

# Hostname Snappier advertises (used by TLS / HLS). Keep default unless you've
# set up a reverse proxy with a real hostname.
SNAPPIER_DOMAIN=snappier.local

# API token. LEAVE BLANK — Snappier auto-generates one on first launch and
# stores it in data/config.json. Find it in the Dashboard Settings or in
# config.json after the container starts.
#
# Only set this if you want to PIN a specific token across rebuilds (e.g. so
# the bundled helper scripts keep working without re-reading config.json).
# Setting it here will overwrite whatever Snappier generates.
SNAPPIER_API_TOKEN=

# Host directory holding all persistent data (recordings, movies, series, epg,
# logs, config). Will be created on first boot. Relative paths are resolved
# against the directory containing docker-compose.yml.
DATA_DIR=./data

# ---------- EPG ----------
ENABLE_EPG=1
EPG_INTERVAL_HOURS=6

# Multi-provider EPG list as a single-line JSON array. Example:
# EPG_URLS_JSON=[{"url":"https://example.com/xmltv.php?username=U&password=P","name":"Provider1","priority":1,"enabled":true,"tvGuide":true}]
EPG_URLS_JSON=

# Hosts allowed to talk plain HTTP (never upgraded to HTTPS). Comma-separated.
ALLOW_HTTP_HOSTS=localhost,127.0.0.1,snappier-server

# ---------- Recording / download ----------
ENABLE_REMUX=1
DOWNLOAD_SPEED_LIMIT_MBS=0
USE_CURL_TO_DOWNLOAD=false

# Catch-up (timeshift) extension: add N minutes to every catch-up download so
# the end of the show isn't clipped.
CATCHUP_EXTENSION_ENABLED=1
CATCHUP_BUFFER_MINUTES=5

# ---------- Commercial detection (Comskip) ----------
# Runs Comskip on finished recordings and writes a .edl sidecar marking
# commercial breaks, which players use to skip them. Off by default: it is
# CPU-heavy and takes minutes per recording.
# The image builds its own Comskip — the paths below are where it lands, and
# you only need to change them to supply your own binary or tuning file.
ENABLE_COMSKIP=false
COMSKIP_PATH=/usr/local/bin/comskip
COMSKIP_INI=/usr/local/etc/comskip.ini

# ---------- HLS live-playback tuning ----------
# Optimises dashboard HLS playback: switches H.264 sources to -c copy (zero CPU).
# Non-H.264 sources keep Snappier's transcode args unchanged. Disable (0) if you
# hit playback issues.
HLS_OPTIMIZE_ENABLED=1

# ---------- Notifications (webhook) ----------
# Port the FastAPI webhook listens on inside the container. 0 = disable.
NOTIFICATION_HTTP_PORT=9080
NOTIFICATION_SSE_PATH=/events
NOTIFY_TITLE_PREFIX=Snappier
NOTIFY_DESC_LIMIT=900

# ---------- Pushover (optional) ----------
# Leave blank to disable.
PUSHOVER_USER_KEY=
PUSHOVER_APP_TOKEN=

# ---------- TMDB metadata enrichment (optional) ----------
# Free API key: https://www.themoviedb.org/settings/api
TMDB_ENABLED=1
TMDB_API_KEY=
TMDB_CACHE_MAX_SIZE=500
TMDB_TIMEOUT=5

# ---------- Health watcher ----------
HEALTH_INTERVAL_SEC=30
HEALTH_FAIL_THRESHOLD=3
HEALTH_WARN_COOLDOWN_SEC=300
HEALTH_HTTP_TIMEOUT=5
HEALTH_EXPECT_MIN=200
HEALTH_EXPECT_MAX=399
HEALTH_WARN_ON_RECOVERY=0
HEALTH_ENDPOINT=/serverStats
SNAPPY_API_BASE=https://127.0.0.1:8000
SNAPPY_API_TIMEOUT=5

# ============================================================
# VPN (gluetun overlay) — only applies when you include
# docker-compose.vpn.yml. Leave blank if you're not using VPN.
#
# gluetun supports 40+ providers (NordVPN, Mullvad, ProtonVPN, PIA,
# Surfshark, AirVPN, ...). Pick yours and set the required vars.
# Full reference: https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers
# ============================================================

# [REQUIRED if VPN overlay is used]
# Provider name in lowercase. Examples: nordvpn | mullvad | protonvpn |
# private internet access | surfshark | airvpn | custom
VPN_SERVICE_PROVIDER=

# wireguard | openvpn (provider-dependent — check gluetun docs)
VPN_TYPE=wireguard

# --- WireGuard auth (when VPN_TYPE=wireguard) ---
# Most providers: just the private key. Mullvad/AirVPN also need addresses.
WIREGUARD_PRIVATE_KEY=
#WIREGUARD_PRESHARED_KEY=
#WIREGUARD_ADDRESSES=

# --- OpenVPN auth (when VPN_TYPE=openvpn) ---
#OPENVPN_USER=
#OPENVPN_PASSWORD=

# --- Server selection (all optional, all provider-dependent) ---
# Country / region / city / hostname filters. Leave blank for "any server".
SERVER_COUNTRIES=
SERVER_CITIES=
#SERVER_REGIONS=
#SERVER_HOSTNAMES=

# --- gluetun runtime knobs ---
# Ports allowed through gluetun's firewall (must include 8000 for Snappier).
FIREWALL_INPUT_PORTS=8000
# gluetun HTTP control server (off 8000 to avoid colliding with snappier-server).
HTTP_CONTROL_SERVER_ADDRESS=:8001
DNS_PLAINTEXT_ADDRESS=9.9.9.9
BLOCK_MALICIOUS=off
HTTPPROXY=off
```

</details>

### 3. Start it

In that folder:

```bash
docker compose pull
docker compose up -d
```

That's it. Your recordings will be saved to a new `data/` folder right next
to `docker-compose.yml`.

---

## Open the Web UI

The Web UI (dashboard) is where you set Snappier Server up and manage it:
providers, the TV guide, recordings and settings. It also walks you through
connecting the Snappier IPTV app. It does not play video; watch in the app.

Go to **`http://<docker-host-ip>:8000`** in a browser on any device on your
network (or `http://localhost:8000` on the Docker host itself). The Snappier
IPTV app connects to the same address.

The port is open to your local network so the app can reach it. Don't
forward it to the internet; for access from outside, use a VPN such as
Tailscale or a reverse proxy with HTTPS.

---

## Find your API token

Snappier creates an API token the first time it starts. The easiest place to
see it is in the container's logs:

```bash
docker logs snappier-server | grep -i token
```

(It's also stored in `data/config.json`, and visible in the Web UI's
**Dashboard → Settings** once you can reach the UI.)

---

## What you get out of the box

Everything below is already in the image — no extra setup needed:

- **FFmpeg 9.0.1** (built from source with x264/x265/vpx/opus).
  **You do NOT need to install FFmpeg on the host** — it's inside the
  container.
- **Recording optimisations:** HLS streams from H.264 sources are copied
  instead of re-encoded, catch-up (timeshift) extension, automatic retry if a
  remux fails.
- **Notifications:** a webhook that fires on every recording event. Plug in
  Pushover keys to get push notifications on your phone (see below).
- **Background helpers** that keep metadata tidy, monitor health, and cache
  provider data.
- **Comskip** for commercial detection on finished recordings, writing `.edl`
  sidecars that players use to skip breaks. Off by default — see below.

---

## Common things you'll want to set

Edit `.env` and uncomment / fill in these:

| If you want…                          | Set this in `.env`                                          |
|---------------------------------------|-------------------------------------------------------------|
| Your own timezone                     | `TZ=America/New_York` *(or any IANA zone)*                  |
| A different web port                  | `HOST_PORT=8080` *(default is 8000)*                        |
| Your IPTV provider's EPG (TV guide)   | `EPG_URLS_JSON=[{...}]` *(see comments in example.env)*     |
| Push notifications on your phone      | `PUSHOVER_USER_KEY=…` and `PUSHOVER_APP_TOKEN=…`            |
| Commercial skipping on recordings     | `ENABLE_COMSKIP=true` *(CPU-heavy; takes minutes per recording)* |
| Longer catch-up safety margin         | `CATCHUP_BUFFER_MINUTES=10` *(default is 5)*                 |
| Posters & descriptions in notifications | `TMDB_API_KEY=…` *(free key from themoviedb.org; enriches notification messages only — Snappier still records fine without it)* |

After any change to `.env`, restart:

```bash
docker compose up -d
```

---

## Add a VPN (optional)

If you want all IPTV traffic routed through a VPN, Snappier supports 40+ VPN
providers via [gluetun](https://github.com/qdm12/gluetun) (NordVPN, Mullvad,
ProtonVPN, PIA, Surfshark, AirVPN, and more).

1. Add your VPN settings to `.env`. Example for Mullvad over WireGuard:

   ```env
   VPN_SERVICE_PROVIDER=mullvad
   VPN_TYPE=wireguard
   WIREGUARD_PRIVATE_KEY=<paste-your-key>
   SERVER_COUNTRIES=Sweden
   ```

   The exact variable names for your provider are in the
   [gluetun wiki](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers).

2. Set `PUBLIC_BASE_URL` in `.env` to the address the app uses, for example
   `PUBLIC_BASE_URL=http://192.168.1.50:8000`. Inside gluetun the server
   would otherwise give the app its internal Docker address, and playback
   fails.

3. Save `docker-compose.vpn.yml` (below) next to `docker-compose.yml`.

<details>
<summary><code>docker-compose.vpn.yml</code></summary>

```yaml
########################################
# Snappier Server — VPN Overlay (gluetun)
#
# Routes snappier-server traffic through a gluetun VPN sidecar. Independent of
# the ffmpeg overlay — use whichever combination you need:
#
#   VPN, built-in ffmpeg (most users):
#     docker compose -f docker-compose.yml -f docker-compose.vpn.yml up -d
#
#   VPN + host ffmpeg (x86-64 dev only):
#     docker compose -f docker-compose.yml \
#                    -f docker-compose.vpn.yml \
#                    -f docker-compose.host-ffmpeg.yml up -d
#
# Or set COMPOSE_FILE in .env to combine overlays automatically.
#
# PROVIDER-AGNOSTIC: gluetun supports 40+ VPN providers. Configure yours by
# setting VPN_SERVICE_PROVIDER, VPN_TYPE, and the provider-specific auth vars
# (WIREGUARD_PRIVATE_KEY, OPENVPN_USER, OPENVPN_PASSWORD, etc.) in .env.
# Full provider list & required vars: https://github.com/qdm12/gluetun-wiki
#
# All variables in .env are passed through to the gluetun container, so any
# gluetun-supported knob (SERVER_REGIONS, SERVER_HOSTNAMES, etc.) works
# without editing this file.
########################################

services:
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: snappier-gluetun
    init: true
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    # Ports move here because snappier-server shares gluetun's network namespace
    ports:
      # [mackid1993] On your network, so the Snappier IPTV app can reach it
      - "${HOST_PORT:-8000}:8000"
      - "127.0.0.1:${NOTIFICATION_HTTP_PORT:-9080}:${NOTIFICATION_HTTP_PORT:-9080}"
    # All VPN config comes from .env — any gluetun var (VPN_SERVICE_PROVIDER,
    # VPN_TYPE, WIREGUARD_PRIVATE_KEY, OPENVPN_USER, SERVER_COUNTRIES, etc.)
    # is passed through automatically.
    env_file:
      - .env
    environment:
      # Only firewall plumbing is pinned here (must match Snappier's port)
      FIREWALL_INPUT_PORTS: "${FIREWALL_INPUT_PORTS:-8000}"
    # Base compose pins SNAPPIER_DOMAIN→127.0.0.1 as an internal hairpin shortcut.
    # That only works when SNAPPIER_DOMAIN is a placeholder (e.g. snappier.local).
    # When it's a REAL public hostname, snappier-server's ffmpeg HLS pipeline
    # tries to fetch https://<real-domain>/recordings/stream/... and lands on
    # 127.0.0.1:443 inside the gluetun namespace (nothing listening) →
    # "Connection refused" → manifest never produces segments → playback fails.
    # Clear it so DNS resolves naturally and the request goes out via VPN/tunnel.
    extra_hosts: !reset []
    volumes:
      - ./gluetun:/gluetun
    healthcheck:
      test:
        - CMD-SHELL
        - ping -c 1 8.8.8.8 || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  snappier-server:
    # Route all traffic through gluetun
    network_mode: service:gluetun
    depends_on:
      gluetun:
        condition: service_healthy
    # network_mode: service:X forbids ports/extra_hosts on the joining container
    ports: !reset []
    extra_hosts: !reset []
    labels:
      - com.centurylinklabs.watchtower.depends-on=snappier-gluetun
```

</details>

4. Start with the VPN turned on:

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.vpn.yml up -d
   ```

Snappier Server 2.0.2 also has its own VPN/proxy setting (dashboard:
Settings → IPTV Provider → *Send provider traffic through a VPN or proxy*). It
is off by default. Use either that or the gluetun overlay above, not both —
turning it on under gluetun puts provider traffic through two tunnels.

---

## GPU acceleration

The heaviest job in this container is commercial detection: Comskip decodes
every finished recording in full, which can keep several CPU cores busy for
minutes. With a GPU passed in, Comskip decodes on the GPU instead. On an Intel
UHD 770 (12th-gen Core) this roughly halved Comskip's CPU time with the same
commercial breaks found.

| GPU | Set in `.env` | Used for |
|---|---|---|
| Intel (Broadwell and newer) | `GPU_DEVICE=/dev/dri` | Comskip decoding (Quick Sync) and FFmpeg (VAAPI, Quick Sync) |
| AMD | `GPU_DEVICE=/dev/dri` | FFmpeg (VAAPI). Comskip has no AMD decoder, so it stays on the CPU |
| NVIDIA | `DOCKER_RUNTIME=nvidia` | Comskip decoding (NVDEC) and FFmpeg (NVENC/NVDEC) |

- NVIDIA needs the NVIDIA driver and the
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  on the host (on Unraid, the Nvidia Driver plugin).
- Nothing else to configure: the container detects the GPU itself. If a GPU
  run ever fails, Comskip repeats it on the CPU, so a GPU problem never
  costs you commercial markers.
- Snappier Server's own recording and remux steps copy the stream without
  re-encoding, so they barely use the CPU with or without a GPU. FFmpeg's GPU
  support is there for any transcoding.
- Quick Sync needs Intel's libraries, which exist for `amd64` only; on `arm64`
  the image has VAAPI and NVIDIA support.

---

## Where are my files?

Everything lives under `data/` beside `docker-compose.yml`:

```
data/
├── Recordings/     # Scheduled + live recordings
├── Movies/         # VOD movies
├── TVSeries/       # VOD series
├── PVR/            # Timer / PVR state
├── epg/            # Cached TV guide data
├── logs/           # All server + wrapper logs
├── snappier-cli/   # Downloaded Snappier Server builds (newest three kept)
└── config.json     # Snappier's own config (includes your API token)
```

Want them somewhere else? Set `DATA_DIR=/some/other/path` in `.env`.

---

## Basic commands cheat sheet

```bash
docker compose up -d           # start (detached)
docker compose down            # stop and remove containers
docker compose pull            # download the latest image
docker compose restart         # quick restart
docker compose logs -f         # follow the logs
docker logs -f snappier-server # just the Snappier container's logs
```

---

## Troubleshooting

<details>
<summary>I can't reach the server from another device</summary>

- Use the Docker host's IP address and the port in `HOST_PORT` (default
  `8000`): `http://<docker-host-ip>:8000`.
- Check the host's firewall allows that port from your network.
- With the VPN overlay, set `PUBLIC_BASE_URL` in `.env` to that same
  address. Without it, the dashboard loads but playback in the app fails,
  because the server gives the app its internal Docker address.

</details>

<details>
<summary>Where's my API token?</summary>

Quickest:

```bash
docker logs snappier-server | grep -i token
```

Also visible in `data/config.json` and the Web UI's **Dashboard → Settings**.

</details>

<details>
<summary>Something broke — how do I reset?</summary>

```bash
docker compose down
docker compose pull
docker compose up -d
```

If you want to nuke the data too, delete the `data/` folder. **This wipes
your recordings** — don't do it unless you mean it.

</details>

---

## Advanced

<details>
<summary>Build the image yourself instead of pulling from GHCR</summary>

Building needs the whole repository (the Dockerfile and scripts), so clone it
first, then from its folder:

```bash
docker compose build
docker compose up -d
```

The Dockerfile handles both `amd64` and `arm64` automatically via Docker's
`TARGETARCH`. The FFmpeg build stage compiles the pinned version (9.0.1); pass
`--build-arg FFMPEG_VERSION=latest` to build the newest upstream stable
instead.

</details>

<details>
<summary>Use your host's FFmpeg instead of the built-in one</summary>

The built-in FFmpeg is fully featured, including GPU acceleration (see
[GPU acceleration](#gpu-acceleration)), and works on both Intel and ARM. Only
override it if you need a vendor-patched FFmpeg. This overlay mounts the
wrapper scripts from the repository, so run it from a clone. **x86-64 hosts
only.**

```bash
docker compose -f docker-compose.yml -f docker-compose.host-ffmpeg.yml up -d
```

</details>

<details>
<summary>Turn on VPN + host FFmpeg at the same time</summary>

```env
# in .env
COMPOSE_FILE=docker-compose.yml:docker-compose.vpn.yml:docker-compose.host-ffmpeg.yml
```

Then just `docker compose up -d`.

</details>

<details>
<summary>Full variable reference</summary>

See the `.env` file under [Install](#install-5-minutes): every supported
variable is documented inline.

</details>

---

## License

See upstream Snappier Server licensing at <https://snappierserver.app>. This
repository contains only the Docker packaging, wrappers, and helper scripts;
those are by RyDizz214 except `snappier-select.sh`, `requirements.txt`, the
workflows and the changes described at the top.
