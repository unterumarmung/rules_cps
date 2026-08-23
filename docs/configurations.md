# Choose a CPS configuration

CPS configuration names have no built-in meaning. `debug`, `release`,
`static`, and `shared` are ordinary strings.

## Preference order

For a normal component label, the importer checks names in this order.

1. Package preferences, or global preferences when the package has none
2. Preferences added for the current Bazel compilation mode
3. Fallback configurations listed by the CPS package

The first occurrence of a name wins. Duplicate names are removed without
changing order.

```starlark
cps.config(
    default_configuration_preferences = ["shared"],
    compilation_mode_preferences = {
        "dbg": ["debug"],
        "opt": ["release"],
        "fastbuild": ["release"],
    },
)

cps.package(
    name = "foo",
    configuration_preferences = ["static"],
)
```

The package-specific list replaces the global list. The mode-specific list is
then appended.

`linkstatic` does not select a CPS configuration. If a project wants that
mapping, it must state the mapping in the extension configuration.

## Exact selection

An exact public label has this form.

```text
@foo//core:debug
```

Exact selection does not use preferences or fallback. The target fails if the
selected physical variant does not provide `debug` for `core`.

A CPS requirement can also request an exact configuration.

```text
:core@debug
ZLIB:zlib@release
```

## Same selection

`@@` means use the requiring component's selected configuration.

```text
:headers@@
```

The importer keeps this as a separate `same` mode. It does not flatten the
requirement into a normal preferred dependency.

If component `app` selects `debug`, then `:headers@@` must find
`headers@debug`. A missing matching configuration fails with the original
requirement in the message.

## Overlay rules

A selected configuration overlays the base component.

A top-level null removes the base attribute. A non-null map replaces or merges
according to the CPS field model. A definition with a null value remains a
valueless definition. It does not remove the definitions field.

Configuration files are loaded in lexical filename order because CPS does not
define an order between matching files. Filesystem enumeration order differs
between archive formats and operating systems. Sorting the package-relative
filenames keeps the generated BUILD file stable.

Later configuration fragments replace earlier values for the same component
field, including a top-level null. Renaming overlapping files can therefore
change the result.

## Bazel compilation modes

The extension recognizes the Bazel mode names `dbg`, `opt`, and
`fastbuild` only as lookup keys. It assigns no CPS names to them.

The repository emits a target for each mode. This keeps configuration selection
inside Bazel analysis and lets the same logical repository serve different
configured targets.
