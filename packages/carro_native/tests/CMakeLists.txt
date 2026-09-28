# Desktop build of the Carro DSP core + unit tests.
#   cmake -S packages/carro_native/tests -B build/dsp_tests -DCMAKE_BUILD_TYPE=Release
#   cmake --build build/dsp_tests --config Release
#   ctest --test-dir build/dsp_tests -C Release --output-on-failure
cmake_minimum_required(VERSION 3.16)
project(carro_dsp_tests CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CARRO_CORE ${CMAKE_CURRENT_SOURCE_DIR}/../ios/carro_native/Sources/CarroDSP/core)
file(GLOB CARRO_SOURCES ${CARRO_CORE}/carro_api.cpp ${CARRO_CORE}/dsp/*.cpp)

add_executable(dsp_tests dsp_tests.cpp ${CARRO_SOURCES})
target_include_directories(dsp_tests PRIVATE ${CARRO_CORE})
find_package(Threads REQUIRED)
target_link_libraries(dsp_tests PRIVATE Threads::Threads)
if(MSVC)
  target_compile_options(dsp_tests PRIVATE /W4 /O2)
else()
  target_compile_options(dsp_tests PRIVATE -Wall -Wextra -Wno-unused-parameter -O2)
endif()

enable_testing()
add_test(NAME carro_dsp COMMAND dsp_tests)
