"""Deterministic BUILD rendering for a normalized single CPS package."""

load(":configuration.bzl", "effective_preferences", "merge_nullable", "select_configuration")
load(":names.bzl", "encode_name")
load(":paths.bzl", "resolve_cps_path")
load(":requirements.bzl", "parse_component_requirement")
load(":model.bzl", "build_semantic_model")

def _quote(value):
    return json.encode(value)

def _unique(values):
    seen = {}
    result = []
    for value in values:
        if value not in seen:
            seen[value] = True
            result.append(value)
    return result

def _common_language_value(value):
    return value if type(value) == "list" else value.get("*", [])

def _common_definitions(value):
    if not value:
        return []
    result = []
    for name in sorted(value.get("*", {}).keys()):
        item = value["*"][name]
        result.append(name if item == None else name + "=" + item)
    return result

def _usage(component):
    return {
        "compile_features": component.get("compile_features", []),
        "compile_flags": component.get("compile_flags", []),
        "compile_requires": component.get("compile_requires", []),
        "definitions": component.get("definitions", {}),
        "includes": component.get("includes", []),
    }

def _local_semantic_package(package, remove_configurations = False):
    local = dict(package)
    components = {}
    for name, original in package["components"].items():
        component = dict(original)
        for field in ["requires", "compile_requires", "link_requires", "dyld_requires"]:
            component[field] = [
                specification
                for specification in component.get(field, [])
                if parse_component_requirement(specification, package["name"]).package == package["name"]
            ]
        if remove_configurations:
            component["configurations"] = {}
        else:
            configurations = {}
            for configuration, original_overlay in component.get("configurations", {}).items():
                overlay = dict(original_overlay)
                for field in ["requires", "compile_requires", "link_requires", "dyld_requires"]:
                    if field in overlay and overlay[field] != None:
                        overlay[field] = [
                            specification
                            for specification in overlay[field]
                            if parse_component_requirement(specification, package["name"]).package == package["name"]
                        ]
                configurations[configuration] = overlay
            component["configurations"] = configurations
        components[name] = component
    local["components"] = components
    return local

def _validate_local_semantics(package, preference_sets):
    roots = [package["name"] + ":" + name for name in sorted(package["components"].keys())]
    local = _local_semantic_package(package)
    for preferences in preference_sets:
        build_semantic_model({package["name"]: local}, roots, {package["name"]: preferences})
    for name, component in package["components"].items():
        for configuration in component.get("configurations", {}).keys():
            build_semantic_model(
                {package["name"]: local},
                [package["name"] + ":" + name + "@" + configuration],
                {package["name"]: []},
            )
    base = _local_semantic_package(package, remove_configurations = True)
    base_roots = [
        package["name"] + ":" + name
        for name, component in base["components"].items()
        if component["type"] in ["interface", "symbolic"] or component.get("location") != None
    ]
    if base_roots:
        build_semantic_model({package["name"]: base}, base_roots, {package["name"]: []})

def _native_gaps(component, source, default_policy, feature_policy):
    gaps = []
    if component.get("compile_flags", []):
        gaps.append({
            "feature": "compile_flags",
            "source": source,
            "json_path": "components.%s.compile_flags" % component["name"],
            "values": component["compile_flags"],
            "reason": "CcInfo cannot propagate arbitrary compiler flags to consumers",
            "policy": feature_policy.get("compile_flags", default_policy),
        })
    for feature in ["includes", "definitions"]:
        value = component.get(feature, {})
        if type(value) == "dict" and [key for key in value.keys() if key != "*"]:
            gaps.append({
                "feature": "language_specific_" + feature,
                "source": source,
                "json_path": "components.%s.%s" % (component["name"], feature),
                "values": value,
                "reason": "CcInfo cannot select consumer usage by source language",
                "policy": feature_policy.get("language_specific_" + feature, default_policy),
            })
    if component.get("dyld_requires", []):
        gaps.append({
            "feature": "dyld_requires",
            "source": source,
            "json_path": "components.%s.dyld_requires" % component["name"],
            "values": component["dyld_requires"],
            "reason": "CcInfo does not propagate loader-only runtime requirements through a native dependency edge",
            "policy": feature_policy.get("dyld_requires", default_policy),
        })
    if component["type"] == "module":
        gaps.append({
            "feature": "module_runtime",
            "source": source,
            "json_path": "components.%s.type" % component["name"],
            "values": ["module"],
            "reason": "CcInfo does not place runtime-loaded module artifacts in consumer runfiles",
            "policy": feature_policy.get("module_runtime", default_policy),
        })
    return gaps

