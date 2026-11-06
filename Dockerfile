########################################
# Snappier Server, build chosen at runtime
#
# Mirrors ghcr.io/rydizz214/snappier-server-docker (Dockerfile, entrypoint,
# notify webhook, helper scripts and wrappers by RyDizz214; see README) with
# two differences:
#
#   1. The Snappier Server CLI is not baked in. At container start
#      snappier-select.sh installs the build named by SNAPPIER_VERSION
#      (stable | beta | an exact release) and verifies its minisign signature.
#   2. FFmpeg is built without --enable-nonfree / libfdk_aac, which make an
#      FFmpeg build unredistributable. FFmpeg's native AAC encoder is used.
#
# Build modes (unchanged from upstream):
#   USE_HOST_FFMPEG=false (default) - builds FFmpeg from source (publishable image)
#   USE_HOST_FFMPEG=true            - skips FFmpeg build (local dev, host-mounted)
########################################

ARG USE_HOST_FFMPEG=false

########################################
# Stage 1: Build FFmpeg and codec libraries from source
# (BuildKit skips this entirely when USE_HOST_FFMPEG=true)
########################################
FROM ubuntu:26.04 AS ffmpeg-build

ARG DEBIAN_FRONTEND=noninteractive
# Same pin as upstream: 9.0.1 is the version ffmpeg-wrapper.sh is tested against.
# Setting FFMPEG_VERSION=latest resolves the newest stable tarball.
ARG FFMPEG_VERSION=9.0.1

