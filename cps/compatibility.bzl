"""Always-on validation aspect for lossy stock C++ consumption edges."""

load("//cps:providers.bzl", "CpsComponentInfo", "CpsUsageInfo")
load("//cps/private:compatibility_types.bzl", "CpsAwareInfo")
load("//cps/private:names.bzl", "public_component_label")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

CpsCompatibilityInfo = provider(
    doc = "Machine-readable compatibility diagnostics observed on a target.",
    fields = {"diagnostics": "Ordered records with consumer, dependency, feature, policy, and rendered message fields."},
)

def _is_aware(target, ctx):
    if CpsAwareInfo in target:
        return True
    if hasattr(ctx.rule.attr, "aspect_hints"):
        for hint in ctx.rule.attr.aspect_hints:
            if CpsAwareInfo in hint:
                return True
    return False

def _diagnostic(consumer, dependency, component, gap):
    logical_dependency = public_component_label(component.package.logical_name, component.name)
    return """%s: %s consumes %s through a non-CPS-aware C++ rule.

CPS package/component/configuration: %s / %s / %s
Unsupported CPS field: %s
Values: %s
Reason: %s
Source: %s (%s)

To preserve the CPS behavior, use the CPS-aware wrapper:
    load("@rules_cps//cps:defs.bzl", "cc_library")

To accept the loss, set native_unsupported or a matching native_feature_policy entry to "warning" or "ignore".
""" % (
        gap["policy"].upper(),
        consumer,
        logical_dependency,
        component.package.name,
        component.name,
        component.configuration,
        gap["feature"],
        gap["values"],
        gap["reason"],
        gap["source"],
        gap["json_path"],
    )

def _compatibility_aspect_impl(target, ctx):
    diagnostics = []
    if CcInfo not in target or _is_aware(target, ctx):
        return [CpsCompatibilityInfo(diagnostics = diagnostics)]
    for attribute in ["deps", "implementation_deps"]:
        if not hasattr(ctx.rule.attr, attribute):
            continue
        for dependency in getattr(ctx.rule.attr, attribute):
            if CpsUsageInfo not in dependency or CpsComponentInfo not in dependency:
                continue
            for gap in dependency[CpsUsageInfo].native_gaps:
                message = _diagnostic(target.label, dependency.label, dependency[CpsComponentInfo], gap)
                record = {
                    "consumer": str(target.label),
                    "dependency": str(dependency.label),
                    "feature": gap["feature"],
                    "message": message,
                    "policy": gap["policy"],
                }
                diagnostics.append(record)
                if gap["policy"] == "error":
                    fail(message)
                elif gap["policy"] == "warning":
                    print(message)
    return [CpsCompatibilityInfo(diagnostics = diagnostics)]

cps_compatibility_aspect = aspect(
    implementation = _compatibility_aspect_impl,
    doc = "Reports CPS semantics that a non-aware native C++ edge cannot honor.",
    attr_aspects = ["deps", "implementation_deps"],
)
