"""Internal repository rules for CPS package acquisition."""

load(":paths.bzl", "normalize_relative_path", "resolve_cps_path")
load(":render_build.bzl", "render_physical_package")
load(":merge.bzl", "merge_common_packages", "merge_configuration_fragments")
load(":schema.bzl", "parse_configuration_fragment_json", "parse_cps_json")

def _assert_under_root(root, candidate, description):
    root_real = str(root.realpath)
    candidate_real = str(candidate.realpath)
    if candidate_real != root_real and not candidate_real.startswith(root_real + "/"):
        fail("%s escapes materialized CPS package root %s: %s" % (description, root_real, candidate_real))

def _validate_consumed_path(root, value, cps_directory, description):
    relative = resolve_cps_path(value, ".", cps_directory)
    candidate = root.get_child(relative)
    if not candidate.exists:
        fail("%s does not exist inside materialized CPS package root: %s" % (description, value))
    _assert_under_root(root, candidate, description)
    return candidate

def _validate_tree_under_root(root, directory, description):
    pending = [directory]
    for _ in range(100000):
        if not pending:
            return
        current = pending.pop()
        for child in current.readdir():
            _assert_under_root(root, child, description + " entry")
            if child.is_dir:
                pending.append(child)
    fail("%s tree exceeds the 100000-entry safety limit" % description)

def _validate_language_paths(root, value, cps_directory, description):
    if type(value) == "list":
        for path in value:
            candidate = _validate_consumed_path(root, path, cps_directory, description)
            if candidate.is_dir:
                _validate_tree_under_root(root, candidate, description)
    else:
        for language, paths in value.items():
            for path in paths:
                language_description = "%s for language %s" % (description, language)
                candidate = _validate_consumed_path(root, path, cps_directory, language_description)
                if candidate.is_dir:
                    _validate_tree_under_root(root, candidate, language_description)

def _validate_component_paths(root, component, cps_directory, description):
    for field in ["location", "link_location", "cpp_module_metadata"]:
        if component.get(field) != None:
            _validate_consumed_path(root, component[field], cps_directory, description + "." + field)
    for field in ["link_libraries"]:
        for value in component.get(field, []):
            _validate_consumed_path(root, value, cps_directory, description + "." + field)
    for field in ["includes", "embeds"]:
        if component.get(field) != None:
            _validate_language_paths(root, component[field], cps_directory, description + "." + field)

def _validate_package_paths(root, package, cps_directory):
    if package.get("prefix") != None:
        fail("hermetic CPS archive %s uses non-relocatable prefix %r; use cps_path and @prefix@ paths" % (package["source"], package["prefix"]))
    declared_cps_directory = normalize_relative_path(package["cps_path"][len("@prefix@/"):]) if package["cps_path"].startswith("@prefix@/") else None
    if declared_cps_directory == None or declared_cps_directory != cps_directory:
        fail("%s cps_path %r does not match actual package-relative CPS directory %r" % (package["source"], package["cps_path"], cps_directory))
    for name, component in package["components"].items():
        description = "%s.components.%s" % (package["source"], name)
        _validate_component_paths(root, component, cps_directory, description)
        for configuration, overlay in component.get("configurations", {}).items():
            _validate_component_paths(root, overlay, cps_directory, "%s.configurations.%s" % (description, configuration))
        for index, fileset in enumerate(component.get("file_sets", [])):
            root_value = fileset["root"]
            root_relative = resolve_cps_path(root_value, ".", cps_directory)
            _validate_consumed_path(root, root_value, cps_directory, "%s.file_sets[%d].root" % (description, index))
            for file_value in fileset["files"]:
                _validate_consumed_path(
                    root,
                    root_relative + "/" + file_value,
                    ".",
                    "%s.file_sets[%d].files" % (description, index),
                )

