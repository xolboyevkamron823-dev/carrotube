# libcarro_dsp.so = shared C++ DSP core (also compiled for iOS) + JNI bridge.
# dart:ffi opens the same library (DynamicLibrary.open('libcarro_dsp.so')), so the player's
# AudioProcessor (JNI) and the Dart UI (FFI) talk to one engine instance.
cmake_minimum_required(VERSION 3.22.1)
project(carro_dsp CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CARRO_CORE ${CMAKE_CURRENT_SOURCE_DIR}/../ios/carro_native/Sources/CarroDSP/core)
file(GLOB CARRO_SOURCES ${CARRO_CORE}/carro_api.cpp ${CARRO_CORE}/dsp/*.cpp)

add_library(carro_dsp SHARED ${CARRO_SOURCES} src/main/cpp/carro_jni.cpp)
target_include_directories(carro_dsp PRIVATE ${CARRO_CORE})
target_compile_options(carro_dsp PRIVATE
  -O3 -fvisibility=hidden -ffunction-sections -fdata-sections -Wall -Wno-unused-parameter)
if(ANDROID_ABI STREQUAL "armeabi-v7a")
  target_compile_options(carro_dsp PRIVATE -mfpu=neon)
endif()
# Android 15+ 16 KB page size support + dead code removal.
target_link_options(carro_dsp PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)

find_library(log-lib log)
target_link_libraries(carro_dsp ${log-lib})
