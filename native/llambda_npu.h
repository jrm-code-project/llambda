#ifndef LLAMBDA_NPU_H
#define LLAMBDA_NPU_H

#include <stddef.h>

#ifdef _WIN32
#  ifdef LLAMBDA_NPU_BUILD
#    define LLAMBDA_NPU_API __declspec(dllexport)
#  else
#    define LLAMBDA_NPU_API __declspec(dllimport)
#  endif
#else
#  define LLAMBDA_NPU_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct llambda_npu_session llambda_npu_session;

LLAMBDA_NPU_API int llambda_npu_probe(void);
LLAMBDA_NPU_API const char* llambda_npu_bridge_version(void);
LLAMBDA_NPU_API const char* llambda_npu_runtime_version(void);
LLAMBDA_NPU_API const char* llambda_npu_last_error(void);
LLAMBDA_NPU_API int llambda_npu_sha256(
    const void* data,
    size_t data_size,
    char* output,
    size_t output_size);

LLAMBDA_NPU_API int llambda_npu_session_create(
    const char* model_path,
    const char* cache_dir,
    const char* cache_key,
    llambda_npu_session** result);
LLAMBDA_NPU_API void llambda_npu_session_destroy(llambda_npu_session* session);
LLAMBDA_NPU_API size_t llambda_npu_session_input_element_count(
    const llambda_npu_session* session);
LLAMBDA_NPU_API size_t llambda_npu_session_output_element_count(
    const llambda_npu_session* session);
LLAMBDA_NPU_API int llambda_npu_session_run(
    llambda_npu_session* session,
    const float* input,
    size_t input_element_count,
    float* output,
    size_t output_element_count);

#ifdef __cplusplus
}
#endif

#endif
