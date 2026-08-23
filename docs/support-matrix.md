# CPS 0.15 support

The v1 build baseline is Bazel 9 with `rules_cc` 0.2.22. Bazel 8 is not
supported. The wrapper compiler response files require the public
`additional_compiler_inputs` attribute exposed by `rules_cc` on Bazel 9.

The status words have fixed meanings.

`FULL` means v1 implements the behavior on the supported C or C++ path.

`WRAPPER_ONLY` means CPS-aware wrappers implement it and stock C++ edges
receive a diagnostic.

`NATIVE_LOSSY` means stock C++ gets an approximation and receives a
diagnostic by default.

`METADATA_ONLY` means the parser validates and retains the value but no build
action uses it.

`UNSUPPORTED_V1` means use of the behavior fails.

| CPS field or type | Status | v1 behavior |
| --- | --- | --- |
| `name` | FULL | Checks package identity and exposes it in `CpsPackageInfo`. |
| `cps_version` | FULL | Accepts CPS 0.15 and later compatible 0.x minors. Exact 0.14.1 is the CMake profile. |
| `cps_path` | FULL | Derives relocatable package paths and checks the real CPS directory. |
| `prefix` | UNSUPPORTED_V1 | Hermetic import rejects an absolute package prefix. |
| `components` | FULL | Generates preferred, base, mode, and exact targets. |
| `default_components` | FULL | Generates `@default` for each Bazel compilation mode. |
| package `configurations` | FULL | Uses ordered package fallback after user preferences. |
| package `requires` | FULL | Resolves only through explicit logical package bindings. |
| `version`, `compat_version`, `simple` | FULL | Uses numeric tuple comparison with an inclusive compatibility floor. |
| `custom` version schema | FULL | Supports equality only. |
| `rpm` and `dpkg` ordering | UNSUPPORTED_V1 | Equality works. An ordered comparison fails without calling host tools. |
| CPS `platform` object | METADATA_ONLY | Retains the object. Bazel constraints select variants. |
| `interface` | FULL | Propagates compile and dependency usage without an artifact. |
| `archive` | FULL | Uses `cc_import` and real static link tests. |
| `dylib` | FULL | Links and runs real dynamic library fixtures on Linux and macOS. |
| `module` | WRAPPER_ONLY | Adds the file to module runfiles and keeps it off the normal link plan. |
| `executable` | METADATA_ONLY | Retains the artifact as runtime data. No command runner is added. |
| `symbolic` | FULL | Validates identity and requirements without files. |
| `jar` | UNSUPPORTED_V1 | Parsing retains the known type. Selecting it fails. |
| common `includes` | FULL | Adds headers and include directories to the compile context. |
| language-specific `includes` | NATIVE_LOSSY | Retains all values. Stock C++ receives a diagnostic. |
| common `definitions` | FULL | Preserves values and valueless definitions. |
| language-specific `definitions` | NATIVE_LOSSY | Retains all values. Stock C++ receives a diagnostic. |
| `compile_flags` | WRAPPER_ONLY | Uses common, C, and C++ response files with source order. |
| `requires` | FULL | Contributes to compile, link, and runtime views. |
| `compile_requires` | FULL | Contributes only to compile usage. |
| `link_requires` | FULL | Contributes only to link and runtime usage. |
| duplicate link positions | WRAPPER_ONLY | Wrapper response files retain repeats. Stock C++ receives `duplicate_link_plan`. |
| `link_flags` | FULL | Writes flags in component order to the link plan. |
| `link_libraries` | FULL | Checks package containment and writes ordered linker inputs. |
| `link_languages` | METADATA_ONLY | Retains unknown or producer-specific values. C and C++ link actions come from Bazel targets. |
| `dyld_requires` | WRAPPER_ONLY | Adds loader-only runtime closure. Stock C++ receives `dyld_requires`. |
| `compile_features` | METADATA_ONLY | Retains values in usage metadata. |
| `link_features` | METADATA_ONLY | Retains values without changing Bazel feature selection. |
| `embeds` | METADATA_ONLY | Checks roots and retains values. |
| file sets | METADATA_ONLY | Checks roots and members and exposes normalized records. |
| `cpp_module_metadata` | METADATA_ONLY | Checks the path and exposes it in `CpsComponentInfo`. |
| unknown package fields | METADATA_ONLY | Retains them in `CpsPackageInfo.extensions`. |
| unknown component fields | METADATA_ONLY | Retains them in `CpsComponentInfo.extensions`. |
| unknown component types | METADATA_ONLY | Ignores their build targets and records their names. |

## Acquisition

| Input | Status | Notes |
| --- | --- | --- |
| Bazel-owned archive | FULL | Supports `strip_prefix` and automatic CPS discovery. |
| HTTP archive | FULL | Requires integrity, supports mirrors and Bazel patches, rejects `file://`. |
| Local package | FULL | Watches the tree and applies the non-hermetic policy. |
| Local archive | FULL | Watches the archive and checks integrity. |
| Environment package | FULL | Tracks the variable and tree. Optional unset variants fail only when selected. |

## Export

Explicit wrapper and stock archive components produce deterministic relocatable
JSON and `CpsPackageLayoutInfo`. The exporter retains public headers,
definitions, compiler flags, link flags, and all four requirement channels.

The relocation test consumes one installed layout at two prefixes. CMake tests
compile and link in both directions through CPS 0.14.1. CPS 0.15.0 remains the
default output.

Core export does not create an archive. Packaging tools consume the layout
provider.

## Declared limits

v1 does not support Windows, Java archive consumption, Fortran consumer rules,
automatic C++ module setup, static archive cycle grouping, automatic RPATH
repair, runtime launcher scripts, package registries, dependency solving, or
implicit system package discovery. Bazel 8 is outside the v1 compatibility
baseline.
