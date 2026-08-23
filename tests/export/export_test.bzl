"""Analysis assertions for the public CPS export package layout."""

load("//cps:providers.bzl", "CpsPackageLayoutInfo")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _two_archives_impl(ctx):
    first = ctx.actions.declare_file(ctx.label.name + "_one.a")
    second = ctx.actions.declare_file(ctx.label.name + "_two.a")
    ctx.actions.write(first, "")
    ctx.actions.write(second, "")
    return [DefaultInfo(files = depset([first, second]))]

two_archives = rule(implementation = _two_archives_impl)

def _layout_impl(ctx):
    env = analysistest.begin(ctx)
    info = analysistest.target_under_test(env)[CpsPackageLayoutInfo]
    asserts.equals(env, "ExportedFoo", info.package["name"])
    asserts.equals(env, [
        "include/foo/foo.h",
        "lib/libexported_foo.a",
        "share/cps/ExportedFoo/ExportedFoo.cps",
    ], [entry.destination for entry in info.entries])
    return analysistest.end(env)

_layout_test = analysistest.make(_layout_impl)

def _ambiguous_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "multiple candidate archive artifacts")
    asserts.expect_failure(env, "unambiguous DefaultInfo")
    return analysistest.end(env)

_ambiguous_test = analysistest.make(_ambiguous_impl, expect_failure = True)

def _duplicate_destination_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "duplicate export destination lib/libexported_foo.a")
    return analysistest.end(env)

_duplicate_destination_test = analysistest.make(_duplicate_destination_impl, expect_failure = True)

def _escaping_symlink_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "path escapes the package root")
    return analysistest.end(env)

_escaping_symlink_test = analysistest.make(_escaping_symlink_impl, expect_failure = True)

def export_test_suite(name):
    _layout_test(name = name + "_layout_test", target_under_test = ":package")
    _ambiguous_test(name = name + "_ambiguous_test", target_under_test = ":ambiguous_component")
    _duplicate_destination_test(name = name + "_duplicate_destination_test", target_under_test = ":duplicate_destination_package")
    _escaping_symlink_test(name = name + "_escaping_symlink_test", target_under_test = ":escaping_symlink_package")
