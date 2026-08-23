"""Analysis tests for edge-specific native compatibility diagnostics."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cps//cps:compatibility.bzl", "cps_compatibility_aspect")
load("@rules_cps//cps:compatibility.bzl", "CpsCompatibilityInfo")
load("@rules_cps//cps:providers.bzl", "CpsComponentInfo", "CpsPackageInfo", "CpsUsageInfo")
load("@rules_cc//cc:cc_library.bzl", _cc_library = "cc_library")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _policy_fixture_impl(ctx):
    package = CpsPackageInfo(
        name = "PolicyFixture",
        version = "1",
        compat_version = "1",
        version_schema = "simple",
        cps_version = "0.15.0",
        logical_name = "policy_fixture",
        variant = "test",
        platform = {},
        compatible_with = [],
        default_components = ["core"],
        configurations = [],
        origin = "test",
        source = "PolicyFixture.cps",
        extensions = {},
    )
    component = CpsComponentInfo(
        package = package,
        name = "core",
        type = "interface",
        configuration = None,
        requirements = {},
        file_sets = [],
        cpp_module_metadata = None,
        extensions = {},
        source = "PolicyFixture.cps.components.core",
    )
    usage = CpsUsageInfo(
        compile = {"compile_flags": ["-DPOLICY_FIXTURE"]},
        link = {},
        native_gaps = [{
            "feature": ctx.attr.feature,
            "json_path": "components.core." + (ctx.attr.json_field or ctx.attr.feature),
            "policy": ctx.attr.policy,
            "reason": ctx.attr.reason,
            "source": "PolicyFixture.cps",
            "values": json.decode(ctx.attr.values_json),
        }],
    )
    return [CcInfo(), package, component, usage]

_policy_fixture = rule(
    implementation = _policy_fixture_impl,
    attrs = {
        "feature": attr.string(default = "compile_flags"),
        "json_field": attr.string(),
        "policy": attr.string(mandatory = True),
        "reason": attr.string(default = "test native gap"),
        "values_json": attr.string(default = "[\"-DPOLICY_FIXTURE\"]"),
    },
)

def _native_gap_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "consumes @foo//:headers through a non-CPS-aware C++ rule")
    asserts.expect_failure(env, "Unsupported CPS field: compile_flags")
    asserts.expect_failure(env, "CcInfo cannot propagate arbitrary compiler flags")
    return analysistest.end(env)

_native_gap_test = analysistest.make(
    _native_gap_impl,
    expect_failure = True,
    extra_target_under_test_aspects = [cps_compatibility_aspect],
)

def _duplicate_gap_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "Unsupported CPS field: duplicate_link_plan")
    asserts.expect_failure(env, "CcInfo linking depsets cannot retain deliberate duplicate component placement")
    return analysistest.end(env)

_duplicate_gap_test = analysistest.make(
    _duplicate_gap_impl,
    expect_failure = True,
    extra_target_under_test_aspects = [cps_compatibility_aspect],
)

def _runtime_gap_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "Unsupported CPS field: dyld_requires")
    asserts.expect_failure(env, "CcInfo does not propagate loader-only runtime requirements")
    return analysistest.end(env)

_runtime_gap_test = analysistest.make(
    _runtime_gap_impl,
    expect_failure = True,
    extra_target_under_test_aspects = [cps_compatibility_aspect],
)

def _module_runtime_gap_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "Unsupported CPS field: module_runtime")
    asserts.expect_failure(env, "CcInfo does not place runtime-loaded module artifacts in consumer runfiles")
    asserts.expect_failure(env, "Source: share/cps/Foo/Foo.cps (components.plugin.type)")
    return analysistest.end(env)

_module_runtime_gap_test = analysistest.make(
    _module_runtime_gap_impl,
    expect_failure = True,
    extra_target_under_test_aspects = [cps_compatibility_aspect],
)

def _language_gap_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "Unsupported CPS field: " + ctx.attr.expected_feature)
    asserts.expect_failure(env, "CcInfo cannot select consumer usage by source language")
    asserts.expect_failure(env, "Source: PolicyFixture.cps (components.core." + ctx.attr.expected_json_field + ")")
    return analysistest.end(env)

_language_gap_test = analysistest.make(
    _language_gap_impl,
    expect_failure = True,
    attrs = {
        "expected_feature": attr.string(mandatory = True),
        "expected_json_field": attr.string(mandatory = True),
    },
    extra_target_under_test_aspects = [cps_compatibility_aspect],
)

def _sentinel_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "global compatibility aspect is required but its sentinel is disabled")
    return analysistest.end(env)

_sentinel_test = analysistest.make(
    _sentinel_impl,
    expect_failure = True,
    config_settings = {"@@//cps:compatibility_aspect_enabled": False},
)

def _policy_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(env, CpsCompatibilityInfo in target)
    diagnostics = target[CpsCompatibilityInfo].diagnostics
    asserts.equals(env, 1, len(diagnostics))
    asserts.equals(env, ctx.attr.expected_policy, diagnostics[0]["policy"])
    asserts.equals(env, "compile_flags", diagnostics[0]["feature"])
    message = diagnostics[0]["message"]
    asserts.true(env, message.startswith(ctx.attr.expected_policy.upper() + ":"), message)
    asserts.true(env, "Values: [\"-DPOLICY_FIXTURE\"]" in message, message)
    asserts.true(env, "Reason: test native gap" in message, message)
    asserts.true(env, "To preserve the CPS behavior" in message, message)
    asserts.true(env, "To accept the loss" in message, message)
    asserts.true(env, "Source: PolicyFixture.cps (components.core.compile_flags)" in message, message)
    return analysistest.end(env)

_policy_test = analysistest.make(
    _policy_impl,
    attrs = {"expected_policy": attr.string(mandatory = True)},
    extra_target_under_test_aspects = [cps_compatibility_aspect],
)

def compatibility_test_suite(name):
    """Instantiates native-gap and installation-sentinel failure tests."""
    _native_gap_test(
        name = name + "_native_gap_test",
        target_under_test = ":stock_consumer",
    )
    _sentinel_test(
        name = name + "_sentinel_test",
        target_under_test = "@foo//:headers",
    )
    _duplicate_gap_test(
        name = name + "_duplicate_gap_test",
        target_under_test = ":stock_duplicate_consumer",
    )
    _runtime_gap_test(
        name = name + "_runtime_gap_test",
        target_under_test = ":stock_runtime_consumer",
    )
    _module_runtime_gap_test(
        name = name + "_module_runtime_gap_test",
        target_under_test = ":stock_module_consumer",
    )
    language_tests = []
    for feature, json_field in [
        ("language_specific_includes", "includes"),
        ("language_specific_definitions", "definitions"),
    ]:
        fixture = name + "_" + feature + "_fixture"
        consumer = name + "_" + feature + "_consumer"
        test = name + "_" + feature + "_test"
        _policy_fixture(
            name = fixture,
            feature = feature,
            json_field = json_field,
            policy = "error",
            reason = "CcInfo cannot select consumer usage by source language",
            values_json = json.encode({"cpp": ["fixture-value"]}),
        )
        _cc_library(
            name = consumer,
            deps = [":" + fixture],
            tags = ["manual"],
        )
        _language_gap_test(
            name = test,
            target_under_test = ":" + consumer,
            expected_feature = feature,
            expected_json_field = json_field,
        )
        language_tests.append(test)
    policy_tests = []
    for policy in ["warning", "ignore"]:
        fixture = name + "_" + policy + "_fixture"
        consumer = name + "_" + policy + "_consumer"
        test = name + "_" + policy + "_test"
        _policy_fixture(name = fixture, policy = policy)
        _cc_library(
            name = consumer,
            deps = [":" + fixture],
            tags = ["manual"],
        )
        _policy_test(
            name = test,
            target_under_test = ":" + consumer,
            expected_policy = policy,
        )
        policy_tests.append(test)
    native.test_suite(
        name = name,
        tests = [
            name + "_native_gap_test",
            name + "_sentinel_test",
            name + "_duplicate_gap_test",
            name + "_runtime_gap_test",
            name + "_module_runtime_gap_test",
        ] + language_tests + policy_tests,
    )
