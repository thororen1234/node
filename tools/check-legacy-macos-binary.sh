#!/bin/sh
# Fails if a macOS binary will not run on the given macOS version: its minimum
# OS load command is newer, or (with --static-libcxx) it still links the system
# libc++, which lacks std::filesystem before macOS 10.15.
#
# Usage: tools/check-legacy-macos-binary.sh <binary> <min-version> [--static-libcxx]

set -eu

BINARY=${1:?usage: $0 <binary> <min-version> [--static-libcxx]}
WANT=${2:?usage: $0 <binary> <min-version> [--static-libcxx]}
STATIC_LIBCXX=${3:-}
status=0

# LC_BUILD_VERSION reports "minos X", LC_VERSION_MIN_MACOSX reports "version X".
FOUND=$(otool -l "$BINARY" | awk '
  /cmd LC_BUILD_VERSION|cmd LC_VERSION_MIN_MACOSX/ { want = 1; next }
  want && ($1 == "minos" || $1 == "version") { print $2; exit }')

if [ -z "$FOUND" ]; then
  echo "::error file=$BINARY::no minimum macOS version load command found"
  exit 1
fi

if ! python3 -c 'import sys; v=lambda s: tuple(map(int, s.split("."))); sys.exit(v(sys.argv[1]) > v(sys.argv[2]))' "$FOUND" "$WANT"; then
  echo "::error file=$BINARY::minimum macOS is $FOUND, expected $WANT or lower"
  status=1
else
  echo "$BINARY: minimum macOS $FOUND"
fi

if [ "$STATIC_LIBCXX" = "--static-libcxx" ]; then
  if otool -L "$BINARY" | grep -E 'libc\+\+(abi)?(\.1)?\.dylib'; then
    echo "::error file=$BINARY::links the system libc++; expected it statically linked"
    status=1
  else
    echo "$BINARY: libc++ is statically linked"
  fi
fi

exit $status
