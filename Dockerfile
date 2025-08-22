ARG DEBIAN_VERSION=bookworm
ARG MOSQUITTO_VERSION=2.0.22
ARG MOSQUITTO_GO_AUTH_VERSION=3.0.0
ARG GO_VERSION=1.24

FROM debian:${DEBIAN_VERSION}-slim AS mosquitto-builder

RUN apt update &&  \
    apt install -y \
		build-essential \
		cmake \
		libssl-dev \
		libwebsockets-dev \
		libcjson-dev \
		libsystemd-dev \
		uuid-dev \
		wget \
		ca-certificates

ARG MOSQUITTO_VERSION
WORKDIR /tmp
RUN wget https://mosquitto.org/files/source/mosquitto-${MOSQUITTO_VERSION}.tar.gz \
    && tar -xzf mosquitto-${MOSQUITTO_VERSION}.tar.gz \
    && cd mosquitto-${MOSQUITTO_VERSION} \
    && make \
    && make install

ARG GO_VERSION
ARG DEBIAN_VERSION
FROM golang:${GO_VERSION}-${DEBIAN_VERSION} AS auth-plugin-builder

RUN apt update && apt install -y \
    git \
    gcc \
    libc6-dev \
    libpq-dev \
    pkg-config \
	build-essential \
    libmosquitto-dev

ARG MOSQUITTO_VERSION
COPY --from=mosquitto-builder /tmp/mosquitto-${MOSQUITTO_VERSION} /mosquitto-src

WORKDIR /build/mosquitto-go-auth
ARG MOSQUITTO_GO_AUTH_VERSION
RUN git clone --branch ${MOSQUITTO_GO_AUTH_VERSION} --depth 1 https://github.com/iegomez/mosquitto-go-auth.git .

RUN cp -r /mosquitto-src/include/* /usr/local/include/ && \
    cp -r /mosquitto-src/lib/* /usr/local/include/ && \
    cp -r /mosquitto-src/src/* /usr/local/include/ && \
    make

ARG DEBIAN_VERSION
FROM debian:${DEBIAN_VERSION}-slim

RUN groupadd -r mosquitto && useradd -r -g mosquitto mosquitto

RUN apt-get update && \
    apt-get install -y \
		libssl3 \
		libwebsockets17 \
		libcjson1 \
		libsystemd0 \
		uuid-runtime \
		ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=mosquitto-builder /usr/local/sbin/mosquitto /usr/local/sbin/
COPY --from=mosquitto-builder /usr/local/bin/mosquitto_* /usr/local/bin/
COPY --from=mosquitto-builder /usr/local/lib/libmosquitto* /usr/local/lib/
COPY --from=mosquitto-builder /usr/local/include/mosquitto* /usr/local/include/
COPY --from=auth-plugin-builder /build/mosquitto-go-auth/go-auth.so /usr/local/lib/
COPY --from=auth-plugin-builder /build/mosquitto-go-auth/pw /usr/local/bin/
COPY mosquitto.conf /mosquitto/mosquitto.conf

RUN ldconfig && \
    mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log && \
    chown -R mosquitto:mosquitto /mosquitto

USER mosquitto

CMD ["/usr/local/sbin/mosquitto", "-c", "/mosquitto/mosquitto.conf"]
