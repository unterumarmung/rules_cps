cmake_minimum_required(VERSION 4.3)

project(CMakeProduced VERSION 2.1.0 LANGUAGES CXX)

add_library(cmake_produced STATIC produced.cc)
set_target_properties(cmake_produced PROPERTIES EXPORT_NAME core)
target_include_directories(
  cmake_produced
  PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
    "$<INSTALL_INTERFACE:include>"
)
target_compile_definitions(cmake_produced PUBLIC CMAKE_PRODUCED=1)

install(
  TARGETS cmake_produced
  EXPORT CMakeProducedTargets
  ARCHIVE DESTINATION lib
)
install(FILES include/cmake_produced.h DESTINATION include)
install(
  PACKAGE_INFO CMakeProduced
  EXPORT CMakeProducedTargets
  VERSION 2.1.0
  COMPAT_VERSION 2.0.0
  DEFAULT_TARGETS core
)
