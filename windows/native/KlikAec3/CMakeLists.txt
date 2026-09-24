cmake_minimum_required(VERSION 3.25)
project(KlikAec3 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

set(AEC3_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../Sources/CWebRTCAEC3")
file(GLOB_RECURSE AEC3_SOURCES CONFIGURE_DEPENDS
    "${AEC3_ROOT}/*.cc"
    "${AEC3_ROOT}/*.cpp")

list(FILTER AEC3_SOURCES EXCLUDE REGEX ".*_avx2\\.cc$")
list(FILTER AEC3_SOURCES EXCLUDE REGEX ".*_neon\\.cc$")
list(FILTER AEC3_SOURCES EXCLUDE REGEX ".*_mips\\.cc$")
list(FILTER AEC3_SOURCES EXCLUDE REGEX ".*_sse2?\\.cc$")

add_library(KlikAec3 SHARED ${AEC3_SOURCES})
set_target_properties(KlikAec3 PROPERTIES
    WINDOWS_EXPORT_ALL_SYMBOLS ON
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

target_include_directories(KlikAec3 PRIVATE
    "${AEC3_ROOT}"
    "${AEC3_ROOT}/api"
    "${AEC3_ROOT}/base"
    "${AEC3_ROOT}/base/rtc_base"
    "${AEC3_ROOT}/base/system_wrappers/include"
    "${AEC3_ROOT}/base/jsoncpp/include"
    "${AEC3_ROOT}/absl"
    "${AEC3_ROOT}/audio_processing"
    "${AEC3_ROOT}/audio_processing/aec3"
    "${AEC3_ROOT}/audio_processing/include"
    "${AEC3_ROOT}/audio_processing/logging"
    "${AEC3_ROOT}/audio_processing/resampler"
    "${AEC3_ROOT}/audio_processing/utility"
    "${AEC3_ROOT}/common_audio"
    "${AEC3_ROOT}/common_audio/third_party/ooura/fft_size_128"
    "${AEC3_ROOT}/rtc_base/experiments")

target_compile_definitions(KlikAec3 PRIVATE
    WEBRTC_WIN
    NOMINMAX
    WIN32_LEAN_AND_MEAN
    _CRT_SECURE_NO_WARNINGS)

if(MSVC)
    target_compile_options(KlikAec3 PRIVATE /EHsc /W3 /wd4244 /wd4267 /wd4996)
endif()

add_executable(KlikAec3SyntheticTest synthetic_test.cpp)
target_include_directories(KlikAec3SyntheticTest PRIVATE "${AEC3_ROOT}/include")
target_link_libraries(KlikAec3SyntheticTest PRIVATE KlikAec3)
set_target_properties(KlikAec3SyntheticTest PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

enable_testing()
add_test(NAME suppresses_delayed_echo
    COMMAND "${CMAKE_BINARY_DIR}/bin/$<CONFIG>/KlikAec3SyntheticTest.exe")
