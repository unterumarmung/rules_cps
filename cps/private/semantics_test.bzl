"""Unit tests for pure CPS semantics."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(":configuration.bzl", "effective_preferences", "merge_nullable", "select_configuration")
load(":bindings.bzl", "resolve_package_bindings")
load(":graph.bzl", "expand_link_plan", "find_cycle")
load(":names.bzl", "decode_name", "encode_name", "public_exact_label")
load(":model.bzl", "build_semantic_model", "compile_plan", "component_key", "link_plan", "runtime_closure")
load(":merge.bzl", "merge_common_packages", "merge_configuration_fragments")
load(":paths.bzl", "normalize_relative_path", "resolve_cps_path")
load(":requirements.bzl", "parse_component_requirement")
load(":schema.bzl", "parse_cps_json")
load(":schema.bzl", "parse_configuration_fragment_json")
load(":version.bzl", "compare_simple_versions", "parse_simple_version", "version_satisfies")

def _names_test_impl(ctx):
    env = unittest.begin(ctx)
    for name in ["core", "with:colon", "with%percent", "a:%:b", "plus+dot.name"]:
        asserts.equals(env, name, decode_name(encode_name(name)))
    asserts.equals(env, "with%253Acolon", encode_name("with%3Acolon"))
    asserts.equals(env, "@foo//core%3Aapi:debug%3Aasan", public_exact_label("foo", "core:api", "debug:asan"))
    return unittest.end(env)

names_test = unittest.make(_names_test_impl)

def _version_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, [1, 2, 0], parse_simple_version("01.2.000+vendor"))
    asserts.equals(env, 0, compare_simple_versions("1.2", "1.2.0"))
    asserts.equals(env, -1, compare_simple_versions("1.2.9", "1.10"))
    asserts.equals(env, 1, compare_simple_versions("2", "1.999"))
    asserts.true(env, version_satisfies("2.4.1", "2.0", "2.3"))
    asserts.false(env, version_satisfies("2.4.1", "2.0", "1.9"))
    asserts.false(env, version_satisfies(None, None, "1.0"))
    asserts.true(env, version_satisfies("opaque", None, "opaque", "custom"))
    return unittest.end(env)

version_test = unittest.make(_version_test_impl)

def _paths_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, "lib/libfoo.a", normalize_relative_path("share/../lib/./libfoo.a"))
    asserts.equals(env, "include/foo", resolve_cps_path("@prefix@/include/foo", ".", "share/cps/Foo"))
    asserts.equals(env, "share/cps/lib/foo.a", resolve_cps_path("../lib/foo.a", ".", "share/cps/Foo"))
    return unittest.end(env)

paths_test = unittest.make(_paths_test_impl)

def _configuration_test_impl(ctx):
    env = unittest.begin(ctx)
    preferences = effective_preferences(["shared", "debug"], ["debug", "release"], ["release", "static"])
    asserts.equals(env, ["shared", "debug", "release", "static"], preferences)
    asserts.equals(env, "debug", select_configuration(["release", "debug"], preferences))
    asserts.equals(env, "release", select_configuration(["release"], [], exact = "release"))
    asserts.equals(
        env,
        {"nested": {"y": 3}, "list": [9]},
        merge_nullable(
            {"a": 1, "nested": {"x": 1, "y": 2}, "list": [1, 2]},
            {"a": None, "nested": {"y": 3}, "list": [9]},
        ),
    )
    return unittest.end(env)

configuration_test = unittest.make(_configuration_test_impl)

def _requirements_test_impl(ctx):
    env = unittest.begin(ctx)
    relative = parse_component_requirement(":core@@", "Foo")
    asserts.equals(env, "Foo", relative.package)
    asserts.equals(env, "core", relative.component)
    asserts.equals(env, "same", relative.configuration_mode)
    absolute = parse_component_requirement("ZLIB:zlib:static@release:asan", "Foo")
    asserts.equals(env, "ZLIB", absolute.package)
    asserts.equals(env, "zlib:static", absolute.component)
    asserts.equals(env, "release:asan", absolute.configuration)
    asserts.equals(env, "exact", absolute.configuration_mode)
    preferred = parse_component_requirement(":core", "Foo")
    asserts.equals(env, "preferred", preferred.configuration_mode)
    return unittest.end(env)

requirements_test = unittest.make(_requirements_test_impl)

def _edge(target, kind):
    return struct(target = target, kind = kind)

def _graph_test_impl(ctx):
    env = unittest.begin(ctx)
    graph = {
        "A": [_edge("B", "requires"), _edge("B", "link_requires")],
        "B": [_edge("C", "requires")],
        "C": [],
    }
    asserts.equals(env, ["A", "B", "C", "B", "C"], expand_link_plan("A", graph))
    asserts.equals(env, None, find_cycle(graph, ["requires", "link_requires"]))
    cycle_graph = {
        "A": [_edge("B", "requires")],
        "B": [_edge("C", "link_requires")],
        "C": [_edge("A", "requires")],
    }
    cycle = find_cycle(cycle_graph, ["requires", "link_requires"])
    asserts.equals(env, ["B", "C", "A"], [edge.target for edge in cycle])
    return unittest.end(env)

graph_test = unittest.make(_graph_test_impl)

def _schema_test_impl(ctx):
    env = unittest.begin(ctx)
    cmake_package = parse_cps_json("""{
      "name": "CMakeCompat", "cps_version": "0.14.1", "cps_path": "@prefix@/lib/cps/CMakeCompat",
      "components": {"core": {"type": "interface"}}
    }""", "CMakeCompat.cps")
    asserts.equals(env, "0.14.1", cmake_package["cps_version"])
    package = parse_cps_json("""{
      "name": "Foo",
      "cps_version": "0.16.0",
      "cps_path": "@prefix@/share/cps/Foo",
      "version": "2.4.1",
      "x_vendor_note": {"stable": true},
      "requires": {
        "ZLIB": {"version": "1.3", "components": ["zlib"], "hints": ["/ignored"]},
        "Threads": null
      },
      "components": {
        "core": {
          "type": "archive",
          "location": "@prefix@/lib/libfoo.a",
          "includes": {"*": ["@prefix@/include"], "cpp": ["@prefix@/include/cpp"]},
          "definitions": {"*": {"FOO": null, "FOO_ABI": "2"}},
          "requires": [":headers@@"],
          "configurations": {"debug": {"compile_flags": ["-fno-omit-frame-pointer"], "includes": null}},
          "x_component_note": "kept"
        },
        "headers": {"type": "interface"},
        "future": {"type": "future-kind"}
      }
    }""", "Foo.cps")
    asserts.equals(env, "Foo", package["name"])
    asserts.equals(env, "simple", package["version_schema"])
    asserts.equals(env, {"stable": True}, package["extensions"]["x_vendor_note"])
    asserts.equals(env, ["future"], package["ignored_components"])
    asserts.equals(env, None, package["components"]["core"]["definitions"]["*"]["FOO"])
    asserts.equals(env, ["zlib"], package["requires"]["ZLIB"]["components"])
    asserts.equals(env, {}, package["requires"]["Threads"]["extensions"])
    asserts.equals(env, "kept", package["components"]["core"]["extensions"]["x_component_note"])
    asserts.equals(env, None, package["components"]["core"]["configurations"]["debug"]["includes"])
    return unittest.end(env)

schema_test = unittest.make(_schema_test_impl)

def _package(name, components, version = None, compat_version = None, configurations = [], requires = {}):
    return {
        "name": name,
        "components": components,
        "version": version,
        "compat_version": compat_version,
        "version_schema": "simple",
        "configurations": configurations,
        "requires": requires,
        "source": name + ".cps",
    }

def _bindings_test_impl(ctx):
    env = unittest.begin(ctx)
    zlib = _package("ZLIB", {"zlib": {"name": "zlib", "type": "archive"}}, "1.3.2", "1.3")
    consumer = _package("Foo", {}, requires = {
        "ZLIB": {"version": "1.3", "components": ["zlib"], "extensions": {}},
    })
    selected = resolve_package_bindings(
        consumer,
        {"zlib_default": zlib, "zlib_override": zlib},
        {"ZLIB": "zlib_override"},
        {"ZLIB": "zlib_default"},
    )
    asserts.equals(env, "zlib_override", selected["ZLIB"].logical_name)
    asserts.equals(env, "ZLIB", selected["ZLIB"].package["name"])
    return unittest.end(env)

bindings_test = unittest.make(_bindings_test_impl)

def _model_test_impl(ctx):
    env = unittest.begin(ctx)
    packages = {
        "Foo": _package("Foo", {
            "A": {
                "name": "A",
                "type": "interface",
                "configurations": {
                    "debug": {
                        "requires": [":B@@"],
                        "link_requires": [":C"],
                    },
                },
            },
            "B": {
                "name": "B",
                "type": "interface",
                "configurations": {
                    "debug": {"compile_requires": ["Bar:X@release"]},
                },
            },
            "C": {"name": "C", "type": "dylib", "location": "libC.so", "dyld_requires": [":D"]},
            "D": {"name": "D", "type": "dylib", "location": "libD.so", "dyld_requires": [":C"]},
        }),
        "Bar": _package("Bar", {
            "X": {
                "name": "X",
                "type": "interface",
                "configurations": {"release": {}},
            },
        }),
    }
    model = build_semantic_model(packages, ["Foo:A@debug"])
    a = component_key("Foo", "A", "debug")
    b = component_key("Foo", "B", "debug")
    c = component_key("Foo", "C", None)
    d = component_key("Foo", "D", None)
    x = component_key("Bar", "X", "release")
    asserts.equals(env, [a, b, x], compile_plan(a, model.graph))
    asserts.equals(env, [a, b, c], link_plan(a, model.graph))
    asserts.equals(env, [a, b, c, d], runtime_closure(a, model.graph))
    asserts.equals(env, "same", model.graph[a][0].requirement.configuration_mode)
    return unittest.end(env)

model_test = unittest.make(_model_test_impl)

def _scalability_test_impl(ctx):
    env = unittest.begin(ctx)
    packages = {}
    roots = []
    for package_index in range(100):
        package_name = "Synthetic%d" % package_index
        components = {}
        for component_index in range(5):
            component_name = "component%d" % component_index
            components[component_name] = {
                "name": component_name,
                "type": "interface",
                "requires": [":component%d" % (component_index + 1)] if component_index < 4 else [],
            }
        packages[package_name] = _package(package_name, components)
        roots.append(package_name + ":component0")
    model = build_semantic_model(packages, roots)
    asserts.equals(env, 500, len(model.graph))
    asserts.equals(env, 5, len(compile_plan(component_key("Synthetic99", "component0", None), model.graph)))
    return unittest.end(env)

scalability_test = unittest.make(_scalability_test_impl)

def _supplemental_merge_test_impl(ctx):
    env = unittest.begin(ctx)
    base = parse_cps_json("""{
      "name": "Foo", "cps_version": "0.15.0",
      "cps_path": "@prefix@/share/cps/Foo",
      "components": {
        "core": {"type": "archive", "includes": ["@prefix@/include"]}
      }
    }""", "Foo.cps")
    common = parse_cps_json("""{
      "name": "Foo", "cps_version": "0.15.0",
      "cps_path": "@prefix@/share/cps/Foo",
      "components": {"headers": {"type": "interface"}}
    }""", "Foo-headers.cps")
    combined = merge_common_packages(base, [common])
    fragment = parse_configuration_fragment_json("""{
      "name": "Foo", "configuration": "debug",
      "components": {
        "core": {
          "location": "@prefix@/lib/libfoo_debug.a",
          "includes": null,
          "compile_flags": ["-fno-omit-frame-pointer"]
        }
      }
    }""", "Foo@debug.cps")
    combined = merge_configuration_fragments(combined, [fragment])
    asserts.equals(env, ["debug"], combined["configurations"])
    configured = merge_nullable(combined["components"]["core"], combined["components"]["core"]["configurations"]["debug"])
    asserts.true(env, "headers" in combined["components"])
    asserts.false(env, "includes" in configured)
    asserts.equals(env, "@prefix@/lib/libfoo_debug.a", configured["location"])
    asserts.equals(env, ["-fno-omit-frame-pointer"], configured["compile_flags"])
    return unittest.end(env)

supplemental_merge_test = unittest.make(_supplemental_merge_test_impl)

def semantics_test_suite(name):
    unittest.suite(
        name,
        names_test,
        version_test,
        paths_test,
        configuration_test,
        requirements_test,
        graph_test,
        schema_test,
        bindings_test,
        model_test,
        scalability_test,
        supplemental_merge_test,
    )
