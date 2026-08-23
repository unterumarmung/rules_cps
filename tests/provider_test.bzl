"""Analysis tests for public providers through logical package façades."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cps//cps:providers.bzl", "CpsComponentInfo", "CpsPackageInfo", "CpsRuntimeInfo", "CpsUsageInfo")

def _package_provider_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(env, CpsPackageInfo in target)
    package = target[CpsPackageInfo]
    asserts.equals(env, "Foo", package.name)
    asserts.equals(env, "foo", package.logical_name)
    asserts.equals(env, "1.2.0", package.version)
    asserts.true(env, "tool" in package.components)
    asserts.true(env, package.variant in ["platform_independent", "macos_arm64"])
    return analysistest.end(env)

package_provider_test = analysistest.make(_package_provider_test_impl)

def _component_provider_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    for provider in [CpsPackageInfo, CpsComponentInfo, CpsUsageInfo, CpsRuntimeInfo]:
        asserts.true(env, provider in target)
    component = target[CpsComponentInfo]
    asserts.equals(env, "headers", component.name)
    asserts.equals(env, "interface", component.type)
    asserts.equals(env, "debug", component.configuration)
    asserts.equals(env, "Foo", component.package.name)
    return analysistest.end(env)

component_provider_test = analysistest.make(_component_provider_test_impl)

def _special_component_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    expected_type = ctx.attr.expected_type
    asserts.equals(env, expected_type, target[CpsComponentInfo].type)
    runtime = target[CpsRuntimeInfo]
    if expected_type == "executable":
        asserts.equals(env, 1, len(runtime.files.to_list()))
        asserts.equals(env, 0, len(runtime.modules.to_list()))
    elif expected_type == "symbolic":
        asserts.equals(env, 0, len(runtime.files.to_list()))
    return analysistest.end(env)

special_component_test = analysistest.make(
    _special_component_test_impl,
    attrs = {"expected_type": attr.string(mandatory = True)},
)

def _runtime_closure_test_impl(ctx):
    env = analysistest.begin(ctx)
    runtime = analysistest.target_under_test(env)[CpsRuntimeInfo]
    asserts.equals(env, 1, len(runtime.files.to_list()))
    asserts.equals(env, 1, len(runtime.modules.to_list()))
    asserts.equals(env, ["preferred"], [record["configuration_mode"] for record in runtime.loader_requirements])
    asserts.equals(env, ["plugin"], [record["component"] for record in runtime.loader_requirements])
    return analysistest.end(env)

runtime_closure_test = analysistest.make(_runtime_closure_test_impl)

def _link_plan_test_impl(ctx):
    env = analysistest.begin(ctx)
    plan = analysistest.target_under_test(env)[CpsUsageInfo].link["plan"]
    files = []
    for entry in plan:
        files.extend([file.basename for file in entry["files"]])
    asserts.equals(env, ["libA.a", "libB.a", "libA.a", "libB.a"], files)
    return analysistest.end(env)

link_plan_test = analysistest.make(_link_plan_test_impl)

def _binding_precedence_test_impl(ctx):
    env = analysistest.begin(ctx)
    plan = analysistest.target_under_test(env)[CpsUsageInfo].link["plan"]
    paths = []
    for entry in plan:
        paths.extend([file.path for file in entry["files"]])
    asserts.true(env, any([ctx.attr.expected_repository in path for path in paths]), paths)
    return analysistest.end(env)

binding_precedence_test = analysistest.make(
    _binding_precedence_test_impl,
    attrs = {"expected_repository": attr.string(mandatory = True)},
)

def _missing_exact_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "Exact CPS configuration release is unavailable for component extra")
    return analysistest.end(env)

missing_exact_test = analysistest.make(_missing_exact_test_impl, expect_failure = True)

def _missing_platform_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "No physical variant of logical CPS package requires_custom_platform matches")
    return analysistest.end(env)

missing_platform_test = analysistest.make(_missing_platform_test_impl, expect_failure = True)

def provider_test_suite(name):
    """Instantiates public façade provider tests."""
    package_provider_test(
        name = name + "_package_test",
        target_under_test = "@foo//:@package",
    )
    component_provider_test(
        name = name + "_component_test",
        target_under_test = "@foo//:headers",
    )
    special_component_test(name = name + "_symbolic_test", target_under_test = "@foo//:capability", expected_type = "symbolic")
    special_component_test(name = name + "_executable_test", target_under_test = "@foo//:tool", expected_type = "executable")
    runtime_closure_test(name = name + "_runtime_test", target_under_test = "@foo//:runtime_bundle")
    link_plan_test(name = name + "_link_plan_test", target_under_test = "@cps_link_order//:R")
    binding_precedence_test(name = name + "_package_binding_test", target_under_test = "@bar//:bridge", expected_repository = "internal_foo_macos_arm64")
    binding_precedence_test(name = name + "_global_binding_test", target_under_test = "@bar_global//:bridge", expected_repository = "internal_foo_alias_macos_arm64")
    missing_exact_test(name = name + "_missing_exact_test", target_under_test = "@foo//extra:release")
    missing_platform_test(name = name + "_missing_platform_test", target_under_test = "@requires_custom_platform//:headers")
    native.test_suite(
        name = name,
        tests = [
            name + "_package_test",
            name + "_component_test",
            name + "_symbolic_test",
            name + "_executable_test",
            name + "_runtime_test",
            name + "_link_plan_test",
            name + "_package_binding_test",
            name + "_global_binding_test",
            name + "_missing_exact_test",
            name + "_missing_platform_test",
        ],
    )
