cmake_minimum_required(VERSION 3.22.1)

# Defines the CMake project for Snappy Web Agent Android Service
project("snappy_web_agent")

# Creates the JNI wrapper library that links with the Rust static library
add_library(${CMAKE_PROJECT_NAME} SHARED
    src/main/cpp/jni_wrapper.cpp)

# Include directories
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE
    src/main/cpp)

# Find required libraries
find_library(log-lib log)
find_library(android-lib android)

# Link libraries
target_link_libraries(${CMAKE_PROJECT_NAME}
    ${log-lib}
    ${android-lib})

# Set the path to the Rust library based on Android ABI
set(RUST_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}")

# Link the Rust library
target_link_libraries(${CMAKE_PROJECT_NAME}
    "${RUST_LIB_DIR}/libsnappy_web_agent.so")

# Ensure the Rust library is found at runtime
set_target_properties(${CMAKE_PROJECT_NAME} PROPERTIES
    LINK_DEPENDS "${RUST_LIB_DIR}/libsnappy_web_agent.so")