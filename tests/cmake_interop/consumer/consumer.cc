#include <cmake_produced.h>

#ifndef CMAKE_PRODUCED
#error "rules_cps did not propagate CMake's public definition"
#endif

int main() { return cmake_produced_value() == 17 ? 0 : 1; }
