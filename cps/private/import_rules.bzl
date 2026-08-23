"""Analysis rules used by generated CPS import repositories."""

load("//cps:providers.bzl", "CpsComponentInfo", "CpsPackageInfo", "CpsRuntimeInfo", "CpsUsageInfo")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_cc//cc/common:cc_common.bzl", rules_cc_common = "cc_common")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":version.bzl", "version_satisfies")
load(":requirements.bzl", "parse_component_requirement")

def _validate_bound_packages(ctx):
    for target, payload_json in ctx.attr.bound_packages.items():
        payload = json.decode(payload_json)
        selected = target[CpsPackageInfo]
        required_name = payload["name"]
        requirement = payload["requirement"]
        if selected.name != required_name:
            fail("CPS package %s binds required identity %s to logical package %s, but the selected package identity is %s" % (ctx.attr.package_name, required_name, selected.logical_name, selected.name))
        missing = [name for name in requirement.get("components", []) if name not in selected.components]
        if missing:
            fail("CPS package %s requires components %r from %s, but logical package %s provides %r" % (ctx.attr.package_name, missing, required_name, selected.logical_name, selected.components))
        requested = requirement.get("version")
        if not version_satisfies(selected.version, selected.compat_version, requested, selected.version_schema):
            fail("CPS package %s requires %s version %s; logical package %s provides %s with compatibility floor %s" % (ctx.attr.package_name, required_name, requested, selected.logical_name, selected.version, selected.compat_version or selected.version))

def _imported_component_impl(ctx):
    if ctx.attr.require_global_aspect and not ctx.attr._aspect_enabled[BuildSettingInfo].value:
        fail("rules_cps global compatibility aspect is required but its sentinel is disabled. Install the documented --aspects and --@rules_cps//cps:compatibility_aspect_enabled=true settings in .bazelrc")
    package = _package_info(ctx)
    requirements = json.decode(ctx.attr.requirements_json)
    normalized_requirements = []
    for kind in ["requires", "compile_requires", "link_requires", "dyld_requires"]:
        for specification in requirements.get(kind, []):
            parsed = parse_component_requirement(specification, ctx.attr.package_name)
            normalized_requirements.append({
                "kind": kind,
                "package": parsed.package,
                "component": parsed.component,
                "configuration": parsed.configuration,
                "configuration_mode": parsed.configuration_mode,
                "source": parsed.source,
            })
    component = CpsComponentInfo(
        package = package,
        name = ctx.attr.component_name,
        type = ctx.attr.component_type,
        configuration = ctx.attr.configuration or None,
        requirements = normalized_requirements,
        file_sets = json.decode(ctx.attr.file_sets_json),
        cpp_module_metadata = ctx.attr.cpp_module_metadata or None,
        extensions = json.decode(ctx.attr.component_extensions_json),
        source = ctx.attr.source + ".components." + ctx.attr.component_name,
    )
    direct_compile = json.decode(ctx.attr.compile_json)
    compile_flags = {"*": [], "c": [], "cpp": []}
    for candidate in [direct_compile] + [dep[CpsUsageInfo].compile for dep in ctx.attr.requires + ctx.attr.compile_requires]:
        flags = candidate.get("compile_flags", [])
        if type(flags) == "list":
            compile_flags["*"].extend(flags)
        else:
            for language in compile_flags.keys():
                compile_flags[language].extend(flags.get(language, []))
    direct_compile["compile_flags"] = compile_flags
    direct_link = json.decode(ctx.attr.link_json)
    link_plan = [{
        "component": "%s:%s@%s" % (ctx.attr.package_name, ctx.attr.component_name, ctx.attr.configuration or "<base>"),
        "files": ctx.files.link_artifacts,
        "flags": direct_link.get("link_flags", []),
    }]
    for dep in ctx.attr.requires + ctx.attr.link_requires:
        link_plan.extend(dep[CpsUsageInfo].link.get("plan", []))
    direct_link["plan"] = link_plan
    native_gaps = json.decode(ctx.attr.native_gaps_json)
    seen_link_components = {}
    duplicate_components = []
    for entry in link_plan:
        identity = entry["component"]
        if identity in seen_link_components and identity not in duplicate_components:
            duplicate_components.append(identity)
        seen_link_components[identity] = True
    if duplicate_components:
        native_gaps.append({
            "feature": "duplicate_link_plan",
            "source": ctx.attr.source,
            "json_path": "components.%s.requires/link_requires" % ctx.attr.component_name,
            "values": duplicate_components,
            "reason": "CcInfo linking depsets cannot retain deliberate duplicate component placement",
            "policy": ctx.attr.native_unsupported,
        })
    usage = CpsUsageInfo(
        compile = direct_compile,
        link = direct_link,
        native_gaps = native_gaps,
    )
    runtime_files = [ctx.file.runtime_artifact] if ctx.file.runtime_artifact else []
    runtime = CpsRuntimeInfo(
        files = depset(runtime_files, transitive = [dep[CpsRuntimeInfo].files for dep in ctx.attr.runtime_deps]),
        modules = depset(
            runtime_files if ctx.attr.component_type == "module" else [],
            transitive = [dep[CpsRuntimeInfo].modules for dep in ctx.attr.runtime_deps],
        ),
        requirements = [record for record in normalized_requirements if record["kind"] in ["requires", "link_requires", "dyld_requires"]],
        loader_requirements = [record for record in normalized_requirements if record["kind"] == "dyld_requires"],
    )
    native = ctx.attr.native_target
    compilation_contexts = [native[CcInfo].compilation_context]
    compilation_contexts.extend([dep[CcInfo].compilation_context for dep in ctx.attr.requires])
    compilation_contexts.extend([dep[CcInfo].compilation_context for dep in ctx.attr.compile_requires])
    linking_contexts = [native[CcInfo].linking_context]
    linking_contexts.extend([dep[CcInfo].linking_context for dep in ctx.attr.requires])
    linking_contexts.extend([dep[CcInfo].linking_context for dep in ctx.attr.link_requires])
    projected = CcInfo(
        compilation_context = rules_cc_common.merge_compilation_contexts(compilation_contexts = compilation_contexts),
        linking_context = rules_cc_common.merge_linking_contexts(linking_contexts = linking_contexts),
    )
    return [native[DefaultInfo], projected, package, component, usage, runtime]

