#!/usr/bin/env bash
set -euo pipefail

readonly workspace="$TEST_SRCDIR/_main"
readonly project="$TEST_TMPDIR/project"
cp -R "$workspace/tests/import_basic" "$project"

readonly local_package_source="$workspace/tests/fixtures/basic/package"
readonly local_package="$TEST_TMPDIR/local_package"
cp -RL "$local_package_source" "$local_package"
readonly escaping_package="$TEST_TMPDIR/escaping_package"
cp -RL "$local_package_source" "$escaping_package"
rm "$escaping_package/include/foo/foo.h"
ln -s /etc/hosts "$escaping_package/include/foo/foo.h"
readonly cycle_package="$TEST_TMPDIR/cycle_package"
cp -RL "$workspace/tests/fixtures/cycle/package" "$cycle_package"
readonly multiple_cps_package="$TEST_TMPDIR/multiple_cps_package"
mkdir -p "$multiple_cps_package/share/cps/Foo" "$multiple_cps_package/share/cps/Other"
cp -L "$local_package_source/share/cps/Foo/Foo.cps" "$multiple_cps_package/share/cps/Foo/Foo.cps"
cp -L "$workspace/tests/import_basic/Other.cps" "$multiple_cps_package/share/cps/Other/Other.cps"
readonly absolute_include_package="$TEST_TMPDIR/absolute_include_package"
mkdir -p "$absolute_include_package/share/cps/Foo"
cp -L "$workspace/tests/import_basic/absolute_include.cps" "$absolute_include_package/share/cps/Foo/Foo.cps"
readonly escaping_location_package="$TEST_TMPDIR/escaping_location_package"
mkdir -p "$escaping_location_package/share/cps/Foo"
cp -L "$workspace/tests/import_basic/escaping_location.cps" "$escaping_location_package/share/cps/Foo/Foo.cps"
readonly absolute_link_library_package="$TEST_TMPDIR/absolute_link_library_package"
mkdir -p "$absolute_link_library_package/share/cps/Foo"
cp -L "$workspace/tests/import_basic/absolute_link_library.cps" "$absolute_link_library_package/share/cps/Foo/Foo.cps"
readonly missing_local_path="$TEST_TMPDIR/does_not_exist"
readonly local_archive="$workspace/tests/fixtures/basic/basic.tar.gz"
readonly integrity="sha256-$(openssl dgst -sha256 -binary "$local_archive" | openssl base64 -A)"

readonly http_directory="$TEST_TMPDIR/http"
mkdir -p "$http_directory"
COPYFILE_DISABLE=1 tar -czf "$http_directory/http.tar.gz" -C "$local_package" .
readonly http_integrity="sha256-$(openssl dgst -sha256 -binary "$http_directory/http.tar.gz" | openssl base64 -A)"
mkdir -p "$http_directory/wrapped"
cp -RL "$local_package/." "$http_directory/wrapped/"
COPYFILE_DISABLE=1 tar -czf "$http_directory/http-wrapped.tar.gz" -C "$http_directory" wrapped
readonly http_wrapped_integrity="sha256-$(openssl dgst -sha256 -binary "$http_directory/http-wrapped.tar.gz" | openssl base64 -A)"
readonly http_port=$((30000 + ($$ % 10000)))
python3 -m http.server "$http_port" --bind 127.0.0.1 --directory "$http_directory" &
readonly http_pid=$!
trap 'kill "$http_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 100); do
  /usr/bin/curl -fs "http://127.0.0.1:$http_port/http.tar.gz" >/dev/null 2>&1 && break
  sleep 0.05
done
readonly http_base="http://127.0.0.1:$http_port"
/usr/bin/curl -fs "$http_base/http.tar.gz" >/dev/null

