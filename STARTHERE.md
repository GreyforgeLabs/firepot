# STARTHERE.md - AI Bootstrap Guide

> This file is designed for AI coding assistants. If you are a human,
> see [README.md](README.md) for the human-friendly guide.

## Quick Bootstrap

```bash
git clone https://github.com/GreyforgeLabs/node-healthcheck.git && cd node-healthcheck && ./scripts/setup.sh
```

## What This Project Does

A single bash script that checks a Linux host (load, memory, swap, disk, inodes, network, gateway, DNS, systemd units, ports, peers, failed units, time sync, pending reboot, sessions, zombies), prints text or JSON, exits 0/1/2 for healthy/warning/critical, and can run across several hosts over SSH and aggregate the results.

## Project Structure

```text
node-healthcheck/
  bin/node-healthcheck        # the tool; a single bash file
  examples/
    node-healthcheck.conf     # documented key=value config
  tests/
    run.sh                    # fixture-driven test suite (bash + python3 for JSON asserts)
  scripts/
    setup.sh                  # links the script into ~/.local/bin and runs the tests
  .github/workflows/          # shellcheck + tests + live smoke run; tagged release
  README.md                   # human-facing docs
  STARTHERE.md                # this file
```

## Setup Prerequisites

- bash 4.0 or newer, coreutils, awk (any Linux distribution)
- Optional per check: `ip`, `ss` or `netstat`, `systemctl`, `ping`, `getent`, `timedatectl`, `who`
- Tests only: python3
- No root required

## Installation Steps

1. Clone: `git clone https://github.com/GreyforgeLabs/node-healthcheck.git`
2. Enter directory: `cd node-healthcheck`
3. Run setup: `./scripts/setup.sh`

`setup.sh` symlinks `bin/node-healthcheck` into `~/.local/bin` (override with `NODE_HEALTHCHECK_INSTALL_DIR`) and runs the verification below.

## Verification

```bash
bin/node-healthcheck --version
# Expected output: node-healthcheck 1.0.0
bash tests/run.sh
# Expected output: node-healthcheck tests: N passed, 0 failed
```

## Key Entry Points

- `bin/node-healthcheck` - all logic. Checks are functions named `check_<name>` and are dispatched from the `ALL_CHECKS` list. `record NAME STATUS SUMMARY key=value...` is the single output path for text and JSON.
- `tests/run.sh` - fixture builder (`healthy_proc`, `shim`) and assertions (`assert_eq`, `jget`).

## Configuration

- Flags: see `bin/node-healthcheck --help`
- Config file: `--config FILE`, format in `examples/node-healthcheck.conf`
- Test hooks: `NODE_HEALTHCHECK_PROC` (alternate `/proc` root) and `NODE_HEALTHCHECK_ROOT` (alternate filesystem root for `/var/run/reboot-required`)

## Common Tasks

```bash
# Run the tests
bash tests/run.sh

# Lint
shellcheck -S style bin/node-healthcheck scripts/setup.sh tests/run.sh

# Try it on this machine
bin/node-healthcheck --no-color
bin/node-healthcheck --json | python3 -m json.tool
```
