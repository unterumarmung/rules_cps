"""Test-only rules for the duplicate-preserving link-order feasibility spike."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

LinkPlanTestInfo = provider(fields = {"files": "Library files", "order": "Logical order"})

def _direct_static_library(target):
    candidates = []
    for linker_input in target[CcInfo].linking_context.linker_inputs.to_list():
        for library in linker_input.libraries:
            archive = library.static_library
            if archive == None:
                archive = library.pic_static_library
            if archive != None:
                candidates.append(archive)
    if len(candidates) != 1:
        fail("link-order fixture %s must expose exactly one static archive, got %r" % (target.label, candidates))
    return candidates[0]

def _link_plan_impl(ctx):
    by_name = {}
    for target, logical_name in ctx.attr.libraries.items():
        by_name[logical_name] = _direct_static_library(target)
    ordered = []
    for logical_name in ctx.attr.order:
        if logical_name not in by_name:
            fail("unknown logical library %s in test link plan" % logical_name)
        ordered.append(by_name[logical_name])
    response = ctx.actions.declare_file(ctx.label.name + ".params")
    ctx.actions.write(response, "\n".join([json.encode(file.path) for file in ordered]) + "\n")
    return [
        DefaultInfo(files = depset([response])),
        LinkPlanTestInfo(files = ordered, order = ctx.attr.order),
    ]

link_plan = rule(
    implementation = _link_plan_impl,
    attrs = {
        "libraries": attr.label_keyed_string_dict(mandatory = True, providers = [CcInfo]),
        "order": attr.string_list(mandatory = True),
    },
)

def _link_inputs_impl(ctx):
    return [DefaultInfo(files = depset(ctx.attr.plan[LinkPlanTestInfo].files))]

link_inputs = rule(
    implementation = _link_inputs_impl,
    attrs = {"plan": attr.label(mandatory = True, providers = [LinkPlanTestInfo])},
)
