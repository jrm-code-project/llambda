#include "llambda_npu.h"

#define NOMINMAX
#include <windows.h>
#include <bcrypt.h>

#include <algorithm>
#include <cstring>
#include <filesystem>
#include <limits>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

#define ORT_API_MANUAL_INIT
#include <onnxruntime_cxx_api.h>
#include <dml_provider_factory.h>

namespace {

thread_local std::string last_error;
std::once_flag ort_api_init_flag;
const OrtApi* ort_api = nullptr;
// A 1x1 identity GEMM verifies that DirectML can create and execute a session.
constexpr unsigned char directml_probe_model[] = {
    0x08, 0x08, 0x12, 0x07, 0x6c, 0x6c, 0x61, 0x6d, 0x62, 0x64, 0x61, 0x3a,
    0x85, 0x01, 0x0a, 0x27, 0x0a, 0x05, 0x69, 0x6e, 0x70, 0x75, 0x74, 0x0a,
    0x01, 0x77, 0x12, 0x06, 0x6f, 0x75, 0x74, 0x70, 0x75, 0x74, 0x22, 0x04,
    0x47, 0x65, 0x6d, 0x6d, 0x2a, 0x0d, 0x0a, 0x06, 0x74, 0x72, 0x61, 0x6e,
    0x73, 0x42, 0x18, 0x01, 0xa0, 0x01, 0x02, 0x12, 0x16, 0x6c, 0x6c, 0x61,
    0x6d, 0x62, 0x64, 0x61, 0x5f, 0x64, 0x69, 0x72, 0x65, 0x63, 0x74, 0x6d,
    0x6c, 0x5f, 0x70, 0x72, 0x6f, 0x62, 0x65, 0x2a, 0x0f, 0x08, 0x01, 0x08,
    0x01, 0x10, 0x01, 0x22, 0x04, 0x00, 0x00, 0x80, 0x3f, 0x42, 0x01, 0x77,
    0x5a, 0x17, 0x0a, 0x05, 0x69, 0x6e, 0x70, 0x75, 0x74, 0x12, 0x0e, 0x0a,
    0x0c, 0x08, 0x01, 0x12, 0x08, 0x0a, 0x02, 0x08, 0x01, 0x0a, 0x02, 0x08,
    0x01, 0x62, 0x18, 0x0a, 0x06, 0x6f, 0x75, 0x74, 0x70, 0x75, 0x74, 0x12,
    0x0e, 0x0a, 0x0c, 0x08, 0x01, 0x12, 0x08, 0x0a, 0x02, 0x08, 0x01, 0x0a,
    0x02, 0x08, 0x01, 0x42, 0x04, 0x0a, 0x00, 0x10, 0x11};

void set_error(const char* message) {
  last_error = message ? message : "Unknown accelerator backend error.";
}

void set_error(const std::exception& error) {
  set_error(error.what());
}

void ensure_ort_api() {
  std::call_once(ort_api_init_flag, [] {
    ort_api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (ort_api) {
      Ort::InitApi(ort_api);
    }
  });
  if (!ort_api) {
    throw std::runtime_error(
        "Loaded ONNX Runtime does not provide the API version required by "
        "the llambda accelerator bridge.");
  }
}

size_t element_count(const std::vector<int64_t>& shape) {
  size_t result = 1;
  for (const int64_t dimension : shape) {
    if (dimension <= 0) {
      throw std::runtime_error(
          "NPU sessions require fixed, positive tensor dimensions.");
    }
    const size_t value = static_cast<size_t>(dimension);
    if (result > std::numeric_limits<size_t>::max() / value) {
      throw std::runtime_error("NPU tensor element count overflows size_t.");
    }
    result *= value;
  }
  return result;
}

size_t gpu_element_count(const std::vector<int64_t>& shape) {
  size_t result = 1;
  for (const int64_t dimension : shape) {
    if (dimension <= 0) {
      throw std::runtime_error(
          "GPU sessions require fixed, positive tensor dimensions.");
    }
    const size_t value = static_cast<size_t>(dimension);
    if (result > std::numeric_limits<size_t>::max() / value) {
      throw std::runtime_error("GPU tensor element count overflows size_t.");
    }
    result *= value;
  }
  return result;
}

void resolve_dynamic_dimensions(std::vector<int64_t>& shape) {
  for (int64_t& dimension : shape) {
    if (dimension < 0) {
      dimension = 1;
    } else if (dimension == 0) {
      throw std::runtime_error(
          "NPU sessions do not support zero-sized tensor dimensions.");
    }
  }
}

bool vitisai_available() {
  const auto providers = Ort::GetAvailableProviders();
  return std::find(providers.begin(), providers.end(),
                   "VitisAIExecutionProvider") != providers.end();
}

bool directml_available() {
  const auto providers = Ort::GetAvailableProviders();
  return std::find(providers.begin(), providers.end(),
                   "DmlExecutionProvider") != providers.end();
}

const OrtDmlApi* get_directml_api() {
  const void* provider_api = nullptr;
  Ort::ThrowOnError(ort_api->GetExecutionProviderApi(
      "DML", ORT_API_VERSION, &provider_api));
  if (!provider_api) {
    throw std::runtime_error(
        "ONNX Runtime returned an empty DirectML provider API.");
  }
  return static_cast<const OrtDmlApi*>(provider_api);
}

void configure_directml_session_options(Ort::SessionOptions& options) {
  options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
  options.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
  options.DisableMemPattern();
  // DirectML dispatches D3D12 compute shaders. Reject graphs that would need
  // ONNX Runtime's CPU execution provider instead of hiding a CPU fallback.
  options.AddConfigEntry("session.disable_cpu_ep_fallback", "1");
  Ort::ThrowOnError(
      get_directml_api()->SessionOptionsAppendExecutionProvider_DML(
          options, 0));
}

void verify_directml_execution() {
  Ort::Env env{ORT_LOGGING_LEVEL_ERROR, "llambda-directml-probe"};
  Ort::SessionOptions options;
  configure_directml_session_options(options);
  Ort::Session session(env, directml_probe_model, sizeof(directml_probe_model),
                       options);

  constexpr int64_t shape[] = {1, 1};
  float input = 1.25f;
  float output = 0.0f;
  const auto memory_info =
      Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
  auto input_tensor = Ort::Value::CreateTensor<float>(
      memory_info, &input, 1, shape, 2);
  auto output_tensor = Ort::Value::CreateTensor<float>(
      memory_info, &output, 1, shape, 2);
  const char* input_names[] = {"input"};
  const char* output_names[] = {"output"};
  session.Run(Ort::RunOptions{nullptr}, input_names, &input_tensor, 1,
              output_names, &output_tensor, 1);
  if (output != input) {
    throw std::runtime_error(
        "DirectML probe inference returned an incorrect result.");
  }
}

}  // namespace