def _load_supplements(ctx, base_path, base_relative, package):
    base_name = base_path.basename
    stem = base_name[:-len(".cps")]
    common_paths = []
    configuration_paths = []
    for candidate in base_path.dirname.readdir():
        name = candidate.basename
        if name == base_name or not name.endswith(".cps"):
            continue
        suffix = name[len(stem):] if name.startswith(stem) else ""
        if not suffix or suffix[0] not in [":", "-", "@"]:
            continue
        if "@" in suffix:
            configuration_paths.append(candidate)
        else:
            common_paths.append(candidate)
    common_by_name = {path.basename: path for path in common_paths}
    common = []
    for name in sorted(common_by_name.keys()):
        path = common_by_name[name]
        relative = base_relative.rpartition("/")[0] + "/" + path.basename
        common.append(parse_cps_json(ctx.read(path), relative))
    merged = merge_common_packages(package, common)
    configuration_by_name = {path.basename: path for path in configuration_paths}
    configurations = []
    for name in sorted(configuration_by_name.keys()):
        path = configuration_by_name[name]
        relative = base_relative.rpartition("/")[0] + "/" + path.basename
        configurations.append(parse_configuration_fragment_json(ctx.read(path), relative))
    return merge_configuration_fragments(merged, configurations)

def _relative_path(root, path):
    root_text = str(root)
    path_text = str(path)
    if not path_text.startswith(root_text + "/"):
        fail("path %s is not below repository package root %s" % (path_text, root_text))
    return path_text[len(root_text) + 1:]

def _discover_cps_file(ctx, package_directory):
    candidates = []
    pending = [package_directory]
    for _ in range(100000):
        if not pending:
            break
        directory = pending.pop()
        for child in directory.readdir():
            if child.is_dir:
                pending.append(child)
            elif child.basename.endswith(".cps") and not child.basename.startswith("._"):
                content = ctx.read(child)
                value = json.decode(content)
                if type(value) != "dict" or type(value.get("name")) != "string" or value.get("cps_version") == None:
                    continue
                stem = child.basename[:-len(".cps")]
                if stem in [value["name"], value["name"].lower()]:
                    candidates.append(_relative_path(package_directory, child))
    if pending:
        fail("automatic CPS discovery exceeds the 100000-directory-entry safety limit")
    candidates = sorted(candidates)
    if not candidates:
        fail("automatic CPS discovery found no base CPS document inside %s" % package_directory)
    if len(candidates) > 1:
        fail("automatic CPS discovery found multiple base CPS documents; set cps_file explicitly. Candidates: %s" % ", ".join(candidates))
    return candidates[0]

def _finish_repository(ctx, origin, package_directory = None):
    package_directory = package_directory or ctx.path(".")
    cps_relative = normalize_relative_path(ctx.attr.cps_file) if ctx.attr.cps_file else _discover_cps_file(ctx, package_directory)
    cps_path = package_directory.get_child(cps_relative)
    if not cps_path.exists:
        fail("declared CPS file does not exist in archive: %s" % ctx.attr.cps_file)
    _assert_under_root(package_directory, cps_path, "CPS document")
    package = parse_cps_json(ctx.read(cps_path), cps_relative)
    package = _load_supplements(ctx, cps_path, cps_relative, package)
    if ctx.attr.expected_name and package["name"] != ctx.attr.expected_name:
        fail("selected CPS package identity %r does not match expected_name %r" % (package["name"], ctx.attr.expected_name))
    cps_directory = cps_relative.rpartition("/")[0] or "."
    _validate_package_paths(package_directory, package, cps_directory)
    rendered = render_physical_package(
        package,
        ctx.attr.logical_name,
        ctx.attr.variant,
        ".",
        cps_directory,
        ctx.attr.configuration_preferences,
        ctx.attr.compilation_mode_preferences,
        ctx.attr.variant_constraints,
        ctx.attr.package_bindings,
        origin,
        ctx.attr.native_unsupported,
        ctx.attr.native_feature_policy,
        ctx.attr.require_global_aspect,
    )
    ctx.file("BUILD.bazel", rendered.build)
    ctx.file("_rules_cps_manifest.json", json.encode_indent(rendered.manifest, indent = "  "))

