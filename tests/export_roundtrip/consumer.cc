#include <foo.h>

#ifndef EXPORTED_CONSUMER
#error "export/import round trip lost the consumer compile flag"
#endif

int main() { return exported_foo() == 5 ? 0 : 1; }
