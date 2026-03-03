cmake_minimum_required(VERSION 3.14)
project(CrowSociServer)

include(FetchContent)

# --- 1. NETWORKING (ASIO for Crow) ---
FetchContent_Declare(
    asio
    GIT_REPOSITORY https://github.com/chriskohlhoff/asio.git
    GIT_TAG        asio-1-30-2
)
FetchContent_MakeAvailable(asio)
set(ASIO_INCLUDE_DIR "${asio_SOURCE_DIR}/asio/include" CACHE PATH "ASIO include directory" FORCE)

# --- 2. WEB FRAMEWORK (Crow) ---
FetchContent_Declare(
    Crow
    GIT_REPOSITORY https://github.com/CrowCpp/Crow.git
    GIT_TAG        master
)
FetchContent_MakeAvailable(Crow)

# --- 3. DATABASE (SOCI & MySQL) ---
# Swapped odbc for mysql here
find_package(Soci REQUIRED COMPONENTS core mysql)

# --- 4. BUILD & LINK ---
add_executable(my_server main.cpp)

# 👇 ADD THIS LINE HERE: Force CMake to allow bcrypt's old version policy
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

# Swapped soci_odbc for soci_mysql here
add_subdirectory(bcrypt_lib)

target_link_libraries(my_server 
    PRIVATE 
    Crow::Crow 
    soci_core 
    soci_mysql
    bcrypt
)

target_include_directories(my_server PRIVATE 
    "${ASIO_INCLUDE_DIR}"
    "/usr/include/mysql"
)