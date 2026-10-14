# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.3.0] - 2026-10-14

### Added

- `FIREPOT_PROBE_TIMEOUT` sets the time limit for filesystem probes (default 10 seconds), so a stuck mount can no longer hang a run.

### Fixed

- Fleet mode accepts remote reports that contain `info` checks. `sessions` is always `info` and `swap` is `info` without swap, so a `--host` run with the default check set now aggregates every node instead of marking each one as an invalid report.
- A remote that runs but exits with a code other than 0, 1, or 2 is reported as `remote run failed with exit N`; `ssh failed` is kept for ssh's own exit 255.
- Text-mode fleet output prints each failing check's summary decoded from JSON, so quotes and backslashes come through intact.
- Remote reports stream straight into the 1 MiB-bounded validator rather than being buffered in a shell variable first. `ServerAliveInterval` (the `--ssh-timeout` value) with three retries ends dead connections.
- `df` runs under a deadline (10 seconds, `FIREPOT_PROBE_TIMEOUT`), so a hung mount becomes a critical result instead of stalling the run. The default filesystem list uses `df -l`, matching the documented local-filesystem scope.
- Lists given to `--services`, `--peers`, `--mounts`, and the other list options are never glob-expanded against the working directory, and empty items are dropped.
- Load per core divides by online CPUs from `/sys/devices/system/cpu/online`. `nproc` (the fallback) follows the caller's CPU affinity and `OMP_NUM_THREADS`, which do not bound the system-wide load average.
- The gateway check follows the first default route: multipath next hops are pinged correctly, and a point-to-point default route (WireGuard, PPP), which has no next hop to ping, is reported as `info`.
- Mount points containing spaces or `=` keep their full names in the disk and inode metrics.
- String metrics (`hostname`, `kernel`, `name`, `address`, `gateway`) are always JSON strings, so every hostname, including all-digit names such as `007`, yields valid JSON.
- Port lists accept leading zeros (`022` matches port 22), reject numbers above 65535 as usage errors, and work with `ss` builds that lack `-H`.
- An empty `/proc/loadavg` or an incomplete `/proc/meminfo` is reported as a skipped check. Any unexpected runtime failure exits 3, as documented, rather than with a status that reads as a health state.
- Arguments after `--` are rejected as usage errors instead of being ignored.

### Changed

- A full local check starts 12 processes instead of 559 and finishes in about a tenth of the time (median 76 ms instead of 886 ms on the reference host). JSON escaping, thresholds, and percentages are computed in bash; the hostname, kernel release, CPU count, uptime, and memory figures are read from `/proc` and `/sys`; and each probe's output is parsed without awk, sed, sort, or tr.
- Configured peers are pinged in parallel, so unreachable peers cost one ping timeout in total rather than one each.
- Configured systemd units are checked with one `systemctl is-active` call, falling back to one call per unit if systemctl cannot answer for the whole list.
- The script runs with `LC_ALL=C`, so probe output parses the same way in every locale.
- Long options and config keys share one table, and fleet mode forwards the effective settings, whether they came from flags or `--config`.
- awk is no longer required.
- The deprecated `node-healthcheck` name keeps working; its stderr note now says it will be removed in a future release.

## [1.2.0] - 2026-10-05

### Changed

- Renamed from node-healthcheck to firepot. The script is now `bin/firepot`, and the usage text, version banner, and error prefix say `firepot`. The example config is `examples/firepot.conf`.
- `scripts/setup.sh` links `firepot` into the install directory. It also links the deprecated `node-healthcheck` alias unless `FIREPOT_LEGACY_LINK=0`.
- Release assets are `firepot` and `firepot.sha256`. A deprecated `node-healthcheck` copy and checksum are also published for this release.
- New environment variables `FIREPOT_PROC`, `FIREPOT_ROOT`, and `FIREPOT_INSTALL_DIR`.

### Deprecated

- The `node-healthcheck` name keeps working for this release only. `bin/node-healthcheck` stays in the repository as an identical copy of `bin/firepot`, so the old raw download URL keeps serving the script. Invoked through the old name, the script prints a one-line deprecation note to stderr and then behaves identically. Remote hosts in fleet mode never print it.
- `NODE_HEALTHCHECK_PROC`, `NODE_HEALTHCHECK_ROOT`, and `NODE_HEALTHCHECK_INSTALL_DIR` are still read as fallbacks when the `FIREPOT_*` variable is unset.

### Compatibility

- The JSON version key stays `"node-healthcheck"` in local, fleet, and per-node error reports. Fleet validation accepts reports keyed `"node-healthcheck"` or `"firepot"`.

## [1.1.0] - 2026-09-27

### Fixed

- Treat missing explicitly requested mounts and missing probe commands for configured services, ports, peers, and DNS as critical instead of healthy skips.
- Validate and bound remote JSON before inserting it into a fleet report; malformed reports now become critical node errors.

### Changed

- Fleet aggregation requires Python 3 on the originating host for JSON validation. Remote hosts and local-only scans retain the single-script deployment model.

## [1.0.0] - 2026-09-06

### Added

- Single-file bash health check with no dependencies beyond coreutils, awk, and the tools each check probes
- Eighteen checks: system, load, memory, swap, disk, inodes, network, gateway, dns, services, user_services, ports, peers, failed_units, time_sync, reboot_required, sessions, zombies
- `--json` output with per-check status, summary, and numeric metrics, generated without `jq`
- Exit codes `0` healthy, `1` warning, `2` critical, `3` usage or runtime error
- Configurable warn and crit thresholds for load per core, memory, swap, disk, inodes, and zombies
- `--config` key=value files that are parsed, never sourced
- `--host` multi-node mode that streams the script over SSH, runs it remotely, and aggregates the results
- `--check`, `--skip`, `--quiet`, and `--no-color` selection and output controls
- Fixture-driven test suite in plain bash (`tests/run.sh`) with fake `/proc` trees and shimmed system commands
- GitHub Actions CI running shellcheck, the test suite, and a live smoke run; tagged release workflow with a checksummed script artifact
- README, STARTHERE bootstrap, example configuration, and idempotent setup script
