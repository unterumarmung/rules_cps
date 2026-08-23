# Import packages

Import has two names for one package.

The logical name is the stable Bazel repository name. The physical variant is a
specific archive or local tree for one platform. A logical package may have
many variants, but users depend on one logical label.

## Declare the logical package

```starlark
cps = use_extension("@rules_cps//cps:extensions.bzl", "cps")

cps.package(
    name = "openssl",
    expected_name = "OpenSSL",
    expose_components = ["ssl", "crypto"],
    expose_configurations = ["debug", "release"],
    configuration_preferences = ["shared"],
    cps_file = "share/cps/OpenSSL/OpenSSL.cps",
)
```

`name` becomes the public repository name. `expected_name` checks the CPS
package identity. A mismatch fails during repository setup.

`expose_components` creates short public labels. Internal CPS requirements can
still use components that are not exposed.

`expose_configurations` creates exact labels under each exposed component
package. An exact label fails if the selected variant lacks that configuration.

The base CPS file may be set on the logical package or on a physical variant.
The variant value wins. If neither value is set, the importer searches the
declared package tree. It accepts one base document whose filename matches its
CPS package name. Zero or two matches fail.

## Add physical variants

```starlark
cps.http_archive(
    package = "openssl",
    variant = "linux_x86_64",
    urls = [
        "https://mirror-1.example.com/openssl.tar.zst",
        "https://mirror-2.example.com/openssl.tar.zst",
    ],
    integrity = "sha256-...",
    strip_prefix = "openssl-3.5",
    compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)

cps.archive(
    package = "openssl",
    variant = "macos_arm64",
    archive = "//third_party/openssl:macos_arm64.tar.gz",
    compatible_with = [
        "@platforms//os:macos",
        "@platforms//cpu:aarch64",
    ],
)

use_repo(cps, "openssl")
```

Bazel selects a variant through `compatible_with`. The CPS `platform`
object remains available as metadata. It does not override Bazel constraints.

An empty constraint list means platform independent. Two platform independent
variants for one logical package fail because Bazel could not distinguish them.
A configured target fails with a package-specific message when no variant
matches.

Custom constraints work the same way as operating system and CPU constraints.
The rules do not assign meaning to the labels.

## Choose an acquisition type

`cps.archive` extracts a Bazel-owned archive. This is the simplest hermetic
form.

`cps.http_archive` downloads a digest-pinned archive. URL order is mirror
order. `file://` is rejected. Patches must be Bazel labels and run through
Bazel's patch operation.

`cps.local_package` reads one explicit directory. It does not expand shell
variables in the path.

`cps.local_archive` reads one explicit archive path and checks its digest.
The file still depends on host state, so this mode is non-hermetic.

`cps.env_package` reads one named environment variable and an optional
subpath. Bazel tracks the variable value and watches the resolved tree.

```starlark
cps.env_package(
    package = "vendor_sdk",
    variant = "local_sdk",
    env = "VENDOR_SDK_ROOT",
    subpath = "linux/x86_64",
    required = False,
)
```

If `required` is false and the variable is unset, the variant remains
declared but unavailable. Analysis fails only when the configured graph selects
it.

Root policy controls non-hermetic declarations.

```starlark
cps.config(nonhermetic = "error")
```

Allowed values are `allow`, `warning`, and `error`. The default is
`allow` because choosing a `local_*` or environment tag already names the
source.

## Bind package requirements

CPS requirements name CPS package identities. Bazel dependencies use logical
repository names. A binding connects them.

```starlark
cps.config(
    default_package_bindings = {
        "ZLIB": "zlib",
    },
)

cps.package(
    name = "png",
    expected_name = "PNG",
    package_bindings = {
        "ZLIB": "patched_zlib",
    },
)
```

The package binding wins over the global binding. A missing binding fails. The
selected package must have the requested CPS name, components, and compatible
version.

Bindings never download a transitive package. Every bound logical package needs
its own declaration and physical variant.

## Load supplemental files

The importer reads matching common and configuration files next to the base CPS
file. It sorts filenames before merging them.

A file named `Foo-extra.cps` adds common package data. A file named
`Foo@debug.cps` adds the `debug` configuration. Configuration filenames
also add their configuration names to package fallback order. This matters for
CMake packages that put an archive location only in a configuration file.

Common supplements may add disjoint components and package requirements.
Conflicting values for the same identity fail instead of depending on file
enumeration order. Configuration supplements follow the lexical merge rules in
`configurations.md`.

## CPS versions

The main parser accepts CPS 0.15 and later compatible 0.x minor revisions.
Unknown fields do not invalidate a document. The importer keeps package and
component extensions in public providers.

The parser also accepts exactly CPS 0.14.1 for maintained CMake
interoperability. It does not accept 0.14.0 or older schemas.

## Repository fetching

The logical repository reads every physical manifest so it can build one
configured `select`. Bazel may fetch all declared physical variants when the
logical package is first used. Variant selection still happens in the configured
graph.

The manifests keep CPS authoritative for component and configuration names.
Copying those names into `MODULE.bazel` would create a second package
description that could disagree with the CPS documents. A constrained variant
wins over a platform-independent fallback when Bazel considers it the more
specific match.

Fetching variant manifests acquires metadata only. It does not add a package
manager or version solver to the build.
