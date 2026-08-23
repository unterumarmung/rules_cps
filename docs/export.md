# Export packages

Export describes installed files. It never writes a Bazel output path into a
CPS document.

The package author chooses the package boundary, component names, public
headers, requirements, and installed destinations. The exporter does not walk
an arbitrary transitive graph and guess a package API.

## Declare a component

```starlark
load("@rules_cps//cps:defs.bzl", "cps_component")

cps_component(
    name = "core_cps",
    component_name = "core",
    target = ":core",
    component_type = "archive",
    install_library = "lib/libcore.a",
    headers = {
        ":public_headers": "include/core",
    },
    definitions = {
        "CORE_ABI": "2",
    },
    compile_flags = ["-DCORE_CONSUMER=1"],
    requires = ["ZLIB:zlib"],
)
```

`component_type` accepts `archive`, `dylib`, `executable`,
`interface`, `module`, and `symbolic`.

An archive, dynamic library, module, or executable needs an explicit installed
artifact path. The target must expose one unambiguous artifact of the requested
type. Two candidate archives fail. The exporter does not choose one based on
filename order.

Header values are installed directories. Each source label may provide one or
more files. The exporter keeps the source `File` and the installed
destination as separate values.

By default, each header destination is also a consumer include root. Set
`include_roots` when the installed directory is below the include root. For
example, a header installed as `include/foo/foo.h` can use `include_roots =
["include"]` so consumers keep writing `#include <foo/foo.h>`.

Requirements remain in separate channels.

```starlark
cps_component(
    name = "frontend_cps",
    component_name = "frontend",
    target = ":frontend",
    component_type = "archive",
    install_library = "lib/libfrontend.a",
    requires = [":base"],
    compile_requires = [":headers"],
    link_requires = [":backend"],
    dyld_requires = [":plugin"],
)
```

## Declare the package

```starlark
load("@rules_cps//cps:defs.bzl", "cps_package")

cps_package(
    name = "core_package",
    package_name = "Core",
    version = "2.4.1",
    compat_version = "2.0.0",
    version_schema = "simple",
    components = [
        ":core_cps",
        ":frontend_cps",
    ],
    default_components = ["core"],
)
```

Every default component must exist. Duplicate component names fail.

The default output schema is CPS 0.15.0. Set `cps_version = "0.14.1"` only
for the maintained CMake compatibility profile. No other output versions are
accepted by the rule.

## Read the package layout

`cps_package` returns `CpsPackageLayoutInfo`.

The provider has four fields.

- `cps_files` contains generated CPS documents.
- `entries` contains ordered source and destination records.
- `symlinks` contains ordered installed symlink records.
- `package` contains exported package metadata.

A small package may have these entries.

```text
include/core/core.h
lib/libcore.a
share/cps/Core/Core.cps
```

Destinations are sorted, unique, and package relative. An absolute destination
or a path with `..` fails.

Core export does not build a tarball or installer. A `rules_pkg` adapter, a
distribution rule, or a custom installer can consume the provider without
changing CPS generation.

## Relocation

Generated paths use `@prefix@`.

```json
{
  "cps_path": "@prefix@/share/cps/Core",
  "location": "@prefix@/lib/libcore.a"
}
```

The test suite materializes an exported package at one prefix, consumes it,
moves the whole prefix, and consumes it again. The CPS file does not contain an
execroot, output base, or temporary directory.

## Export wrapper and stock targets

The export aspect reads rich usage metadata from CPS-aware wrappers. This keeps
consumer flags that `CcInfo` cannot represent.

For known stock `rules_cc` targets, the aspect inspects stable rule
attributes and `CcInfo`. Public definitions may be inferred. Local
definitions are not exported. An ambiguous artifact fails and asks for explicit
metadata.

The aspect gathers facts. `cps_component` still defines the package boundary
and installed names.

## CMake output

CMake 4.4 reads CPS 0.14.1. The CMake interoperability test uses an explicit
0.14.1 package with fields supported by both tools. The default 0.15 output does
not change.

See `docs/cmake-interoperability.md` for the exact test paths.
