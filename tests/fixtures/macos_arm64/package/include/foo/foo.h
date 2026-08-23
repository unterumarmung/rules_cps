#ifndef RULES_CPS_TEST_FOO_H_
#define RULES_CPS_TEST_FOO_H_

#ifndef FOO_IMPORTED
#error "CPS consumer definition did not propagate"
#endif

inline int cps_foo_answer() { return 42; }

#endif