def _exact_target_name(component, configuration):
    return "_cps_exact_" + encode_name(component) + "__" + encode_name(configuration)

def _base_target_name(component):
    return "_cps_base_" + encode_name(component)

def _mode_target_name(component, mode):
    return "_cps_mode_" + mode + "_" + encode_name(component)

def _dependency_names(component, field, configuration, target_names, components, package_name, package_bindings):
    dependency_names = []
    for specification in component.get(field, []):
        requirement = parse_component_requirement(specification, package_name)
        required_name = requirement.component
        if requirement.package == package_name:
            if required_name not in target_names:
                fail("component requirement %r refers to missing component %s in CPS package %s" % (specification, required_name, package_name))
            if requirement.configuration_mode == "same":
                if configuration == None:
                    dependency_names.append(":" + _base_target_name(required_name))
                else:
                    if configuration not in components[required_name].get("configurations", {}):
                        fail("same-configuration requirement %r cannot select %s on component %s" % (specification, configuration, required_name))
                    dependency_names.append(":" + _exact_target_name(required_name, configuration))
            elif requirement.configuration_mode == "exact":
                if requirement.configuration not in components[required_name].get("configurations", {}):
                    fail("exact requirement %r selects unavailable configuration on component %s" % (specification, required_name))
                dependency_names.append(":" + _exact_target_name(required_name, requirement.configuration))
            else:
                dependency_names.append(":" + target_names[required_name])
        else:
            logical_name = package_bindings.get(requirement.package)
            if logical_name == None:
                fail("%s component requirement %r needs CPS package %s, but no explicit package binding exists" % (package_name, specification, requirement.package))
            encoded = encode_name(required_name)
            if requirement.configuration_mode == "same":
                suffix = "_cps_internal_base_" + encoded if configuration == None else "_cps_internal_exact_" + encoded + "__" + encode_name(configuration)
            elif requirement.configuration_mode == "exact":
                suffix = "_cps_internal_exact_" + encoded + "__" + encode_name(requirement.configuration)
            else:
                suffix = "_cps_internal_component_" + encoded
            dependency_names.append("@%s//:%s" % (logical_name, suffix))
    return dependency_names

def _package_file(value, package_root, cps_directory):
    """Returns a generated-repository file label for a CPS path value."""
    relative = resolve_cps_path(value, ".", cps_directory)
    path = relative if package_root == "." else package_root + "/" + relative
    return "//:" + path

def _bound_packages(package, package_bindings):
    result = {}
    for required_name in sorted(package.get("requires", {}).keys()):
        logical_name = package_bindings.get(required_name)
        if logical_name == None:
            fail("%s requires CPS package %s, but no explicit package binding exists" % (package["name"], required_name))
        result["@%s//:@package" % logical_name] = json.encode({
            "name": required_name,
            "requirement": package["requires"][required_name],
        })
    return result

