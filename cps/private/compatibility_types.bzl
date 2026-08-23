"""Private capability marker shared by wrappers and the compatibility aspect."""

CpsAwareInfo = provider(doc = "Private marker for a CPS-aware target or aspect hint.")

def _aware_hint_impl(ctx):
    return [CpsAwareInfo()]

cps_aware_hint = rule(
    implementation = _aware_hint_impl,
    doc = "Produces the private CPS-aware aspect capability marker.",
)
