#include <foo/foo.h>

#if FOO_IMPORTED != EXPECTED_FOO_CONFIGURATION
#error "Bazel compilation mode did not select CPS configuration preferences"
#endif

int main() { return cps_foo_answer() == 42 ? 0 : 1; }