def _append_native_artifact(lines, component, target_name, package_root, cps_directory):
    """Emits the direct native link projection and returns its target metadata."""
    component_type = component["type"]
    artifact_name = "_artifact_" + target_name
    location = component.get("location")
    link_location = component.get("link_location")
    runtime_artifact = None
    direct_dep = None
    if component_type == "archive":
        lines.extend([
            "cc_import(",
            "    name = %s," % _quote(artifact_name),
            "    static_library = %s," % _quote(_package_file(location, package_root, cps_directory)),
            ")",
            "",
        ])
        direct_dep = ":" + artifact_name
    elif component_type == "dylib":
        runtime_artifact = _package_file(location, package_root, cps_directory)
        lines.extend([
            "cc_import(",
            "    name = %s," % _quote(artifact_name),
            "    shared_library = %s," % _quote(runtime_artifact),
        ])
        if link_location != None:
            lines.append("    interface_library = %s," % _quote(_package_file(link_location, package_root, cps_directory)))
        lines.extend([
            ")",
            "",
        ])
        direct_dep = ":" + artifact_name
    elif component_type in ["module", "executable"]:
        runtime_artifact = _package_file(location, package_root, cps_directory)
    return struct(direct_dep = direct_dep, runtime_artifact = runtime_artifact)

def _append_component_target(lines, package, component, logical_name, variant, package_root, cps_directory, compatible_with, target_name, configuration, target_names, package_bindings, origin, native_policy, native_feature_policy, require_global_aspect):
        native_name = "_native_" + target_name
        artifact = _append_native_artifact(lines, component, target_name, package_root, cps_directory)
        includes = _common_language_value(component.get("includes", []))
        include_paths = []
        for include in includes:
            resolved_include = resolve_cps_path(include, ".", cps_directory)
            include_paths.append(resolved_include if package_root == "." else package_root + "/" + resolved_include)
        definitions = _common_definitions(component.get("definitions", {}))
        requires = _dependency_names(component, "requires", configuration, target_names, package["components"], package["name"], package_bindings)
        compile_requires = _dependency_names(component, "compile_requires", configuration, target_names, package["components"], package["name"], package_bindings)
        link_requires = _dependency_names(component, "link_requires", configuration, target_names, package["components"], package["name"], package_bindings)
        dyld_requires = _dependency_names(component, "dyld_requires", configuration, target_names, package["components"], package["name"], package_bindings)
        dependency_names = []
        if artifact.direct_dep != None:
            dependency_names.insert(0, artifact.direct_dep)
        link_inputs = [_package_file(value, package_root, cps_directory) for value in component.get("link_libraries", [])]
        link_artifacts = list(link_inputs)
        if component["type"] == "archive":
            link_artifacts.insert(0, _package_file(component["location"], package_root, cps_directory))
        elif component["type"] == "dylib":
            link_artifacts.insert(0, _package_file(component.get("link_location") or component["location"], package_root, cps_directory))
        linkopts = list(component.get("link_flags", []))
        linkopts.extend(["$(location %s)" % value for value in link_inputs])
        requirements = {
            "requires": component.get("requires", []),
            "compile_requires": component.get("compile_requires", []),
            "link_requires": component.get("link_requires", []),
            "dyld_requires": component.get("dyld_requires", []),
        }
        lines.extend([
            "cc_library(",
            "    name = %s," % _quote(native_name),
            "    hdrs = glob(%s, allow_empty = True)," % _quote([path + "/**" for path in include_paths]),
            "    includes = %s," % _quote(include_paths),
            "    defines = %s," % _quote(definitions),
            "    deps = %s," % _quote(dependency_names),
            "    additional_linker_inputs = %s," % _quote(link_inputs),
            "    linkopts = %s," % _quote(linkopts),
            "    aspect_hints = [\"@rules_cps//cps:_aware_hint\"],",
            ")",
            "",
            "cps_imported_component(",
            "    name = %s," % _quote(target_name),
            "    native_target = %s," % _quote(":" + native_name),
            "    requires = %s," % _quote(requires),
            "    compile_requires = %s," % _quote(compile_requires),
            "    link_requires = %s," % _quote(link_requires),
            "    runtime_deps = %s," % _quote(_unique(requires + link_requires + dyld_requires)),
            "    link_artifacts = %s," % _quote(link_artifacts),
            "    package_name = %s," % _quote(package["name"]),
            "    package_version = %s," % _quote(package.get("version", "")),
            "    compat_version = %s," % _quote(package.get("compat_version", "")),
            "    version_schema = %s," % _quote(package["version_schema"]),
            "    cps_version = %s," % _quote(package["cps_version"]),
            "    logical_name = %s," % _quote(logical_name),
            "    variant = %s," % _quote(variant),
            "    platform_json = %s," % _quote(json.encode(package["platform"])),
            "    variant_constraints = %s," % _quote([str(label) for label in compatible_with]),
            "    default_components = %s," % _quote(package["default_components"]),
            "    package_components = %s," % _quote(sorted(package["components"].keys())),
            "    package_configurations = %s," % _quote(package["configurations"]),
            "    origin = %s," % _quote(origin),
            "    source = %s," % _quote(package["source"]),
            "    package_extensions_json = %s," % _quote(json.encode(package["extensions"])),
            "    bound_packages = %s," % _quote(_bound_packages(package, package_bindings)),
            "    component_name = %s," % _quote(component["name"]),
            "    component_type = %s," % _quote(component["type"]),
            "    configuration = %s," % _quote(configuration or ""),
            "    requirements_json = %s," % _quote(json.encode(requirements)),
            "    file_sets_json = %s," % _quote(json.encode(component.get("file_sets", []))),
            "    cpp_module_metadata = %s," % _quote(component.get("cpp_module_metadata", "")),
            "    component_extensions_json = %s," % _quote(json.encode(component.get("extensions", {}))),
            "    compile_json = %s," % _quote(json.encode(_usage(component))),
            "    link_json = %s," % _quote(json.encode({
                "location": component.get("location"),
                "link_flags": component.get("link_flags", []),
                "link_libraries": component.get("link_libraries", []),
                "requires": component.get("requires", []),
                "link_requires": component.get("link_requires", []),
            })),
            "    native_gaps_json = %s," % _quote(json.encode(_native_gaps(component, package["source"], native_policy, native_feature_policy))),
            "    native_unsupported = %s," % _quote(native_policy),
            "    runtime_artifact = %s," % (_quote(artifact.runtime_artifact) if artifact.runtime_artifact != None else "None"),
            "    require_global_aspect = %s," % ("True" if require_global_aspect else "False"),
            ")",
            "",
        ])

