"""Repository rule generating stable logical CPS package labels."""

load(":names.bzl", "encode_name")

def _quote(value):
    return json.encode(value)

def _repo_prefix(label):
    text = str(label)
    separator = text.rfind("//")
    if separator < 0:
        fail("unexpected physical CPS manifest label %r" % text)
    return text[:separator + 2]

def _config_name(variant, mode = None):
    base = "_cps_variant_" + encode_name(variant)
    return base + ("_" + mode if mode != None else "")

def _logical_repository_impl(ctx):
    variants = []
    for manifest_label in ctx.attr.manifests:
        manifest = json.decode(ctx.read(manifest_label))
        manifest["repository_prefix"] = _repo_prefix(manifest_label)
        variants.append(manifest)
    if not variants:
        fail("logical CPS package %s has no physical variants" % ctx.attr.logical_name)
    for variant in variants:
        if variant["logical_name"] != ctx.attr.logical_name:
            fail("physical variant %s belongs to logical package %s, expected %s" % (
                variant["variant"],
                variant["logical_name"],
                ctx.attr.logical_name,
            ))
    variants_by_constraints = {}
    for variant in variants:
        key = "\n".join(sorted(variant["compatible_with"]))
        if key in variants_by_constraints:
            fail("logical CPS package %s has indistinguishable physical variants %s and %s with the same compatible_with constraints: %s" % (
                ctx.attr.logical_name,
                variants_by_constraints[key],
                variant["variant"],
                ", ".join(sorted(variant["compatible_with"])) or "<platform-independent>",
            ))
        variants_by_constraints[key] = variant["variant"]

    component_set = {component: True for component in ctx.attr.expose_components}
    for variant in variants:
        for component in variant["components"].keys():
            component_set[component] = True
    all_components = sorted(component_set.keys())

    lines = [
        'load("@rules_cps//cps/private:facade_rules.bzl", "cps_unavailable")',
        "",
        "package(default_visibility = [\"//visibility:public\"])",
        "",
    ]
    for variant in variants:
        constraints = variant["compatible_with"]
        if constraints:
            lines.extend([
                "config_setting(",
                "    name = %s," % _quote(_config_name(variant["variant"])),
                "    constraint_values = %s," % _quote(constraints),
                ")",
                "",
            ])
        for mode in ["dbg", "opt", "fastbuild"]:
            lines.extend([
                "config_setting(",
                "    name = %s," % _quote(_config_name(variant["variant"], mode)),
                "    constraint_values = %s," % _quote(constraints),
                "    values = {\"compilation_mode\": %s}," % _quote(mode),
                ")",
                "",
            ])
    lines.extend([
        "cps_unavailable(",
        "    name = \"_cps_no_matching_variant\",",
        "    message = %s," % _quote(
            "No physical variant of logical CPS package %s matches the configured Bazel platform. Declared variants: %s" % (
                ctx.attr.logical_name,
                ", ".join([variant["variant"] for variant in variants]),
            ),
        ),
        ")",
        "",
    ])

    for component in all_components:
        encoded = encode_name(component)
        choices = {}
        for variant in variants:
            info = variant["components"].get(component)
            for mode in ["dbg", "opt", "fastbuild"]:
                key = ":" + _config_name(variant["variant"], mode)
                choices[key] = (
                    variant["repository_prefix"] + ":" + info["mode_targets"][mode]
                    if info != None
                    else ":_cps_missing_component_" + encoded + "_" + encode_name(variant["variant"])
                )
            if info == None:
                missing = "_cps_missing_component_" + encoded + "_" + encode_name(variant["variant"])
                missing_message = (
                    variant["source"]
                    if not variant.get("available", True)
                    else "CPS component %s is absent from logical package %s variant %s" % (
                        component,
                        ctx.attr.logical_name,
                        variant["variant"],
                    )
                )
                lines.extend([
                    "cps_unavailable(",
                    "    name = %s," % _quote(missing),
                    "    message = %s," % _quote(missing_message),
                    ")",
                    "",
                ])
        choices["//conditions:default"] = ":_cps_no_matching_variant"
        lines.extend([
            "alias(",
            "    name = %s," % _quote("_cps_internal_component_" + encoded),
            "    actual = select(%s)," % _quote(choices),
            ")",
            "",
        ])
        if component in ctx.attr.expose_components:
            lines.extend([
                "alias(name = %s, actual = %s)" % (_quote(encoded), _quote(":_cps_internal_component_" + encoded)),
                "",
            ])

        base_choices = {}
        all_configurations = {}
        for variant in variants:
            info = variant["components"].get(component)
            key = ":" + _config_name(variant["variant"]) if variant["compatible_with"] else "//conditions:default"
            if info != None:
                base_choices[key] = variant["repository_prefix"] + ":" + info["base_target"]
                for configuration in info["configurations"].keys():
                    all_configurations[configuration] = True
            else:
                base_choices[key] = ":_cps_missing_component_" + encoded + "_" + encode_name(variant["variant"])
        if "//conditions:default" not in base_choices:
            base_choices["//conditions:default"] = ":_cps_no_matching_variant"
        lines.extend([
            "alias(name = %s, actual = select(%s))" % (
                _quote("_cps_internal_base_" + encoded),
                _quote(base_choices),
            ),
            "",
        ])
        for configuration in sorted(all_configurations.keys()):
            exact_choices = {}
            for variant in variants:
                info = variant["components"].get(component)
                target = info["configurations"].get(configuration) if info != None else None
                key = ":" + _config_name(variant["variant"]) if variant["compatible_with"] else "//conditions:default"
                exact_choices[key] = (
                    variant["repository_prefix"] + ":" + target
                    if target != None
                    else ":_cps_missing_exact_" + encoded + "__" + encode_name(configuration) + "_" + encode_name(variant["variant"])
                )
                if target == None:
                    lines.extend([
                        "cps_unavailable(",
                        "    name = %s," % _quote("_cps_missing_exact_" + encoded + "__" + encode_name(configuration) + "_" + encode_name(variant["variant"])),
                        "    message = %s," % _quote("Exact CPS configuration %s is unavailable for component %s in logical package %s variant %s" % (configuration, component, ctx.attr.logical_name, variant["variant"])),
                        ")",
                        "",
                    ])
            if "//conditions:default" not in exact_choices:
                exact_choices["//conditions:default"] = ":_cps_no_matching_variant"
            lines.extend([
                "alias(name = %s, actual = select(%s))" % (
                    _quote("_cps_internal_exact_" + encoded + "__" + encode_name(configuration)),
                    _quote(exact_choices),
                ),
                "",
            ])

    default_choices = {}
    package_choices = {}
    for variant in variants:
        prefix = variant["repository_prefix"]
        if variant["compatible_with"]:
            package_choices[":" + _config_name(variant["variant"])] = prefix + ":" + variant["package_target"]
        else:
            package_choices["//conditions:default"] = prefix + ":" + variant["package_target"]
        for mode in ["dbg", "opt", "fastbuild"]:
            default_choices[":" + _config_name(variant["variant"], mode)] = prefix + ":" + variant["default_targets"][mode]
    default_choices["//conditions:default"] = ":_cps_no_matching_variant"
    if "//conditions:default" not in package_choices:
        package_choices["//conditions:default"] = ":_cps_no_matching_variant"
    lines.extend([
        "alias(name = \"@default\", actual = select(%s))" % _quote(default_choices),
        "alias(name = \"@package\", actual = select(%s))" % _quote(package_choices),
        "",
    ])
    ctx.file("BUILD.bazel", "\n".join(lines))

    for component in ctx.attr.expose_components:
        component_lines = [
            'load("@rules_cps//cps/private:facade_rules.bzl", "cps_unavailable")',
            "package(default_visibility = [\"//visibility:public\"])",
            "",
        ]
        for configuration in ctx.attr.expose_configurations:
            choices = {}
            for variant in variants:
                info = variant["components"].get(component)
                target = info["configurations"].get(configuration) if info != None else None
                selection_key = "//:" + _config_name(variant["variant"]) if variant["compatible_with"] else "//conditions:default"
                if target != None:
                    choices[selection_key] = variant["repository_prefix"] + ":" + target
                else:
                    missing = "_missing_" + encode_name(configuration) + "_" + encode_name(variant["variant"])
                    missing_message = (
                        variant["source"]
                        if not variant.get("available", True)
                        else "Exact CPS configuration %s is unavailable for component %s in logical package %s variant %s; available: %s" % (
                            configuration,
                            component,
                            ctx.attr.logical_name,
                            variant["variant"],
                            ", ".join(sorted(info["configurations"].keys())) if info != None else "<component absent>",
                        )
                    )
                    component_lines.extend([
                        "cps_unavailable(",
                        "    name = %s," % _quote(missing),
                        "    message = %s," % _quote(missing_message),
                        ")",
                        "",
                    ])
                    choices[selection_key] = ":" + missing
            if "//conditions:default" not in choices:
                choices["//conditions:default"] = "//:_cps_no_matching_variant"
            component_lines.extend([
                "alias(",
                "    name = %s," % _quote(encode_name(configuration)),
                "    actual = select(%s)," % _quote(choices),
                ")",
                "",
            ])
        ctx.file(encode_name(component) + "/BUILD.bazel", "\n".join(component_lines))

cps_logical_repository = repository_rule(
    implementation = _logical_repository_impl,
    doc = "Generates stable logical labels selecting configured physical CPS variants.",
    attrs = {
        "logical_name": attr.string(mandatory = True),
        "manifests": attr.label_list(mandatory = True, allow_files = True),
        "expose_components": attr.string_list(),
        "expose_configurations": attr.string_list(),
    },
)
