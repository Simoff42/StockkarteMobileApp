cmake_minimum_required(VERSION 3.10)
project(native_backend LANGUAGES CXX)

# Build a shared library named "native_backend"
# add_subdirectory(bcrypt_lib)
add_library(native_backend SHARED logic.cpp)
find_library(log-lib log)
target_link_libraries(native_backend ${log-lib})
target_include_directories(native_backend PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/json/single_include)