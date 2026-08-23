"""CPS component requirement parsing with configuration intent preserved."""

def parse_component_requirement(specification, current_package):
    """Parses a CPS component specification into a normalized record.

    The configuration mode is one of `preferred`, `exact`, or `same`; `@@` is
    never flattened into ordinary package preferences.
    """
    if type(specification) != "string" or not specification:
        fail("CPS component requirement must be a non-empty string, got %r" % specification)
    at = specification.find("@")
    reference = specification if at < 0 else specification[:at]
    configuration = None if at < 0 else specification[at + 1:]
    if at >= 0 and configuration != "@" and "@" in configuration:
        fail("invalid CPS component requirement %r" % specification)

    # Package names may not contain ':', while component names may. Therefore
    # only the first colon is structural and the remainder belongs to the
    # component name unchanged.
    colon = reference.find(":")
    if colon < 0:
        package = current_package
        component = reference
    else:
        package = reference[:colon] if colon > 0 else current_package
        component = reference[colon + 1:]

    mode = "preferred"
    if configuration == "@":
        configuration = None
        mode = "same"
    elif configuration != None:
        if not configuration:
            fail("empty CPS configuration in requirement %r" % specification)
        mode = "exact"
    if not package or not component:
        fail("CPS component requirement must identify a component: %r" % specification)
    return struct(
        package = package,
        component = component,
        configuration = configuration,
        configuration_mode = mode,
        source = specification,
    )
