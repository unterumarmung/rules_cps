"""Explicit CPS package-boundary export rules."""

load("//cps:providers.bzl", "CpsComponentInfo", "CpsPackageLayoutInfo", "CpsUsageInfo")
load("//cps/private:paths.bzl", "normalize_relative_path")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_CpsExportComponentInfo = provider(fields = {
    "component": "Normalized CPS component object.",
    "entries": "Installed source-to-destination records.",
    "name": "CPS component name.",
})

_CpsExportInspectionInfo = provider(fields = {
    "attributes": "Stable rule attributes observed for export inference.",
    "dependencies": "Transitive export inspection records.",
})

def _export_aspect_impl(target, ctx):
    attributes = {}
    for name in ["hdrs", "textual_hdrs", "defines", "local_defines", "includes", "include_prefix", "strip_include_prefix", "linkopts"]:
        if hasattr(ctx.rule.attr, name):
            attributes[name] = getattr(ctx.rule.attr, name)
    dependencies = []
    for name in ["deps", "implementation_deps"]:
        if hasattr(ctx.rule.attr, name):
            dependencies.extend([
                dep[_CpsExportInspectionInfo]
                for dep in getattr(ctx.rule.attr, name)
                if _CpsExportInspectionInfo in dep
            ])
    return [_CpsExportInspectionInfo(attributes = attributes, dependencies = dependencies)]

_cps_export_aspect = aspect(
    implementation = _export_aspect_impl,
    attr_aspects = ["deps", "implementation_deps"],
)

def _entry_destination(entry):
    return entry.destination

def _validate_install_destination(value, description):
    normalized = normalize_relative_path(value)
    if normalized != value:
        fail("%s must be a normalized package-relative path, got %s" % (description, value))
    return normalized

def _validate_symlink_target(destination, target):
    if not target or target.startswith("/"):
        fail("export symlink target must be a non-empty relative path, got %s" % target)
    directory = destination.rpartition("/")[0]
    candidate = directory + "/" + target if directory else target
    normalize_relative_path(candidate)

def _library_candidate(component_type, files):
    extensions = {
        "archive": ["a", "lib"],
        "dylib": ["dylib", "so", "dll"],
        "module": ["dylib", "so", "dll", "bundle"],
        "executable": ["exe", ""],
    }.get(component_type, [])
    candidates = [file for file in files if file.extension in extensions]
    if len(candidates) > 1:
        fail("export target has multiple candidate %s artifacts %r; use a target with an unambiguous DefaultInfo" % (component_type, [file.path for file in candidates]))
    return candidates[0] if candidates else None

def _component_impl(ctx):
    entries = []
    component = {"type": ctx.attr.component_type}
    target_files = ctx.attr.target[DefaultInfo].files.to_list() if ctx.attr.target else []
    if ctx.attr.target and CpsUsageInfo in ctx.attr.target:
        direct_link_plan = ctx.attr.target[CpsUsageInfo].link.get("plan", [])
        if direct_link_plan:
            target_files.extend(direct_link_plan[0].get("files", []))
    if ctx.attr.install_library:
        if not ctx.attr.target:
            fail("export component %s declares install_library but has no target" % ctx.attr.component_name)
        artifact = _library_candidate(ctx.attr.component_type, target_files)
        if artifact == None:
            fail("export component %s declares install_library but target %s has no unambiguous %s artifact" % (ctx.attr.component_name, ctx.attr.target.label, ctx.attr.component_type))
        entries.append(struct(source = artifact, destination = ctx.attr.install_library))
        component["location"] = "@prefix@/" + ctx.attr.install_library
    elif ctx.attr.component_type not in ["interface", "symbolic"]:
        fail("export component %s of type %s requires install_library" % (ctx.attr.component_name, ctx.attr.component_type))

    include_roots = {}
    for header_target, destination in ctx.attr.headers.items():
        _validate_install_destination(destination, "export header directory")
        for header in header_target[DefaultInfo].files.to_list():
            installed = destination.rstrip("/") + "/" + header.basename
            entries.append(struct(source = header, destination = installed))
        if not ctx.attr.include_roots:
            include_roots["@prefix@/" + destination.rstrip("/")] = True
    for include_root in ctx.attr.include_roots:
        _validate_install_destination(include_root, "export include root")
        include_roots["@prefix@/" + include_root.rstrip("/")] = True
    if include_roots:
        component["includes"] = sorted(include_roots.keys())
    definitions = dict(ctx.attr.definitions)
    if not definitions and ctx.attr.target and CcInfo in ctx.attr.target:
        for definition in ctx.attr.target[CcInfo].compilation_context.defines.to_list():
            separator = definition.find("=")
            if separator < 0:
                definitions[definition] = None
            else:
                definitions[definition[:separator]] = definition[separator + 1:]
    if definitions:
        component["definitions"] = {"*": definitions}

    compile_flags = ctx.attr.compile_flags
    if not compile_flags and ctx.attr.target and CpsUsageInfo in ctx.attr.target:
        compile_flags = ctx.attr.target[CpsUsageInfo].compile.get("compile_flags", [])
    if compile_flags:
        component["compile_flags"] = compile_flags
    imported_requirements = {}
    if ctx.attr.target and CpsComponentInfo in ctx.attr.target:
        for requirement in ctx.attr.target[CpsComponentInfo].requirements:
            imported_requirements.setdefault(requirement["kind"], []).append(requirement["source"])
    for field, explicit_value in [
        ("requires", ctx.attr.requires),
        ("compile_requires", ctx.attr.compile_requires),
        ("link_requires", ctx.attr.link_requires),
        ("dyld_requires", ctx.attr.dyld_requires),
        ("link_flags", ctx.attr.link_flags),
    ]:
        value = explicit_value or imported_requirements.get(field, [])
        if value:
            component[field] = value
    return [
        DefaultInfo(files = depset([entry.source for entry in entries])),
        _CpsExportComponentInfo(name = ctx.attr.component_name, component = component, entries = entries),
    ]

