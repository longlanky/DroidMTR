cmake_minimum_required(VERSION 3.16)
project(dmtr_host C)

add_library(dmtr SHARED dmtr_engine.c)
target_compile_options(dmtr PRIVATE -std=c17 -O2 -Wall -Wextra)
target_link_libraries(dmtr m pthread)

add_executable(dmtr_cli dmtr_cli.c)
target_link_libraries(dmtr_cli dmtr m pthread)
