# Hermeticity and path checks

Archive and HTTP imports are hermetic. Local paths and environment packages are
explicit host inputs.

Every mode uses the same package root rule. A consumed file must remain inside
the declared package root after lexical normalization and realpath resolution.

## Paths the importer checks

The importer checks these CPS values.

- Component `location` and `link_location`
- Include and embed roots
- `link_libraries`
- File set roots and members
- C++ module metadata paths
- The base CPS file and matching supplemental files

The check has two steps.

First, the lexical parser removes `.` and resolves `..`. It rejects an
absolute path or a path that climbs above the root.

Second, the repository rule follows symlinks with `realpath`. It rejects a
file or directory that lands outside the root. Directory checks walk the tree
with a fixed entry limit, so a symlink hidden below an include directory cannot
escape.

## Relocatable CPS paths

Hermetic packages use `cps_path` and `@prefix@`.

```json
{
  "cps_path": "@prefix@/share/cps/Foo",
  "components": {
    "core": {
      "location": "@prefix@/lib/libfoo.a"
    }
  }
}
```

The declared `cps_path` must match the real directory that contains the base
document.

A package-level absolute `prefix` is rejected for hermetic import. It would
bind the package to a host path outside Bazel's materialized repository.

## Local package behavior

`cps.local_package` names one directory. The repository rule watches the
tree, links its entries into the external repository, and validates paths
against the original directory.

The path string does not run through a shell. A dollar sign is rejected instead
of being expanded.

`cps.local_archive` watches one archive file and checks its digest before
extraction.

`cps.env_package` reads one named variable through Bazel's repository API.
The variable value becomes a repository dependency. The resolved tree is
watched too.

Local and environment modes are non-hermetic because another process can
replace the host files. The `nonhermetic` root policy can allow, warn, or reject
their declarations.

## CPS stays declarative

The importer parses JSON as data. It does not evaluate CPS strings as Starlark,
shell code, compiler discovery commands, or package manager requests.

Repository recursion and link expansion have fixed limits. Compile and link
cycles fail before action generation. Runtime cycles terminate through a visited
set because runtime closure does not preserve repeated positions.
