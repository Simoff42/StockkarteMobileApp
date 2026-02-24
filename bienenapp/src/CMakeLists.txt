cmake_minimum_required(VERSION 3.10)
project(native_backend LANGUAGES CXX)

# Build a shared library named "native_backend"
add_library(native_backend SHARED logic.cpp)