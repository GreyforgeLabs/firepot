#!/usr/bin/env bash
set -euo pipefail

# node-healthcheck setup script
# Idempotent - safe to run multiple times

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="${NODE_HEALTHCHECK_INSTALL_DIR:-$HOME/.local/bin}"

echo "=== node-healthcheck Setup ==="

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "ERROR: $1 is required but not installed."
        exit 1
    fi
}

check_command bash
check_command awk
check_command df

if (( BASH_VERSINFO[0] < 4 )); then
    echo "ERROR: bash 4.0 or newer is required (found ${BASH_VERSION})."
    exit 1
fi

chmod +x "$PROJECT_DIR/bin/node-healthcheck"

mkdir -p "$INSTALL_DIR"
ln -sf "$PROJECT_DIR/bin/node-healthcheck" "$INSTALL_DIR/node-healthcheck"
echo "Linked $INSTALL_DIR/node-healthcheck -> $PROJECT_DIR/bin/node-healthcheck"

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) echo "NOTE: $INSTALL_DIR is not on PATH; add it or call $PROJECT_DIR/bin/node-healthcheck directly." ;;
esac

echo "=== Setup complete ==="

echo "Running verification..."
"$PROJECT_DIR/bin/node-healthcheck" --version
bash "$PROJECT_DIR/tests/run.sh"