awk \
  -v package_path="$local_package" \
  -v archive_path="$local_archive" \
  -v escaping_path="$escaping_package" \
  -v cycle_path="$cycle_package" \
  -v multiple_cps_path="$multiple_cps_package" \
  -v absolute_include_path="$absolute_include_package" \
  -v escaping_location_path="$escaping_location_package" \
  -v absolute_link_library_path="$absolute_link_library_package" \
  -v missing_local_path="$missing_local_path" \
  -v integrity="$integrity" \
  -v rules_cps_path="$workspace" \
  -v http_base="$http_base" \
  -v http_integrity="$http_integrity" \
  -v http_wrapped_integrity="$http_wrapped_integrity" \
  '{gsub(/__RULES_CPS_PATH__/, rules_cps_path); gsub(/__LOCAL_PACKAGE_PATH__/, package_path); gsub(/__ESCAPING_PACKAGE_PATH__/, escaping_path); gsub(/__CYCLE_PACKAGE_PATH__/, cycle_path); gsub(/__MULTIPLE_CPS_PATH__/, multiple_cps_path); gsub(/__ABSOLUTE_INCLUDE_PATH__/, absolute_include_path); gsub(/__ESCAPING_LOCATION_PATH__/, escaping_location_path); gsub(/__ABSOLUTE_LINK_LIBRARY_PATH__/, absolute_link_library_path); gsub(/__MISSING_LOCAL_PATH__/, missing_local_path); gsub(/__LOCAL_ARCHIVE_PATH__/, archive_path); gsub(/__LOCAL_ARCHIVE_INTEGRITY__/, integrity); gsub(/__HTTP_ARCHIVE_INTEGRITY__/, http_integrity); gsub(/__HTTP_WRAPPED_INTEGRITY__/, http_wrapped_integrity); gsub(/__HTTP_BASE__/, http_base); print}' \
  "$project/MODULE.bazel" > "$project/MODULE.bazel.generated"
mv "$project/MODULE.bazel.generated" "$project/MODULE.bazel"

cd "$project"
readonly bazel_args=(--output_user_root="$TEST_TMPDIR/bazel_root")
bazel "${bazel_args[@]}" run //:consumer
bazel "${bazel_args[@]}" run //:local_consumer
bazel "${bazel_args[@]}" run //:local_archive_consumer
bazel "${bazel_args[@]}" run //:http_consumer
bazel "${bazel_args[@]}" run //:http_patched_consumer
bazel "${bazel_args[@]}" build //:local_consumer >"$TEST_TMPDIR/local_noop.log" 2>&1
if grep -q "repository.*foo_local.*fetch" "$TEST_TMPDIR/local_noop.log"; then
  cat "$TEST_TMPDIR/local_noop.log" >&2
  exit 1
fi

assert_build_fails() {
  local target=$1
  local expected=$2
  local log="$TEST_TMPDIR/${target//[:\/]/_}.log"
  if bazel "${bazel_args[@]}" build "$target" >"$log" 2>&1; then
    echo "expected $target to fail" >&2
    return 1
  fi
  if ! grep -qi "$expected" "$log"; then
    cat "$log" >&2
    return 1
  fi
}

assert_build_fails //:bad_integrity_consumer "checksum"
assert_build_fails //:missing_cps_consumer "declared CPS file does not exist"
assert_build_fails //:wrong_name_consumer "does not match expected_name"
assert_build_fails //:escaping_header_consumer "escapes materialized CPS package root"
assert_build_fails //:cycle_consumer "CPS compile cycle detected"
assert_build_fails //:multiple_cps_consumer "multiple base CPS documents"
assert_build_fails //:missing_local_consumer "not an existing directory"
assert_build_fails //:absolute_include_consumer "absolute CPS path"
assert_build_fails //:escaping_location_consumer "path escapes the package root"
assert_build_fails //:absolute_link_library_consumer "absolute CPS path"

materialize_roundtrip_prefix() {
  local prefix=$1
  mkdir -p "$prefix/include/foo" "$prefix/lib" "$prefix/share/cps/RoundTrip"
  cp -L "$workspace/tests/export/foo.h" "$prefix/include/foo/foo.h"
  cp -L "$workspace/tests/export/lib_rules_cps_foo_native.a" "$prefix/lib/libroundtrip.a"
  cp -L "$workspace/tests/export/RoundTrip.cps" "$prefix/share/cps/RoundTrip/RoundTrip.cps"
}

