#if FOO_COMMON_FLAG != 11 || FOO_C_ONLY_FLAG != 13
#error "CPS common/C compile flags did not reach direct C action"
#endif
#ifdef FOO_CPP_ONLY_FLAG
#error "C++-only CPS flag leaked into C action"
#endif
int direct_c(void) { return 1; }