def _archive_repository_impl(ctx):
    package_directory = ctx.path(".")
    ctx.extract(ctx.path(ctx.attr.archive), output = package_directory, stripPrefix = ctx.attr.strip_prefix)
    _finish_repository(ctx, "archive")

def _http_archive_repository_impl(ctx):
    for url in ctx.attr.urls:
        if url.startswith("file://"):
            fail("cps.http_archive forbids file:// URLs; use cps.local_archive for explicit host-local acquisition")
    ctx.download_and_extract(
        url = ctx.attr.urls,
        integrity = ctx.attr.integrity,
        output = ".",
        stripPrefix = ctx.attr.strip_prefix,
    )
    for patch in ctx.attr.patches:
        ctx.patch(patch, strip = ctx.attr.patch_strip)
    _finish_repository(ctx, "http_archive")

def _link_local_tree(ctx, source):
    for child in source.readdir():
        if child.basename in ["BUILD", "BUILD.bazel", "MODULE.bazel", "REPO.bazel", "WORKSPACE", "WORKSPACE.bazel"]:
            continue
        ctx.symlink(child, child.basename)

def _local_package_repository_impl(ctx):
    if "$" in ctx.attr.path:
        fail("cps.local_package path does not perform environment expansion: %r" % ctx.attr.path)
    source = ctx.path(ctx.attr.path)
    if not source.exists or not source.is_dir:
        fail("cps.local_package path is not an existing directory: %s" % source)
    ctx.watch_tree(source)
    _link_local_tree(ctx, source)
    _finish_repository(ctx, "local_package", source)

def _local_archive_repository_impl(ctx):
    archive = ctx.path(ctx.attr.path)
    if not archive.exists or archive.is_dir:
        fail("cps.local_archive path is not an existing archive file: %s" % archive)
    ctx.watch(archive)
    ctx.download_and_extract(
        url = "file://" + str(archive),
        integrity = ctx.attr.integrity,
        output = ".",
        stripPrefix = ctx.attr.strip_prefix,
    )
    _finish_repository(ctx, "local_archive")

def _write_unavailable_repository(ctx, reason):
    ctx.file("BUILD.bazel", """load("@rules_cps//cps/private:facade_rules.bzl", "cps_unavailable")
package(default_visibility = ["//visibility:public"])
cps_unavailable(name = "_cps_unavailable", message = %s)
""" % json.encode(reason))
    manifest = {
        "available": False,
        "compatible_with": [str(label) for label in ctx.attr.variant_constraints],
        "components": {},
        "default_targets": {
            "dbg": "_cps_unavailable",
            "fastbuild": "_cps_unavailable",
            "opt": "_cps_unavailable",
        },
        "logical_name": ctx.attr.logical_name,
        "package_name": ctx.attr.expected_name,
        "package_target": "_cps_unavailable",
        "source": reason,
        "variant": ctx.attr.variant,
    }
    ctx.file("_rules_cps_manifest.json", json.encode_indent(manifest, indent = "  "))

def _env_package_repository_impl(ctx):
    value = ctx.getenv(ctx.attr.env)
    if value == None or not value:
        reason = "environment variable %s is unset, so CPS variant (%s, %s) is unavailable" % (
            ctx.attr.env,
            ctx.attr.logical_name,
            ctx.attr.variant,
        )
        if ctx.attr.required:
            fail(reason)
        _write_unavailable_repository(ctx, reason)
        return
    source = ctx.path(value).get_child(ctx.attr.subpath) if ctx.attr.subpath else ctx.path(value)
    if not source.exists or not source.is_dir:
        fail("environment-provided CPS package root is not an existing directory: %s=%s, subpath=%s" % (
            ctx.attr.env,
            value,
            ctx.attr.subpath,
        ))
    ctx.watch_tree(source)
    _link_local_tree(ctx, source)
    _finish_repository(ctx, "env_package", source)

