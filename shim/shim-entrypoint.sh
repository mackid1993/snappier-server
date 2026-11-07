#!/bin/bash
# Starts nginx on PORT with the time-zone rewrite, moves the Snappier Server
# to SNAPPIER_INTERNAL_PORT, then hands off to the normal start-up unchanged.
set -e

PUBLIC_PORT="${PORT:-8000}"
INTERNAL_PORT="${SNAPPIER_INTERNAL_PORT:-8010}"
HOST_TZ="${TZ:-America/New_York}"      # same default as entrypoint.sh
PROV_TZ="${PROVIDER_TZ:-UTC}"

log() { echo "[snappier-shim] $*" >&2; }

mkdir -p /run /var/log/nginx /var/lib/nginx
sed -e "s#__PORT__#${PUBLIC_PORT}#g" \
    -e "s#__INTERNAL_PORT__#${INTERNAL_PORT}#g" \
    -e "s#__TZ__#${HOST_TZ}#g" \
    -e "s#__PROVIDER_TZ__#${PROV_TZ}#g" \
    /etc/snappier-shim/nginx.conf.template > /etc/snappier-shim/nginx.conf

nginx -t -c /etc/snappier-shim/nginx.conf >/dev/null
nginx -c /etc/snappier-shim/nginx.conf
log "nginx on :${PUBLIC_PORT} -> server on :${INTERNAL_PORT}; player_api.php timezone ${HOST_TZ} -> ${PROV_TZ}"

# The stock entrypoint launches the CLI with -p "$PORT".
export PORT="${INTERNAL_PORT}"
exec /usr/local/bin/snappier-select.sh "$@"
