"""Analysis-failure tests for mandatory CPS semantic diagnostics."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(":bindings.bzl", "resolve_package_bindings")
load(":model.bzl", "build_semantic_model")
load(":paths.bzl", "normalize_relative_path")
load(":schema.bzl", "parse_cps_json")
load(":version.bzl", "version_satisfies")

def _package(name, components, requires = {}):
    return {
        "name": name,
        "components": components,
        "version_schema": "simple",
        "configurations": [],
        "requires": requires,
        "source": name + ".cps",
    }

def _subject_impl(ctx):
    case = ctx.attr.case
    if case == "missing_binding":
        resolve_package_bindings(
            _package("Foo", {}, {"ZLIB": {"extensions": {}}}),
            {},
            {},
            {},
        )
    elif case == "compile_cycle":
        build_semantic_model({
            "Foo": _package("Foo", {
                "A": {"name": "A", "type": "interface", "requires": [":B"]},
                "B": {"name": "B", "type": "interface", "compile_requires": [":A"]},
            }),
        }, ["Foo:A"])
    elif case == "link_cycle":
        build_semantic_model({
            "Foo": _package("Foo", {
                "A": {"name": "A", "type": "interface", "requires": [":B"]},
                "B": {"name": "B", "type": "interface", "link_requires": [":A"]},
            }),
        }, ["Foo:A"])
    elif case == "same_configuration_missing":
        build_semantic_model({
            "Foo": _package("Foo", {
                "A": {
                    "name": "A",
                    "type": "interface",
                    "configurations": {"debug": {"requires": [":B@@"]}},
                },
                "B": {"name": "B", "type": "interface", "configurations": {"release": {}}},
            }),
        }, ["Foo:A@debug"])
    elif case == "unsupported_component":
        build_semantic_model({
            "Foo": _package("Foo", {"java": {"name": "java", "type": "jar"}}),
        }, ["Foo:java"])
    elif case == "missing_configured_location":
        build_semantic_model({
            "Foo": _package("Foo", {
                "lib": {"name": "lib", "type": "archive", "configurations": {"debug": {}}},
            }),
        }, ["Foo:lib@debug"])
    elif case == "path_escape":
        normalize_relative_path("include/../../../outside")
    elif case == "unsupported_version_order":
        version_satisfies("2", "1", "1.5", "rpm")
    elif case == "incompatible_cps_version":
        parse_cps_json("""{
          "name": "Old", "cps_version": "0.14.0", "cps_path": "@prefix@/share/cps/Old",
          "components": {}
        }""", "Old.cps")
    else:
        fail("unknown negative test case %r" % case)
    return []

_subject = rule(
    implementation = _subject_impl,
    attrs = {"case": attr.string(mandatory = True)},
)

def _expected_failure_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.expected)
    return analysistest.end(env)

_expected_failure_test = analysistest.make(
    _expected_failure_impl,
    expect_failure = True,
    attrs = {"expected": attr.string(mandatory = True)},
)

def negative_semantics_test_suite(name):
    """Instantiates semantic failure subjects and their diagnostic assertions."""
    cases = {
        "compile_cycle": "CPS compile cycle detected",
        "incompatible_cps_version": "is incompatible",
        "link_cycle": "CPS link cycle detected",
        "missing_binding": "no explicit package binding exists",
        "missing_configured_location": "has no location after configuration selection",
        "path_escape": "path escapes the package root",
        "same_configuration_missing": "same-configuration requirement",
        "unsupported_component": "unsupported v1 CPS component type jar",
        "unsupported_version_order": "ordered CPS version comparison for schema \"rpm\" is unsupported",
    }
    tests = []
    for case, expected in cases.items():
        subject = name + "_" + case + "_subject"
        test = name + "_" + case + "_test"
        _subject(name = subject, case = case, tags = ["manual"])
        _expected_failure_test(
            name = test,
            target_under_test = subject,
            expected = expected,
        )
        tests.append(test)
    native.test_suite(name = name, tests = tests)
