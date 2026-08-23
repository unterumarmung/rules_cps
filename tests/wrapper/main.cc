#if FOO_COMMON_FLAG != 11 || FOO_CPP_ONLY_FLAG != 17
#error "transitive CPS flags did not reach final wrapper test"
#endif
int main() { return 0; }
