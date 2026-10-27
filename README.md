# corplink-tunnel-rs

A **fully self-contained, pure-Rust** CorpLink / feilian client. No Go, no
`libwg`, no CGO, no TUN device, no root — a single `cargo build`.

Two crates:

- **`tunnel/`** (`corplink-tunnel`) — the userspace WireGuard-over-TCP datapath:
  a `connect()` API returning `AsyncRead + AsyncWrite` streams, and a SOCKS5 server.
- **`client/`** (`corplink-client`) — login (company lookup, password / 2FA, session
  keepalive, terminal logout) that produces a `WgConf`, then brings up the tunnel and
  exposes a local SOCKS5 proxy.

It brings up a WireGuard session over the CorpLink TCP transport using
[boringtun](https://github.com/cloudflare/boringtun) for the crypto and
[smoltcp](https://github.com/smoltcp-rs/smoltcp) for a userspace TCP/IP stack,
then lets you either:

- open connections programmatically — `Tunnel::connect(ip, port) -> TunnelStream`
  (an `AsyncRead + AsyncWrite` stream), or
- expose a local **SOCKS5** proxy that forwards through the tunnel.

## How it works

```
your app / SOCKS5  ──▶  smoltcp (userspace TCP/IP, holds the tunnel IP)
                          │  IP packets
                          ▼
                        boringtun  (WireGuard encrypt/decrypt)
                          │  WG packets
                          ▼
                        CorpLink TCP transport  (u32-LE length-prefixed frames)
                          │
                          ▼
                        TCP  ──▶  WireGuard endpoint
```

Two protocol details make CorpLink differ from stock WireGuard, both handled here:

1. **Transport**: WireGuard runs over TCP with a 4-byte little-endian length
   prefix per packet (instead of UDP).
2. **Handshake identifier**: the Noise `IDENTIFIER` constant is
   `"CorpLink v1 vpn@feilian-----------"` instead of the stock WireGuard one.
   The fork at [wilinz/boringtun](https://github.com/wilinz/boringtun) recomputes
   `INITIAL_CHAIN_HASH` accordingly (one commit on top of upstream 0.7.1).

## Quick start (self-contained client)

```bash
cargo run --release -p corplink-client -- config.json
# then point any client at the SOCKS5 proxy from your config
```

`config.json`:

```json
{
  "company_name": "<feilian company code>",
  "username": "<user>",
  "password": "<pass>",
  "platform": "feilian_v1",
  "device_id": "<stable id>",
  "device_name": "corplink-client",
  "socks5_listen": "127.0.0.1:1080",
  "socks5_username": "u",
  "socks5_password": "p"
}
```

## Library usage (datapath only)

You supply a `WgConf` (private/peer keys, endpoint, tunnel address, DNS, MTU),
typically obtained from a CorpLink login handshake:

```rust
use corplink_tunnel::{Tunnel, WgConf};

let conf: WgConf = serde_json::from_slice(&std::fs::read("wgconf.json")?)?;
let tun = Tunnel::start(conf).await?;

// direct stream
let mut s = tun.connect_host("example.internal", 443).await?; // resolves via tunnel DNS
// ... use s as an AsyncRead + AsyncWrite ...

// or a SOCKS5 proxy
corplink_tunnel::socks5::serve(tun, "127.0.0.1:1080").await?;
```

### WgConf JSON

```json
{
  "address": "10.0.0.2/24",
  "peer_address": "192.0.2.1:443",
  "mtu": 1400,
  "private_key": "<base64>",
  "peer_key": "<base64>",
  "dns": "10.0.0.1",
  "protocol": 1
}
```

## Binaries (manual testing)

```bash
# SOCKS5 proxy on 127.0.0.1:1080
cargo run --release --bin socks5d -- wgconf.json 127.0.0.1:1080

# one-shot: connect + TLS + HTTP GET through the tunnel
cargo run --release --bin test-conn -- wgconf.json <ip> <port> <sni> [path]
```

## Docker

```bash
docker build -t corplink-pure-rs .
docker run --rm -p 1080:1080 -v "$PWD/data:/data" corplink-pure-rs
```

The container runs `corplink-client /data/config.json`; `config.json` and the
`corplink_cookies.json` the client writes next to it live in the mounted
directory. Inside the container set `socks5_listen` to `0.0.0.0:1080` if you
want to publish the port. A different config path can be passed as the command:
`docker run … corplink-pure-rs /data/other.json`.

CI publishes `nrt.vultrcr.com/wilinz/corplink-pure-rs:latest` on every push to
`main` (and `v*` tags / manual runs).

## Keeping up with upstream boringtun

`tunnel/Cargo.toml` pins [wilinz/boringtun](https://github.com/wilinz/boringtun)
at tag `corplink-0.7.1`. The fork's `corplink` branch is upstream tag
`boringtun-0.7.1` plus one commit (the `INITIAL_CHAIN_HASH` swap). To move to a
newer upstream release:

```bash
git clone https://github.com/wilinz/boringtun && cd boringtun
git remote add upstream https://github.com/cloudflare/boringtun
git fetch upstream --tags
git rebase boringtun-<new-version>
# verify INITIAL_CHAIN_HASH = BLAKE2s-256(INITIAL_CHAIN_KEY || "CorpLink v1 vpn@feilian-----------")
git tag corplink-<new-version>
git push origin corplink corplink-<new-version>
```

Then bump the tag in `tunnel/Cargo.toml` and run `cargo update -p boringtun`.

## License

MIT (this crate). `boringtun` is BSD-3-Clause, © Cloudflare, Inc.; it is used
from [wilinz/boringtun](https://github.com/wilinz/boringtun), a fork with a
single commit changing the handshake identifier.
