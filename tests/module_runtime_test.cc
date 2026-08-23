#include <cstdlib>
#include <dirent.h>
#include <string>
#include <sys/stat.h>

static bool contains(const std::string& directory, const std::string& expected) {
  DIR* handle = opendir(directory.c_str());
  if (handle == nullptr) return false;
  while (dirent* entry = readdir(handle)) {
    const std::string name = entry->d_name;
    if (name == "." || name == "..") continue;
    if (name == expected) {
      closedir(handle);
      return true;
    }
    const std::string path = directory + "/" + name;
    struct stat status;
    if (lstat(path.c_str(), &status) == 0 && S_ISDIR(status.st_mode) &&
        contains(path, expected)) {
      closedir(handle);
      return true;
    }
  }
  closedir(handle);
  return false;
}

int main() {
  const char* root = std::getenv("RUNFILES_DIR");
  if (root == nullptr) root = std::getenv("TEST_SRCDIR");
  if (root == nullptr) return 2;
#ifdef __APPLE__
  const std::string expected = "libfoo_plugin.dylib";
#else
  const std::string expected = "libfoo_plugin.so";
#endif
  return contains(root, expected) ? 0 : 1;
}
