cmake_minimum_required(VERSION 3.22.1)
project(dmtr C)

set(DMTR_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../../../native")

add_library(dmtr SHARED
    ${DMTR_SOURCE_DIR}/dmtr_engine.c
)

target_include_directories(dmtr PRIVATE ${DMTR_SOURCE_DIR})
target_compile_options(dmtr PRIVATE -std=c17 -O2 -Wall -Wextra -fvisibility=hidden)
target_link_libraries(dmtr log)
