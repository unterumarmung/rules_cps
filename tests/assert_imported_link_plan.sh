#!/bin/sh
set -eu

actual=$(sed 's|.*/||; s|"$||' "$1" | tr '\n' ' ')
expected='libA.a libB.a libA.a libB.a '
if [ "$actual" != "$expected" ]; then
  echo "expected duplicate-preserving CPS link plan: $expected" >&2
  echo "actual: $actual" >&2
  exit 1
fi
