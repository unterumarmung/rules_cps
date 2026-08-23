#!/usr/bin/env bash
set -euo pipefail

readonly workspace="$TEST_SRCDIR/_main"
readonly producer_source="$TEST_TMPDIR/cmake_producer_source"
readonly producer_prefix="$TEST_TMPDIR/cmake_produced_prefix"
readonly producer_build="$TEST_TMPDIR/cmake_produced_build"

version="$(cmake --version | awk 'NR == 1 {print $3}')"
major="${version%%.*}"
minor_patch="${version#*.}"
minor="${minor_patch%%.*}"
if (( major < 4 || (major == 4 && minor < 3) )); then
  echo "CMake 4.3 or newer is required for CPS interoperability; found $version" >&2
  exit 1
fi

cp -RL "$workspace/tests/cmake_interop/producer" "$producer_source"
cmake \
  -S "$producer_source" \
  -B "$producer_build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$producer_prefix"
cmake --build "$producer_build"
cmake --install "$producer_build"
grep -q '"cps_version" : "0.14.1"' "$producer_prefix/lib/cps/CMakeProduced/CMakeProduced.cps"

readonly bazel_consumer="$TEST_TMPDIR/bazel_consumer"
cp -RL "$workspace/tests/cmake_interop/consumer" "$bazel_consumer"
cp "$bazel_consumer/BUILD.bazel.template" "$bazel_consumer/BUILD.bazel"
awk \
  -v rules_cps_path="$workspace" \
  -v prefix="$producer_prefix" \
  '{gsub(/__RULES_CPS_PATH__/, rules_cps_path); gsub(/__PACKAGE_PREFIX__/, prefix); print}' \
  "$bazel_consumer/MODULE.bazel.template" > "$bazel_consumer/MODULE.bazel"
(cd "$bazel_consumer" && bazel --output_user_root="$TEST_TMPDIR/bazel_root" run //:consumer)

materialize_export() {
  local prefix=$1
  mkdir -p "$prefix/include/foo" "$prefix/lib" "$prefix/share/cps/CMakeExported"
  cp -L "$workspace/tests/export/foo.h" "$prefix/include/foo/foo.h"
  cp -L "$workspace/tests/export/lib_rules_cps_foo_native.a" "$prefix/lib/libcmake_exported.a"
  cp -L "$workspace/tests/export/CMakeExported.cps" "$prefix/share/cps/CMakeExported/CMakeExported.cps"
}

run_cmake_consumer() {
  local name=$1
  local prefix=$2
  local build="$TEST_TMPDIR/cmake_export_consumer_$name"
  cmake \
    -S "$workspace/tests/cmake_interop/export_consumer" \
    -B "$build" \
    -DCMAKE_PREFIX_PATH="$prefix"
  cmake --build "$build"
  "$build/consumer"
}

readonly export_prefix_a="$TEST_TMPDIR/cmake_export_prefix_a"
readonly export_prefix_b="$TEST_TMPDIR/cmake_export_prefix_b"
materialize_export "$export_prefix_a"
run_cmake_consumer a "$export_prefix_a"
mv "$export_prefix_a" "$export_prefix_b"
run_cmake_consumer b "$export_prefix_b"
