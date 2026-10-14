#!/bin/bash
# Always build current source; share verification and installation with the test entry.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/test-and-install.sh" --install-only
