# CMake interoperability

CMake added native CPS import and export in version 4.3. CMake 4.4.2 writes CPS
0.14.1. It rejects a CPS 0.15 document before reading package components.

`rules_cps` uses CPS 0.15.0 by default. It also accepts and exports exactly
0.14.1 so the two tools can exchange packages today.

## What the 0.14.1 profile covers

The CMake test covers package identity, version, compatibility floor,
components, configuration files, public include directories, public
definitions, archive locations, compile actions, link actions, execution, and
prefix relocation.

CMake 4.4 does not implement CPS 0.15 consumer flags. Its 0.14 reader ignores
`compile_flags`.

## CMake to Bazel

The producer in `tests/cmake_interop/producer` builds a static library.

```cmake
install(
  PACKAGE_INFO CMakeProduced
  EXPORT CMakeProducedTargets
  VERSION 2.1.0
  COMPAT_VERSION 2.0.0
  DEFAULT_TARGETS core
)
```

CMake installs a base file and a release configuration file. The base component
has no archive location. The release file supplies it.

The test imports that installed prefix with
`cps_local_package_repository`. The importer adds `Release` to the package
configuration list, selects the location, compiles a Bazel consumer, links the
CMake archive, and runs the binary.

## Bazel to CMake

The Bazel export uses this package setting.

```starlark
cps_package(
    name = "cmake_package",
    package_name = "CMakeExported",
    cps_version = "0.14.1",
    version = "1.0.0",
    components = [":cmake_component"],
)
```

The CMake consumer uses a normal package lookup.

```cmake
find_package(CMakeExported 1.0 REQUIRED)
target_link_libraries(consumer PRIVATE CMakeExported::core)
```

The test installs the header, archive, and CPS file at prefix A. CMake compiles,
links, and runs the consumer. The test moves the package to prefix B and repeats
the build.

## Required version

The test requires CMake 4.3 or newer. CI installs CMake 4.4.2 on Linux and
macOS.

Run it directly with this command.

```sh
bazel test //tests:cmake_interoperability_test --test_output=all
```

Support is exact rather than an open-ended older-version rule. Accepting every
older 0.x document would hide schema differences. Import rejects 0.14.0 and
older documents. CPS 0.15.0 remains the normal import and export format.
