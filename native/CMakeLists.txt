cmake_minimum_required(VERSION 3.26)

project(llambda_npu LANGUAGES CXX)

set(RYZEN_AI_ROOT "C:/Program Files/RyzenAI/1.7.1" CACHE PATH
    "Root of the AMD Ryzen AI Software installation")
set(ORT_ROOT "${RYZEN_AI_ROOT}/onnxruntime" CACHE PATH
    "Root of the ONNX Runtime installation")
set(ORT_RUNTIME_DIR "" CACHE PATH
    "Optional directory containing ONNX Runtime deployment DLLs")
option(LLAMBDA_COPY_RUNTIME_DLLS
       "Copy available ONNX Runtime and Ryzen AI deployment DLLs" ON)
set(RYZEN_AI_ORT_ROOT "${RYZEN_AI_ROOT}/onnxruntime")
cmake_path(NORMAL_PATH RYZEN_AI_ORT_ROOT
           OUTPUT_VARIABLE NORMALIZED_RYZEN_AI_ORT_ROOT)
cmake_path(NORMAL_PATH ORT_ROOT OUTPUT_VARIABLE NORMALIZED_ORT_ROOT)
if(NORMALIZED_ORT_ROOT STREQUAL NORMALIZED_RYZEN_AI_ORT_ROOT)
  set(DEFAULT_COPY_RYZEN_AI_DLLS ON)
else()
  set(DEFAULT_COPY_RYZEN_AI_DLLS OFF)
endif()
option(LLAMBDA_COPY_RYZEN_AI_DLLS
       "Copy Ryzen AI deployment DLLs (required by the VitisAI provider)"
       ${DEFAULT_COPY_RYZEN_AI_DLLS})

unset(ORT_INCLUDE_DIR CACHE)
unset(ORT_INCLUDE_DIR)
find_path(ORT_INCLUDE_DIR
  NAMES onnxruntime_cxx_api.h dml_provider_factory.h
  HINTS "${ORT_ROOT}"
  PATH_SUFFIXES
    include
    include/onnxruntime/core/session
    build/native/include
  NO_DEFAULT_PATH
  NO_CACHE)
unset(ORT_LIBRARY CACHE)
unset(ORT_LIBRARY)
find_library(ORT_LIBRARY
  NAMES onnxruntime
  HINTS "${ORT_ROOT}"
  PATH_SUFFIXES lib lib/x64 runtimes/win-x64/native
  NO_DEFAULT_PATH
  NO_CACHE)

if(NOT ORT_INCLUDE_DIR OR
   NOT EXISTS "${ORT_INCLUDE_DIR}/onnxruntime_cxx_api.h" OR
   NOT EXISTS "${ORT_INCLUDE_DIR}/dml_provider_factory.h")
  message(FATAL_ERROR
    "ONNX Runtime C/C++ and DirectML provider headers were not found under ${ORT_ROOT}")
endif()
if(NOT ORT_LIBRARY)
  message(FATAL_ERROR "ONNX Runtime library was not found under ${ORT_ROOT}")
endif()

add_library(llambda_npu SHARED llambda_npu.cpp)
target_compile_features(llambda_npu PRIVATE cxx_std_20)
target_compile_definitions(llambda_npu PRIVATE LLAMBDA_NPU_BUILD)
target_include_directories(llambda_npu PRIVATE "${ORT_INCLUDE_DIR}")
target_link_libraries(llambda_npu PRIVATE
  "${ORT_LIBRARY}"
  bcrypt)

if(MSVC)
  target_compile_options(llambda_npu PRIVATE /W4 /EHsc)
endif()

add_executable(llambda_npu_smoke llambda_npu_smoke.cpp)
target_compile_features(llambda_npu_smoke PRIVATE cxx_std_20)
target_link_libraries(llambda_npu_smoke PRIVATE llambda_npu)

if(LLAMBDA_COPY_RUNTIME_DLLS)
  set(runtime_dlls)
  if(LLAMBDA_COPY_RYZEN_AI_DLLS)
    file(GLOB RYZEN_AI_RUNTIME_DLLS "${RYZEN_AI_ROOT}/deployment/*.dll")
    list(APPEND runtime_dlls ${RYZEN_AI_RUNTIME_DLLS})
  endif()
  file(GLOB ORT_ROOT_RUNTIME_DLLS
    "${ORT_ROOT}/bin/*.dll"
    "${ORT_ROOT}/lib/*.dll"
    "${ORT_ROOT}/lib/x64/*.dll"
    "${ORT_ROOT}/runtimes/win-x64/native/*.dll")
  list(APPEND runtime_dlls ${ORT_ROOT_RUNTIME_DLLS})
  if(ORT_RUNTIME_DIR)
    file(GLOB ORT_RUNTIME_DLLS "${ORT_RUNTIME_DIR}/*.dll")
    list(APPEND runtime_dlls ${ORT_RUNTIME_DLLS})
  endif()
  list(REMOVE_DUPLICATES runtime_dlls)
  foreach(runtime_dll IN LISTS runtime_dlls)
    add_custom_command(TARGET llambda_npu POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
              "${runtime_dll}" "$<TARGET_FILE_DIR:llambda_npu>")
  endforeach()
endif()
