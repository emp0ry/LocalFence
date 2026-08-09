#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$PROJECT_DIR/build/tests"

mkdir -p "$BUILD_DIR"
clang -std=c11 -Wall -Wextra -Werror -I"$PROJECT_DIR/Shared" \
    "$PROJECT_DIR/Shared/LFCore.c" "$PROJECT_DIR/tests/test_core.c" \
    -o "$BUILD_DIR/test_core"
"$BUILD_DIR/test_core"

OUI_DATABASE="$PROJECT_DIR/app/Resources/OUI.sqlite"
if [ ! -f "$OUI_DATABASE" ]; then
    echo "Missing $OUI_DATABASE; run scripts/update-oui.py" >&2
    exit 1
fi

if [ "$(sqlite3 "$OUI_DATABASE" 'PRAGMA integrity_check;')" != "ok" ]; then
    echo "OUI database integrity check failed" >&2
    exit 1
fi

OUI_COUNT=$(sqlite3 "$OUI_DATABASE" 'SELECT count(*) FROM prefix;')
if [ "$OUI_COUNT" -lt 50000 ]; then
    echo "OUI database has an unexpectedly small prefix table" >&2
    exit 1
fi

echo "LocalFence OUI database tests passed ($OUI_COUNT prefixes)"
