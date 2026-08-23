{
  "name": "Foo",
  "cps_version": "0.15.0",
  "cps_path": "@prefix@/share/cps/Foo",
  "version": "1.2.0",
  "default_components": ["headers"],
  "components": {
    "headers": {
      "type": "interface",
      "includes": ["@prefix@/include"],
      "definitions": {"*": {"FOO_IMPORTED": "1", "FOO_VARIANT": "2"}},
      "compile_flags": {
        "*": ["-DFOO_COMMON_FLAG=11", "-DFOO_TEXT_FLAG=\"hello world\"", "-DFOO_ORDER_FLAG=1", "-UFOO_ORDER_FLAG", "-DFOO_ORDER_FLAG=2"],
        "c": ["-DFOO_C_ONLY_FLAG=13"],
        "cpp": ["-DFOO_CPP_ONLY_FLAG=17"]
      }
    },
    "static": {
      "type": "archive",
      "location": "@prefix@/lib/libfoo_value.a",
      "requires": [":headers"]
    },
    "dynamic": {
      "type": "dylib",
      "location": "@prefix@/lib/libfoo_dynamic.dylib",
      "requires": [":headers"]
    },
    "plugin": {
      "type": "module",
      "location": "@prefix@/lib/libfoo_plugin.dylib"
    },
    "runtime_bundle": {
      "type": "interface",
      "dyld_requires": [":plugin"]
    },
    "compile_bridge": {
      "type": "interface",
      "compile_requires": [":headers"]
    },
    "link_bridge": {
      "type": "interface",
      "link_requires": [":static"]
    },
    "same_bridge": {
      "type": "interface",
      "requires": [":headers"],
      "configurations": {
        "debug": {
          "requires": [":headers@@"]
        }
      }
    },
    "capability": {
      "type": "symbolic"
    },
    "tool": {
      "type": "executable",
      "location": "@prefix@/bin/foo_tool"
    }
  }
}
