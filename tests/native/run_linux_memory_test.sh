#!/bin/sh
# Focused memory accounting tests; no Godot build or dependencies required.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin=$(mktemp /tmp/ogh-linux-memory.XXXXXX)
trap 'rm -f "$bin"' EXIT HUP INT TERM
"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror -pedantic \
    "$here/linux_memory_test.c" -o "$bin"
"$bin"
