#include <foo/foo.h>

#ifndef FOO_DEBUG
#error "the exact debug CPS configuration was not selected"
#endif

int main() { return cps_foo_answer() == 42 ? 0 : 1; }
