cmake_minimum_required(VERSION 4.3)

project(rules_cps_cmake_export_consumer LANGUAGES CXX)

find_package(CMakeExported 1.0 REQUIRED)

add_executable(consumer consumer.cc)
target_link_libraries(consumer PRIVATE CMakeExported::core)
