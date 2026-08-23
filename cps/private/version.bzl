"""CPS package version parsing, ordering, and compatibility."""

_DIGITS = "0123456789"

def _simple_core(version):
    stop = len(version)
    for marker in ["-", "+"]:
        found = version.find(marker)
        if found >= 0 and found < stop:
            stop = found
    return version[:stop]

def parse_simple_version(version):
    """Parses a CPS `simple` version into its numeric ordering tuple.

    CPS suffix text after `-` or `+` is validated as non-empty but does not
    participate in the numeric tuple ordering. Leading zeroes are ignored by
    integer conversion. The returned list is never empty.
    """
    if type(version) != "string" or not version:
        fail("simple CPS version must be a non-empty string, got %r" % version)
    core = _simple_core(version)
    if len(core) < len(version) and len(core) + 1 == len(version):
        fail("simple CPS version suffix must not be empty: %r" % version)
    fields = core.split(".")
    result = []
    for field in fields:
        if not field:
            fail("simple CPS version has an empty numeric field: %r" % version)
        for char in field.elems():
            if char not in _DIGITS:
                fail("simple CPS version has a non-numeric field: %r" % version)
        result.append(int(field))
    return result

def compare_simple_versions(left, right):
    """Returns -1, 0, or 1 using CPS numeric-tuple ordering."""
    lhs = parse_simple_version(left)
    rhs = parse_simple_version(right)
    width = max(len(lhs), len(rhs))
    for index in range(width):
        lv = lhs[index] if index < len(lhs) else 0
        rv = rhs[index] if index < len(rhs) else 0
        if lv < rv:
            return -1
        if lv > rv:
            return 1
    return 0

def version_satisfies(package_version, compat_version, requested, schema = "simple"):
    """Returns whether a CPS package satisfies an exact-version request.

    For `simple`, the requested version must lie inclusively between the oldest
    compatible version and the provided package version. `custom` can only use
    equality. Ordered checks for rpm/dpkg deliberately fail without invoking a
    host package-manager executable.
    """
    if requested == None:
        return True
    if package_version == None:
        return False
    normalized = schema.lower()
    if normalized in ["simple", "semver"]:
        oldest = compat_version if compat_version != None else package_version
        return compare_simple_versions(oldest, requested) <= 0 and compare_simple_versions(requested, package_version) <= 0
    if normalized == "custom":
        return package_version == requested
    if normalized in ["rpm", "dpkg"]:
        if package_version == requested:
            return True
        fail("ordered CPS version comparison for schema %r is unsupported" % schema)
    fail("unknown CPS version schema %r" % schema)
