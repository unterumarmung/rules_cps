#include <foo/foo.h>
#ifndef FOO_IMPORTED
#error "compile_requires did not propagate compilation context"
#endif
int main() { return cps_foo_answer() == 42 ? 0 : 1; }
