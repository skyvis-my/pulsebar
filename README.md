# Pulsebar

A minimal macOS menu bar monitor for network bandwidth and ping. It stays a fixed width, so the
menu bar never shifts as the numbers change.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/menubar-dark.png">
  <img alt="The four menu bar styles side by side" src="docs/menubar-light.png" width="640">
</picture>

<img alt="Popover with ping and bandwidth history" src="docs/popover.png" width="366">

## Install

```bash
brew install --cask skyvis-my/tap/pulsebar
```

Or download `Pulsebar-<version>.zip` from [Releases](https://github.com/skyvis-my/pulsebar/releases),
unzip, and move `Pulsebar.app` to `/Applications`.

Pulsebar is ad-hoc signed, not notarized by Apple. The Homebrew cask clears the download
quarantine flag for you. If you install from the zip, macOS will block the first launch: right-click
the app, choose **Open**, then confirm (or run `xattr -dr com.apple.quarantine /Applications/Pulsebar.app`).

Requires macOS 14 or later, on Apple silicon or Intel.

## Menu bar styles

Every style has a fixed width: numbers are monospaced and padded to a fixed length, and the
status item width is computed once from worst-case strings. Pick a style in the popover.

| Style | Shows | Width |
|---|---|---|
| Twin stack | ↑/↓ speeds, ping | 60 pt |
| Stack + spark (default) | Same layout, with faint bandwidth history behind the speeds and ping history behind the ping | 60 pt |
| Single line | `↓ 98M ↑  1M 214` | 93 pt |
| Ping only | last 6 pings as latency bars, ping | 49 pt |

The ↓ (green) and ↑ (purple) arrows fade when idle and brighten with traffic, up to full strength
at 1 MB/s. Speeds are bytes per second with a one-letter unit (`K`, `M`, `G`), always whole numbers: the unit
steps up at 1000, so three digits always fit. Ping is always in milliseconds, so the menu bar shows
no unit. To keep it calm, the number only changes when a reading differs from the one shown by at
least 4 ms and more than 10%; the graphs still record every reading. A red `–` means the probe timed out.

## Popover

Click the item for ping and bandwidth history graphs (1m / 5m / 15m / 1h), with min / avg / max /
jitter / loss for ping and peak / total moved for bandwidth. You can also change the menu bar
style, the ping host, and open at login there. The last hour of samples is saved to
`~/Library/Application Support/Pulsebar/history.json` and reloaded on launch.

## Backpack mode: lid closed, screen off, still running

Two switches in the popover:

- **Keep running with lid closed** disables sleep (`pmset -a disablesleep 1`) so macOS and the
  network keep running with the lid shut. It always starts off, and turns itself off (restoring
  normal sleep):
  - at 20% battery when not charging,
  - when macOS reports the Mac is running seriously hot,
  - when Pulsebar quits, including logout, shutdown, or a `kill`,
  - on the next launch, if Pulsebar crashed while it was on.

- **Screen off when lid closes** (on by default). With sleep disabled, macOS leaves the built-in
  screen lit behind a closed lid. Pulsebar turns it off about 2 seconds after the lid closes. It
  does nothing while an external monitor is awake, so lid-closed desk setups are unaffected.

A closed bag blocks airflow, so keep heavy workloads out of the backpack.

### One-time permission

Turning sleep off needs root, and the guards must be able to turn it back on unattended, so
Pulsebar runs exactly two commands through `sudo -n`. It never installs privileges itself. If the
popover says it needs permission, allow those two commands (and nothing else) for your user:

```bash
echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0" > /tmp/pulsebar.sudoers
sudo visudo -cf /tmp/pulsebar.sudoers && sudo install -m 0440 -o root -g wheel /tmp/pulsebar.sudoers /etc/sudoers.d/pulsebar
```

Remove it any time with `sudo rm /etc/sudoers.d/pulsebar`. If another app (such as Amphetamine)
already allows these commands, nothing more is needed.

## How it measures

- **Bandwidth**: 64-bit interface counters from `sysctl(NET_RT_IFLIST2)`, summed over physical
  interfaces (`en*`, `pdp_ip*`). VPN tunnels are skipped to avoid counting traffic twice.
- **Ping**: unprivileged ICMP echo (`SOCK_DGRAM` / `IPPROTO_ICMP`) once a second, 0.9 s timeout.
  No root and no `ping` subprocess. The default host is `1.1.1.1`.

Pulsebar makes no network requests other than the ping, and collects no data.

## Build from source

```bash
./scripts/build-app.sh && open build/Pulsebar.app
```

Needs Xcode 16 or later. `swift test` checks the fixed-width formatting.
`Pulsebar --snapshot <dir>` renders every style and the popover to PNGs (used for the screenshots
above), then quits. `Pulsebar --open-at-login` / `--no-open-at-login` toggle the login item from
the command line.

## Releasing

```bash
./scripts/release.sh 0.2.0
```

Builds a universal app, publishes a GitHub release with the zip, and bumps the cask in
[skyvis-my/homebrew-tap](https://github.com/skyvis-my/homebrew-tap).

## License

[MIT](LICENSE)
