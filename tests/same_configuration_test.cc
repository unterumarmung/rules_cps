#include <foo/foo.h>
#ifndef FOO_DEBUG
#error "@@ did not select the source component configuration on its requirement"
#endif
int main() { return FOO_IMPORTED == 2 ? 0 : 1; }
