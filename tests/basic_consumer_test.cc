#include <foo/foo.h>

#ifndef FOO_DEBUG
#error "configuration-specific CPS definition did not propagate"
#endif

#ifndef FOO_EXTRA
#error "common supplemental CPS component did not propagate"
#endif

#if FOO_IMPORTED != 2
#error "debug CPS configuration was not selected"
#endif

int main() {
  return cps_foo_answer() == 42 ? 0 : 1;
}
