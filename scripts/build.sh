#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
THEOS_DIR=${THEOS:-"$HOME/theos"}

if [ ! -f "$THEOS_DIR/makefiles/common.mk" ]; then
    echo "Theos was not found at $THEOS_DIR" >&2
    exit 1
fi

cd "$PROJECT_DIR"
THEOS="$THEOS_DIR" make clean package FINALPACKAGE=1
