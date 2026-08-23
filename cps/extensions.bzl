"""Public root-controlled Bzlmod import API for CPS packages."""

load("//cps/private:facade_repository.bzl", "cps_logical_repository")
load(
    "//cps/private:repositories.bzl",
    "cps_archive_repository",
    "cps_env_package_repository",
    "cps_http_archive_repository",
    "cps_local_archive_repository",
    "cps_local_package_repository",
)

_config = tag_class(
    doc = "Declares root-wide CPS binding, configuration, and compatibility policy.",
    attrs = {
        "default_package_bindings": attr.string_dict(doc = "Maps required CPS package identities to declared logical package names."),
        "default_configuration_preferences": attr.string_list(doc = "Ordered root-wide CPS configuration preferences."),
        "compilation_mode_preferences": attr.string_list_dict(doc = "Maps dbg, opt, and fastbuild to additional ordered CPS preferences."),
        "native_unsupported": attr.string(default = "error", values = ["error", "warning", "ignore"], doc = "Default policy for CPS behavior lost at a stock rules_cc edge."),
        "native_feature_policy": attr.string_dict(doc = "Per-feature overrides of native_unsupported."),
        "nonhermetic": attr.string(default = "allow", values = ["allow", "warning", "error"], doc = "Policy for local and environment acquisition declarations."),
        "require_global_aspect": attr.bool(default = True, doc = "Makes imported targets require the compatibility aspect sentinel."),
    },
)

_package = tag_class(
    doc = "Declares one stable logical CPS package and its public label surface.",
    attrs = {
        "name": attr.string(mandatory = True, doc = "Stable logical repository name imported with use_repo."),
        "expected_name": attr.string(doc = "Optional CPS package identity required from every selected variant."),
        "package_bindings": attr.string_dict(doc = "Package-local required identity to logical package bindings."),
        "configuration_preferences": attr.string_list(doc = "Ordered package preferences replacing root defaults."),
        "compilation_mode_preferences": attr.string_list_dict(doc = "Package-specific dbg, opt, and fastbuild preference additions."),
        "expose_components": attr.string_list(doc = "Component names that receive short public aliases."),
        "expose_configurations": attr.string_list(doc = "Configuration names that receive exact public aliases."),
        "cps_file": attr.string(doc = "Package-relative base CPS path used unless a variant overrides it."),
    },
)

_archive = tag_class(
    doc = "Declares a hermetic Bazel-owned archive physical package variant.",
    attrs = {
        "package": attr.string(mandatory = True, doc = "Declared logical package that owns this physical variant."),
        "variant": attr.string(mandatory = True, doc = "Physical variant name unique within the logical package."),
        "archive": attr.label(mandatory = True, allow_single_file = True, doc = "Bazel-owned archive file to extract."),
        "strip_prefix": attr.string(doc = "Archive directory prefix removed during extraction."),
        "compatible_with": attr.label_list(doc = "Opaque Bazel constraints required by this variant."),
        "cps_file": attr.string(doc = "Variant-level package-relative base CPS path override."),
    },
)

_http_archive = tag_class(
    doc = "Declares a digest-pinned remote archive physical package variant.",
    attrs = {
        "package": attr.string(mandatory = True, doc = "Declared logical package that owns this physical variant."),
        "variant": attr.string(mandatory = True, doc = "Physical variant name unique within the logical package."),
        "urls": attr.string_list(mandatory = True, doc = "Ordered HTTP or HTTPS mirror URLs. file URLs are rejected."),
        "integrity": attr.string(mandatory = True, doc = "Mandatory Subresource Integrity digest for the archive."),
        "strip_prefix": attr.string(doc = "Archive directory prefix removed during extraction."),
        "patches": attr.label_list(allow_files = True, doc = "Bazel-owned patch files applied after extraction."),
        "patch_strip": attr.int(default = 0, doc = "Leading patch path components removed by repository_ctx.patch."),
        "compatible_with": attr.label_list(doc = "Opaque Bazel constraints required by this variant."),
        "cps_file": attr.string(doc = "Variant-level package-relative base CPS path override."),
    },
)

