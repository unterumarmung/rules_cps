"""CPS-aware wrappers delegating compile/link actions to public rules_cc rules."""

load("//cps:providers.bzl", "CpsRuntimeInfo", "CpsUsageInfo")
load(":compatibility_types.bzl", "CpsAwareInfo")
load("@rules_cc//cc:cc_binary.bzl", _rules_cc_binary = "cc_binary")
load("@rules_cc//cc:cc_library.bzl", _rules_cc_library = "cc_library")
load("@rules_cc//cc:cc_test.bzl", _rules_cc_test = "cc_test")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_CpsLinkInputsInfo = provider(fields = {"files": "Files named by a wrapper link response"})

def _flags_for_language(usage, language):
    flags = usage.compile.get("compile_flags", [])
    if type(flags) == "list":
        return flags if language == "common" else []
    if language == "common":
        return flags.get("*", [])
    return flags.get(language, [])

def _collect_flags(deps, language):
    result = []
    for dep in deps:
        if CpsUsageInfo in dep:
            result.extend(_flags_for_language(dep[CpsUsageInfo], language))
    return result

def _compile_flags_file_impl(ctx):
    flags = _collect_flags(ctx.attr.deps, ctx.attr.language)
    output = ctx.actions.declare_file(ctx.label.name + ".params")
    # JSON string quoting is accepted by Clang/GCC response-file parsers and
    # preserves whitespace, quotes, and backslashes without shell evaluation.
    ctx.actions.write(output, "\n".join([json.encode(flag) for flag in flags]) + ("\n" if flags else ""))
    return [DefaultInfo(files = depset([output]))]

_compile_flags_file = rule(
    implementation = _compile_flags_file_impl,
    attrs = {
        "deps": attr.label_list(),
        "language": attr.string(mandatory = True, values = ["common", "c", "cpp"]),
    },
)

def _link_plan_file_impl(ctx):
    arguments = []
    inputs = []
    for dep in ctx.attr.deps:
        if CpsUsageInfo not in dep:
            continue
        for entry in dep[CpsUsageInfo].link.get("plan", []):
            arguments.extend(entry.get("flags", []))
            for file in entry.get("files", []):
                arguments.append(file.path)
                inputs.append(file)
    output = ctx.actions.declare_file(ctx.label.name + ".params")
    ctx.actions.write(output, "\n".join([json.encode(argument) for argument in arguments]) + ("\n" if arguments else ""))
    return [DefaultInfo(files = depset([output])), _CpsLinkInputsInfo(files = depset(inputs))]

_link_plan_file = rule(
    implementation = _link_plan_file_impl,
    attrs = {"deps": attr.label_list()},
)

def _link_inputs_impl(ctx):
    return [DefaultInfo(files = ctx.attr.plan[_CpsLinkInputsInfo].files)]

_link_inputs = rule(
    implementation = _link_inputs_impl,
    attrs = {"plan": attr.label(mandatory = True, providers = [_CpsLinkInputsInfo])},
)

def _runtime_inputs_impl(ctx):
    files = []
    transitive = []
    for dep in ctx.attr.deps:
        if CpsRuntimeInfo in dep:
            transitive.extend([dep[CpsRuntimeInfo].files, dep[CpsRuntimeInfo].modules])
    closure = depset(files, transitive = transitive)
    return [DefaultInfo(files = closure, runfiles = ctx.runfiles(transitive_files = closure))]

_runtime_inputs = rule(
    implementation = _runtime_inputs_impl,
    attrs = {"deps": attr.label_list()},
)

def _wrapper_library_impl(ctx):
    native = ctx.attr.native
    public_deps = ctx.attr.public_deps
    common = _collect_flags(public_deps, "common")
    c_flags = _collect_flags(public_deps, "c")
    cpp_flags = _collect_flags(public_deps, "cpp")
    link_plan = []
    for dep in public_deps:
        if CpsUsageInfo in dep:
            link_plan.extend(dep[CpsUsageInfo].link.get("plan", []))
    usage = CpsUsageInfo(
        compile = {
            "compile_flags": {
                "*": common,
                "c": c_flags,
                "cpp": cpp_flags,
            },
        },
        link = {
            "wrapper": str(ctx.label),
            "plan": link_plan,
        },
        native_gaps = [],
    )
    runtime_deps = [dep[CpsRuntimeInfo] for dep in ctx.attr.runtime_deps if CpsRuntimeInfo in dep]
    runtime = CpsRuntimeInfo(
        files = depset(transitive = [info.files for info in runtime_deps]),
        modules = depset(transitive = [info.modules for info in runtime_deps]),
        requirements = [requirement for info in runtime_deps for requirement in info.requirements],
        loader_requirements = [requirement for info in runtime_deps for requirement in info.loader_requirements],
    )
    return [native[DefaultInfo], native[CcInfo], usage, runtime, CpsAwareInfo()]

_wrapper_library = rule(
    implementation = _wrapper_library_impl,
    attrs = {
        "native": attr.label(mandatory = True, providers = [CcInfo]),
        "public_deps": attr.label_list(),
        "runtime_deps": attr.label_list(),
    },
)

def _flag_target_name(name, language):
    return "_rules_cps_%s_%s_flags" % (name, language)

