"""CPS 0.15 JSON validation and normalization.

This module validates declarative data only. It never resolves paths, package
bindings, platform variants, or component graphs; those phases own contextual
errors after schema normalization.
"""

_PACKAGE_FIELDS = {
    "compat_version": True,
    "components": True,
    "configuration": True,
    "configurations": True,
    "cps_path": True,
    "cps_version": True,
    "default_components": True,
    "name": True,
    "platform": True,
    "prefix": True,
    "requires": True,
    "version": True,
    "version_schema": True,
}

_COMPONENT_FIELDS = {
    "compile_features": True,
    "compile_flags": True,
    "compile_requires": True,
    "configurations": True,
    "cpp_module_metadata": True,
    "definitions": True,
    "dyld_requires": True,
    "embeds": True,
    "file_sets": True,
    "includes": True,
    "link_features": True,
    "link_flags": True,
    "link_languages": True,
    "link_libraries": True,
    "link_location": True,
    "link_requires": True,
    "location": True,
    "requires": True,
    "type": True,
}

_KNOWN_COMPONENT_TYPES = {
    "archive": True,
    "dylib": True,
    "executable": True,
    "interface": True,
    "jar": True,
    "module": True,
    "symbolic": True,
}

_LIST_USAGE_FIELDS = [
    "compile_features",
    "compile_requires",
    "dyld_requires",
    "link_features",
    "link_flags",
    "link_languages",
    "link_libraries",
    "link_requires",
    "requires",
]

def _fail_type(path, expected, value):
    fail("%s must be %s, got %s" % (path, expected, type(value)))

def _require_type(value, expected, path):
    if type(value) != expected:
        _fail_type(path, expected, value)

def _optional_string(value, path):
    if value != None:
        _require_type(value, "string", path)

def _string_list(value, path):
    _require_type(value, "list", path)
    result = []
    for index, item in enumerate(value):
        _require_type(item, "string", "%s[%d]" % (path, index))
        result.append(item)
    return result

def _extensions(value, known):
    return {key: item for key, item in value.items() if key not in known}

def _validate_language_lists(value, path):
    if type(value) == "list":
        return _string_list(value, path)
    _require_type(value, "dict", path)
    return {language: _string_list(items, "%s.%s" % (path, language)) for language, items in value.items()}

def _validate_definitions(value, path):
    _require_type(value, "dict", path)
    result = {}
    for language, definitions in value.items():
        _require_type(language, "string", path + " language key")
        _require_type(definitions, "dict", "%s.%s" % (path, language))
        normalized = {}
        for name, definition_value in definitions.items():
            _require_type(name, "string", "%s.%s definition key" % (path, language))
            if definition_value != None:
                _require_type(definition_value, "string", "%s.%s.%s" % (path, language, name))
            normalized[name] = definition_value
        result[language] = normalized
    return result

def _normalize_fileset(value, path):
    _require_type(value, "dict", path)
    for required in ["type", "root", "files"]:
        if required not in value or value[required] == None:
            fail("%s.%s is required" % (path, required))
    _require_type(value["type"], "string", path + ".type")
    _require_type(value["root"], "string", path + ".root")
    files = _string_list(value["files"], path + ".files")
    return {
        "type": value["type"],
        "root": value["root"],
        "files": files,
        "extensions": _extensions(value, {"type": True, "root": True, "files": True}),
    }

def _normalize_usage(value, path, allow_type, preserve_null = False):
    _require_type(value, "dict", path)
    result = {}
    for field in _LIST_USAGE_FIELDS:
        if field in value:
            if value[field] == None:
                if preserve_null:
                    result[field] = None
            else:
                result[field] = _string_list(value[field], path + "." + field)
    for field in ["compile_flags", "includes", "embeds"]:
        if field in value:
            if value[field] == None:
                if preserve_null:
                    result[field] = None
            else:
                result[field] = _validate_language_lists(value[field], path + "." + field)
    if "definitions" in value:
        if value["definitions"] == None:
            if preserve_null:
                result["definitions"] = None
        else:
            result["definitions"] = _validate_definitions(value["definitions"], path + ".definitions")
    for field in ["location", "link_location", "cpp_module_metadata"]:
        if field in value:
            if value[field] == None:
                if preserve_null:
                    result[field] = None
            else:
                _require_type(value[field], "string", path + "." + field)
                result[field] = value[field]
    if allow_type and "type" in value and value["type"] != None:
        _require_type(value["type"], "string", path + ".type")
        result["type"] = value["type"]
    return result

def _normalize_component(name, value, path):
    _require_type(value, "dict", path)
    if "type" not in value or value["type"] == None:
        fail("%s.type is required" % path)
    _require_type(value["type"], "string", path + ".type")
    component_type = value["type"]
    if component_type not in _KNOWN_COMPONENT_TYPES:
        # CPS requires parsers to ignore unrecognized component types.
        return None
    result = _normalize_usage(value, path, True)
    result["name"] = name
    result["type"] = component_type
    if "file_sets" in value and value["file_sets"] != None:
        _require_type(value["file_sets"], "list", path + ".file_sets")
        result["file_sets"] = [
            _normalize_fileset(item, "%s.file_sets[%d]" % (path, index))
            for index, item in enumerate(value["file_sets"])
        ]
    if "configurations" in value and value["configurations"] != None:
        _require_type(value["configurations"], "dict", path + ".configurations")
        configurations = {}
        for configuration, overlay in value["configurations"].items():
            _require_type(configuration, "string", path + ".configurations key")
            configurations[configuration] = _normalize_usage(
                overlay,
                "%s.configurations.%s" % (path, configuration),
                False,
                preserve_null = True,
            )
        result["configurations"] = configurations
    result["extensions"] = _extensions(value, _COMPONENT_FIELDS)
    return result

