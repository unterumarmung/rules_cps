"""Public rules_cps build APIs."""

load("//cps/private:wrappers.bzl", _cc_binary = "cc_binary", _cc_library = "cc_library", _cc_test = "cc_test")
load("//cps/private:export_rules.bzl", _cps_component = "cps_component", _cps_package = "cps_package")

cc_library = _cc_library
cc_binary = _cc_binary
cc_test = _cc_test
cps_component = _cps_component
cps_package = _cps_package
