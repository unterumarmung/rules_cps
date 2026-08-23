#include <foo/foo.h>

#ifndef FOO_IMPORTED
#error "automatically discovered CPS package did not propagate usage"
#endif

int main() { return cps_foo_answer() == 42 ? 0 : 1; }
