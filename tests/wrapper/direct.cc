#if FOO_COMMON_FLAG != 11 || FOO_CPP_ONLY_FLAG != 17
#error "CPS common/C++ compile flags did not reach direct C++ action"
#endif
#ifdef FOO_C_ONLY_FLAG
#error "C-only CPS flag leaked into C++ action"
#endif
static_assert(sizeof(FOO_TEXT_FLAG) == sizeof("hello world"), "quoted/space response-file flag was corrupted");
#if FOO_ORDER_FLAG != 2
#error "CPS compile flag ordering was not preserved"
#endif
int direct_cpp() { return 2; }
