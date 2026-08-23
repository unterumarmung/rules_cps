#if FOO_COMMON_FLAG != 11 || FOO_CPP_ONLY_FLAG != 17
#error "implementation CPS flags did not apply to current wrapper"
#endif
int private_cpp() { return 4; }