_local_package = tag_class(
    doc = "Declares an explicit non-hermetic materialized local CPS prefix.",
    attrs = {
        "package": attr.string(mandatory = True, doc = "Declared logical package that owns this physical variant."),
        "variant": attr.string(mandatory = True, doc = "Physical variant name unique within the logical package."),
        "path": attr.string(mandatory = True, doc = "Explicit host directory. Shell and environment expansion are not performed."),
        "compatible_with": attr.label_list(doc = "Opaque Bazel constraints required by this variant."),
        "cps_file": attr.string(doc = "Variant-level package-relative base CPS path override."),
    },
)

_local_archive = tag_class(
    doc = "Declares an explicit non-hermetic digest-pinned local CPS archive.",
    attrs = {
        "package": attr.string(mandatory = True, doc = "Declared logical package that owns this physical variant."),
        "variant": attr.string(mandatory = True, doc = "Physical variant name unique within the logical package."),
        "path": attr.string(mandatory = True, doc = "Explicit host archive file watched by the repository rule."),
        "integrity": attr.string(mandatory = True, doc = "Mandatory Subresource Integrity digest for the local archive."),
        "strip_prefix": attr.string(doc = "Archive directory prefix removed during extraction."),
        "compatible_with": attr.label_list(doc = "Opaque Bazel constraints required by this variant."),
        "cps_file": attr.string(doc = "Variant-level package-relative base CPS path override."),
    },
)

_env_package = tag_class(
    doc = "Declares an explicit non-hermetic environment-provided CPS prefix.",
    attrs = {
        "package": attr.string(mandatory = True, doc = "Declared logical package that owns this physical variant."),
        "variant": attr.string(mandatory = True, doc = "Physical variant name unique within the logical package."),
        "env": attr.string(mandatory = True, doc = "Exact environment variable read through the Bazel repository API."),
        "subpath": attr.string(doc = "Relative path appended to the environment variable value."),
        "required": attr.bool(default = True, doc = "Whether an unset variable fails repository setup instead of making the variant unavailable."),
        "compatible_with": attr.label_list(doc = "Opaque Bazel constraints required by this variant."),
        "cps_file": attr.string(doc = "Variant-level package-relative base CPS path override."),
    },
)

def _internal_repo_name(package, variant):
    return "rules_cps_internal_%s_%s" % (package.replace("-", "_"), variant.replace("-", "_"))

