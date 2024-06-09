# Stage 1: Prepare builder image
FROM --platform=${TARGETPLATFORM} alpine:latest as builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

RUN --mount=type=cache,id=apk-cache-${TARGETARCH},target=/var/cache/apk \
	apk add --update --cache-dir=/var/cache/apk \
	binutils \
	bind-tools \
	build-base \
	ca-certificates-bundle \
  coreutils \
  curl \
  gnupg \
	libevent-dev \
  nghttp2-dev \
	libsodium-dev \
  linux-headers \
	openssl-dev \
  perl \
  protobuf-c \
  protobuf-c-compiler \
  protobuf-c-dev \
  protobuf-dev \
  protoc \
	expat-dev

ARG UNBOUND_UID=101
ARG UNBOUND_GID=102

RUN addgroup -S -g ${UNBOUND_GID} _unbound \
	&& adduser -S -g _unbound -h /var/unbound -u ${UNBOUND_UID} -D -H -G _unbound _unbound

# Stage 2: Build OpenSSL
FROM --platform=${TARGETPLATFORM} builder as openssl

ENV VERSION_OPENSSL=openssl-3.3.0 \
    SHA256_OPENSSL=53e66b043322a606abf0087e7699a0e033a37fa13feb9742df35c3a33b18fb02 \
    SOURCE_OPENSSL=https://www.openssl.org/source/ \
    # OpenSSL OMC
    OPGP_OPENSSL_1=EFC0A467D613CB83C7ED6D30D894E2CE8B3D79F5 \
    # Richard Levitte
    OPGP_OPENSSL_2=7953AC1FBC3DC8B3B292393ED5E9E43F7DF9EE8C \
    # Matt Caswell
    OPGP_OPENSSL_3=8657ABB260F056B1E5190839D9C4D26D0E604491 \
    # Paul Dale
    OPGP_OPENSSL_4=B7C1C14360F353A36862E4D5231C84CDDCC69C45 \
    # Tomas Mraz
    OPGP_OPENSSL_5=A21FAB74B0088AA361152586B8EF1A6BA9DA2D5C

WORKDIR /tmp/src

RUN curl -L $SOURCE_OPENSSL$VERSION_OPENSSL.tar.gz -o openssl.tar.gz && \
    echo "${SHA256_OPENSSL} ./openssl.tar.gz" | sha256sum -c - && \
    curl -L $SOURCE_OPENSSL$VERSION_OPENSSL.tar.gz.asc -o openssl.tar.gz.asc && \
    GNUPGHOME="$(mktemp -d)" && \
    export GNUPGHOME && \
    gpg --no-tty --keyserver keyserver.ubuntu.com --recv-keys "$OPGP_OPENSSL_1" "$OPGP_OPENSSL_2" "$OPGP_OPENSSL_3" "$OPGP_OPENSSL_4" "$OPGP_OPENSSL_5" && \
    gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz && \
    tar xzf openssl.tar.gz && \
    cd $VERSION_OPENSSL && \
    ./config \
      --prefix=/opt/openssl \
      --openssldir=/opt/openssl \
      no-weak-ssl-ciphers \
      no-ssl3 \
      no-shared \
      -DOPENSSL_NO_HEARTBEATS \
      -O3 -pipe \
      -fstack-protector-strong && \
    make depend && \
    nproc | xargs -I % make -j% && \
    make install_sw

# Stage 2: Build unbound from source
FROM --platform=${TARGETPLATFORM} builder as unbound

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

# Build unbound from source
ENV NAME=unbound \
    UNBOUND_VERSION=1.20.0 \
    UNBOUND_SHA256=56b4ceed33639522000fd96775576ddf8782bb3617610715d7f1e777c5ec1dbf \
    UNBOUND_DOWNLOAD_URL=https://nlnetlabs.nl/downloads/unbound/unbound-1.20.0.tar.gz \
    ROOT_HINTS_URL=https://www.internic.net/domain/named.cache \
    ROOT_HINTS_MD5_URL=https://www.internic.net/domain/named.cache.md5

WORKDIR /src
COPY --from=openssl /opt/openssl /opt/openssl
RUN curl -sSL $UNBOUND_DOWNLOAD_URL -o unbound.tar.gz && \
    echo "${UNBOUND_SHA256} *unbound.tar.gz" | sha256sum -c - && \
    tar xzf unbound.tar.gz --strip-components=1 && \
    rm -f unbound.tar.gz && \
    CFLAGS="-O3 -pipe" \
    ./configure \
        --prefix=/opt/unbound \
        --with-pthreads \
        --with-username=_unbound \
        --with-ssl=/opt/openssl \
        --with-libevent \
        --with-libnghttp2 \
        --enable-dnstap \
        --enable-tfo-server \
        --enable-tfo-client \
        --enable-event-api \
        --enable-dnscrypt \
        --enable-cachedb \
        --disable-shared \
        --disable-static \
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

# Stage 3: Final image
FROM --platform=${TARGETPLATFORM} busybox:musl
ENV NAME=unbound \
    SUMMARY="${NAME} is a validating, recursive, and caching DNS resolver." \
    DESCRIPTION="${NAME} is a validating, recursive, and caching DNS resolver."

COPY --from=builder /lib/ld-musl*.so.1 /lib/
COPY --from=builder /usr/lib/libsodium.so.* /usr/lib/libevent-2.1.so.* /usr/lib/libexpat.so.* /usr/lib/libprotobuf-c.so.* /usr/lib/libnghttp2.so.* /usr/lib/
COPY --from=builder /etc/ssl/ /etc/ssl/
COPY --from=builder /etc/passwd /etc/group /etc/

COPY --from=unbound /opt /opt

RUN rm -rf /opt/unbound/include && \
    rm -rf /opt/unbound/lib && \
    rm -rf /opt/openssl

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