cps_archive_repository = repository_rule(
    implementation = _archive_repository_impl,
    doc = "Materializes a Bazel-owned CPS archive for semantic import testing.",
    attrs = {
        "archive": attr.label(mandatory = True, allow_single_file = True),
        "cps_file": attr.string(),
        "strip_prefix": attr.string(),
        "logical_name": attr.string(mandatory = True),
        "variant": attr.string(mandatory = True),
        "expected_name": attr.string(),
        "configuration_preferences": attr.string_list(),
        "compilation_mode_preferences": attr.string_list_dict(),
        "variant_constraints": attr.label_list(),
        "package_bindings": attr.string_dict(),
        "native_unsupported": attr.string(default = "error"),
        "native_feature_policy": attr.string_dict(),
        "require_global_aspect": attr.bool(default = True),
    },
)

cps_http_archive_repository = repository_rule(
    implementation = _http_archive_repository_impl,
    doc = "Downloads and validates a digest-pinned hermetic CPS package archive.",
    attrs = {
        "urls": attr.string_list(mandatory = True),
        "integrity": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
        "patches": attr.label_list(allow_files = True),
        "patch_strip": attr.int(default = 0),
        "cps_file": attr.string(),
        "logical_name": attr.string(mandatory = True),
        "variant": attr.string(mandatory = True),
        "expected_name": attr.string(),
        "configuration_preferences": attr.string_list(),
        "compilation_mode_preferences": attr.string_list_dict(),
        "variant_constraints": attr.label_list(),
        "package_bindings": attr.string_dict(),
        "native_unsupported": attr.string(default = "error"),
        "native_feature_policy": attr.string_dict(),
        "require_global_aspect": attr.bool(default = True),
    },
)

_LOCAL_COMMON_ATTRS = {
    "cps_file": attr.string(),
    "logical_name": attr.string(mandatory = True),
    "variant": attr.string(mandatory = True),
    "expected_name": attr.string(),
    "configuration_preferences": attr.string_list(),
    "compilation_mode_preferences": attr.string_list_dict(),
    "variant_constraints": attr.label_list(),
    "package_bindings": attr.string_dict(),
    "native_unsupported": attr.string(default = "error"),
    "native_feature_policy": attr.string_dict(),
    "require_global_aspect": attr.bool(default = True),
}

_LOCAL_PACKAGE_ATTRS = dict(_LOCAL_COMMON_ATTRS)
_LOCAL_PACKAGE_ATTRS.update({"path": attr.string(mandatory = True)})
cps_local_package_repository = repository_rule(
    implementation = _local_package_repository_impl,
    doc = "Imports and recursively watches an explicit host-local CPS prefix.",
    attrs = _LOCAL_PACKAGE_ATTRS,
)

_LOCAL_ARCHIVE_ATTRS = dict(_LOCAL_COMMON_ATTRS)
_LOCAL_ARCHIVE_ATTRS.update({
    "path": attr.string(mandatory = True),
    "integrity": attr.string(mandatory = True),
    "strip_prefix": attr.string(),
})
cps_local_archive_repository = repository_rule(
    implementation = _local_archive_repository_impl,
    doc = "Imports and watches an explicit digest-pinned host-local CPS archive.",
    attrs = _LOCAL_ARCHIVE_ATTRS,
)

_ENV_PACKAGE_ATTRS = dict(_LOCAL_COMMON_ATTRS)
_ENV_PACKAGE_ATTRS.update({
    "env": attr.string(mandatory = True),
    "subpath": attr.string(),
    "required": attr.bool(default = True),
})
cps_env_package_repository = repository_rule(
    implementation = _env_package_repository_impl,
    doc = "Imports an explicit environment-provided CPS prefix with invalidation.",
    attrs = _ENV_PACKAGE_ATTRS,
)
