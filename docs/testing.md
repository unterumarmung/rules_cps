# Tests

Run the full suite with this command.

```sh
bazel test //...
```

The suite contains pure Starlark tests, analysis tests, compiler and linker
tests, runtime tests, nested repository tests, export tests, and CMake tests.

## Pure semantics

`//cps/private:semantics_tests` checks name escaping, version comparison,
path normalization, configuration selection, requirement parsing, graph order,
schema parsing, bindings, semantic plans, supplemental merge, and a synthetic
500-component model.

`//cps/private:negative_semantics_tests` checks stable failures for missing
bindings, compile cycles, link cycles, missing same configuration, configured
artifacts without locations, root escapes, unsupported component types,
unsupported ordered version schemas, and incompatible CPS versions.

The pure semantic tests do not create compiler actions. They run the functions
used by repository generation.

## Provider analysis

`//tests:provider_tests` reads public providers from logical repository
labels. It checks package identity, component identity, exact configuration,
runtime closure, package binding precedence, link plan order, symbolic
components, executable components, and unavailable selections.

`//tests/native_compatibility:compatibility_tests` attaches the public aspect
to stock C++ consumers. It checks error, warning, and ignore policies. It also
checks duplicate link plans, loader-only runtime requirements, and the global
aspect sentinel.

## Compiler tests

`//tests/wrapper:wrapper_flags_test` compiles C and C++ sources through public
and private wrapper edges. Its sources fail compilation if a common or
language-specific flag is missing, leaks past a private edge, changes order, or
reaches an unrelated target.

The import tests compile headers and definitions through `requires` and
`compile_requires`. `//tests:link_requires_test` proves that a link-only
edge does not provide compile usage.

CI runs the suite with the host compiler on Linux and macOS. The runner images
cover GCC and Apple Clang.

## Linker tests

`//tests/link_order:duplicate_link_order_test` links a program that needs the
archive order `A B A`.

`//tests/link_order:wrapped_transitive_link_test` sends an imported CPS link
plan through another wrapper and checks the response file.

`//tests:imported_link_order_test` checks the imported plan
`A B A B`. The helper script reads the exact linker response file rather than
inferring order from provider shape.

## Runtime tests

`//tests:dynamic_library_test` executes a binary linked to an imported dynamic
library.

`//tests:module_runtime_test` loads the runtime bundle and checks that the
module is absent from the normal link plan. Provider tests check runtime cycles
and loader-only closure.

Fixtures contain ELF x86_64 files and Mach-O arm64 files. Bazel picks the
matching physical variant.

## Repository tests

`//tests:nested_archive_repository_test` copies test projects into a clean
temporary directory and launches a separate Bazel server.

The test covers these cases.

- Bazel-owned archive import
- Local package import
- Local archive import with integrity
- HTTP import with a failed first mirror
- Invalid HTTP integrity
- Missing CPS file
- Wrong package identity
- Escaping symlink
- Compile cycle
- Duplicate module configuration
- Duplicate package and variant declarations
- Unknown package in a variant
- Binding to an unknown logical package
- Concrete acquisition from a non-root module
- Export, materialization, import, relocation, and second import

`//tests:env_package_test` runs separately with
`RULES_CPS_TEST_PACKAGE_ROOT` set through `--repo_env`.

## Export tests

`//tests/export:export_tests` reads `CpsPackageLayoutInfo` and checks exact
installed destinations. It also proves that two candidate archives produce an
analysis error.

`//tests/export:export_json_test` checks requirements, relocatable paths, and
the absence of Bazel output paths. The stock export test proves that a public
definition is kept and a local definition is dropped.

The nested round-trip test installs the generated layout at prefix A, imports
it, moves it to prefix B, and imports it again.

## CMake tests

`//tests:cmake_interoperability_test` requires CMake 4.3 or newer.

First, CMake builds and installs a library with `install(PACKAGE_INFO)`.
Bazel imports CMake's root and release configuration files, compiles a consumer,
links the archive, and runs it.

Second, Bazel builds an archive and `rules_cps` exports CPS 0.14.1. CMake
finds the package, builds a consumer, and runs it at two different installation
prefixes.

CI installs CMake 4.4.2 for this test.

## Executable documentation

`//examples:documentation_examples` builds the archive import, physical
variant, package binding, exact configuration, and wrapper examples used by the
docs.

The nested tests are the executable examples for HTTP, local, environment, and
CMake setup.

## CI matrix

CI runs Bazel 9 on Linux and macOS. Each job runs the full suite and these
focused configuration commands.

```sh
bazel test --compilation_mode=opt \
  //tests:compilation_mode_configuration_test

bazel test --platforms=//tests:custom_host_platform \
  //tests:custom_constraint_variant_test

bazel test \
  --repo_env=RULES_CPS_TEST_PACKAGE_ROOT="$PWD/tests/fixtures/basic/package" \
  //tests:env_package_test
```