cps_component = rule(
    implementation = _component_impl,
    doc = "Declares one explicit component inside an exported CPS package boundary.",
    attrs = {
        "component_name": attr.string(mandatory = True, doc = "CPS component identity written inside the package."),
        "target": attr.label(aspects = [_cps_export_aspect], doc = "Bazel target that produces the component artifact and public usage metadata."),
        "component_type": attr.string(mandatory = True, values = ["archive", "dylib", "executable", "interface", "module", "symbolic"], doc = "CPS component type."),
        "install_library": attr.string(doc = "Normalized package-relative installed artifact destination."),
        "headers": attr.label_keyed_string_dict(allow_files = True, doc = "Header sources mapped to package-relative installed directories."),
        "include_roots": attr.string_list(doc = "Package-relative consumer include roots. Header destinations are used when omitted."),
        "definitions": attr.string_dict(doc = "Public consumer definitions. CcInfo definitions are used when omitted."),
        "compile_flags": attr.string_list(doc = "Ordered consumer compiler flags."),
        "link_flags": attr.string_list(doc = "Ordered consumer linker flags."),
        "requires": attr.string_list(doc = "Ordered normal CPS component requirements."),
        "compile_requires": attr.string_list(doc = "Ordered compile-only CPS component requirements."),
        "link_requires": attr.string_list(doc = "Ordered link-only CPS component requirements."),
        "dyld_requires": attr.string_list(doc = "Ordered loader-only CPS component requirements."),
    },
)

def _package_impl(ctx):
    by_name = {}
    entries = []
    for target in ctx.attr.components:
        info = target[_CpsExportComponentInfo]
        if info.name in by_name:
            fail("duplicate exported CPS component name %s" % info.name)
        by_name[info.name] = info.component
        entries.extend(info.entries)
    missing_defaults = [name for name in ctx.attr.default_components if name not in by_name]
    if missing_defaults:
        fail("exported CPS package %s names missing default components %r" % (ctx.attr.package_name, missing_defaults))

    document = {
        "name": ctx.attr.package_name,
        "cps_version": ctx.attr.cps_version,
        "cps_path": "@prefix@/share/cps/%s" % ctx.attr.package_name,
        "components": {name: by_name[name] for name in sorted(by_name.keys())},
    }
    if ctx.attr.version:
        document["version"] = ctx.attr.version
        document["version_schema"] = ctx.attr.version_schema
    if ctx.attr.compat_version:
        document["compat_version"] = ctx.attr.compat_version
    if ctx.attr.default_components:
        document["default_components"] = ctx.attr.default_components
    for key in sorted(ctx.attr.extensions.keys()):
        document[key] = ctx.attr.extensions[key]

    cps_file = ctx.actions.declare_file(ctx.attr.package_name + ".cps")
    ctx.actions.write(cps_file, json.encode_indent(document, indent = "  ") + "\n")
    cps_destination = "share/cps/%s/%s.cps" % (ctx.attr.package_name, ctx.attr.package_name)
    entries.append(struct(source = cps_file, destination = cps_destination))
    entries = sorted(entries, key = _entry_destination)
    destinations = {}
    for entry in entries:
        _validate_install_destination(entry.destination, "export destination")
        if entry.destination in destinations:
            fail("duplicate export destination %s" % entry.destination)
        destinations[entry.destination] = True
    symlinks = []
    for destination in sorted(ctx.attr.symlinks.keys()):
        target = ctx.attr.symlinks[destination]
        _validate_install_destination(destination, "export symlink destination")
        if destination in destinations:
            fail("duplicate export destination %s" % destination)
        _validate_symlink_target(destination, target)
        destinations[destination] = True
        symlinks.append(struct(destination = destination, target = target))
    package = {
        "name": ctx.attr.package_name,
        "version": ctx.attr.version or None,
        "compat_version": ctx.attr.compat_version or None,
        "version_schema": ctx.attr.version_schema,
        "default_components": ctx.attr.default_components,
    }
    return [
        DefaultInfo(files = depset([cps_file])),
        OutputGroupInfo(cps_layout = depset([entry.source for entry in entries])),
        CpsPackageLayoutInfo(
            cps_files = depset([cps_file]),
            entries = entries,
            symlinks = symlinks,
            package = package,
        ),
    ]

cps_package = rule(
    implementation = _package_impl,
    doc = "Generates relocatable CPS JSON and an installation-layout provider.",
    attrs = {
        "package_name": attr.string(mandatory = True, doc = "CPS package identity and generated file basename."),
        "cps_version": attr.string(default = "0.15.0", values = ["0.14.1", "0.15.0"], doc = "Output CPS schema profile. 0.14.1 exists for maintained CMake interoperability."),
        "version": attr.string(doc = "Provided package version."),
        "compat_version": attr.string(doc = "Oldest package version covered by compatibility."),
        "version_schema": attr.string(default = "simple", doc = "CPS version comparison schema."),
        "components": attr.label_list(mandatory = True, providers = [_CpsExportComponentInfo], doc = "Explicit component declarations in this package boundary."),
        "default_components": attr.string_list(doc = "Ordered package default component names."),
        "symlinks": attr.string_dict(doc = "Installed symlink destinations mapped to relative targets."),
        "extensions": attr.string_dict(doc = "String-valued CPS package extension fields."),
    },
)
