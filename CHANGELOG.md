# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

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