struct llambda_npu_session {
  Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "llambda"};
  std::unique_ptr<Ort::Session> session;
  std::string input_name;
  std::string output_name;
  std::vector<int64_t> input_shape;
  std::vector<int64_t> output_shape;
  size_t input_element_count = 0;
  size_t output_element_count = 0;
};

struct llambda_gpu_session {
  Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "llambda-directml"};
  std::unique_ptr<Ort::Session> session;
  std::string input_name;
  std::string output_name;
  std::vector<int64_t> input_shape;
  std::vector<int64_t> output_shape;
  size_t input_element_count = 0;
  size_t output_element_count = 0;
};

extern "C" {

int llambda_npu_probe(void) {
  try {
    last_error.clear();
    ensure_ort_api();
    return vitisai_available() ? 1 : 0;
  } catch (const std::exception& error) {
    set_error(error);
    return -1;
  }
}

const char* llambda_npu_runtime_version(void) {
  try {
    last_error.clear();
    thread_local std::string runtime_version;
    runtime_version = Ort::GetVersionString();
    return runtime_version.c_str();
  } catch (const std::exception& error) {
    set_error(error);
    return nullptr;
  }
}

const char* llambda_npu_bridge_version(void) {
  return "2";
}

const char* llambda_npu_last_error(void) {
  return last_error.c_str();
}

int llambda_npu_sha256(const void* data,
                       size_t data_size,
                       char* output,
                       size_t output_size) {
  if ((!data && data_size != 0) || !output || output_size < 65) {
    set_error("SHA-256 requires input data and a 65-byte output buffer.");
    return -1;
  }
  if (data_size > std::numeric_limits<ULONG>::max()) {
    set_error("SHA-256 input exceeds the Windows one-shot hash size limit.");
    return -1;
  }

  BCRYPT_ALG_HANDLE algorithm = nullptr;
  try {
    last_error.clear();
    NTSTATUS status = BCryptOpenAlgorithmProvider(
        &algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
    if (!BCRYPT_SUCCESS(status)) {
      throw std::runtime_error("BCryptOpenAlgorithmProvider failed.");
    }

    unsigned char digest[32];
    status = BCryptHash(
        algorithm, nullptr, 0,
        reinterpret_cast<PUCHAR>(const_cast<void*>(data)),
        static_cast<ULONG>(data_size), digest, sizeof(digest));
    if (!BCRYPT_SUCCESS(status)) {
      throw std::runtime_error("BCryptHash failed.");
    }

    static constexpr char hex[] = "0123456789abcdef";
    for (size_t index = 0; index < sizeof(digest); ++index) {
      output[index * 2] = hex[digest[index] >> 4];
      output[index * 2 + 1] = hex[digest[index] & 0x0f];
    }
    output[64] = '\0';
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return 0;
  } catch (const std::exception& error) {
    if (algorithm) {
      BCryptCloseAlgorithmProvider(algorithm, 0);
    }
    set_error(error);
    return -1;
  }
}

int llambda_npu_session_create(const char* model_path,
                               const char* cache_dir,
                               const char* cache_key,
                               llambda_npu_session** result) {
  if (!model_path || !result) {
    set_error("Model path and result pointer are required.");
    return -1;
  }
  *result = nullptr;

  try {
    last_error.clear();
    ensure_ort_api();
    if (!vitisai_available()) {
      throw std::runtime_error(
          "VitisAIExecutionProvider is not available in ONNX Runtime.");
    }

    auto state = std::make_unique<llambda_npu_session>();
    Ort::SessionOptions options;
    options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    options.AddConfigEntry("session.disable_cpu_ep_fallback", "1");

    std::unordered_map<std::string, std::string> provider_options;
    if (cache_dir && *cache_dir) {
      provider_options.emplace("cacheDir", cache_dir);
    }
    if (cache_key && *cache_key) {
      provider_options.emplace("cacheKey", cache_key);
    }
    options.AppendExecutionProvider_VitisAI(provider_options);

    const auto* model_path_begin =
        reinterpret_cast<const char8_t*>(model_path);
    const std::filesystem::path native_model_path{
        std::u8string(model_path_begin,
                      model_path_begin + std::strlen(model_path))};
    state->session = std::make_unique<Ort::Session>(
        state->env, native_model_path.c_str(), options);

    if (state->session->GetInputCount() != 1 ||
        state->session->GetOutputCount() != 1) {
      throw std::runtime_error(
          "NPU projection models must have exactly one input and one output.");
    }

    Ort::AllocatorWithDefaultOptions allocator;
    auto input_name = state->session->GetInputNameAllocated(0, allocator);
    auto output_name = state->session->GetOutputNameAllocated(0, allocator);
    state->input_name = input_name.get();
    state->output_name = output_name.get();

    const auto input_type_info = state->session->GetInputTypeInfo(0);
    const auto output_type_info = state->session->GetOutputTypeInfo(0);
    const auto input_tensor_info =
        input_type_info.GetTensorTypeAndShapeInfo();
    const auto output_tensor_info =
        output_type_info.GetTensorTypeAndShapeInfo();
    if (input_tensor_info.GetElementType() !=
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
        output_tensor_info.GetElementType() !=
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
      throw std::runtime_error(
          "NPU projection model inputs and outputs must be float32.");
    }

    state->input_shape = input_tensor_info.GetShape();
    state->output_shape = output_tensor_info.GetShape();
    resolve_dynamic_dimensions(state->input_shape);
    resolve_dynamic_dimensions(state->output_shape);
    state->input_element_count = element_count(state->input_shape);
    state->output_element_count = element_count(state->output_shape);

    *result = state.release();
    return 0;
  } catch (const std::exception& error) {
    set_error(error);
    return -1;
  }
}

void llambda_npu_session_destroy(llambda_npu_session* session) {
  delete session;
}

size_t llambda_npu_session_input_element_count(
    const llambda_npu_session* session) {
  return session ? session->input_element_count : 0;
}

size_t llambda_npu_session_output_element_count(
    const llambda_npu_session* session) {
  return session ? session->output_element_count : 0;
}

int llambda_npu_session_run(llambda_npu_session* session,
                            const float* input,
                            size_t input_element_count,
                            float* output,
                            size_t output_element_count) {
  if (!session || !input || !output) {
    set_error("Session, input, and output are required.");
    return -1;
  }
  if (input_element_count != session->input_element_count ||
      output_element_count != session->output_element_count) {
    set_error("Input or output element count does not match the NPU model.");
    return -1;
  }

  try {
    last_error.clear();
    const auto memory_info =
        Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    auto input_tensor = Ort::Value::CreateTensor<float>(
        memory_info, const_cast<float*>(input), input_element_count,
        session->input_shape.data(), session->input_shape.size());
    auto output_tensor = Ort::Value::CreateTensor<float>(
        memory_info, output, output_element_count,
        session->output_shape.data(), session->output_shape.size());
    const char* input_names[] = {session->input_name.c_str()};
    const char* output_names[] = {session->output_name.c_str()};
    session->session->Run(Ort::RunOptions{nullptr}, input_names, &input_tensor,
                          1, output_names, &output_tensor, 1);
    return 0;
  } catch (const std::exception& error) {
    set_error(error);
    return -1;
  }
}

int llambda_gpu_probe(void) {
  try {
    last_error.clear();
    ensure_ort_api();
    if (!directml_available()) {
      set_error(
          "DmlExecutionProvider is not available in ONNX Runtime.");
      return 0;
    }
    verify_directml_execution();
    return 1;
  } catch (const std::exception& error) {
    set_error(error);
    return -1;
  }
}

int llambda_gpu_session_create(const char* model_path,
                               llambda_gpu_session** result) {
  if (!model_path || !result) {
    set_error("Model path and result pointer are required.");
    return -1;
  }
  *result = nullptr;

  try {
    last_error.clear();
    ensure_ort_api();
    if (!directml_available()) {
      throw std::runtime_error(
          "DmlExecutionProvider is not available in ONNX Runtime.");
    }

    auto state = std::make_unique<llambda_gpu_session>();
    Ort::SessionOptions options;
    configure_directml_session_options(options);

    const auto* model_path_begin =
        reinterpret_cast<const char8_t*>(model_path);
    const std::filesystem::path native_model_path{
        std::u8string(model_path_begin,
                      model_path_begin + std::strlen(model_path))};
    state->session = std::make_unique<Ort::Session>(
        state->env, native_model_path.c_str(), options);

    if (state->session->GetInputCount() != 1 ||
        state->session->GetOutputCount() != 1) {
      throw std::runtime_error(
          "GPU projection models must have exactly one input and one output.");
    }

    Ort::AllocatorWithDefaultOptions allocator;
    auto input_name = state->session->GetInputNameAllocated(0, allocator);
    auto output_name = state->session->GetOutputNameAllocated(0, allocator);
    state->input_name = input_name.get();
    state->output_name = output_name.get();

    const auto input_type_info = state->session->GetInputTypeInfo(0);
    const auto output_type_info = state->session->GetOutputTypeInfo(0);
    const auto input_tensor_info =
        input_type_info.GetTensorTypeAndShapeInfo();
    const auto output_tensor_info =
        output_type_info.GetTensorTypeAndShapeInfo();
    if (input_tensor_info.GetElementType() !=
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
        output_tensor_info.GetElementType() !=
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
      throw std::runtime_error(
          "GPU projection model inputs and outputs must be float32.");
    }

    state->input_shape = input_tensor_info.GetShape();
    state->output_shape = output_tensor_info.GetShape();
    state->input_element_count = gpu_element_count(state->input_shape);
    state->output_element_count = gpu_element_count(state->output_shape);

    *result = state.release();
    return 0;
  } catch (const std::exception& error) {
    set_error(error);
    return -1;
  }
}

void llambda_gpu_session_destroy(llambda_gpu_session* session) {
  delete session;
}

size_t llambda_gpu_session_input_element_count(
    const llambda_gpu_session* session) {
  return session ? session->input_element_count : 0;
}

size_t llambda_gpu_session_output_element_count(
    const llambda_gpu_session* session) {
  return session ? session->output_element_count : 0;
}

int llambda_gpu_session_run(llambda_gpu_session* session,
                            const float* input,
                            size_t input_element_count,
                            float* output,
                            size_t output_element_count) {
  if (!session || !input || !output) {
    set_error("Session, input, and output are required.");
    return -1;
  }
  if (input_element_count != session->input_element_count ||
      output_element_count != session->output_element_count) {
    set_error("Input or output element count does not match the GPU model.");
    return -1;
  }

  try {
    last_error.clear();
    const auto memory_info =
        Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    auto input_tensor = Ort::Value::CreateTensor<float>(
        memory_info, const_cast<float*>(input), input_element_count,
        session->input_shape.data(), session->input_shape.size());
    auto output_tensor = Ort::Value::CreateTensor<float>(
        memory_info, output, output_element_count,
        session->output_shape.data(), session->output_shape.size());
    const char* input_names[] = {session->input_name.c_str()};
    const char* output_names[] = {session->output_name.c_str()};
    session->session->Run(Ort::RunOptions{nullptr}, input_names, &input_tensor,
                          1, output_names, &output_tensor, 1);
    return 0;
  } catch (const std::exception& error) {
    set_error(error);
    return -1;
  }
}

}  // extern "C"
