# Stage 1: Create builder image
FROM --platform=${TARGETPLATFORM} debian:bookworm as unbound

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

# Build unbound from source
ENV NAME=unbound \
    UNBOUND_VERSION=1.19.0 \
    UNBOUND_SHA256=a97532468854c61c2de48ca4170de854fd3bc95c8043bb0cfb0fe26605966624 \
    UNBOUND_DOWNLOAD_URL=https://nlnetlabs.nl/downloads/unbound/unbound-1.19.0.tar.gz \
    ROOT_HINTS_URL=https://www.internic.net/domain/named.cache \
    ROOT_HINTS_MD5_URL=https://www.internic.net/domain/named.cache.md5

WORKDIR /src
RUN build_deps="curl gcc libc-dev libevent-dev libexpat1-dev libnghttp2-dev libssl-dev libsodium-dev make" && \
    set -x && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      $build_deps \
      bsdmainutils \
      ca-certificates \
      ldnsutils \
      libevent-2.1-7 \
      libexpat1 \
      libprotobuf-c-dev \
      protobuf-c-compiler && \
    curl -sSL $UNBOUND_DOWNLOAD_URL -o unbound.tar.gz && \
    echo "${UNBOUND_SHA256} *unbound.tar.gz" | sha256sum -c - && \
    tar xzf unbound.tar.gz --strip-components=1 && \
    rm -f unbound.tar.gz && \
    groupadd _unbound && \
    useradd -g _unbound -s /dev/null -d /etc _unbound && \
    sed -e 's/@LDFLAGS@/@LDFLAGS@ -all-static/' -i Makefile.in && \
	  LIBS="-lpthread -lm" LDFLAGS="-Wl,-static -static -static-libgcc -no-pie" \
    CFLAGS="-Ofast -funsafe-math-optimizations -ffinite-math-only -fno-rounding-math -fexcess-precision=fast -funroll-loops -ffunction-sections -fdata-sections -pipe" \
    ./configure \
        --enable-fully-static \
        --prefix=/opt/unbound \
        --with-pthreads \
        --with-username=_unbound \
        --with-ssl \
        --with-libevent \
        --with-libnghttp2 \
        --enable-dnstap \
        --enable-tfo-server \
        --enable-tfo-client \
        --enable-event-api \
        --enable-dnscrypt \
        --disable-shared \
	      --disable-rpath \
        --enable-subnet && \
    make -j$(($(nproc --all)+1)) && \
    make install && \
    rm /opt/unbound/etc/unbound/unbound.conf && \
    rm -rf /opt/unbound/share && \
    curl -sSL $ROOT_HINTS_URL -o root.hints && \
    ROOT_HINTS_MD5_HASHVAL=$(curl -sSL $ROOT_HINTS_MD5_URL) && \
    echo "${ROOT_HINTS_MD5_HASHVAL} *root.hints" | md5sum -c - && \
    mv root.hints /opt/unbound/etc/unbound/root.hints && \
    strip /opt/unbound/sbin/unbound \
          /opt/unbound/sbin/unbound-anchor \
          /opt/unbound/sbin/unbound-checkconf \
          /opt/unbound/sbin/unbound-control \
          /opt/unbound/sbin/unbound-host

# Stage 2: Final image
FROM --platform=${TARGETPLATFORM} alpine:latest
ENV NAME=unbound \
    SUMMARY="${NAME} is a validating, recursive, and caching DNS resolver." \
    DESCRIPTION="${NAME} is a validating, recursive, and caching DNS resolver."

COPY --from=unbound /opt /opt

RUN apk add --no-cache bc && rm -rf /var/cache/apk/* && \
    rm -rf /opt/unbound/include && \
    rm -rf /opt/unbound/lib && \
    addgroup -S _unbound && adduser -S _unbound -G _unbound

COPY data/ /
RUN chmod +x /unbound.sh

WORKDIR /opt/unbound/

ENV PATH /opt/unbound/sbin:"$PATH"

LABEL org.opencontainers.image.version=${UNBOUND_VERSION} \
      org.opencontainers.image.title="vincejv/unbound" \
      org.opencontainers.image.description="a validating, recursive, and caching DNS resolver" \
      org.opencontainers.image.url="https://github.com/vincejv/unbound-docker" \
      org.opencontainers.image.vendor="Vince Jerald Villamora" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/vincejv/unbound-docker"

EXPOSE 53/tcp
EXPOSE 53/udp

CMD ["/unbound.sh"]