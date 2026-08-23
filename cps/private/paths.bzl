"""Lexical path normalization used before repository realpath validation."""

def normalize_relative_path(path):
    """Normalizes a package-relative POSIX path and rejects root escape.

    This pure lexical layer deliberately does not claim to validate symlinks;
    repository acquisition must resolve real paths and prove that the result
    remains within the materialized package root.
    """
    if type(path) != "string" or not path:
        fail("package path must be a non-empty string, got %r" % path)
    if path.startswith("/"):
        fail("absolute path is outside the package root: %r" % path)
    parts = []
    for part in path.split("/"):
        if part in ["", "."]:
            continue
        if part == "..":
            if not parts:
                fail("path escapes the package root: %r" % path)
            parts.pop()
        else:
            parts.append(part)
    if not parts:
        return "."
    return "/".join(parts)

def resolve_cps_path(value, prefix, cps_directory):
    """Resolves a CPS path lexically to a path relative to the package root."""
    if value.startswith("@prefix@"):
        tail = value[len("@prefix@"):]
        if tail.startswith("/"):
            tail = tail[1:]
        return normalize_relative_path(tail)
    if value.startswith("/"):
        fail("absolute CPS path is outside hermetic package root %r: %r" % (prefix, value))
    base = cps_directory + "/" + value if cps_directory not in ["", "."] else value
    return normalize_relative_path(base)
