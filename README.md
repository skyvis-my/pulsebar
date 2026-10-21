# Pulsebar

A minimal macOS menu bar monitor for network bandwidth and ping, with a fixed width that never shifts.

## Menu bar styles

Every style has a fixed width: numbers are monospaced and padded to a fixed length, and the
status item width is computed once from worst-case strings. Pick a style in the popover.

| Style | Shows | Width |
|---|---|---|
| Twin stack | ↑/↓ speeds, ping | 59 pt |
| Stack + spark (default) | Same layout, with faint bandwidth history behind the speeds and ping history behind the ping | 59 pt |
| Single line | `↓ 98M ↑  1M 214` | 99 pt |
| Ping only | last 6 pings as latency bars, ping | 48 pt |

Speeds are bytes per second with a one-letter unit (`K`, `M`, `G`), always whole numbers: the unit
steps up at 1000, so three digits always fit. Ping is always in milliseconds, so the menu bar shows
no unit. A red `–` means the probe timed out.

## Popover

Click the item for ping and bandwidth history graphs (1m / 5m / 15m / 1h), with min / avg / max /
jitter / loss for ping and peak / total moved for bandwidth. The last hour of samples is saved to
`~/Library/Application Support/Pulsebar/history.json` and reloaded on launch.

## How it measures

- **Bandwidth**: 64-bit interface counters from `sysctl(NET_RT_IFLIST2)`, summed over physical
  interfaces (`en*`, `pdp_ip*`). VPN tunnels are skipped to avoid counting traffic twice.
- **Ping**: unprivileged ICMP echo (`SOCK_DGRAM` / `IPPROTO_ICMP`) once a second, 0.9 s timeout.
  The default host is `1.1.1.1`.

## Build and run

```bash
./scripts/build-app.sh && open build/Pulsebar.app
```

Requires macOS 14+ and Xcode command line tools. `swift test` checks the fixed-width formatting.
`Pulsebar --snapshot <dir>` renders every style and the popover to PNGs, then quits.

To install and start at login:

```bash
ditto build/Pulsebar.app /Applications/Pulsebar.app
/Applications/Pulsebar.app/Contents/MacOS/Pulsebar --open-at-login
open /Applications/Pulsebar.app
```

`--no-open-at-login` turns it off again (same as the checkbox in the popover).
