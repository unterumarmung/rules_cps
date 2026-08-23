#include <foo/foo.h>

#ifndef FOO_COMMON_FLAG
#error "import and export lost the CPS consumer compile flag"
#endif

#ifndef FOO_DEBUG
#error "import and export lost the selected configuration definition"
#endif

extern "C" int foo_prebuilt_value(void);

int main() {
  return cps_foo_answer() == 42 && foo_prebuilt_value() == 73 ? 0 : 1;
}
