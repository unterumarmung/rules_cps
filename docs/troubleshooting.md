# Troubleshooting

## The global aspect sentinel is disabled

The workspace did not install the native compatibility aspect, or it installed
the aspect without enabling its sentinel.

Add both lines to `.bazelrc`.

```text
build --aspects=@rules_cps//cps:compatibility.bzl%cps_compatibility_aspect
build --@rules_cps//cps:compatibility_aspect_enabled=true
```

Do not set `require_global_aspect = False` in a normal workspace. Tests use
that escape hatch only when they call an internal repository rule directly.

## No physical variant matches

The configured Bazel platform did not satisfy any declared
`compatible_with` list.

Check the target platform with `bazel cquery`. Then compare its constraint
values with each physical variant. CPS platform metadata does not select a
variant.

An optional environment variant also becomes unavailable when its variable is
unset. Set the declared variable or choose a platform with another variant.

## A package binding is missing

The CPS document requires another package identity, but the root module did not
bind that identity to a logical package.

Add a global binding or a package override. The bound logical package must be
declared and imported with `use_repo`.

```starlark
cps.config(default_package_bindings = {"ZLIB": "zlib"})
```

The rules will not search for ZLIB or download it on demand.

## A path escapes the package root

The message includes the CPS field and resolved file. Common causes are an
absolute include directory, too many `..` segments, or a symlink inside an
include tree that points to a host SDK.

Fix the package layout. Disabling the check is not supported.

## An exact configuration is unavailable

An exact label or requirement named a configuration missing from the selected
physical variant.

Use a normal preferred label if fallback is acceptable. Otherwise add that
configuration to the package or select a different physical variant.

## CMake cannot read the CPS file

CMake 4.4 reads CPS 0.14.1. A default `rules_cps` export uses CPS 0.15.0, so
CMake reports an unknown version before it reads the components.

For a package limited to the shared CMake feature set, export with this
attribute.

```starlark
cps_package(
    name = "cmake_package",
    package_name = "Example",
    cps_version = "0.14.1",
    components = [":core_cps"],
)
```

Do not edit the generated version string after export. Fields added in CPS 0.15
may not exist in the older schema.

## A stock C++ dependency fails on a CPS field

The stock edge would lose behavior. Use a wrapper from
`@rules_cps//cps:defs.bzl` or set a feature policy after checking that the
loss is safe for this target.

The error names the exact field and values. `ignore` hides the diagnostic. It
does not implement the missing behavior.

## A nested integration test is slow

The repository and CMake tests launch clean Bazel workspaces. A first run may
extract Bazel and resolve module dependencies more than once.

Use a focused target while debugging.

```sh
bazel test //tests:nested_archive_repository_test --test_output=all
bazel test //tests:cmake_interoperability_test --test_output=all
```
