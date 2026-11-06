#!/bin/bash
# Installs the Snappier Server CLI chosen by SNAPPIER_VERSION at container
# start, then hands off to the stock entrypoint unchanged.
#
#   SNAPPIER_VERSION=stable    latest stable release (default; "latest" works too)
#   SNAPPIER_VERSION=beta      latest beta
#   SNAPPIER_VERSION=2.0.6-15  that exact release (stable or beta)
#
# Downloads come from snappierserver.app and are verified with the publisher's
# minisign key before use. Builds are cached under the appdata mount, so a
# restart without a new release downloads nothing. If the site can't be
# reached, the last verified build is used.

REQ="${SNAPPIER_VERSION:-stable}"
SITE="https://snappierserver.app"
PUBKEY="RWTX5W4+F8l4vXGixpj7+eZtv1u4zxGZRdOMcxMzuQowFbYKm51XfcW0"
CACHE="/root/SnappierServer/.snappier-cli"
DEST="/opt/SnappierServer"
STOCK_ENTRYPOINT="/usr/local/bin/entrypoint.sh"

log() { echo "[snappier-select] $*" >&2; }

case "$(uname -m)" in
  aarch64|arm64) ARCH="linux-arm64" ;;
  x86_64|amd64)  ARCH="linux-x64" ;;
  *) log "unsupported architecture $(uname -m)"; exit 1 ;;
esac

case "$REQ" in
  stable|latest) MODE="stable" ;;
  beta)          MODE="beta" ;;
  [0-9]*)        MODE="pinned" ;;
  *) log "SNAPPIER_VERSION must be stable, beta or a release like 2.0.6-15 (got '$REQ')"; exit 1 ;;
esac

# Prints "<version> <zip url>" for the requested build, or fails.
resolve() {
  local v base
  case "$MODE" in
    pinned)
      for base in files betaFiles; do
        if curl -fsI -m 20 "$SITE/$base/v$REQ/snappier-server-cli-v$REQ-$ARCH.zip" >/dev/null; then
          echo "$REQ $SITE/$base/v$REQ/snappier-server-cli-v$REQ-$ARCH.zip"
          return 0
        fi
      done
      return 1 ;;
    beta)
      v="$(curl -fsSL -m 30 "$SITE/betaFiles/" | grep -oE "cli: *'[0-9][^']*'" | head -n1 | grep -oE "[0-9][^']*")"
      [ -n "$v" ] || return 1
      echo "$v $SITE/betaFiles/v$v/snappier-server-cli-v$v-$ARCH.zip" ;;
    stable)
      curl -fsSL -m 30 "$SITE/latest.json" | python3 -c '
import json, sys
os_, arch = sys.argv[1].split("-")
j = json.load(sys.stdin)
print(j["version"], j["cli"][os_][arch]["url"])' "$ARCH" ;;
  esac
}

# Downloads, verifies and unpacks one build into the cache. Prints its folder.
fetch() {
  local ver="$1" url="$2" dir="$CACHE/$1-$ARCH" tmp
  if [ -x "$dir/snappier-server-cli-v$ver-$ARCH" ]; then
    echo "$dir"; return 0
  fi
  tmp="$(mktemp -d)"
  log "downloading $ver ($ARCH)"
  if ! curl -fsSL -m 600 -o "$tmp/cli.zip" "$url" ||
     ! curl -fsSL -m 60 -o "$tmp/cli.zip.minisig" "$url.minisig"; then
    log "download failed"; rm -rf "$tmp"; return 1
  fi
  if ! minisign -Vm "$tmp/cli.zip" -x "$tmp/cli.zip.minisig" -P "$PUBKEY" -q; then
    log "SIGNATURE CHECK FAILED for $ver, not using it"; rm -rf "$tmp"; return 1
  fi
  log "signature verified for $ver"
  mkdir -p "$tmp/x" && unzip -q -o "$tmp/cli.zip" -d "$tmp/x" &&
    [ -f "$tmp/x/snappier-server-cli-v$ver-$ARCH" ] || { log "unexpected archive layout"; rm -rf "$tmp"; return 1; }
  # Same permissions step as the upstream image's build.
  find "$tmp/x" -maxdepth 2 -type f \( -name "*.sh" -o -name "snappier*" -o -name "*.bin" -o -name "wireproxy" \) -exec chmod +x {} +
  mkdir -p "$CACHE" && rm -rf "$dir" && mv "$tmp/x" "$dir"
  rm -rf "$tmp"
  echo "$dir"
}

# Puts one cached build where the stock entrypoint expects it, laid out the
# way the upstream image unpacks it at build time.
install_build() {
  local ver="$1" dir="$2"
  cp -af "$dir/." "$DEST/"
  ln -sfn "snappier-server-cli-v$ver-$ARCH" "$DEST/snappier-server-cli"
  {
    echo "version=$ver"
    echo "arch=$ARCH"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "requested=$REQ"
  } > "$DEST/.artifact_info"
  echo "$ver $dir" > "$CACHE/current"
  export SNAPPIER_SERVER_VERSION="$ver"
  log "running Snappier Server $ver (SNAPPIER_VERSION=$REQ)"
}

use_last() {
  local ver dir
  if [ -s "$CACHE/current" ]; then
    read -r ver dir < "$CACHE/current"
    if [ -x "$dir/snappier-server-cli-v$ver-$ARCH" ]; then
      log "$1, using last verified build"
      install_build "$ver" "$dir"; return 0
    fi
  fi
  log "$1 and no verified build is cached; cannot start (will retry on restart)"
  exit 1
}

mkdir -p "$CACHE"
if RES="$(resolve)" && [ -n "$RES" ]; then
  read -r VER URL <<<"$RES"
  if DIR="$(fetch "$VER" "$URL")"; then
    install_build "$VER" "$DIR"
  else
    use_last "could not get $VER"
  fi
else
  use_last "could not reach $SITE for SNAPPIER_VERSION=$REQ"
fi

# Keep the three newest cached builds.
ls -1dt "$CACHE"/*-"$ARCH" 2>/dev/null | tail -n +4 | xargs -r rm -rf

exec "$STOCK_ENTRYPOINT" "$@"
