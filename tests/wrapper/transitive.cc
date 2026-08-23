#if FOO_COMMON_FLAG != 11 || FOO_CPP_ONLY_FLAG != 17
#error "transitive CPS consumer flags did not propagate through wrapper"
#endif
int transitive_cpp() { return 3; }
