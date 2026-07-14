#include "llambda_npu.h"

#define NOMINMAX
#include <windows.h>

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <string>
#include <string_view>
#include <vector>

namespace {

std::string loaded_runtime_path() {
  const HMODULE module = GetModuleHandleW(L"onnxruntime.dll");
  if (!module) {
    return "<unknown>";
  }
  std::vector<wchar_t> wide_path(32768);
  const DWORD length = GetModuleFileNameW(
      module, wide_path.data(), static_cast<DWORD>(wide_path.size()));
  if (length == 0 || length == wide_path.size()) {
    return "<unknown>";
  }
  const int utf8_length = WideCharToMultiByte(
      CP_UTF8, 0, wide_path.data(), static_cast<int>(length),
      nullptr, 0, nullptr, nullptr);
  if (utf8_length <= 0) {
    return "<unknown>";
  }
  std::string path(static_cast<size_t>(utf8_length), '\0');
  WideCharToMultiByte(
      CP_UTF8, 0, wide_path.data(), static_cast<int>(length),
      path.data(), utf8_length, nullptr, nullptr);
  return path;
}

}  // namespace

int main(int argc, char** argv) {
  int argument = 1;
  bool use_gpu = false;
  if (argc >= 2 && (std::string_view(argv[1]) == "--gpu" ||
                    std::string_view(argv[1]) == "--npu")) {
    use_gpu = std::string_view(argv[1]) == "--gpu";
    ++argument;
  }
  if (argc - argument < 1 || argc - argument > 3) {
    std::cerr
        << "usage: llambda_npu_smoke [--npu|--gpu] MODEL.onnx "
           "[WARMUP_RUNS] [TIMED_RUNS]\n";
    return 2;
  }
  const char* model_path = argv[argument++];
  const int warmup_runs =
      argument < argc ? std::atoi(argv[argument++]) : 1;
  const int timed_runs =
      argument < argc ? std::atoi(argv[argument]) : 1;
  if (warmup_runs < 0 || timed_runs <= 0) {
    std::cerr << "Warmup runs must be nonnegative and timed runs positive.\n";
    return 2;
  }

  const auto session_start = std::chrono::steady_clock::now();
  const int probe = use_gpu ? llambda_gpu_probe() : llambda_npu_probe();
  if (probe != 1) {
    std::cerr << (use_gpu ? "DirectML" : "VitisAI")
              << " probe failed: " << llambda_npu_last_error()
              << " (runtime: " << loaded_runtime_path() << ")\n";
    return 1;
  }

  llambda_npu_session* npu_session = nullptr;
  llambda_gpu_session* gpu_session = nullptr;
  const int create_status =
      use_gpu ? llambda_gpu_session_create(model_path, &gpu_session)
              : llambda_npu_session_create(
                    model_path, nullptr, nullptr, &npu_session);
  if (create_status != 0) {
    std::cerr << "Session creation failed: " << llambda_npu_last_error()
              << " (runtime: " << loaded_runtime_path() << ")\n";
    return 1;
  }
  const auto session_end = std::chrono::steady_clock::now();

  const size_t input_count = use_gpu
      ? llambda_gpu_session_input_element_count(gpu_session)
      : llambda_npu_session_input_element_count(npu_session);
  const size_t output_count = use_gpu
      ? llambda_gpu_session_output_element_count(gpu_session)
      : llambda_npu_session_output_element_count(npu_session);
  std::vector<float> input(input_count, 0.5f);
  std::vector<float> output(output_count);
  for (int index = 0; index < warmup_runs; ++index) {
    const int status = use_gpu
        ? llambda_gpu_session_run(gpu_session, input.data(), input.size(),
                                  output.data(), output.size())
        : llambda_npu_session_run(npu_session, input.data(), input.size(),
                                  output.data(), output.size());
    if (status != 0) {
      std::cerr << "Warmup failed: " << llambda_npu_last_error() << '\n';
      if (use_gpu) {
        llambda_gpu_session_destroy(gpu_session);
      } else {
        llambda_npu_session_destroy(npu_session);
      }
      return 1;
    }
  }

  const auto run_start = std::chrono::steady_clock::now();
  for (int index = 0; index < timed_runs; ++index) {
    const int status = use_gpu
        ? llambda_gpu_session_run(gpu_session, input.data(), input.size(),
                                  output.data(), output.size())
        : llambda_npu_session_run(npu_session, input.data(), input.size(),
                                  output.data(), output.size());
    if (status != 0) {
      std::cerr << "Inference failed: " << llambda_npu_last_error() << '\n';
      if (use_gpu) {
        llambda_gpu_session_destroy(gpu_session);
      } else {
        llambda_npu_session_destroy(npu_session);
      }
      return 1;
    }
  }
  const auto run_end = std::chrono::steady_clock::now();

  const auto compile_ms =
      std::chrono::duration<double, std::milli>(session_end - session_start)
          .count();
  const auto run_ms =
      std::chrono::duration<double, std::milli>(run_end - run_start).count() /
      timed_runs;
  std::cout << (use_gpu ? "DirectML " : "VitisAI ")
            << llambda_npu_runtime_version() << ": "
            << input_count << " inputs -> " << output_count
            << " outputs; session = " << compile_ms
            << " ms; warm run = " << run_ms
            << " ms; first output = "
            << (output.empty() ? 0.0f : output.front())
            << "; runtime = " << loaded_runtime_path() << '\n';
  if (use_gpu) {
    llambda_gpu_session_destroy(gpu_session);
  } else {
    llambda_npu_session_destroy(npu_session);
  }
  return 0;
}