# Upstream's build packages, plus the static libraries current Ubuntu 26.04
# OpenSSL needs for a --pkg-config-flags=--static link (zlib, zstd,
# jitterentropy); without them configure stops with a misleading
# "OpenSSL <3.0.0 is incompatible with the gpl".
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates wget unzip xz-utils grep coreutils \
    build-essential pkg-config autoconf automake cmake libtool \
    yasm nasm meson ninja-build \
    libfreetype6-dev libass-dev libfontconfig1-dev libunistring-dev libnuma-dev \
    libfribidi-dev libharfbuzz-dev \
    libssl-dev \
    zlib1g-dev libzstd-dev libjitterentropy3-dev \
    libva-dev libdrm-dev \
    libx11-dev libxext-dev libxfixes-dev libxi-dev libxrender-dev libxrandr-dev \
 && rm -rf /var/lib/apt/lists/*

# x264 (static)
RUN git clone --depth=1 https://code.videolan.org/videolan/x264.git /tmp/x264 \
 && cd /tmp/x264 \
 && ./configure --prefix=/usr/local --enable-static --enable-pic \
 && make -j"$(nproc)" && make install

# x265 (static) + pkg-config metadata
ARG X265_VERSION=4.2
RUN git clone --depth=1 --branch "${X265_VERSION}" https://bitbucket.org/multicoreware/x265_git.git /tmp/x265 \
 && cd /tmp/x265/build/linux \
 && cmake -G "Unix Makefiles" \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DENABLE_SHARED=OFF \
    ../../source \
 && make -j"$(nproc)" && make install \
 && mkdir -p /usr/local/lib/pkgconfig \
 && { \
    echo 'prefix=/usr/local'; \
    echo 'exec_prefix=${prefix}'; \
    echo 'libdir=${exec_prefix}/lib'; \
    echo 'includedir=${prefix}/include'; \
    echo ''; \
    echo 'Name: x265'; \
    echo 'Description: H.265/HEVC video encoder'; \
    echo "Version: ${X265_VERSION}"; \
    echo 'Libs: -L${libdir} -lx265 -lstdc++ -lm -lpthread -ldl -lnuma'; \
    echo 'Cflags: -I${includedir}'; \
 } > /usr/local/lib/pkgconfig/x265.pc \
 && ldconfig

# (upstream builds fdk-aac here; omitted, it is what makes the build nonfree)

# libvpx (static)
RUN git clone --depth=1 https://chromium.googlesource.com/webm/libvpx /tmp/libvpx \
 && cd /tmp/libvpx \
 && ./configure --prefix=/usr/local --disable-examples --disable-unit-tests --enable-vp9-highbitdepth \
 && make -j"$(nproc)" && make install

# [mackid1993] GPU support. NVIDIA: the ffnvcodec headers (FFmpeg loads the
# driver's libraries at run time, injected by the NVIDIA Container Toolkit).
# Intel Quick Sync: libvpl, which Intel ships for amd64 only.
RUN git clone --depth=1 https://github.com/FFmpeg/nv-codec-headers.git /tmp/nv-codec-headers \
 && make -C /tmp/nv-codec-headers PREFIX=/usr/local install \
 && if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
      apt-get update && apt-get install -y --no-install-recommends libvpl-dev \
      && rm -rf /var/lib/apt/lists/*; \
    fi

# opus (static)
RUN git clone --depth=1 https://github.com/xiph/opus.git /tmp/opus \
 && cd /tmp/opus && ./autogen.sh \
 && ./configure --prefix=/usr/local --disable-shared \
 && make -j"$(nproc)" && make install

# FFmpeg. Upstream's configure line with --enable-nonfree --enable-libfdk_aac
# replaced by --enable-version3 (needed for OpenSSL 3 under the GPL).
ARG FFMPEG_REFRESH=1
RUN set -eux; \
  echo "FFMPEG_REFRESH=${FFMPEG_REFRESH} FFMPEG_VERSION=${FFMPEG_VERSION}"; \
  if [ "${FFMPEG_VERSION}" = "latest" ]; then \
    FFMPEG_TARBALL="$(curl -fsSL https://ffmpeg.org/releases/ | grep -Eo 'ffmpeg-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.xz' | grep -vE 'rc|git' | sort -V | uniq | tail -1)"; \
  else \
    FFMPEG_TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.xz"; \
  fi; \
  if [ -z "${FFMPEG_TARBALL}" ]; then echo "Failed to resolve FFmpeg tarball" >&2; exit 1; fi; \
  echo "Selected FFmpeg: ${FFMPEG_TARBALL}"; \
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o "/tmp/${FFMPEG_TARBALL}" "https://ffmpeg.org/releases/${FFMPEG_TARBALL}"; \
  mkdir -p /tmp/ffmpeg && tar -xf "/tmp/${FFMPEG_TARBALL}" -C /tmp/ffmpeg --strip-components=1; \
  cd /tmp/ffmpeg; \
  export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"; \
  ./configure \
    --prefix=/usr/local \
    --pkg-config-flags="--static" \
    --extra-cflags="-I/usr/local/include" \
    --extra-ldflags="-L/usr/local/lib" \
    --extra-libs="-lpthread -lm -ldl -lnuma" \
    --bindir=/usr/local/bin \
    --enable-gpl --enable-version3 \
    --enable-openssl \
    --enable-libx264 --enable-libx265 \
    --enable-libvpx --enable-libopus --enable-libass --enable-libfreetype \
    --enable-vaapi --enable-ffnvcodec --enable-nvdec --enable-nvenc --enable-cuvid \
    $( [ "$(dpkg --print-architecture)" = "amd64" ] && echo --enable-libvpl ) \
    --disable-debug --disable-doc \
    || { tail -40 ffbuild/config.log; exit 1; }; \
  make -j"$(nproc)" && make install && hash -r; \
  # [mackid1993] Fail the build if GPU encoders are missing.
  enc="$(/usr/local/bin/ffmpeg -hide_banner -encoders)"; \
  for e in h264_vaapi hevc_vaapi h264_nvenc hevc_nvenc; do echo "$enc" | grep -q " $e " || { echo "missing $e" >&2; exit 1; }; done; \
  if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    for e in h264_qsv hevc_qsv; do echo "$enc" | grep -q " $e " || { echo "missing $e" >&2; exit 1; }; done; \
  fi

########################################
# Stage 1b: Build Comskip from source (identical to upstream)
########################################
FROM ubuntu:26.04 AS comskip-build

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ca-certificates build-essential autoconf automake libtool pkg-config \
      libargtable2-dev libavformat-dev libavcodec-dev libavutil-dev libswscale-dev \
      libsdl2-dev \
 && rm -rf /var/lib/apt/lists/*

# FFmpeg 8 removed AVCodecContext.ticks_per_frame, which Comskip still uses
# (upstream issue #186); same replacement as upstream's image.
RUN git clone --depth=1 https://github.com/erikkaashoek/Comskip.git /tmp/comskip \
 && cd /tmp/comskip \
 && sed -i -e '/codec_id == AV_CODEC_ID_MPEG1VIDEO)/{N;/ticks_per_frame = 1;/d}' \
      -e 's/is->dec_ctx->ticks_per_frame/COMSKIP_TICKS_PER_FRAME(is->dec_ctx)/g' \
      -e '/#include <libavcodec\/avcodec.h>/a #define COMSKIP_TICKS_PER_FRAME(c) (((c)->codec_id != AV_CODEC_ID_MPEG1VIDEO \&\& (c)->codec_descriptor \&\& ((c)->codec_descriptor->props \& AV_CODEC_PROP_FIELDS)) ? 2 : 1)' \
      mpeg2dec.c \
 && grep -q '^#define COMSKIP_TICKS_PER_FRAME' mpeg2dec.c \
 && ! grep -n 'TICKS_PER_FRAME(is->dec_ctx) = 1' mpeg2dec.c \
 && ./autogen.sh \
 && ./configure --bindir=/usr/local/bin \
 && make -j"$(nproc)" comskip \
 && install -m 0755 comskip /usr/local/bin/comskip \
 && test -x /usr/local/bin/comskip

########################################
# Stage 2: Common runtime base (upstream's package list, plus minisign)
########################################
FROM ubuntu:26.04 AS runtime-base

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    curl jq ca-certificates tzdata tini procps inotify-tools iproute2 coreutils \
    unzip minisign \
    libssl3t64 \
    libxcb1 libxcb-shm0 libxcb-shape0 libxcb-xfixes0 \
    libx11-6 libxext6 libxrender1 libxfixes3 libxi6 libxrandr2 \
    libnuma1 libstdc++6 \
    libass9 libfreetype6 libfribidi0 libharfbuzz0b libfontconfig1 libpng16-16t64 \
    fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*

# [mackid1993] GPU drivers, used by FFmpeg and by Comskip's GPU decoding:
#   Intel: intel-media-va-driver-non-free (iHD, Broadwell and newer),
#          i965-va-driver (older), libvpl2 + libmfx-gen1.2 (Quick Sync).
#          amd64 only, as Intel ships them.
#   AMD:   mesa-va-drivers (VAAPI), every architecture.
#   NVIDIA: nothing to install; the NVIDIA Container Toolkit injects the
#          driver libraries when the container runs with runtime: nvidia.
RUN arch="$(dpkg --print-architecture)"; extra=""; \
    if [ "$arch" = "amd64" ]; then extra="intel-media-va-driver-non-free i965-va-driver libvpl2 libmfx-gen1.2"; fi; \
    apt-get update && apt-get install -y --no-install-recommends \
      libva2 libva-drm2 libdrm2 mesa-va-drivers $extra \
 && rm -rf /var/lib/apt/lists/*
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,video,utility

########################################
# Stage 3a: Built-in FFmpeg (published image)
########################################
FROM runtime-base AS runtime-false

# Upstream copies all of /usr/local (static libs and headers included); only
# the programs and FFmpeg's data files are needed at runtime.
COPY --from=ffmpeg-build /usr/local/bin /usr/local/bin
COPY --from=ffmpeg-build /usr/local/share /usr/local/share
RUN mv /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg.real \
 && ln -sf /usr/local/bin/ffmpeg.real /usr/bin/ffmpeg.real \
 && ln -sf /usr/local/bin/ffprobe /usr/bin/ffprobe

########################################
# Stage 3b: Host FFmpeg (local dev)
########################################
FROM runtime-base AS runtime-true

RUN mkdir -p /usr/local/bin \
 && ln -sf /usr/local/bin/ffmpeg /usr/bin/ffmpeg \
 && ln -sf /usr/local/bin/ffprobe /usr/bin/ffprobe

########################################
# Stage 4: Final image
########################################
FROM runtime-${USE_HOST_FFMPEG} AS final

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_DATE
ARG VERSION

LABEL org.opencontainers.image.title="Snappier Server"
LABEL org.opencontainers.image.description="Snappier Server; the server build is chosen at runtime with SNAPPIER_VERSION"
LABEL org.opencontainers.image.source="https://github.com/mackid1993/snappier-server"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"

# Python dependencies for webhook and helper scripts: upstream's packages,
# pinned to the versions in its published image.
COPY requirements.txt /tmp/requirements.txt
RUN python3 -m pip install --no-cache-dir --break-system-packages -r /tmp/requirements.txt \
 && rm /tmp/requirements.txt

WORKDIR /opt
RUN mkdir -p /logs /root/SnappierServer/epg /root/SnappierServer /opt/certs

# Same layout upstream creates at build time; the CLI itself is installed
# into /opt/SnappierServer by snappier-select.sh at start-up.
RUN mkdir -p /opt/SnappierServer \
 && ln -sf /opt/SnappierServer /root/SnappierServer \
 && echo '{}' > /opt/SnappierServer/config.json

# Notification webhook + helper scripts
COPY notify/enhanced_webhook.py notify/tmdb_helper.py /opt/notify/
COPY scripts/health_watcher.py scripts/log_monitor.sh scripts/metadata_fixer.py scripts/timestamp_helpers.py scripts/xtream_cache.py /opt/scripts/
RUN chmod +x /opt/scripts/*.sh 2>/dev/null || true

# FFmpeg wrapper (becomes /usr/local/bin/ffmpeg, calls ffmpeg.real under the hood)
COPY ffmpeg-wrapper.sh /usr/local/bin/ffmpeg
RUN chmod +x /usr/local/bin/ffmpeg \
 && ln -sf /usr/local/bin/ffmpeg /usr/bin/ffmpeg

# Comskip: real binary from stage 1b, fronted by upstream's wrapper.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libargtable2-0 libavformat62 libavcodec62 libavutil60 libswscale9 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=comskip-build /usr/local/bin/comskip /usr/local/bin/comskip.real
COPY scripts/comskip-wrapper.sh /usr/local/bin/comskip
COPY comskip.ini /usr/local/etc/comskip.ini
RUN chmod +x /usr/local/bin/comskip /usr/local/bin/comskip.real \
 && ldd /usr/local/bin/comskip.real \
 && ! ldd /usr/local/bin/comskip.real | grep -q 'not found'

# Entrypoint (upstream's) and the runtime build selector that runs before it.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY snappier-select.sh /usr/local/bin/snappier-select.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/snappier-select.sh

# Default environment variables (TZ intentionally unset, as upstream)
ENV PORT=8000 \
    NOTIFICATION_HTTP_PORT=9080 \
    NOTIFICATION_SSE_PATH=/events \
    NOTIFY_TITLE_PREFIX="Snappier" \
    SNAPPY_API_BASE="http://127.0.0.1:8000" \
    SNAPPY_API_TIMEOUT=5 \
    NOTIFY_DESC_LIMIT=900 \
    HEALTH_INTERVAL_SEC=30 \
    HEALTH_FAIL_THRESHOLD=3 \
    HEALTH_WARN_COOLDOWN_SEC=300 \
    HEALTH_HTTP_TIMEOUT=5 \
    HEALTH_EXPECT_MIN=200 \
    HEALTH_EXPECT_MAX=399 \
    HEALTH_WARN_ON_RECOVERY=0 \
    HEALTH_NOTIFY_URL="http://127.0.0.1:9080/notify" \
    HEALTH_ENDPOINT="/serverStats" \
    SNAPPIER_VERSION=stable

EXPOSE 8000 9080

HEALTHCHECK --interval=60s --timeout=5s --retries=3 \
  CMD timeout 2 bash -c 'echo > /dev/tcp/127.0.0.1/8000' || exit 1

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/snappier-select.sh"]
