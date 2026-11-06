# Snappier Server for Docker

**Snappier is not affiliated with this package and will *not* provide support.**

[Snappier Server](https://snappierserver.app) is the companion server for the
**Snappier IPTV** app on Apple TV, iPhone and iPad. It records, gathers your
channels, films and shows into one playlist, and supplies the TV guide. You
watch in the app; the server's web dashboard is for setup and management.

This image runs Snappier Server in Docker on Intel/AMD (`amd64`) and ARM
(`arm64`). It is built on
[RyDizz214/snappier-server-docker](https://github.com/RyDizz214/snappier-server-docker)
(see [Credits](#credits-and-thanks)).

## What this image adds

- **Always the latest Snappier release, no image update needed.** The image
  doesn't contain Snappier Server. On every start it installs the release you
  choose (`stable`, `beta` or an exact version) from snappierserver.app. A
  build is downloaded once; later starts reuse it until there is a newer
  release. A restart is all it takes to update.
- **Every download is verified** with the publisher's minisign signature
  before it runs. If the site is down, the last verified build starts.
- **GPU acceleration for Intel, AMD and NVIDIA.** Commercial detection
  (Comskip) decodes on the GPU, and FFmpeg has VAAPI, Quick Sync and
  NVENC/NVDEC. On a 12th-gen Intel iGPU, Comskip's CPU use roughly halved.
- **Works on your network out of the box:** port `8000`, reachable from the
  app, and `PUBLIC_BASE_URL` for setups behind a VPN.
- **A fresh install just works, and keeps everything.** The whole data folder
  is mounted, so nothing Snappier writes is lost on a re-create (guide
  catalog, metadata database, settings). Mounting `config.json` on its own
  makes Docker create a directory on a fresh install, and the server
  restart-loops.
- **A redistributable FFmpeg** (no non-free components) and a smaller image.
- **Monthly rebuilds** on the 1st with a fresh Ubuntu base and current
  packages, so security fixes arrive on their own. Pull `latest` to get them.

Everything else (the notification webhook, health watcher, metadata fixer,
FFmpeg wrapper, Comskip, every variable) works as in the original image.

---

## Install

You need Docker with Docker Compose v2
([install Docker](https://docs.docker.com/engine/install/)).

1. Make a folder named `snappier-server` and save these two files in it.
   Every setting has a default, so neither needs editing to start. Keep
   `.env` private (`chmod 600 .env`).

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
      # [mackid1993] The whole data folder (config.json, PVR, epg, logs,
      # Recordings, Movies, TVSeries, the Xtream catalog and the downloaded
      # Snappier builds in .snappier-cli). Defaults to ./data beside this
      # file; override DATA_DIR in .env. Mounting config.json on its own, as
      # the original does, makes Docker create a directory on a fresh install
      # and the server restart-loops.
      - ${DATA_DIR:-./data}:/root/SnappierServer
      - ${DATA_DIR:-./data}/certs:/opt/SnappierServer/certs:ro

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
# $DATA_DIR/.snappier-cli; later starts only download when a newer release
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

2. In that folder, start it:

   ```bash
   docker compose up -d
   ```

3. Open **`http://<docker-host-ip>:8000`** in a browser. The dashboard walks
   you through adding your IPTV provider and connecting the Snappier IPTV
   app, which uses the same address.

The settings most people change:

| Variable | Default | What it does |
|---|---|---|
| `SNAPPIER_VERSION` | `stable` | Which Snappier Server to run: `stable`, `beta`, or an exact release such as `2.0.6-15`. See [Versions and updates](#versions-and-updates). |
| `HOST_PORT` | `8000` | Port for the dashboard and the app. |
| `TZ` | `UTC` | Your timezone (for example `America/New_York`), used for recording times. |
| `DATA_DIR` | `./data` | Where settings, the guide, logs and recordings are kept. See [Your files](#your-files). |
| `PUBLIC_BASE_URL` | empty | The address the app uses, for example `http://192.168.1.50:8000`. Only needed with the VPN. |
| `ENABLE_COMSKIP` | `false` | `true` marks commercial breaks in finished recordings. See [Commercial detection](#commercial-detection). |
| `GPU_DEVICE` / `DOCKER_RUNTIME` | empty | GPU acceleration. See [GPU acceleration](#gpu-acceleration). |
| `ENABLE_REMUX` | `1` | `1` saves finished recordings as `.mkv`; `0` keeps `.ts`. |
| `EPG_URLS_JSON` | empty | Extra TV guide sources as JSON (example in `.env`). Most people add guides in the dashboard instead. |
| `PUSHOVER_USER_KEY` / `PUSHOVER_APP_TOKEN` | empty | Push notifications. See [Notifications](#notifications). |

After changing `.env`, apply it with `docker compose up -d`.

---

## Versions and updates

There are two separate things to keep current:

| What | How it updates |
|---|---|
| **Snappier Server** (the app) | Restart the container: `docker compose restart`. It installs the newest release for your `SNAPPIER_VERSION`, or keeps the current one if nothing is newer. |
| **The image** (Ubuntu, FFmpeg, Comskip, scripts) | Rebuilt on the 1st of each month. Update with `docker compose pull && docker compose up -d`. |

`SNAPPIER_VERSION` values:

- `stable`: the latest stable release (recommended).
- `beta`: the latest beta, for new features and fixes before they reach
  stable.
- An exact release such as `2.0.6-15`: stays on that build. Use it to roll
  back or to hold a version.

To see what is running and whether a start downloaded anything:

```bash
docker logs snappier-server 2>&1 | grep snappier-select
```

`running Snappier Server 2.0.6-17 (SNAPPIER_VERSION=beta)` alone means the
cached build started. `downloading` and `signature verified` before it mean a
new release was installed. Downloaded builds are kept in
`DATA_DIR/.snappier-cli` (the newest three).

---

## Your files

Everything is kept under `DATA_DIR` (`./data` beside the compose file by
default):

```
data/
├── Recordings/     # Recordings
├── Movies/         # Downloaded movies
├── TVSeries/       # Downloaded series
├── PVR/            # Recording rules and schedules
├── epg/            # Cached TV guide
├── logs/           # Server and FFmpeg logs
├── Xtream/         # Provider channel catalog
├── .snappier-cli/  # Downloaded Snappier Server builds (newest three)
└── config.json     # Snappier's settings, including the API token
```

Back up `config.json` and `PVR/` to keep your setup and recording rules.

**API token.** Snappier creates one on first start and logs where to find it
(`docker logs snappier-server | grep -i token`): in the dashboard's
preferences, or as `api_token` in `config.json`. Only set `SNAPPIER_API_TOKEN`
in `.env` if you want to pin your own.

---

## VPN (optional)

Routes all of Snappier's provider traffic (logins, guides, streams,
recordings) through a VPN with [gluetun](https://github.com/qdm12/gluetun),
which supports 40+ providers. If the tunnel drops, gluetun blocks traffic
instead of leaking it.

1. Add your provider's settings to `.env`. For example, Mullvad over
   WireGuard:

   ```sh
   VPN_SERVICE_PROVIDER=mullvad
   VPN_TYPE=wireguard
   WIREGUARD_PRIVATE_KEY=<your key>
   SERVER_COUNTRIES=Sweden
   ```

   Your provider's variable names are in the
   [gluetun wiki](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers).

2. Set `PUBLIC_BASE_URL` in `.env` to the address the app uses, such as
   `http://192.168.1.50:8000`. Behind the VPN the server can't see your
   network address and would hand the app its internal Docker address, so
   playback would fail.

3. Save `docker-compose.vpn.yml` next to `docker-compose.yml`:

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

4. Start with both files:

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.vpn.yml up -d
   ```

   To avoid typing that every time, add
   `COMPOSE_FILE=docker-compose.yml:docker-compose.vpn.yml` to `.env`.

If devices on your network or on Tailscale can't reach the server through the
VPN, add their ranges to `.env`, for example
`FIREWALL_OUTBOUND_SUBNETS=192.168.1.0/24,100.64.0.0/10`.

Snappier Server also has its own VPN/proxy setting (dashboard: **Settings →
IPTV Provider → Send provider traffic through a VPN or proxy**). Use that or
gluetun, not both.

---

## GPU acceleration

Commercial detection is the heaviest job in this container: Comskip decodes
every finished recording in full. With a GPU passed in, it decodes on the GPU.
The container detects the GPU itself; if a GPU run ever fails, Comskip repeats
it on the CPU, so you never lose the markers.

| GPU | Set in `.env` | What uses it |
|---|---|---|
| Intel (Broadwell and newer) | `GPU_DEVICE=/dev/dri` | Comskip (Quick Sync) and FFmpeg (VAAPI, Quick Sync) |
| AMD | `GPU_DEVICE=/dev/dri` | FFmpeg (VAAPI). Comskip has no AMD decoder, so it stays on the CPU |
| NVIDIA | `DOCKER_RUNTIME=nvidia` | Comskip (NVDEC) and FFmpeg (NVENC/NVDEC) |

- NVIDIA needs the NVIDIA driver and the
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  on the host.
- Quick Sync exists for `amd64` only; on `arm64` the image has VAAPI and
  NVIDIA.
- Recording and remuxing copy the stream without re-encoding, so they barely
  use the CPU with or without a GPU.

Check that the GPU works (Intel or AMD); it prints `GPU-OK`:

```bash
docker exec snappier-server ffmpeg.real -hide_banner -loglevel error -init_hw_device vaapi=va:/dev/dri/renderD128 -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 3 -vf format=nv12,hwupload -c:v h264_vaapi -f null - && echo GPU-OK
```

After a recording finishes, confirm Comskip used it (look for
`decoding on the GPU`):

```bash
grep -a "comskip-wrapper" data/logs/server.log | tail -3
```

---

## Commercial detection

With `ENABLE_COMSKIP=true`, Comskip runs on each finished recording and writes
a `.edl` file next to it marking the commercial breaks, which players use to
skip them. It takes a few minutes per recording; use a GPU to take most of
the load off the CPU. `COMSKIP_INI` points at its tuning file if you want to
supply your own.

---

## Notifications

A built-in webhook sends events to your phone through
[Pushover](https://pushover.net) when `PUSHOVER_USER_KEY` and
`PUSHOVER_APP_TOKEN` are set. A free [TMDB](https://www.themoviedb.org/settings/api)
key (`TMDB_API_KEY`) adds posters and descriptions.

- **Health alerts** (the server stops responding) work as expected.
- **Recording alerts** (scheduled, started, finished) come from a log monitor
  that watches `server.log` in the data folder. Current Snappier releases
  write their log to `logs/server.log` instead, so recording alerts don't
  fire for now. This is inherited from the original image.

---

## Everyday commands

Run these in the folder with the compose file:

```bash
docker compose up -d                                 # start, or apply .env changes
docker compose restart                               # restart (picks up a new Snappier release)
docker compose pull && docker compose up -d          # update the image
docker compose logs -f snappier-server               # follow the server's log
docker compose down                                  # stop and remove the containers (your data stays)
```

---

## Troubleshooting

<details>
<summary>The dashboard or the app can't reach the server</summary>

- Use the Docker host's IP and `HOST_PORT` (default `8000`):
  `http://<docker-host-ip>:8000`.
- Make sure the host's firewall allows that port from your network.
- With the VPN, see the `FIREWALL_OUTBOUND_SUBNETS` note under [VPN](#vpn-optional).

</details>

<details>
<summary>The dashboard works but playback in the app fails (VPN)</summary>

Set `PUBLIC_BASE_URL` in `.env` to the address the app uses, such as
`http://192.168.1.50:8000`, then `docker compose up -d`. Restart the app so it
fetches fresh stream addresses.

</details>

<details>
<summary>The server doesn't start after a restart</summary>

Check the selector's lines in the log:

```bash
docker logs snappier-server 2>&1 | grep snappier-select
```

- `could not reach https://snappierserver.app ... and no verified build is
  cached`: the first start needs internet access to download Snappier
  Server. Check the host's (or the VPN's) connection; the container retries
  on every restart.
- `SNAPPIER_VERSION must be stable, beta or a release`: fix the value in
  `.env`.
- `SIGNATURE CHECK FAILED`: the download didn't match the publisher's
  signature and was not used. Try again later.

</details>

<details>
<summary>Commercial detection uses a lot of CPU</summary>

Pass in a GPU (see [GPU acceleration](#gpu-acceleration)), or set
`ENABLE_COMSKIP=false` if you don't skip commercials.

</details>

<details>
<summary>Start over</summary>

```bash
docker compose down
docker compose pull
docker compose up -d
```

To also reset Snappier's settings, delete `data/config.json` before starting.
Deleting the whole `data/` folder **also deletes your recordings**.

</details>

---

## Advanced

<details>
<summary>Build the image yourself</summary>

Building needs the whole repository (the Dockerfile and scripts). From a
clone of it:

```bash
docker compose build
docker compose up -d
```

The FFmpeg stage compiles the pinned version (9.0.1); pass
`--build-arg FFMPEG_VERSION=latest` for the newest stable FFmpeg.

</details>

<details>
<summary>Use the host's FFmpeg instead of the built-in one</summary>

Only for a vendor-patched FFmpeg; the built-in one is fully featured and
GPU-enabled. Run from a clone of the repository (the overlay mounts its
wrapper scripts), x86-64 hosts only:

```bash
docker compose -f docker-compose.yml -f docker-compose.host-ffmpeg.yml up -d
```

</details>

<details>
<summary>Every variable</summary>

The full `.env` under [Install](#install) lists every supported variable with
a comment on each.

</details>

---

## Credits and thanks

This image is built on
**[RyDizz214/snappier-server-docker](https://github.com/RyDizz214/snappier-server-docker)**.
The entrypoint, notification webhook, helper scripts, FFmpeg and Comskip
wrappers and the compose files are his work, used here with credit (the
source commit is recorded in [`UPSTREAM`](UPSTREAM)). A big thank you to
RyDizz214 for all the hard work that went into his container; it is the
foundation of everything here. If you prefer the original, please use his
image.

Snappier IPTV and Snappier Server are made by the Snappier developer
([snappierserver.app](https://snappierserver.app),
[snappieriptv.app](https://snappieriptv.app)). This repository only packages
the server for Docker. Snappier Server is downloaded from its official site
and remains under its own license.

### Switching from the original image

Your existing `data` folder works as is: it has the same folders this image
uses. The simplest switch is to use the compose file above with your `.env`
and add `SNAPPIER_VERSION`. To keep your own compose file instead, change the
image, add the variable, and mount the whole data folder:

```yaml
services:
  snappier-server:
    image: ghcr.io/mackid1993/snappier-server:latest
    environment:
      SNAPPIER_VERSION: "stable"   # or "beta", or e.g. "2.0.6-15"
    volumes:
      - ./data:/root/SnappierServer   # replaces the per-folder mounts
      - ./data/certs:/opt/SnappierServer/certs:ro
```

Your settings and every other variable stay as they are. For a GPU, add
the lines from [GPU acceleration](#gpu-acceleration).

### What changed from the original, file by file

- **Dockerfile:** no Snappier Server built in; FFmpeg 9.0.1 built with the
  same options minus `--enable-nonfree` and `libfdk_aac` (an FFmpeg build with
  those may not be redistributed), plus VAAPI, Quick Sync and NVENC/NVDEC;
  Intel and AMD GPU drivers; only FFmpeg's programs copied into the image;
  the static libraries current Ubuntu needs to build it.
- **`snappier-select.sh`** (new): installs the build chosen by
  `SNAPPIER_VERSION`, verifies it, caches it, then starts the original
  entrypoint.
- **`requirements.txt`** (new): the original's Python packages, pinned to the
  versions in its published image.
- **`ffmpeg-wrapper.sh`:** uses FFmpeg's built-in AAC encoder where
  `libfdk_aac` is requested, at the same bitrate and channel count.
- **`scripts/comskip-wrapper.sh`:** decodes on an Intel or NVIDIA GPU when one
  is present, with a CPU retry.
- **`docker-compose.yml`, `docker-compose.vpn.yml`, `example.env`:** the image
  name, `SNAPPIER_VERSION`, one mount for the whole data folder instead of
  per-folder mounts, the GPU lines, port `8000` on your network and
  `PUBLIC_BASE_URL`; the unused `SNAPPIER_SERVER_VERSION` build argument is
  removed.
- **Workflows** (new): the monthly and manual multi-arch build, and a weekly
  keepalive commit so the schedule stays enabled.

Changed lines in his files are marked `[mackid1993]`. Everything else is
byte-for-byte RyDizz214's.

## License

See Snappier Server's licensing at <https://snappierserver.app>. This
repository contains only the Docker packaging, wrappers and helper scripts;
those are by RyDizz214 except `snappier-select.sh`, `requirements.txt`, the
workflows and the changes listed above.
