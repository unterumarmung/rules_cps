#include <foo/foo.h>

#ifndef FOO_DEBUG
#error "exact debug CPS configuration did not propagate"
#endif

#if FOO_IMPORTED != 2
#error "wrong exact CPS configuration selected"
#endif

int main() { return cps_foo_answer() == 42 ? 0 : 1; }
