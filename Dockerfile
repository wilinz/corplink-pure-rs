# syntax=docker/dockerfile:1

# musl build on Alpine; the runtime matches the builder's Alpine release so
# the dynamically linked OpenSSL sonames line up.
FROM rust:1-alpine3.24 AS builder
WORKDIR /src
# git: fetch the boringtun fork; openssl-dev/pkgconf: openssl-sys (native-tls);
# build-base: ring's C/asm build scripts
RUN apk add --no-cache build-base git pkgconf openssl-dev
COPY . .
RUN cargo build --release -p corplink-client --bin corplink-client

FROM alpine:3.24
RUN apk add --no-cache ca-certificates libcrypto3 libgcc libssl3
COPY --from=builder /src/target/release/corplink-client /usr/local/bin/corplink-client
ENV RUST_LOG=info
WORKDIR /data
EXPOSE 1080
ENTRYPOINT ["corplink-client"]
CMD ["/data/config.json"]
