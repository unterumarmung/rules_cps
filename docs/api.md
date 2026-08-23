# Public Starlark API

Public code lives in four files.

- `cps/extensions.bzl` declares imports.
- `cps/defs.bzl` exports C++ wrappers and export rules.
- `cps/providers.bzl` defines CPS providers.
- `cps/compatibility.bzl` defines the stock C++ validation aspect.

Code under `cps/private` may change without notice.

## Module extension

```starlark
cps = use_extension("@rules_cps//cps:extensions.bzl", "cps")
```

Only the root module may use the tags below. One root module may declare at most
one `cps.config`.

### cps.config

| Attribute | Type | Default |
| --- | --- | --- |
| `default_package_bindings` | string dictionary | empty |
| `default_configuration_preferences` | string list | empty |
| `compilation_mode_preferences` | string to string-list dictionary | empty |
| `native_unsupported` | `error`, `warning`, or `ignore` | `error` |
| `native_feature_policy` | string dictionary | empty |
| `nonhermetic` | `allow`, `warning`, or `error` | `allow` |
| `require_global_aspect` | boolean | true |

Binding keys are CPS package identities. Binding values are logical package
names declared by `cps.package`.

### cps.package

| Attribute | Type | Default |
| --- | --- | --- |
| `name` | string | required |
| `expected_name` | string | empty |
| `package_bindings` | string dictionary | empty |
| `configuration_preferences` | string list | empty |
| `compilation_mode_preferences` | string to string-list dictionary | empty |
| `expose_components` | string list | empty |
| `expose_configurations` | string list | empty |
| `cps_file` | string | automatic discovery |

Every logical package needs at least one physical acquisition tag.

### cps.archive

| Attribute | Type | Default |
| --- | --- | --- |
| `package` | string | required |
| `variant` | string | required |
| `archive` | one file label | required |
| `strip_prefix` | string | empty |
| `compatible_with` | label list | empty |
| `cps_file` | string | package value or discovery |

`cps.archive` is hermetic because Bazel owns the archive input.

### cps.http_archive

| Attribute | Type | Default |
| --- | --- | --- |
| `package` | string | required |
| `variant` | string | required |
| `urls` | string list | required |
| `integrity` | string | required |
| `strip_prefix` | string | empty |
| `patches` | file label list | empty |
| `patch_strip` | integer | zero |
| `compatible_with` | label list | empty |
| `cps_file` | string | package value or discovery |

URLs are ordered mirrors. A `file://` URL fails.

### cps.local_package

| Attribute | Type | Default |
| --- | --- | --- |
| `package` | string | required |
| `variant` | string | required |
| `path` | string | required |
| `compatible_with` | label list | empty |
| `cps_file` | string | package value or discovery |

The repository watches the directory. The path does not expand environment
variables.

### cps.local_archive

| Attribute | Type | Default |
| --- | --- | --- |
| `package` | string | required |
| `variant` | string | required |
| `path` | string | required |
| `integrity` | string | required |
| `strip_prefix` | string | empty |
| `compatible_with` | label list | empty |
| `cps_file` | string | package value or discovery |

The repository watches the archive file. Host availability makes this mode
non-hermetic even with a digest.

### cps.env_package

| Attribute | Type | Default |
| --- | --- | --- |
| `package` | string | required |
| `variant` | string | required |
| `env` | string | required |
| `subpath` | string | empty |
| `required` | boolean | true |
| `compatible_with` | label list | empty |
| `cps_file` | string | package value or discovery |

Bazel tracks the variable value and watches the resolved tree.

## C++ wrappers

```starlark
load("@rules_cps//cps:defs.bzl", "cc_binary", "cc_library", "cc_test")
```

The macros accept the matching public `rules_cc` arguments. They add compiler
response files, the CPS link plan, runtime data, and an aspect awareness hint.

`cc_library` keeps `implementation_deps` private. `cc_binary` and
`cc_test` add the full runtime closure to runfiles.

The wrapper macros return the native rule providers. Wrapper libraries also
return CPS usage and awareness providers needed by downstream wrappers.

## cps_component

```starlark
cps_component(
    name = "core_cps",
    component_name = "core",
    target = ":core",
    component_type = "archive",
    install_library = "lib/libcore.a",
    headers = {":headers": "include/core"},
    include_roots = ["include"],
)
```

| Attribute | Type | Default |
| --- | --- | --- |
| `component_name` | string | required |
| `target` | label | none |
| `component_type` | component type string | required |
| `install_library` | string | empty |
| `headers` | label to string dictionary | empty |
| `include_roots` | string list | header destinations |
| `definitions` | string dictionary | empty |
| `compile_flags` | string list | empty |
| `link_flags` | string list | empty |
| `requires` | string list | empty |
| `compile_requires` | string list | empty |
| `link_requires` | string list | empty |
| `dyld_requires` | string list | empty |

Allowed component types are `archive`, `dylib`, `executable`,
`interface`, `module`, and `symbolic`.

Non-interface and non-symbolic types need `target` and
`install_library`. More than one candidate artifact fails.

## cps_package

```starlark
cps_package(
    name = "core_package",
    package_name = "Core",
    components = [":core_cps"],
)
```

| Attribute | Type | Default |
| --- | --- | --- |
| `package_name` | string | required |
| `cps_version` | `0.15.0` or `0.14.1` | `0.15.0` |
| `version` | string | empty |
| `compat_version` | string | empty |
| `version_schema` | string | `simple` |
| `components` | component label list | required |
| `default_components` | string list | empty |
| `symlinks` | string dictionary | empty |
| `extensions` | string dictionary | empty |

The rule returns `DefaultInfo` with the generated CPS file and
`CpsPackageLayoutInfo` with installed paths.

## Providers

### CpsPackageInfo

Fields are `name`, `version`, `compat_version`, `version_schema`,
`cps_version`, `logical_name`, `variant`, `platform`,
`compatible_with`, `default_components`, `components`,
`configurations`, `origin`, `source`, and `extensions`.

### CpsComponentInfo

Fields are `package`, `name`, `type`, `configuration`,
`requirements`, `file_sets`, `cpp_module_metadata`, `extensions`, and
`source`.

### CpsUsageInfo

`compile` holds direct and propagated compile usage. `link` holds the
ordered plan. `native_gaps` holds structured stock C++ diagnostics.

### CpsRuntimeInfo

`files` and `modules` are depsets. `requirements` holds runtime
requirement records. `loader_requirements` holds `dyld_requires` records.

### CpsPackageLayoutInfo

`cps_files` is a depset. `entries` and `symlinks` are ordered records.
`package` is exported package metadata.

## Compatibility aspect

`cps_compatibility_aspect` visits `deps` and
`implementation_deps`. It returns `CpsCompatibilityInfo` with ordered
diagnostic records. Each record contains `consumer`, `dependency`, `feature`,
`policy`, and `message`. The message is the same text used for an analysis error
or warning.

The aspect has no execution actions. Install it with the two `.bazelrc`
settings shown in the README.
