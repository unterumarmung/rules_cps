cmake_minimum_required(VERSION 4.3)

project(rules_cps_export_roundtrip LANGUAGES CXX)

find_package(RoundTrip 1.0 REQUIRED)

add_executable(consumer cmake_consumer.cc)
target_link_libraries(consumer PRIVATE RoundTrip::core)
