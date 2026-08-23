#include <foo.h>

#ifndef EXPORTED_FOO
#error "CMake did not propagate rules_cps's public definition"
#endif

int main() { return exported_foo() == 5 ? 0 : 1; }