def _emit_flag_files(name, deps):
    targets = []
    for language in ["common", "c", "cpp"]:
        target = _flag_target_name(name, language)
        _compile_flags_file(
            name = target,
            deps = deps,
            language = language,
            visibility = ["//visibility:private"],
            tags = ["manual"],
        )
        targets.append(":" + target)
    return targets

def _compiler_options(name, deps, copts, conlyopts, cxxopts, additional_compiler_inputs):
    flag_targets = _emit_flag_files(name, deps)
    return struct(
        additional_compiler_inputs = additional_compiler_inputs + flag_targets,
        conlyopts = conlyopts + ["@$(location %s)" % flag_targets[1]],
        copts = copts + ["@$(location %s)" % flag_targets[0]],
        cxxopts = cxxopts + ["@$(location %s)" % flag_targets[2]],
    )

def _linker_options(name, deps, linkopts, additional_linker_inputs, tags):
    plan_name = "_rules_cps_%s_link_plan" % name
    inputs_name = "_rules_cps_%s_link_inputs" % name
    _link_plan_file(
        name = plan_name,
        deps = deps,
        visibility = ["//visibility:private"],
        tags = tags + ["manual"],
    )
    _link_inputs(
        name = inputs_name,
        plan = ":" + plan_name,
        visibility = ["//visibility:private"],
        tags = tags + ["manual"],
    )
    return struct(
        additional_linker_inputs = additional_linker_inputs + [":" + plan_name, ":" + inputs_name],
        linkopts = linkopts + ["@$(location :%s)" % plan_name],
    )

def cc_library(
        name,
        deps = [],
        implementation_deps = [],
        copts = [],
        conlyopts = [],
        cxxopts = [],
        additional_compiler_inputs = [],
        linkopts = [],
        additional_linker_inputs = [],
        **kwargs):
    """CPS-aware `cc_library` compatible with ordinary rules_cc usage.

    CPS consumer flags from `deps` and `implementation_deps` apply to this
    target. Only flags from public `deps` are retained in the wrapper's
    `CpsUsageInfo`, so implementation requirements do not leak to consumers.
    Remaining keyword arguments are delegated to public rules_cc `cc_library`.
    """
    all_deps = deps + implementation_deps
    options = _compiler_options(name, all_deps, copts, conlyopts, cxxopts, additional_compiler_inputs)
    native_name = "_rules_cps_%s_native" % name
    user_visibility = kwargs.pop("visibility", None)
    user_tags = kwargs.pop("tags", [])
    linker = _linker_options(name, all_deps, linkopts, additional_linker_inputs, user_tags)
    _rules_cc_library(
        name = native_name,
        deps = deps,
        implementation_deps = implementation_deps,
        copts = options.copts,
        conlyopts = options.conlyopts,
        cxxopts = options.cxxopts,
        additional_compiler_inputs = options.additional_compiler_inputs,
        additional_linker_inputs = linker.additional_linker_inputs,
        linkopts = linker.linkopts,
        visibility = ["//visibility:private"],
        tags = user_tags + ["manual"],
        **kwargs
    )
    wrapper_args = {
        "name": name,
        "native": ":" + native_name,
        "public_deps": deps,
        "runtime_deps": all_deps,
        "tags": user_tags,
    }
    if user_visibility != None:
        wrapper_args["visibility"] = user_visibility
    _wrapper_library(**wrapper_args)

def _cc_executable(rule, name, deps, copts, conlyopts, cxxopts, additional_compiler_inputs, linkopts, additional_linker_inputs, kwargs):
    options = _compiler_options(name, deps, copts, conlyopts, cxxopts, additional_compiler_inputs)
    aspect_hints = kwargs.pop("aspect_hints", [])
    tags = kwargs.get("tags", [])
    linker = _linker_options(name, deps, linkopts, additional_linker_inputs, tags)
    runtime_name = "_rules_cps_%s_runtime" % name
    _runtime_inputs(
        name = runtime_name,
        deps = deps,
        visibility = ["//visibility:private"],
        tags = tags + ["manual"],
    )
    data = kwargs.pop("data", [])
    rule(
        name = name,
        deps = deps,
        copts = options.copts,
        conlyopts = options.conlyopts,
        cxxopts = options.cxxopts,
        additional_compiler_inputs = options.additional_compiler_inputs,
        additional_linker_inputs = linker.additional_linker_inputs,
        linkopts = linker.linkopts,
        data = data + [":" + runtime_name],
        aspect_hints = aspect_hints + ["@rules_cps//cps:_aware_hint"],
        **kwargs
    )

def cc_binary(name, deps = [], copts = [], conlyopts = [], cxxopts = [], additional_compiler_inputs = [], linkopts = [], additional_linker_inputs = [], **kwargs):
    """CPS-aware `cc_binary` delegating actions to public rules_cc."""
    _cc_executable(_rules_cc_binary, name, deps, copts, conlyopts, cxxopts, additional_compiler_inputs, linkopts, additional_linker_inputs, kwargs)

def cc_test(name, deps = [], copts = [], conlyopts = [], cxxopts = [], additional_compiler_inputs = [], linkopts = [], additional_linker_inputs = [], **kwargs):
    """CPS-aware `cc_test` delegating actions to public rules_cc."""
    _cc_executable(_rules_cc_test, name, deps, copts, conlyopts, cxxopts, additional_compiler_inputs, linkopts, additional_linker_inputs, kwargs)
