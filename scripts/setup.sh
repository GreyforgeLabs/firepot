#!/usr/bin/env bash
set -euo pipefail

# firepot setup script
# Idempotent - safe to run multiple times

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# FIREPOT_INSTALL_DIR wins; NODE_HEALTHCHECK_INSTALL_DIR is the pre-rename fallback.
INSTALL_DIR="${FIREPOT_INSTALL_DIR:-${NODE_HEALTHCHECK_INSTALL_DIR:-$HOME/.local/bin}}"
# Set FIREPOT_LEGACY_LINK=0 to skip the deprecated node-healthcheck alias link.
LEGACY_LINK="${FIREPOT_LEGACY_LINK:-1}"

echo "=== firepot Setup ==="

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

chmod +x "$PROJECT_DIR/bin/firepot"

mkdir -p "$INSTALL_DIR"
ln -sf "$PROJECT_DIR/bin/firepot" "$INSTALL_DIR/firepot"
echo "Linked $INSTALL_DIR/firepot -> $PROJECT_DIR/bin/firepot"

# Existing cron jobs and fleet callers may still invoke the pre-rename name.
# The alias prints a one-line deprecation note to stderr and then runs firepot.
if [[ "$LEGACY_LINK" != "0" ]]; then
    ln -sf "$PROJECT_DIR/bin/firepot" "$INSTALL_DIR/node-healthcheck"
    echo "Linked $INSTALL_DIR/node-healthcheck -> $PROJECT_DIR/bin/firepot (deprecated alias)"
fi

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) echo "NOTE: $INSTALL_DIR is not on PATH; add it or call $PROJECT_DIR/bin/firepot directly." ;;
esac

echo "=== Setup complete ==="

echo "Running verification..."
"$PROJECT_DIR/bin/firepot" --version
bash "$PROJECT_DIR/tests/run.sh"
