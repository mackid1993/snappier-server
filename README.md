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
   count. This is the only change to RyDizz214's scripts, and it is marked
   `[mackid1993/snappier-server]` in `ffmpeg-wrapper.sh`.

4. **Smaller image** (about 540 MB instead of 750 MB), mostly from not
   shipping FFmpeg's build leftovers. Python packages are pinned to the
   versions in the original image.

Files that differ from the original are marked with `[mackid1993]` comments:
`docker-compose.yml` (image name, `SNAPPIER_VERSION`, the `snappier-cli`
volume; the unused `SNAPPIER_SERVER_VERSION` build argument is removed),
`example.env` (`SNAPPIER_VERSION` replaces `SNAPPIER_SERVER_VERSION`),
`ffmpeg-wrapper.sh`, and the `Dockerfile`. New files: `snappier-select.sh`
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

Your data, settings and every other variable stay exactly as they are.

**Snappier is not affiliated with this package and will *not* provide support.**

---

## Install (5 minutes)

### 1. Install Docker on your Linux host

If you don't already have it: <https://docs.docker.com/engine/install/>

Docker Compose v2 is included with modern Docker installs.

### 2. Get the files

```bash
git clone https://github.com/mackid1993/snappier-server.git
cd snappier-server
cp example.env .env
```

### 3. Start it

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

On the **same machine** running Docker:

- Go to **<http://localhost:7429>** in a browser.

From a **different machine** (phone, laptop, another server):

The web UI isn't exposed to your network by default, for security. You have
two options:

- **Easy:** SSH into the Docker host and use `localhost:7429` there.
- **Better:** Put a reverse proxy (Nginx, Caddy, Cloudflare Tunnel) in front
  of the container and point it at `127.0.0.1:7429`.

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
| A different web port                  | `HOST_PORT=8080` *(default is 7429)*                        |
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

2. Start with the VPN turned on:

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.vpn.yml up -d
   ```

Snappier Server 2.0.2 also has its own VPN/proxy setting (dashboard:
Settings → IPTV Provider → *Send provider traffic through a VPN or proxy*). It
is off by default. Use either that or the gluetun overlay above, not both —
turning it on under gluetun puts provider traffic through two tunnels.

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
<summary>I can't reach http://localhost:7429 from another device</summary>

The port is locked to `127.0.0.1` (localhost only) for security. Either:

- Use a reverse proxy (Nginx, Caddy, Cloudflare Tunnel) — recommended, gives
  you HTTPS too.
- Or edit `docker-compose.yml` and change `"127.0.0.1:${HOST_PORT:-7429}:8000"`
  to just `"${HOST_PORT:-7429}:8000"` to expose on all interfaces. **Only do
  this on a trusted network** — Snappier's built-in TLS is off by default.

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

The built-in FFmpeg is fully featured and works on both Intel and ARM. Only
override it if you need hardware acceleration (NVENC, QuickSync) or a
vendor-patched FFmpeg. **x86-64 hosts only.**

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

See [`example.env`](example.env) — every supported variable is documented
inline.

</details>

---

## License

See upstream Snappier Server licensing at <https://snappierserver.app>. This
repository contains only the Docker packaging, wrappers, and helper scripts;
those are by RyDizz214 except `snappier-select.sh`, `requirements.txt`, the
workflows and the changes described at the top.
