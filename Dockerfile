FROM ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea AS depotdownloader
ARG TARGETARCH
ARG DEPOT_DOWNLOADER_VERSION=3.4.0
ARG DEPOT_DOWNLOADER_SHA256=d9fb612ccebc1db8eeea3b4045d2221ec70431381393ce908fb72f01d4f9c812
RUN test "$TARGETARCH" = arm64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && curl -fL "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOT_DOWNLOADER_VERSION}/DepotDownloader-linux-arm64.zip" -o /tmp/depotdownloader.zip \
    && echo "${DEPOT_DOWNLOADER_SHA256}  /tmp/depotdownloader.zip" | sha256sum -c - \
    && mkdir /opt/depotdownloader \
    && unzip -q /tmp/depotdownloader.zip -d /opt/depotdownloader \
    && chmod +x /opt/depotdownloader/DepotDownloader

FROM ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea AS box64-builder
ARG BOX64_REV=3c670efe6fe07ce290a1496ce750c064d0c6a052
RUN test "$(dpkg --print-architecture)" = arm64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates cmake git python3 \
    && git init /tmp/box64 \
    && git -C /tmp/box64 remote add origin https://github.com/ptitSeb/box64.git \
    && git -C /tmp/box64 fetch --depth 1 origin "$BOX64_REV" \
    && git -C /tmp/box64 checkout --detach FETCH_HEAD \
    && test "$(git -C /tmp/box64 rev-parse HEAD)" = "$BOX64_REV" \
    && cmake -S /tmp/box64 -B /tmp/box64/build -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr \
    && cmake --build /tmp/box64/build --parallel "$(nproc)" \
    && DESTDIR=/out cmake --install /tmp/box64/build

FROM ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea

RUN test "$(dpkg --print-architecture)" = arm64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ciopfs fuse3 iproute2 libice6 libsm6 libx11-6 libxext6 tini util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash zomboid \
    && mkdir -p /opt/zomboid-server /home/zomboid/Zomboid \
    && chown -R zomboid:zomboid /opt/zomboid-server /home/zomboid

COPY --from=depotdownloader /opt/depotdownloader /opt/depotdownloader
COPY --from=box64-builder /out/ /
COPY ProjectZomboid64.json /usr/local/share/zomboid/ProjectZomboid64.json
COPY --chmod=755 entrypoint.sh /usr/local/bin/zomboid-entrypoint
COPY --chmod=755 java-wrapper.sh /usr/local/bin/java

ENV BOX64_DYNAREC_STRONGMEM=3 \
    BOX64_DYNAREC_SAFEFLAGS=2 \
    BOX64_DYNAREC_ALIGNED_ATOMICS=1 \
    BOX64_JVM=0 \
    BOX64_SSE42=0 \
    BOX64_MAXCPU=4 \
    BOX64_LOG=0 \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
    HOME=/home/zomboid

WORKDIR /opt/zomboid-server
EXPOSE 16261/udp
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/zomboid-entrypoint"]
