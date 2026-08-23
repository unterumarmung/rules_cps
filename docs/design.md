# Design

`rules_cps` separates file acquisition from package meaning. Repository rules
obtain a declared tree and check its paths. Pure Starlark code parses CPS,
chooses configurations, validates requirements, and builds dependency plans.
Analysis rules turn those plans into Bazel providers and C++ targets.

## Import path

An import moves through these stages.

1. The root module declares a logical package and physical variants.
2. A repository rule extracts or links each declared physical tree.
3. The repository rule finds the base CPS file and matching supplements.
4. Pure code parses JSON into a normalized package dictionary.
5. Path checks prove that every consumed file stays under the package root.
6. The physical repository writes a BUILD file and a small JSON manifest.
7. The logical repository reads the manifests and writes configured aliases.
8. Bazel selects a physical variant and a CPS configuration during analysis.

The logical name stays stable across platforms. A label such as
`@foo//:core` does not contain an archive name, CPU, or operating system.

## Why physical repositories write manifests

A repository rule cannot defer file reads until target analysis. Each physical
repository therefore writes a manifest with component target names, constraints,
package metadata, and availability.

The logical repository reads every manifest and writes `select` expressions.
The expressions keep platform choice in Bazel's configured graph. First use may
therefore fetch metadata for variants that the target platform will not select.

Public labels never contain physical variant names. Copying component lists
into module tags would make those tags a second package description. The
manifest design instead takes component and exact-configuration names from each
CPS document. A constrained variant beats a platform-independent fallback when
Bazel sees it as the more specific match.

## Normalized package model

The normalized package dictionary is the source for generated targets. It keeps
these values separate.

- CPS package identity and logical Bazel name
- Physical variant name and Bazel constraints
- Base component attributes and configuration overlays
- Normal, compile-only, link-only, and loader-only requirements
- Ordered compiler and linker flags
- Runtime files and runtime-loaded modules
- Unknown package and component fields

`CcInfo` is derived from this model. It is not used to reconstruct CPS
semantics during import.

## Dependency graphs

The model builds compile, link, and runtime views from the same requirement
records.

The compile view follows `requires` and `compile_requires`.

The link view follows `requires` and `link_requires`. It expands
depth-first, processes normal requirements before link-only requirements, and
keeps repeated component positions.

The runtime view follows normal, link-only, and loader-only requirements. It
uses a visited set because repeated runtime files have no ordering meaning.

Compile and link cycles fail with the component path. Runtime cycles terminate.
Static-library cycle grouping is not supported.

## Generated providers

`CpsPackageInfo` records selected package identity, version, variant,
constraints, configurations, origin, and extensions.

`CpsComponentInfo` records the selected component, selected configuration,
requirement records, file sets, module metadata, extensions, and source path.

`CpsUsageInfo` records compile usage, the ordered link plan, and stock C++
compatibility gaps.

`CpsRuntimeInfo` records runtime files, module files, and loader-only
requirements.

`CpsPackageLayoutInfo` belongs to export. It records generated CPS files,
installed destinations, symlinks, and package metadata.

Provider analysis tests read these fields from generated logical labels.

## C++ projection

Each imported component gets a native C++ target for common includes,
definitions, libraries, and link inputs. The imported component rule merges
the native contexts that belong to its compile and link requirement channels.

The CPS-aware wrappers add behavior that `CcInfo` cannot carry. Compiler
response files handle consumer flags. A linker response file handles duplicate
archive placement. Runtime helper targets add files to binary and test runfiles.

The compatibility aspect visits stock C++ edges. It reports a gap only at the
consumer that would lose the behavior.

## Export path

Export starts with one `cps_component` per installed component. The rule
keeps Bazel source files separate from installed destinations.

`cps_package` checks component names and default components, writes sorted
JSON, and returns a package layout provider. Generated CPS paths use
`@prefix@`. The JSON action has no timestamp and no host path.

An attached aspect reads wrapper metadata or safe stock C++ facts. It does not
choose a package boundary or installed filename.

## Determinism and limits

Serialized maps use sorted keys where CPS order does not carry meaning.
Meaningful lists retain source order. Supplemental filenames are sorted before
merge.

Path walks stop after 100000 entries. Link expansion stops after 100000
occurrences. Cycle detection uses a deterministic step budget based on graph
size.

The code does not invoke package managers, parse shell output, or execute tools
named by CPS metadata.
