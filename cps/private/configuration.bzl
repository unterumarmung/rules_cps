"""Deterministic CPS configuration preference and overlay helpers."""

def ordered_unique(values):
    """Returns first occurrences in input order without depset reordering."""
    seen = {}
    result = []
    for value in values:
        if value not in seen:
            seen[value] = True
            result.append(value)
    return result

def effective_preferences(base, mode_preferences, fallback):
    """Builds ordered preferences: explicit, compilation-mode, then CPS fallback."""
    return ordered_unique(base + mode_preferences + fallback)

def select_configuration(available, preferences, exact = None):
    """Selects an exact configuration or the first available preference."""
    if exact != None:
        if exact not in available:
            fail("requested exact CPS configuration %r is unavailable; available: %r" % (exact, available))
        return exact
    for preference in preferences:
        if preference in available:
            return preference
    return None

def merge_nullable(base, overlay):
    """Merges a CPS configuration overlay, with null suppressing fallback.

    CPS selects each component attribute independently: a configuration value
    replaces the entire base attribute rather than recursively merging maps.
    A null overlay removes the inherited attribute. Null values nested inside a
    non-null attribute (for example a valueless compile definition) are retained.
    """
    result = dict(base)
    for key, value in overlay.items():
        if value == None:
            result.pop(key, None)
        else:
            result[key] = value
    return result
