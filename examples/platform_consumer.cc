#include <foo/foo.h>

#if FOO_VARIANT != 1 && FOO_VARIANT != 2
#error "no supported physical package variant was selected"
#endif

int main() { return cps_foo_answer() == 42 ? 0 : 1; }
