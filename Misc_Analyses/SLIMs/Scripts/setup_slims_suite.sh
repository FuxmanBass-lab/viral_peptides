#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SLIMS_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SLIMSUITE_COMMIT="242d0401252f5d5bb021e814ec60a47f8cf8fced"
SLIMSUITE_PATH="${SLIMSUITE_PATH:-$SLIMS_DIR/SLiMSuite}"

if [[ -e "$SLIMSUITE_PATH" ]]; then
    CURRENT_COMMIT="$(git -C "$SLIMSUITE_PATH" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$CURRENT_COMMIT" == "$SLIMSUITE_COMMIT" ]]; then
        echo "SLiMSuite is already installed at the required commit: $SLIMSUITE_PATH"
        exit 0
    fi
    echo "Refusing to overwrite existing path or mismatched checkout: $SLIMSUITE_PATH" >&2
    echo "Set SLIMSUITE_PATH to a new directory, or check out commit $SLIMSUITE_COMMIT manually." >&2
    exit 1
fi

git clone https://github.com/slimsuite/SLiMSuite.git "$SLIMSUITE_PATH"
git -C "$SLIMSUITE_PATH" checkout --detach "$SLIMSUITE_COMMIT"
echo "Installed SLiMSuite commit $SLIMSUITE_COMMIT at $SLIMSUITE_PATH"
