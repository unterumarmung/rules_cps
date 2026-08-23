#include <foo/foo.h>

#ifndef FOO_CPP_ONLY_FLAG
#error "the CPS C++ consumer flag did not reach the wrapper action"
#endif

int wrapped_answer() { return cps_foo_answer(); }
