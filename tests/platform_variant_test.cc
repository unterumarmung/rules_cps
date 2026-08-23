#include <foo/foo.h>

#if FOO_VARIANT != EXPECTED_FOO_VARIANT
#error "Bazel platform did not select the expected physical CPS variant"
#endif

int main() { return cps_foo_answer() == 42 ? 0 : 1; }
