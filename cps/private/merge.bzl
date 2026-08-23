"""Deterministic merging of common and configuration-specific CPS files."""

load(":configuration.bzl", "ordered_unique")

def _merge_map_without_conflicts(destination, incoming, description, source):
    result = dict(destination)
    for key, value in incoming.items():
        if key in result and result[key] != value:
            fail("conflicting %s %r while merging supplemental CPS %s" % (description, key, source))
        result[key] = value
    return result

def merge_common_packages(base, supplements):
    """Appends normalized common supplemental packages in caller-supplied order.

    Component and package-requirement identities must be disjoint or identical;
    silent replacement would make the package depend on filesystem enumeration
    order. Ordered package configuration/default lists use first occurrence.
    """
    result = dict(base)
    result["components"] = dict(base["components"])
    result["requires"] = dict(base.get("requires", {}))
    result["extensions"] = dict(base.get("extensions", {}))
    result["ignored_components"] = list(base.get("ignored_components", []))
    for supplement in supplements:
        if supplement["name"] != result["name"]:
            fail("supplemental CPS %s has package identity %s; expected %s" % (
                supplement["source"],
                supplement["name"],
                result["name"],
            ))
        for field in ["cps_version", "cps_path", "prefix", "version", "compat_version", "version_schema", "platform"]:
            if supplement.get(field) != None and result.get(field) != None and supplement[field] != result[field]:
                fail("supplemental CPS %s conflicts with base package field %s" % (supplement["source"], field))
        result["components"] = _merge_map_without_conflicts(
            result["components"],
            supplement["components"],
            "component",
            supplement["source"],
        )
        result["requires"] = _merge_map_without_conflicts(
            result["requires"],
            supplement.get("requires", {}),
            "package requirement",
            supplement["source"],
        )
        result["extensions"] = _merge_map_without_conflicts(
            result["extensions"],
            supplement.get("extensions", {}),
            "extension",
            supplement["source"],
        )
        result["configurations"] = ordered_unique(result.get("configurations", []) + supplement.get("configurations", []))
        result["default_components"] = ordered_unique(result.get("default_components", []) + supplement.get("default_components", []))
        result["ignored_components"].extend(supplement.get("ignored_components", []))
    return result

def merge_configuration_fragments(base, fragments):
    """Adds configuration-specific fragments in deterministic input order.

    Later fragments replace an earlier value for the same component attribute,
    including null. The repository layer supplies lexical filename order; this
    is documented in ADR 0001 because CPS leaves supplemental append order to
    implementations.
    """
    result = dict(base)
    result["components"] = {name: dict(component) for name, component in base["components"].items()}
    result["configurations"] = list(base.get("configurations", []))
    for fragment in fragments:
        if fragment["name"] != result["name"]:
            fail("configuration CPS %s has package identity %s; expected %s" % (
                fragment["source"],
                fragment["name"],
                result["name"],
            ))
        configuration = fragment["configuration"]
        result["configurations"] = ordered_unique(result["configurations"] + [configuration])
        for name, overlay in fragment["components"].items():
            if name not in result["components"]:
                fail("configuration CPS %s refers to missing component %s" % (fragment["source"], name))
            component = result["components"][name]
            configurations = dict(component.get("configurations", {}))
            combined = dict(configurations.get(configuration, {}))
            combined.update(overlay)
            configurations[configuration] = combined
            component["configurations"] = configurations
    return result