run_roundtrip() {
  local name=$1
  local prefix=$2
  local package_name=$3
  local consumer_source=$4
  local component_name=$5
  local roundtrip_project="$TEST_TMPDIR/roundtrip_$name"
  cp -RL "$workspace/tests/export_roundtrip" "$roundtrip_project"
  awk -v consumer_source="$consumer_source" -v component_name="$component_name" \
    '{gsub(/__CONSUMER_SOURCE__/, consumer_source); gsub(/__COMPONENT_NAME__/, component_name); print}' \
    "$roundtrip_project/BUILD.bazel.template" > "$roundtrip_project/BUILD.bazel"
  awk -v rules_cps_path="$workspace" -v prefix="$prefix" -v package_name="$package_name" \
    '{gsub(/__RULES_CPS_PATH__/, rules_cps_path); gsub(/__PACKAGE_PREFIX__/, prefix); gsub(/__PACKAGE_NAME__/, package_name); print}' \
    "$roundtrip_project/MODULE.bazel.template" > "$roundtrip_project/MODULE.bazel"
  (cd "$roundtrip_project" && bazel "${bazel_args[@]}" run //:consumer)
}

readonly prefix_a="$TEST_TMPDIR/prefix_a"
readonly prefix_b="$TEST_TMPDIR/prefix_b"
materialize_roundtrip_prefix "$prefix_a"
run_roundtrip a "$prefix_a" RoundTrip consumer.cc core
mv "$prefix_a" "$prefix_b"
run_roundtrip b "$prefix_b" RoundTrip consumer.cc core

readonly imported_prefix="$TEST_TMPDIR/imported_prefix"
mkdir -p "$imported_prefix/include/foo" "$imported_prefix/lib" "$imported_prefix/share/cps/ImportedRoundTrip"
cp -L "$workspace/tests/fixtures/basic/package/include/foo/foo.h" "$imported_prefix/include/foo/foo.h"
readonly selected_import_archive="$(find "$TEST_SRCDIR" -path '*/lib/libfoo_value.a' ! -path "$workspace/*" -print -quit)"
test -n "$selected_import_archive"
cp -L "$selected_import_archive" "$imported_prefix/lib/libimported_roundtrip.a"
cp -L "$workspace/tests/export/ImportedRoundTrip.cps" "$imported_prefix/share/cps/ImportedRoundTrip/ImportedRoundTrip.cps"
run_roundtrip imported "$imported_prefix" ImportedRoundTrip imported_consumer.cc static

assert_module_fails() {
  local case_name=$1
  local expected=$2
  local repository=${3:-foo}
  local case_project="$TEST_TMPDIR/module_$case_name"
  cp -RL "$workspace/tests/module_cases/$case_name" "$case_project"
  awk -v rules_cps_path="$workspace" \
    '{gsub(/__RULES_CPS_PATH__/, rules_cps_path); print}' \
    "$case_project/MODULE.bazel.template" > "$case_project/MODULE.bazel"
  local log="$TEST_TMPDIR/module_$case_name.log"
  if (cd "$case_project" && bazel "${bazel_args[@]}" query "@$repository//..." >"$log" 2>&1); then
    echo "expected module case $case_name to fail" >&2
    return 1
  fi
  if ! grep -qi "$expected" "$log"; then
    cat "$log" >&2
    return 1
  fi
}

assert_module_fails duplicate_config "at most one root cps.config"
assert_module_fails duplicate_package "duplicate logical CPS package"
assert_module_fails unknown_variant "unknown logical package" missing
assert_module_fails duplicate_variant "duplicate physical CPS variant"
assert_module_fails indistinguishable_variants "indistinguishable physical variants" foo
assert_module_fails missing_binding_target "unknown logical package not_declared"
assert_module_fails non_root "only the root module may choose CPS packages" forbidden
