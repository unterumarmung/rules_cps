# rules_cps

`rules_cps` lets Bazel consume and produce Common Package Specification files.
The package description stays authoritative. The rules do not search package
registries, system prefixes, compiler caches, or package manager databases.

The rules target CPS 0.15. They support Linux and macOS with Bazel 9.
Windows is not supported.

## Import a package

Declare a logical package and at least one physical variant in `MODULE.bazel`.

```starlark
cps = use_extension("@rules_cps//cps:extensions.bzl", "cps")

cps.package(
    name = "zlib",
    expected_name = "ZLIB",
    expose_components = ["zlib"],
    cps_file = "share/cps/ZLIB/ZLIB.cps",  # Optional; omit for automatic discovery.
)

cps.http_archive(
    package = "zlib",
    variant = "linux_x86_64",
    urls = ["https://packages.example.com/zlib-linux-x86_64.tar.zst"],
    integrity = "sha256-...",
    compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)

use_repo(cps, "zlib")
```

Imported components expose ordinary `CcInfo`, so existing `rules_cc` targets
can depend on them directly.

```starlark
load("@rules_cc//cc:defs.bzl", "cc_binary")

cc_binary(
    name = "app",
    srcs = ["main.cc"],
    deps = ["@zlib//:zlib"],
)
```

Stock `rules_cc` preserves common include directories and definitions,
archives, dynamic libraries, ordinary requirements, and normal linker inputs and flags.
No wrapper is needed when the imported package only uses semantics represented
by `CcInfo`.

Some CPS semantics do not fit in `CcInfo`. Stock `rules_cc` cannot preserve
arbitrary consumer compiler flags, language-specific includes or definitions,
deliberate duplicate link positions, loader-only requirements, or runtime-loaded
modules. Use the matching `rules_cps` wrapper when a dependency needs those
features:

```starlark
load("@rules_cps//cps:defs.bzl", "cc_binary")
```

The wrapper accepts normal `rules_cc` arguments. It adds CPS compiler response
files, preserves the ordered link plan, and places CPS runtime files in
runfiles.

## Install the native compatibility check

Put these lines in the workspace `.bazelrc`.

```text
build --aspects=@rules_cps//cps:compatibility.bzl%cps_compatibility_aspect
build --@rules_cps//cps:compatibility_aspect_enabled=true
```

The aspect allows exact stock `rules_cc` edges and reports an edge that would
lose CPS behavior. The default policy is an error. The diagnostic names the
consumer, package, component, field, value, and CPS source path. A project may
set a specific gap to `warning` or `ignore`, but that accepts the lost behavior;
it does not make the stock edge equivalent to a wrapper edge.

## Public labels

For a logical repository named `foo`, generated labels follow these forms.

```text
@foo//:core
@foo//core:debug
@foo//:@default
@foo//:@package
```

The first label uses configuration preferences. The second requests one exact
configuration. `@default` selects the package defaults. `@package` exposes
package metadata without selecting a component.

## Export a package

Export starts at an explicit package boundary.

```starlark
load("@rules_cps//cps:defs.bzl", "cps_component", "cps_package")

cps_component(
    name = "core_cps",
    component_name = "core",
    target = ":core",
    component_type = "archive",
    install_library = "lib/libcore.a",
    headers = {":public_headers": "include/core"},
)

cps_package(
    name = "core_package",
    package_name = "Core",
    version = "2.4.1",
    compat_version = "2.0.0",
    components = [":core_cps"],
    default_components = ["core"],
)
```

`cps_package` writes relocatable JSON and returns
`CpsPackageLayoutInfo`. The layout maps Bazel files to installed paths. It
does not force an archive format or add a dependency on a packaging rule set.

## Run the tests

```sh
bazel test //...
```

The suite compiles and links real programs. It also runs nested clean
workspaces, HTTP mirror tests, relocation tests, native compatibility failures,
synthetic graph tests, and CMake interoperability in both directions.

CI runs Bazel 9 on Linux and macOS. It installs CMake 4.4.2 for the CPS
interoperability test.

## Read next

- [Import packages](docs/import.md) explains acquisition, variants, labels, and
  bindings.
- [Choose a CPS configuration](docs/configurations.md) defines preference,
  exact, and same selection.
- [Export packages](docs/export.md) explains installed paths and package layout
  records.
- [Use wrappers or stock rules_cc](docs/native-compatibility.md) explains
  wrappers and stock C++ diagnostics.
- [Hermeticity and path checks](docs/hermeticity.md) lists path checks and
  non-hermetic inputs.
- [Public Starlark API](docs/api.md) is the public API reference.
- [CPS 0.15 support](docs/support-matrix.md) states how `rules_cps` handles each
  CPS field.
- [Tests](docs/testing.md) maps requirements to tests.
- [CMake interoperability](docs/cmake-interoperability.md) explains the CPS
  0.14.1 CMake profile.

Runnable BUILD examples live in `examples/BUILD.bazel`.
