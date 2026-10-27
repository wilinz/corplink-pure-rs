# syntax=docker/dockerfile:1

FROM rust:1-bookworm AS builder
WORKDIR /src
# git: fetch the boringtun fork; openssl: native-tls (reqwest)
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*
COPY . .
RUN cargo build --release -p corplink-client --bin corplink-client

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data
COPY --from=builder /src/target/release/corplink-client /usr/local/bin/corplink-client
ENV RUST_LOG=info
WORKDIR /data
EXPOSE 1080
ENTRYPOINT ["corplink-client"]
CMD ["/data/config.json"]
