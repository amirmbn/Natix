# Natix ![GitHub Downloads](https://img.shields.io/github/downloads/amirmbn/Natix/total)

High-performance kernel L3/L2 tunnels, reverse TCP carrier, and encrypted UDP transports between servers with a lightweight Ubuntu CLI and connection quality tester.

## Features

- **28 Tunnel Methods**: Kernel L3 (`gre`, `6to4`, `ipip`, `sit`, `wireguard`, `xfrm-ipsec`, `fou-gre`, `gue-ipip`, `ecmp-lanes`, ...) and L2 (`eoip`, `gretap`, `vxlan`, `geneve`, `l2tpv3`, `etherip`) plus 8 AES-256-GCM UDP-Crypt transports (`dtls-1.3`, `quic-v1`, `srtp-direct`, `wg-stealth`, `rudp-fec`, `dnscrypt-udp`, `ntp-direct`, `openvpn-dco`).
- **Direct & Reverse Modes**: Standard direct tunnels or anti-DPI reverse tunnels (8-stream TLS-shaped TCP carrier or reverse UDP).
- **Connection Quality & Speed Tester**: Probes all methods between two servers, measures latency, packet loss, Path MTU, and bidirectional throughput, and recommends the optimal method.
- **One-Line Setup Links**: Generate a `natix://` link on the Iran server and apply it directly on the Kharej server.
- **Port Forwarding & Built-in Proxy**: Per-tunnel iptables DNAT/SNAT port forwarding and optional built-in SOCKS5/HTTP loopback proxy.
- **Pure CLI**: Lightweight, zero web-panel overhead, managed via `natix` interactive menu or subcommands on Ubuntu/Debian.

---

## Installation

### From GitHub Release (Both Servers)

```bash
bash -c "$(curl -sL https://raw.githubusercontent.com/amirmbn/Natix/main/install.sh)"
```

### From Local Source Checkout (Ubuntu)

```bash
git clone https://github.com/amirmbn/Natix.git
cd Natix
sudo NATIX_LOCAL=1 bash install.sh
```

---

## CLI Usage

Run interactive menu:

```bash
sudo natix
```

Direct commands:

```text
Usage: natix [command]

  (no command)                 interactive menu
  status                       tunnel table with state and traffic
  up|restart|down <name>       start, restart or stop a tunnel
  link <name>                  print the setup link for the other server
  apply-link 'natix://...'     create and start the tunnel from a link
  conntest-server [ip]         iran side of the connection test: prints a link
  conntest 'natix-test://…'    kharej side: which methods pass, speed, recommendation
  linktest [-port N] <host>    latency, loss and speed to <host>
  speedtest-server [-port N]   responder for linktest (default 7711/tcp)
  restart-all                  restart every tunnel
  proxy-serve                  run the built-in SOCKS5/HTTP proxy
  optimize                     apply BBR and buffer tuning
  catalog                      list tunnel methods
  version                      show version
```

---

## Service & Configuration Paths

- `/usr/local/bin/natix` — Management CLI
- `/usr/local/bin/natix-engine` — Userspace & Reverse Carrier Engine
- `/usr/local/lib/natix/natix-kernel` — Kernel interface & firewall helper
- `/etc/natix/state.json` — Tunnels state store
- `/etc/natix/tunnels/<name>.env` — Per-tunnel environment configuration
- `/etc/systemd/system/natix@.service` — Systemd unit for kernel tunnels
- `/etc/systemd/system/natix-engine@.service` — Systemd unit for engine tunnels
- `/etc/sysctl.d/99-natix.conf` — Kernel BBR & socket buffer tuning
