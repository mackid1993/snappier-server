#!/bin/bash
# Wrapper that runs comskip then immediately rebases any orphan sidecars
# (.edl, .txt, .log, .logo.txt) the run produced under the legacy `--<program>`
# stem so live playback gets the channel-prefixed files without waiting for
# the metadata_fixer 60s scan tick.
#
# Install:
#   mv /usr/local/bin/comskip /usr/local/bin/comskip.real
#   cp comskip-wrapper.sh /usr/local/bin/comskip && chmod +x /usr/local/bin/comskip

set -u

COMSKIP_REAL="${COMSKIP_REAL:-/usr/local/bin/comskip.real}"
METADATA_FIXER_DIR="${METADATA_FIXER_DIR:-/opt/scripts}"

recover_orphans() {
  python3 - <<PY 2>&1 || true
import sys
sys.path.insert(0, "$METADATA_FIXER_DIR")
try:
    from metadata_fixer import recover_orphan_sidecars
    n = recover_orphan_sidecars()
    if n:
        print(f"[comskip-wrapper] rebased {n} orphan sidecar(s)")
except Exception as e:
    print(f"[comskip-wrapper] orphan recovery failed: {e}", file=sys.stderr)
PY
}

# [mackid1993/snappier-server] GPU decoding for Comskip. Comskip decodes the
# whole recording, which is the heaviest thing this container does. When a GPU
# is passed in (see "GPU acceleration" in the README), decode on it:
#   Intel (vendor 0x8086 render node): --qsv     (Intel Quick Sync)
#   NVIDIA (/dev/nvidia0 + libcuda):   --cuvid   (NVDEC)
# AMD has no decoder Comskip can use, so it stays on the CPU. If a GPU run
# fails (exit code above 1; Comskip exits 1 when it finds no commercials),
# the run is repeated on the CPU, so a GPU problem never costs the .edl.
gpu_args() {
  local node vendor
  if [[ -e /dev/nvidia0 ]] && ldconfig -p 2>/dev/null | grep -q 'libcuda\.so'; then
    echo "--cuvid --hwassist"; return
  fi
  for node in /dev/dri/renderD*; do
    [[ -e "$node" ]] || continue
    vendor="$(cat "/sys/class/drm/${node##*/}/device/vendor" 2>/dev/null || true)"
    if [[ "$vendor" == "0x8086" ]]; then
      echo "--qsv --hwassist"; return
    fi
  done
}

GPU_ARGS=""
case " $* " in
  *" --qsv "*|*" --cuvid "*|*" --vdpau "*|*" --dxva2 "*|*" --hwassist "*) ;;
  *) GPU_ARGS="$(gpu_args)" ;;
esac

rc=0
if [[ -n "$GPU_ARGS" ]]; then
  echo "[comskip-wrapper] decoding on the GPU ($GPU_ARGS)"
  # shellcheck disable=SC2086
  "$COMSKIP_REAL" $GPU_ARGS "$@"
  rc=$?
  if [[ $rc -gt 1 ]]; then
    echo "[comskip-wrapper] GPU run failed (exit $rc), repeating on the CPU"
    "$COMSKIP_REAL" "$@"
    rc=$?
  fi
else
  "$COMSKIP_REAL" "$@"
  rc=$?
fi
recover_orphans
exit $rc