def _package_info(ctx):
    _validate_bound_packages(ctx)
    return CpsPackageInfo(
        name = ctx.attr.package_name,
        version = ctx.attr.package_version or None,
        compat_version = ctx.attr.compat_version or None,
        version_schema = ctx.attr.version_schema,
        cps_version = ctx.attr.cps_version,
        logical_name = ctx.attr.logical_name,
        variant = ctx.attr.variant,
        platform = json.decode(ctx.attr.platform_json),
        compatible_with = ctx.attr.variant_constraints,
        default_components = ctx.attr.default_components,
        components = ctx.attr.package_components,
        configurations = ctx.attr.package_configurations,
        origin = ctx.attr.origin,
        source = ctx.attr.source,
        extensions = json.decode(ctx.attr.package_extensions_json),
    )

def _package_metadata_impl(ctx):
    return [DefaultInfo(), _package_info(ctx)]

_PACKAGE_ATTRS = {
    "package_name": attr.string(mandatory = True),
    "package_version": attr.string(),
    "compat_version": attr.string(),
    "version_schema": attr.string(mandatory = True),
    "cps_version": attr.string(mandatory = True),
    "logical_name": attr.string(mandatory = True),
    "variant": attr.string(mandatory = True),
    "platform_json": attr.string(mandatory = True),
    "variant_constraints": attr.string_list(),
    "default_components": attr.string_list(),
    "package_components": attr.string_list(),
    "package_configurations": attr.string_list(),
    "origin": attr.string(mandatory = True),
    "source": attr.string(mandatory = True),
    "package_extensions_json": attr.string(mandatory = True),
    "bound_packages": attr.label_keyed_string_dict(providers = [CpsPackageInfo]),
}

cps_package_metadata = rule(
    implementation = _package_metadata_impl,
    doc = "Exposes package identity metadata without selecting a component.",
    attrs = _PACKAGE_ATTRS,
)

_COMPONENT_ATTRS = dict(_PACKAGE_ATTRS)
_COMPONENT_ATTRS.update({
    "native_target": attr.label(mandatory = True, providers = [CcInfo]),
    "requires": attr.label_list(providers = [CcInfo, CpsComponentInfo]),
    "compile_requires": attr.label_list(providers = [CcInfo, CpsComponentInfo]),
    "link_requires": attr.label_list(providers = [CcInfo, CpsComponentInfo]),
    "runtime_artifact": attr.label(allow_single_file = True),
    "link_artifacts": attr.label_list(allow_files = True),
    "runtime_deps": attr.label_list(providers = [CpsRuntimeInfo]),
    "component_name": attr.string(mandatory = True),
    "component_type": attr.string(mandatory = True),
    "configuration": attr.string(),
    "requirements_json": attr.string(mandatory = True),
    "file_sets_json": attr.string(mandatory = True),
    "cpp_module_metadata": attr.string(),
    "component_extensions_json": attr.string(mandatory = True),
    "compile_json": attr.string(mandatory = True),
    "link_json": attr.string(mandatory = True),
    "native_gaps_json": attr.string(mandatory = True),
    "native_unsupported": attr.string(mandatory = True, values = ["error", "warning", "ignore"]),
    "require_global_aspect": attr.bool(default = True),
    "_aspect_enabled": attr.label(default = "//cps:compatibility_aspect_enabled"),
})

cps_imported_component = rule(
    implementation = _imported_component_impl,
    doc = "Attaches rich CPS providers to a generated native C++ projection.",
    attrs = _COMPONENT_ATTRS,
)
