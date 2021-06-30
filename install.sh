#!/usr/bin/env bash

set -eu

HOME_BIN="$HOME/bin"

tool="$(realpath "src/gdrive.sh")"
target="$HOME_BIN/gdrive"

echo "link $tool to $target"
ln -sf "$tool" "$target"
