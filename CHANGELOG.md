# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

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
