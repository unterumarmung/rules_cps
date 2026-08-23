# Use wrappers or stock rules_cc

`rules_cps` produces a normal `CcInfo` projection for imported C++ targets.
That projection handles ordinary include directories, common definitions,
archives, dynamic libraries, and link inputs.

Some CPS fields cannot fit in `CcInfo` without losing behavior. `rules_cps`
uses wrappers for those fields and an aspect to catch lossy stock edges.

## Use the wrappers

```starlark
load("@rules_cps//cps:defs.bzl", "cc_binary", "cc_library", "cc_test")
```

The wrapper macros accept the public `rules_cc` arguments.

`cc_library` applies consumer flags from both `deps` and
`implementation_deps` to its own compile actions. Only public dependency
usage continues to downstream wrappers.

`cc_binary` and `cc_test` apply consumer flags, write the canonical link
plan, and add the CPS runtime closure to runfiles.

Compiler flags use three response files. One file holds common flags, one holds
C flags, and one holds C++ flags. The test suite checks spaces, quotes,
backslashes, order, public propagation, private stopping, and unrelated
targets.

Each response file contains one JSON-quoted argument per line. GCC and Clang
accept that response syntax. The wrapper passes the files through `copts`,
`conlyopts`, and `cxxopts`, and declares them through
`additional_compiler_inputs`. This requirement sets the Bazel 9 baseline.

The linker response file follows CPS depth-first order. It expands
`requires` before `link_requires` and keeps deliberate duplicate archive
positions. Every referenced file is also an `additional_linker_inputs` entry.
Stock `rules_cc` uses the `CcInfo` projection when no repeated position is
needed. A repeated plan produces the `duplicate_link_plan` gap.

## Runtime files

Imported components return `CpsRuntimeInfo`. Binary and test wrappers collect
its files and modules into runfiles.

Dynamic libraries continue through normal `rules_cc` linking. Modules enter
runfiles but stay off the linker response file. `dyld_requires` contributes to
runtime closure only.

The wrappers do not set `LD_LIBRARY_PATH` or `DYLD_LIBRARY_PATH`, rewrite
RPATH, or create launcher scripts. Packages that need custom loader setup must
provide it outside `rules_cps`. A stock edge that loses loader-only files reports
`dyld_requires` or `module_runtime`.

## Install the aspect

Add these settings to the consuming workspace.

```text
build --aspects=@rules_cps//cps:compatibility.bzl%cps_compatibility_aspect
build --@rules_cps//cps:compatibility_aspect_enabled=true
```

Imported targets check the second setting by default. This catches a workspace
that forgot to install the aspect.

The aspect walks `deps` and `implementation_deps`. It ignores wrapper edges
and emits no execution actions.

## Read a diagnostic

A stock edge that loses semantics reports text like this.

```text
ERROR: //app:lib consumes @foo//:headers through a non-CPS-aware C++ rule.

CPS package/component/configuration: Foo / headers / debug
Unsupported CPS field: compile_flags
Values: ["-DFOO_CONSUMER=1"]
Reason: CcInfo cannot propagate arbitrary compiler flags to consumers
Source: share/cps/Foo/Foo.cps

To preserve the CPS behavior, use the CPS-aware wrapper:
    load("@rules_cps//cps:defs.bzl", "cc_library")

To accept the loss, set native_unsupported or a matching
native_feature_policy entry to "warning" or "ignore".
```

The message points to the real consumer. It does not blame the imported target
alone.

## Set policy

The default is `error`.

```starlark
cps.config(
    native_unsupported = "error",
    native_feature_policy = {
        "compile_flags": "warning",
    },
)
```

Each value may be `error`, `warning`, or `ignore`. A feature override
wins over the default.

Stable feature names are listed below.

| Feature | What stock rules_cc loses |
| --- | --- |
| `compile_flags` | Consumer compiler flags do not propagate through `CcInfo`. |
| `language_specific_includes` | `CcInfo` cannot choose includes by source language. |
| `language_specific_definitions` | `CcInfo` cannot choose definitions by source language. |
| `duplicate_link_plan` | Linking depsets remove deliberate repeated component positions. |
| `dyld_requires` | Loader-only requirements do not enter native consumer runfiles. |
| `module_runtime` | Runtime-loaded module artifacts do not enter native consumer runfiles. |

Choose `warning` or `ignore` only after checking the affected target. The
policy accepts lost behavior. It does not make the stock edge equivalent to a
wrapper edge.
