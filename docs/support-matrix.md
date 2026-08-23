# CPS 0.15 support

The build baseline is Bazel 9 with `rules_cc` 0.2.22. Bazel 8 is not
supported. The wrapper compiler response files require the public
`additional_compiler_inputs` attribute exposed by `rules_cc` on Bazel 9.

The status words have fixed meanings.

Full means `rules_cps` implements the behavior on the supported C or C++ path.

Wrapper only means CPS-aware wrappers implement it and stock C++ edges
receive a diagnostic.

Lossy with stock `rules_cc` means stock C++ gets an approximation and receives a
diagnostic by default.

Metadata only means the parser validates and retains the value but no build
action uses it.

Unsupported means use of the behavior fails.

| CPS field or type | Status | Behavior |
| --- | --- | --- |
| `name` | Full | Checks package identity and exposes it in `CpsPackageInfo`. |
| `cps_version` | Full | Accepts CPS 0.15 and later compatible 0.x minors. Exact 0.14.1 is the CMake profile. |
| `cps_path` | Full | Derives relocatable package paths and checks the real CPS directory. |
| `prefix` | Unsupported | Hermetic import rejects an absolute package prefix. |
| `components` | Full | Generates preferred, base, mode, and exact targets. |
| `default_components` | Full | Generates `@default` for each Bazel compilation mode. |
| package `configurations` | Full | Uses ordered package fallback after user preferences. |
| package `requires` | Full | Resolves only through explicit logical package bindings. |
| `version`, `compat_version`, `simple` | Full | Uses numeric tuple comparison with an inclusive compatibility floor. |
| `custom` version schema | Full | Supports equality only. |
| `rpm` and `dpkg` ordering | Unsupported | Equality works. An ordered comparison fails without calling host tools. |
| CPS `platform` object | Metadata only | Retains the object. Bazel constraints select variants. |
| `interface` | Full | Propagates compile and dependency usage without an artifact. |
| `archive` | Full | Uses `cc_import` and real static link tests. |
| `dylib` | Full | Links and runs real dynamic library fixtures on Linux and macOS. |
| `module` | Wrapper only | Adds the file to module runfiles and keeps it off the normal link plan. |
| `executable` | Metadata only | Retains the artifact as runtime data. No command runner is added. |
| `symbolic` | Full | Validates identity and requirements without files. |
| `jar` | Unsupported | Parsing retains the known type. Selecting it fails. |
| common `includes` | Full | Adds headers and include directories to the compile context. |
| language-specific `includes` | Lossy with stock rules_cc | Retains all values. Stock C++ receives a diagnostic. |
| common `definitions` | Full | Preserves values and valueless definitions. |
| language-specific `definitions` | Lossy with stock rules_cc | Retains all values. Stock C++ receives a diagnostic. |
| `compile_flags` | Wrapper only | Uses common, C, and C++ response files with source order. |
| `requires` | Full | Contributes to compile, link, and runtime views. |
| `compile_requires` | Full | Contributes only to compile usage. |
| `link_requires` | Full | Contributes only to link and runtime usage. |
| duplicate link positions | Wrapper only | Wrapper response files retain repeats. Stock C++ receives `duplicate_link_plan`. |
| `link_flags` | Full | Writes flags in component order to the link plan. |
| `link_libraries` | Full | Checks package containment and writes ordered linker inputs. |
| `link_languages` | Metadata only | Retains unknown or producer-specific values. C and C++ link actions come from Bazel targets. |
| `dyld_requires` | Wrapper only | Adds loader-only runtime closure. Stock C++ receives `dyld_requires`. |
| `compile_features` | Metadata only | Retains values in usage metadata. |
| `link_features` | Metadata only | Retains values without changing Bazel feature selection. |
| `embeds` | Metadata only | Checks roots and retains values. |
| file sets | Metadata only | Checks roots and members and exposes normalized records. |
| `cpp_module_metadata` | Metadata only | Checks the path and exposes it in `CpsComponentInfo`. |
| unknown package fields | Metadata only | Retains them in `CpsPackageInfo.extensions`. |
| unknown component fields | Metadata only | Retains them in `CpsComponentInfo.extensions`. |
| unknown component types | Metadata only | Ignores their build targets and records their names. |

## Acquisition

| Input | Status | Notes |
| --- | --- | --- |
| Bazel-owned archive | Full | Supports `strip_prefix` and automatic CPS discovery. |
| HTTP archive | Full | Requires integrity, supports mirrors and Bazel patches, rejects `file://`. |
| Local package | Full | Watches the tree and applies the non-hermetic policy. |
| Local archive | Full | Watches the archive and checks integrity. |
| Environment package | Full | Tracks the variable and tree. Optional unset variants fail only when selected. |

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

`rules_cps` does not support Windows, Java archive consumption, Fortran consumer rules,
automatic C++ module setup, static archive cycle grouping, automatic RPATH
repair, runtime launcher scripts, package registries, dependency solving, or
implicit system package discovery. Bazel 8 is outside the compatibility baseline.
