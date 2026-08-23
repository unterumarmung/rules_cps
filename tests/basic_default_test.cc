#include <foo/foo.h>

#if FOO_IMPORTED != 2
#error "default component did not select the configured CPS variant"
#endif

int main() { return cps_foo_answer() == 42 ? 0 : 1; }
