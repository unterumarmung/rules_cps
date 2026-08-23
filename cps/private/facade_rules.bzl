"""Small analysis helpers used by generated logical package repositories."""

def _unavailable_impl(ctx):
    fail(ctx.attr.message)

cps_unavailable = rule(
    implementation = _unavailable_impl,
    doc = "Fails only when a configured select chooses an unavailable CPS variant.",
    attrs = {"message": attr.string(mandatory = True)},
)
