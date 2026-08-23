#include <foo/foo.h>

#ifndef RULES_CPS_HTTP_PATCHED
#error "the HTTP archive patch was not applied"
#endif

int main() { return cps_foo_answer() == 42 ? 0 : 1; }
