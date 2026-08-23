#if defined(FOO_COMMON_FLAG) || defined(FOO_C_ONLY_FLAG) || defined(FOO_CPP_ONLY_FLAG)
#error "CPS consumer flags leaked to an unrelated target"
#endif
int unrelated() { return 0; }