def _normalize_requirement(value, path):
    if value == None:
        value = {}
    _require_type(value, "dict", path)
    result = {}
    for field in ["version"]:
        if field in value and value[field] != None:
            _require_type(value[field], "string", path + "." + field)
            result[field] = value[field]
    for field in ["components", "hints"]:
        if field in value and value[field] != None:
            result[field] = _string_list(value[field], path + "." + field)
    result["extensions"] = _extensions(value, {"version": True, "components": True, "hints": True})
    return result

def _parse_cps_version(value, path):
    _require_type(value, "string", path)
    pieces = value.split(".")
    if len(pieces) < 2:
        fail("%s must contain CPS major and minor versions, got %r" % (path, value))
    major = int(pieces[0]) if pieces[0].isdigit() else -1
    minor = int(pieces[1]) if pieces[1].isdigit() else -1
    patch = int(pieces[2]) if len(pieces) > 2 and pieces[2].isdigit() else -1
    cmake_compat = major == 0 and minor == 14 and patch == 1
    if not cmake_compat and (major != 0 or minor < 15):
        fail("%s %r is incompatible; rules_cps v1 supports CPS 0.15 and later compatible 0.x minors, plus the CPS 0.14.1 CMake interoperability profile" % (path, value))

def normalize_package(value, source = "<memory>"):
    """Validates and normalizes a decoded CPS 0.15 package object.

    Unknown package/component attributes are retained under `extensions` and do
    not invalidate the document. Null optionals are treated as absent. Unknown
    component types are ignored as required by CPS; known-but-v1-unsupported
    types such as `jar` remain visible for later usage-policy diagnostics.
    """
    _require_type(value, "dict", source)
    for required in ["name", "cps_version", "components"]:
        if required not in value or value[required] == None:
            fail("%s: required CPS package field %r is missing" % (source, required))
    _require_type(value["name"], "string", source + ".name")
    _parse_cps_version(value["cps_version"], source + ".cps_version")
    _require_type(value["components"], "dict", source + ".components")
    has_cps_path = "cps_path" in value and value["cps_path"] != None
    has_prefix = "prefix" in value and value["prefix"] != None
    if has_cps_path == has_prefix:
        fail("%s: exactly one of cps_path or prefix is required" % source)

    result = {
        "name": value["name"],
        "cps_version": value["cps_version"],
        "source": source,
    }
    for field in ["cps_path", "prefix", "version", "compat_version", "version_schema", "configuration"]:
        if field in value and value[field] != None:
            _require_type(value[field], "string", source + "." + field)
            result[field] = value[field]
    result["version_schema"] = result.get("version_schema", "simple")
    for field in ["configurations", "default_components"]:
        if field in value and value[field] != None:
            result[field] = _string_list(value[field], source + "." + field)
        else:
            result[field] = []
    components = {}
    ignored = []
    for name, component in value["components"].items():
        _require_type(name, "string", source + ".components key")
        normalized = _normalize_component(name, component, "%s.components.%s" % (source, name))
        if normalized == None:
            ignored.append(name)
        else:
            components[name] = normalized
    result["components"] = components
    result["ignored_components"] = ignored
    if "requires" in value and value["requires"] != None:
        _require_type(value["requires"], "dict", source + ".requires")
        result["requires"] = {
            name: _normalize_requirement(requirement, "%s.requires.%s" % (source, name))
            for name, requirement in value["requires"].items()
        }
    else:
        result["requires"] = {}
    if "platform" in value and value["platform"] != None:
        _require_type(value["platform"], "dict", source + ".platform")
        result["platform"] = dict(value["platform"])
    else:
        result["platform"] = {}
    result["extensions"] = _extensions(value, _PACKAGE_FIELDS)
    return result

def parse_cps_json(content, source = "<memory>"):
    """Decodes CPS JSON text and returns `normalize_package` output."""
    if type(content) != "string":
        _fail_type(source, "string JSON content", content)
    return normalize_package(json.decode(content), source)

def normalize_configuration_fragment(value, source = "<memory>"):
    """Normalizes a configuration-specific supplemental CPS document.

    Such documents may define only package `name`, `configuration`, and
    `components` among normative package keys. Component entries contain
    configuration attributes directly and preserve null to suppress fallback.
    """
    _require_type(value, "dict", source)
    for required in ["name", "configuration", "components"]:
        if required not in value or value[required] == None:
            fail("%s: configuration-specific CPS field %r is required" % (source, required))
    _require_type(value["name"], "string", source + ".name")
    _require_type(value["configuration"], "string", source + ".configuration")
    _require_type(value["components"], "dict", source + ".components")
    forbidden = [
        key
        for key in value.keys()
        if key in _PACKAGE_FIELDS and key not in ["name", "configuration", "components"] and value[key] != None
    ]
    if forbidden:
        fail("%s: configuration-specific CPS contains forbidden package fields %r" % (source, sorted(forbidden)))
    components = {}
    for name, overlay in value["components"].items():
        _require_type(name, "string", source + ".components key")
        components[name] = _normalize_usage(
            overlay,
            "%s.components.%s" % (source, name),
            False,
            preserve_null = True,
        )
    return {
        "name": value["name"],
        "configuration": value["configuration"],
        "components": components,
        "extensions": _extensions(value, {"name": True, "configuration": True, "components": True}),
        "source": source,
    }

def parse_configuration_fragment_json(content, source = "<memory>"):
    """Decodes configuration-specific CPS JSON and returns a normalized fragment."""
    if type(content) != "string":
        _fail_type(source, "string JSON content", content)
    return normalize_configuration_fragment(json.decode(content), source)
