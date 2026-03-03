cmake_minimum_required(VERSION 3.14)
project(CrowSimpleServer)

include(FetchContent)

# 1. Download ASIO manually first
FetchContent_Declare(
    asio
    GIT_REPOSITORY https://github.com/chriskohlhoff/asio.git
    GIT_TAG        asio-1-30-2
)
FetchContent_MakeAvailable(asio)

# 2. Force-feed the ASIO path into CMake's brain BEFORE Crow looks for it
set(ASIO_INCLUDE_DIR "${asio_SOURCE_DIR}/asio/include" CACHE PATH "ASIO include directory" FORCE)

# 3. Now download Crow (it will immediately find ASIO using the path above)
FetchContent_Declare(
    Crow
    GIT_REPOSITORY https://github.com/CrowCpp/Crow.git
    GIT_TAG        master
)
FetchContent_MakeAvailable(Crow)

# 4. Build the server and link everything
add_executable(my_server main.cpp)
target_link_libraries(my_server PRIVATE Crow::Crow)

# Make sure our own code can see ASIO as well
target_include_directories(my_server PRIVATE "${ASIO_INCLUDE_DIR}")