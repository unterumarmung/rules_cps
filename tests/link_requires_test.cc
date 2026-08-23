extern "C" int foo_prebuilt_value(void);
int main() { return foo_prebuilt_value() == 73 ? 0 : 1; }
