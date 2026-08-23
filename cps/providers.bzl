"""Stable public providers for CPS identity, usage, runtime, and layout."""

CpsPackageInfo = provider(
    doc = "Identifies the selected physical CPS package instance.",
    fields = {
        "name": "Canonical CPS package name.",
        "version": "Package version string or None.",
        "compat_version": "Oldest compatible version string or None.",
        "version_schema": "CPS version ordering schema.",
        "cps_version": "CPS schema version declared by the document.",
        "logical_name": "rules_cps logical package name.",
        "variant": "Physical variant name.",
        "platform": "Preserved CPS platform metadata.",
        "compatible_with": "Opaque Bazel constraint labels declared for the variant.",
        "default_components": "Ordered default CPS component names.",
        "components": "Ordered available CPS component names used for requirement validation.",
        "configurations": "Ordered package fallback configurations.",
        "origin": "Acquisition kind such as archive, http_archive, local, or env.",
        "source": "Source CPS file path used for diagnostics.",
        "extensions": "Unknown and x_* package attributes preserved as metadata.",
    },
)

CpsComponentInfo = provider(
    doc = "Identifies a selected CPS component and configuration.",
    fields = {
        "package": "The CpsPackageInfo instance.",
        "name": "Original CPS component name.",
        "type": "CPS component type.",
        "configuration": "Selected configuration name or None.",
        "requirements": "Normalized requirement records with edge and configuration intent.",
        "file_sets": "Normalized CPS filesets.",
        "cpp_module_metadata": "Preserved C++ module metadata path or None.",
        "extensions": "Unknown and x_* component attributes.",
        "source": "Source CPS file and JSON path information.",
    },
)

CpsUsageInfo = provider(
    doc = "Describes ordered CPS compile/link usage and native compatibility gaps.",
    fields = {
        "compile": "Canonical compile usage plan.",
        "link": "Canonical ordered link usage plan; deliberate duplicates are retained.",
        "native_gaps": "Structured semantics that CcInfo cannot reproduce faithfully.",
    },
)

CpsRuntimeInfo = provider(
    doc = "Describes runtime artifacts and loader-only component requirements.",
    fields = {
        "files": "Depset of runtime artifacts; ordering is not significant.",
        "modules": "Depset of runtime-loaded module artifacts.",
        "requirements": "Normalized runtime component requirements.",
        "loader_requirements": "Normalized dyld_requires records.",
    },
)

CpsPackageLayoutInfo = provider(
    doc = "Describes an exported installed CPS package independent of archive format.",
    fields = {
        "cps_files": "Depset of generated CPS documents.",
        "entries": "Ordered source-to-installed-destination records.",
        "symlinks": "Ordered installed symlink records.",
        "package": "Exported package metadata.",
    },
)
