cmake_minimum_required(VERSION 3.26)

project(llambda_npu LANGUAGES CXX)

set(RYZEN_AI_ROOT "C:/Program Files/RyzenAI/1.7.1" CACHE PATH
    "Root of the AMD Ryzen AI Software installation")
set(ORT_ROOT "${RYZEN_AI_ROOT}/onnxruntime")

if(NOT EXISTS "${ORT_ROOT}/include/onnxruntime/core/session/onnxruntime_cxx_api.h")
  message(FATAL_ERROR "ONNX Runtime headers were not found under ${ORT_ROOT}")
endif()

add_library(llambda_npu SHARED llambda_npu.cpp)
target_compile_features(llambda_npu PRIVATE cxx_std_20)
target_compile_definitions(llambda_npu PRIVATE LLAMBDA_NPU_BUILD)
target_include_directories(llambda_npu PRIVATE
  "${ORT_ROOT}/include/onnxruntime/core/session")
target_link_libraries(llambda_npu PRIVATE
  "${ORT_ROOT}/lib/onnxruntime.lib"
  bcrypt)

if(MSVC)
  target_compile_options(llambda_npu PRIVATE /W4 /EHsc)
endif()

add_executable(llambda_npu_smoke llambda_npu_smoke.cpp)
target_compile_features(llambda_npu_smoke PRIVATE cxx_std_20)
target_link_libraries(llambda_npu_smoke PRIVATE llambda_npu)

file(GLOB RYZEN_AI_RUNTIME_DLLS "${RYZEN_AI_ROOT}/deployment/*.dll")
foreach(runtime_dll IN LISTS RYZEN_AI_RUNTIME_DLLS)
  add_custom_command(TARGET llambda_npu POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${runtime_dll}" "$<TARGET_FILE_DIR:llambda_npu>")
endforeach()
