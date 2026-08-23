#ifdef FOO_COMMON_FLAG
#error "implementation-only CPS flags leaked to a public consumer"
#endif
int private_consumer_cpp() { return 5; }
