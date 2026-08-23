"""Reversible CPS-name parsing and Bazel-label encoding."""

def encode_name(name):
    """Encodes a portable CPS component/configuration name for a Bazel label.

    `%` is escaped first, so decoding is unambiguous. CPS portable names cannot
    contain `/` or `@`; rejecting them here prevents a name from changing Bazel
    repository or package identity. The ordering of characters is preserved.
    """
    if type(name) != "string" or not name:
        fail("CPS name must be a non-empty string, got %r" % name)
    if "/" in name or "@" in name:
        fail("CPS portable name may not contain '/' or '@': %r" % name)
    return name.replace("%", "%25").replace(":", "%3A")

def decode_name(encoded):
    """Decodes `encode_name` output, rejecting malformed escape sequences."""
    if type(encoded) != "string" or not encoded:
        fail("encoded CPS name must be a non-empty string, got %r" % encoded)
    pieces = encoded.split("%")
    out = [pieces[0]]
    for index, piece in enumerate(pieces[1:]):
        if piece.startswith("25"):
            out.append("%" + piece[2:])
        elif piece.startswith("3A"):
            out.append(":" + piece[2:])
        else:
            fail("invalid rules_cps name escape number %d in %r" % (index + 1, encoded))
    return "".join(out)

def public_component_label(repository, component):
    """Returns the preference-based public label for a CPS component."""
    return "@%s//:%s" % (repository, encode_name(component))

def public_exact_label(repository, component, configuration):
    """Returns the public label for an exact component configuration."""
    return "@%s//%s:%s" % (
        repository,
        encode_name(component),
        encode_name(configuration),
    )
