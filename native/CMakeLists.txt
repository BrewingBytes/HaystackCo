# Haystack native module (G2b): C++ ports of sim functions that miss their budget in GDScript.
# Output: addons/haystack_native/bin/libhaystack_native.<platform>.<arch>.<ext>
#   macOS:   cmake -S native -B <build> -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build <build>
#   Android: add -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake
#            -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=24
cmake_minimum_required(VERSION 3.17)
project(haystack_native LANGUAGES CXX)

include(FetchContent)
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "Godot API the bindings target" FORCE)
set(GODOTCPP_TARGET "template_release" CACHE STRING "godot-cpp target")
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/build_profile.json" CACHE PATH "Bind only the classes we use")
FetchContent_Declare(
    godot-cpp
    URL https://github.com/godotengine/godot-cpp/archive/refs/tags/10.0.0-stable.tar.gz
    URL_HASH SHA256=ebbf64f0f8f8b8b66bc4bc4d3797db97f95b19cf0dfb5b3f8cf56683d9df7db4
)
FetchContent_MakeAvailable(godot-cpp)

add_library(haystack_native SHARED src/register_types.cpp src/sim_native.cpp)
target_link_libraries(haystack_native PRIVATE godot-cpp)

if(ANDROID)
    set(PLATFORM android)
    set(ARCH arm64)
    # Play's 16 KB page-size rule (tools/check_16kb.sh verifies it).
    target_link_options(haystack_native PRIVATE "-Wl,-z,max-page-size=16384")
elseif(APPLE)
    set(PLATFORM macos)
    set(ARCH ${CMAKE_SYSTEM_PROCESSOR})
else()
    set(PLATFORM linux)
    set(ARCH ${CMAKE_SYSTEM_PROCESSOR})
endif()

set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../addons/haystack_native/bin")
set_target_properties(
    haystack_native
    PROPERTIES
        CXX_STANDARD 17
        CXX_EXTENSIONS OFF
        CXX_VISIBILITY_PRESET hidden
        POSITION_INDEPENDENT_CODE ON
        PREFIX "lib"
        OUTPUT_NAME "haystack_native.${PLATFORM}.${ARCH}"
        LIBRARY_OUTPUT_DIRECTORY "${OUTPUT_DIR}"
        RUNTIME_OUTPUT_DIRECTORY "${OUTPUT_DIR}"
)