def render_physical_package(package, logical_name, variant, package_root, cps_directory, preferences, compilation_mode_preferences = {}, compatible_with = [], package_bindings = {}, origin = "archive", native_policy = "error", native_feature_policy = {}, require_global_aspect = True):
    """Returns BUILD text and a manifest for one physical package variant.

    Base, every exact configuration, and dbg/opt/fastbuild preference targets
    are emitted. Logical façade selection therefore occurs in the configured
    BUILD graph rather than at repository evaluation time.
    """
    preference_sets = [preferences]
    preference_sets.extend([preferences + compilation_mode_preferences.get(mode, []) for mode in ["dbg", "opt", "fastbuild"]])
    _validate_local_semantics(package, preference_sets)
    lines = [
        'load("@rules_cps//cps/private:import_rules.bzl", "cps_imported_component", "cps_package_metadata")',
        'load("@rules_cc//cc:cc_import.bzl", "cc_import")',
        'load("@rules_cc//cc:cc_library.bzl", "cc_library")',
        "",
        "package(default_visibility = [\"//visibility:public\"])",
        "",
    ]
    lines.extend([
        "cps_package_metadata(",
        "    name = \"_cps_package\",",
        "    package_name = %s," % _quote(package["name"]),
        "    package_version = %s," % _quote(package.get("version", "")),
        "    compat_version = %s," % _quote(package.get("compat_version", "")),
        "    version_schema = %s," % _quote(package["version_schema"]),
        "    cps_version = %s," % _quote(package["cps_version"]),
        "    logical_name = %s," % _quote(logical_name),
        "    variant = %s," % _quote(variant),
        "    platform_json = %s," % _quote(json.encode(package["platform"])),
        "    variant_constraints = %s," % _quote([str(label) for label in compatible_with]),
        "    default_components = %s," % _quote(package["default_components"]),
        "    package_components = %s," % _quote(sorted(package["components"].keys())),
        "    package_configurations = %s," % _quote(package["configurations"]),
        "    origin = %s," % _quote(origin),
        "    source = %s," % _quote(package["source"]),
        "    package_extensions_json = %s," % _quote(json.encode(package["extensions"])),
        "    bound_packages = %s," % _quote(_bound_packages(package, package_bindings)),
        ")",
        "",
    ])
    target_names = {name: encode_name(name) for name in package["components"].keys()}
    manifest_components = {}
    for name in sorted(package["components"].keys()):
        base = package["components"][name]
        configurations = base.get("configurations", {})
        selected = select_configuration(
            configurations.keys(),
            effective_preferences(preferences, [], package["configurations"]),
        )
        selected_data = merge_nullable(base, configurations[selected]) if selected != None else base
        base_data = base
        if base["type"] not in ["interface", "symbolic"] and base.get("location") == None:
            base_data = selected_data
        _append_component_target(
            lines, package, base_data, logical_name, variant, package_root, cps_directory,
            compatible_with, _base_target_name(name), selected if base_data != base else None, target_names, package_bindings, origin,
            native_policy, native_feature_policy, require_global_aspect,
        )
        exact_targets = {}
        for configuration in sorted(configurations.keys()):
            target = _exact_target_name(name, configuration)
            exact_targets[configuration] = target
            _append_component_target(
                lines, package, merge_nullable(base, configurations[configuration]), logical_name, variant,
                package_root, cps_directory, compatible_with, target, configuration, target_names, package_bindings, origin,
                native_policy, native_feature_policy, require_global_aspect,
            )
        _append_component_target(
            lines, package, selected_data, logical_name, variant, package_root, cps_directory,
            compatible_with, target_names[name], selected, target_names, package_bindings, origin,
            native_policy, native_feature_policy, require_global_aspect,
        )
        mode_targets = {}
        for mode in ["dbg", "opt", "fastbuild"]:
            mode_selected = select_configuration(
                configurations.keys(),
                effective_preferences(preferences, compilation_mode_preferences.get(mode, []), package["configurations"]),
            )
            mode_target = _mode_target_name(name, mode)
            mode_targets[mode] = mode_target
            mode_data = merge_nullable(base, configurations[mode_selected]) if mode_selected != None else base
            _append_component_target(
                lines, package, mode_data, logical_name, variant, package_root, cps_directory,
                compatible_with, mode_target, mode_selected, target_names, package_bindings, origin,
                native_policy, native_feature_policy, require_global_aspect,
            )
        manifest_components[name] = {
            "base_target": _base_target_name(name),
            "configurations": exact_targets,
            "mode_targets": mode_targets,
            "preference_target": target_names[name],
        }

    default_targets = {}
    default_components = [name for name in package["default_components"] if name in target_names]
    for mode in ["dbg", "opt", "fastbuild"]:
        target = "_cps_default_" + mode
        default_targets[mode] = target
        lines.extend([
            "cc_library(",
            "    name = %s," % _quote(target),
            "    deps = %s," % _quote([":" + _mode_target_name(name, mode) for name in default_components]),
            "    aspect_hints = [\"@rules_cps//cps:_aware_hint\"],",
            ")",
            "",
        ])
    lines.extend([
        "cc_library(",
        "    name = \"_cps_default\",",
        "    deps = %s," % _quote([":" + target_names[name] for name in default_components]),
        "    aspect_hints = [\"@rules_cps//cps:_aware_hint\"],",
        ")",
        "",
    ])
    manifest = {
        "compatible_with": [str(label) for label in compatible_with],
        "components": manifest_components,
        "default_targets": default_targets,
        "logical_name": logical_name,
        "package_name": package["name"],
        "package_target": "_cps_package",
        "source": package["source"],
        "variant": variant,
    }
    return struct(build = "\n".join(lines), manifest = manifest)
