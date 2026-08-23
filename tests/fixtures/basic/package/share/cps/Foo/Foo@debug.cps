{
  "name": "Foo",
  "configuration": "debug",
  "components": {
    "headers": {
      "compile_flags": {
        "*": ["-DFOO_COMMON_FLAG=11", "-DFOO_TEXT_FLAG=\"hello world\"", "-DFOO_ORDER_FLAG=1", "-UFOO_ORDER_FLAG", "-DFOO_ORDER_FLAG=2"],
        "c": ["-DFOO_C_ONLY_FLAG=13"],
        "cpp": ["-DFOO_CPP_ONLY_FLAG=17"]
      },
      "definitions": {
        "*": {
          "FOO_IMPORTED": "2",
          "FOO_VARIANT": "1",
          "FOO_DEBUG": null
        }
      }
    }
  }
}