def _implementation(module_ctx):
    config_tags = []
    package_tags = []
    archive_tags = []
    http_archive_tags = []
    local_package_tags = []
    local_archive_tags = []
    env_package_tags = []
    for module in module_ctx.modules:
        concrete = (
            module.tags.config +
            module.tags.package +
            module.tags.archive +
            module.tags.http_archive +
            module.tags.local_package +
            module.tags.local_archive +
            module.tags.env_package
        )
        if concrete and not module.is_root:
            fail("module %s declares concrete rules_cps acquisition/configuration tags; only the root module may choose CPS packages" % module.name)
        if module.is_root:
            config_tags.extend(module.tags.config)
            package_tags.extend(module.tags.package)
            archive_tags.extend(module.tags.archive)
            http_archive_tags.extend(module.tags.http_archive)
            local_package_tags.extend(module.tags.local_package)
            local_archive_tags.extend(module.tags.local_archive)
            env_package_tags.extend(module.tags.env_package)
    if len(config_tags) > 1:
        fail("at most one root cps.config() declaration is permitted")
    config = config_tags[0] if config_tags else None

    packages = {}
    for declaration in package_tags:
        if declaration.name in packages:
            fail("duplicate logical CPS package declaration %r" % declaration.name)
        packages[declaration.name] = declaration

    variants = {}
    declarations = (
        [("archive", tag) for tag in archive_tags] +
        [("http_archive", tag) for tag in http_archive_tags] +
        [("local_package", tag) for tag in local_package_tags] +
        [("local_archive", tag) for tag in local_archive_tags] +
        [("env_package", tag) for tag in env_package_tags]
    )
    for kind, declaration in declarations:
        if declaration.package not in packages:
            fail("CPS archive variant %s references unknown logical package %s" % (declaration.variant, declaration.package))
        key = declaration.package + "\n" + declaration.variant
        if key in variants:
            fail("duplicate physical CPS variant (%s, %s)" % (declaration.package, declaration.variant))
        variants[key] = (kind, declaration)

    generated_by_package = {name: [] for name in packages.keys()}
    nonhermetic_kinds = [kind for kind, _ in declarations if kind in ["local_package", "local_archive", "env_package"]]
    nonhermetic_policy = config.nonhermetic if config != None else "allow"
    if nonhermetic_kinds and nonhermetic_policy == "error":
        fail("rules_cps nonhermetic policy is error, but root module declares: %s" % ", ".join(nonhermetic_kinds))
    if nonhermetic_kinds and nonhermetic_policy == "warning":
        print("WARNING: rules_cps root module declares explicit non-hermetic acquisition: %s" % ", ".join(nonhermetic_kinds))
    for key in sorted(variants.keys()):
        kind, declaration = variants[key]
        package = packages[declaration.package]
        internal_name = _internal_repo_name(declaration.package, declaration.variant)
        preferences = package.configuration_preferences
        if not preferences and config != None:
            preferences = config.default_configuration_preferences
        mode_preferences = package.compilation_mode_preferences
        if not mode_preferences and config != None:
            mode_preferences = config.compilation_mode_preferences
        cps_file = declaration.cps_file or package.cps_file
        package_bindings = dict(config.default_package_bindings) if config != None else {}
        package_bindings.update(package.package_bindings)
        for required_name, bound_logical_name in package_bindings.items():
            if bound_logical_name not in packages:
                fail("logical CPS package %s binds CPS identity %s to unknown logical package %s" % (declaration.package, required_name, bound_logical_name))
        common = {
            "name": internal_name,
            "cps_file": cps_file,
            "logical_name": declaration.package,
            "variant": declaration.variant,
            "expected_name": package.expected_name,
            "configuration_preferences": preferences,
            "compilation_mode_preferences": mode_preferences,
            "variant_constraints": declaration.compatible_with,
            "package_bindings": package_bindings,
            "native_unsupported": config.native_unsupported if config != None else "error",
            "native_feature_policy": config.native_feature_policy if config != None else {},
            "require_global_aspect": config.require_global_aspect if config != None else True,
        }
        if kind == "archive":
            cps_archive_repository(archive = declaration.archive, strip_prefix = declaration.strip_prefix, **common)
        elif kind == "http_archive":
            for url in declaration.urls:
                if url.startswith("file://"):
                    fail("cps.http_archive variant (%s, %s) forbids file:// URL %s; use cps.local_archive" % (
                        declaration.package,
                        declaration.variant,
                        url,
                    ))
            cps_http_archive_repository(
                urls = declaration.urls,
                integrity = declaration.integrity,
                patches = declaration.patches,
                patch_strip = declaration.patch_strip,
                strip_prefix = declaration.strip_prefix,
                **common
            )
        elif kind == "local_package":
            cps_local_package_repository(path = declaration.path, **common)
        elif kind == "local_archive":
            cps_local_archive_repository(
                path = declaration.path,
                integrity = declaration.integrity,
                strip_prefix = declaration.strip_prefix,
                **common
            )
        else:
            cps_env_package_repository(
                env = declaration.env,
                subpath = declaration.subpath,
                required = declaration.required,
                **common
            )
        generated_by_package[declaration.package].append(internal_name)

    direct = []
    for name in sorted(packages.keys()):
        package = packages[name]
        internal_names = generated_by_package[name]
        if not internal_names:
            fail("logical CPS package %s has no physical variants" % name)
        cps_logical_repository(
            name = name,
            logical_name = name,
            manifests = ["@%s//:_rules_cps_manifest.json" % internal for internal in internal_names],
            expose_components = package.expose_components,
            expose_configurations = package.expose_configurations,
        )
        direct.append(name)
    non_dev = module_ctx.root_module_has_non_dev_dependency
    return module_ctx.extension_metadata(
        root_module_direct_deps = direct if non_dev else [],
        root_module_direct_dev_deps = [] if non_dev else direct,
        reproducible = True,
    )

cps = module_extension(
    implementation = _implementation,
    doc = "Declares explicit logical CPS packages and physical variants for the root build.",
    tag_classes = {
        "archive": _archive,
        "config": _config,
        "http_archive": _http_archive,
        "local_archive": _local_archive,
        "local_package": _local_package,
        "env_package": _env_package,
        "package": _package,
    },
)
