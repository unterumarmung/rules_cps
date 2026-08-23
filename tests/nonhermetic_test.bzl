"""Analysis tests for optional environment package availability."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _optional_env_unavailable_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "environment variable RULES_CPS_TEST_DEFINITELY_UNSET_7431 is unset")
    return analysistest.end(env)

_optional_env_unavailable_test = analysistest.make(
    _optional_env_unavailable_impl,
    expect_failure = True,
)

def nonhermetic_test_suite(name):
    """Instantiates environment availability diagnostics tests."""
    _optional_env_unavailable_test(
        name = name + "_optional_unset_test",
        target_under_test = "@optional_env//:core",
    )
    native.test_suite(
        name = name,
        tests = [name + "_optional_unset_test"],
    )
