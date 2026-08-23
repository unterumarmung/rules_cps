"""Explicit CPS package binding and requirement validation."""

load(":version.bzl", "version_satisfies")

def resolve_package_bindings(package, packages_by_logical_name, package_bindings, default_bindings):
    """Resolves and validates this package's declared external requirements.

    Package-specific bindings take precedence over global defaults. No search or
    fallback acquisition occurs. The result maps required CPS identities to
    records containing the bound logical name and normalized selected package.
    """
    resolved = {}
    for required_name in sorted(package.get("requires", {}).keys()):
        requirement = package["requires"][required_name]
        logical_name = package_bindings.get(required_name, default_bindings.get(required_name))
        if logical_name == None:
            fail("%s requires CPS package %s, but no explicit package binding exists" % (package["name"], required_name))
        if logical_name not in packages_by_logical_name:
            fail("%s binds required CPS package %s to unknown logical rules_cps package %s" % (package["name"], required_name, logical_name))
        selected = packages_by_logical_name[logical_name]
        if selected["name"] != required_name:
            fail("%s requires CPS package %s, but logical package %s selected CPS identity %s" % (
                package["name"],
                required_name,
                logical_name,
                selected["name"],
            ))
        missing = [component for component in requirement.get("components", []) if component not in selected["components"]]
        if missing:
            fail("%s requires components %r from CPS package %s, but logical package %s does not provide them" % (
                package["name"],
                missing,
                required_name,
                logical_name,
            ))
        requested = requirement.get("version")
        if not version_satisfies(
            selected.get("version"),
            selected.get("compat_version"),
            requested,
            selected.get("version_schema", "simple"),
        ):
            fail("%s requires CPS package %s version %s; logical package %s provides %s with compatibility floor %s (%s schema)" % (
                package["name"],
                required_name,
                requested,
                logical_name,
                selected.get("version"),
                selected.get("compat_version", selected.get("version")),
                selected.get("version_schema", "simple"),
            ))
        resolved[required_name] = struct(
            logical_name = logical_name,
            package = selected,
            requirement = requirement,
        )
    return resolved
