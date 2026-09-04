#
# Copyright (c) 2018 Dell Inc., or its subsidiaries. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#

ARG DOCKER_REGISTRY

# ---- build the zu.jar ensemble helper ----
FROM ${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}eclipse-temurin:11-jdk AS zu-builder
RUN mkdir /zu
COPY zu /zu
WORKDIR /zu
RUN ./gradlew --console=verbose --info shadowJar

# ---- resolve CVE-fixed replacements for jars bundled in the ZK base image ----
# Maven downloads from Maven Central with checksum verification and copies the
# full runtime closure (all transitive deps at the same fixed version) to
# /overrides. See docker/zk-deps/pom.xml for the version rationale per CVE.
FROM ${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}maven:3.9-eclipse-temurin-17 AS dep-resolver
WORKDIR /build
COPY zk-deps/pom.xml ./pom.xml
RUN mvn -B -q package

# ---- ZooKeeper distribution, re-based on a current Ubuntu JRE ----
# The official zookeeper:3.9.5-jre-17 image is Ubuntu 22.04 (jammy) and carries
# ~25 OS CVEs that have no jammy fix. We take the exact ZooKeeper distribution
# and entrypoint from that image but re-base them on eclipse-temurin:17-jre-noble
# (Ubuntu 24.04), which ships current libc / openssl / zlib / sqlite / etc.
# Everything ZK-version-specific still comes from upstream via COPY --from, so a
# ZK bump stays a one-line tag change.
#
# The upstream entrypoint drops privileges with `gosu`, a Go binary last built
# with Go 1.18 (100+ stale stdlib CVEs). We swap it for `setpriv` (util-linux,
# already in the base) which does the same job with no Go.
FROM ${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}zookeeper:3.9.5-jre-17 AS zk-dist

FROM ${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}eclipse-temurin:17-jre-noble
RUN set -eux; \
    # Ubuntu 24.04 ships a default user/group at 1000; reclaim it for zookeeper
    # so the uid/gid matches the upstream image.
    userdel -r ubuntu 2>/dev/null || true; \
    groupdel ubuntu 2>/dev/null || true; \
    groupadd -r zookeeper --gid=1000; \
    useradd -r -g zookeeper --uid=1000 zookeeper; \
    mkdir -p /data /datalog /logs
COPY --from=zk-dist /docker-entrypoint.sh /docker-entrypoint.sh
COPY --from=zk-dist /apache-zookeeper-3.9.5-bin /apache-zookeeper-3.9.5-bin
COPY --from=zk-dist /conf /conf
RUN set -eux; \
    sed -i 's#exec gosu zookeeper #exec setpriv --reuid=zookeeper --regid=zookeeper --init-groups #' /docker-entrypoint.sh; \
    grep -q 'setpriv --reuid=zookeeper' /docker-entrypoint.sh; \
    chown -R zookeeper:zookeeper /apache-zookeeper-3.9.5-bin /conf /data /datalog /logs
ENV ZOO_CONF_DIR=/conf \
    ZOO_DATA_DIR=/data \
    ZOO_DATA_LOG_DIR=/datalog \
    ZOO_LOG_DIR=/logs \
    ZOO_TICK_TIME=2000 \
    ZOO_INIT_LIMIT=5 \
    ZOO_SYNC_LIMIT=2 \
    ZOO_AUTOPURGE_PURGEINTERVAL=0 \
    ZOO_AUTOPURGE_SNAPRETAINCOUNT=3 \
    ZOO_MAX_CLIENT_CNXNS=60 \
    ZOO_STANDALONE_ENABLED=true \
    ZOO_ADMINSERVER_ENABLED=true \
    ZOOCFGDIR=/conf \
    PATH="$PATH:/apache-zookeeper-3.9.5-bin/bin"
WORKDIR /apache-zookeeper-3.9.5-bin
EXPOSE 2181 2888 3888 8080
VOLUME ["/data", "/datalog", "/logs"]
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["zkServer.sh", "start-foreground"]

# ---- operator additions on top of the distribution ----
COPY bin /usr/local/bin
RUN chmod +x /usr/local/bin/*
COPY --from=zu-builder /zu/build/libs/zu.jar /opt/libs/

RUN apt-get -q update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends dnsutils curl procps socat && \
    rm -rf /var/lib/apt/lists/*

# Replace the vulnerable jars ZooKeeper 3.9.5 ships (netty 4.1.130, jackson
# 2.15.2, jline 3.25.1, logback 1.3.15) with the CVE-fixed versions resolved
# above. The script fails the build if an expected jar is missing from the base
# image, so a future ZK bump that reorganises lib/ cannot silently ship
# vulnerable jars.
#
# Jetty 9.4.58 (CVE-2026-2332, CVE-2026-10050, CVE-2024-6763, CVE-2026-6790) is
# NOT patched here: 9.4.60+ is paid-support-only and ZK 3.9.x cannot move to
# Jetty 10+. See .trivyignore and SECURITY.md for the suppression rationale and
# compensating controls.
COPY --from=dep-resolver /overrides/ /tmp/zk-overrides/
COPY zk-lib-override.sh /tmp/zk-lib-override.sh
RUN sh /tmp/zk-lib-override.sh /apache-zookeeper-3.9.5-bin/lib /tmp/zk-overrides && \
    rm -rf /tmp/zk-overrides /tmp/zk-lib-override.sh
# Runs as root like the upstream image; /docker-entrypoint.sh drops to the
# unprivileged `zookeeper` user via gosu.
