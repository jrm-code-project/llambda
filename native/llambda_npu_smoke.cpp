#include "llambda_npu.h"

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <vector>

int main(int argc, char** argv) {
  if (argc < 2 || argc > 4) {
    std::cerr
        << "usage: llambda_npu_smoke MODEL.onnx [WARMUP_RUNS] [TIMED_RUNS]\n";
    return 2;
  }
  const int warmup_runs = argc >= 3 ? std::atoi(argv[2]) : 1;
  const int timed_runs = argc >= 4 ? std::atoi(argv[3]) : 1;
  if (warmup_runs < 0 || timed_runs <= 0) {
    std::cerr << "Warmup runs must be nonnegative and timed runs positive.\n";
    return 2;
  }

  const auto session_start = std::chrono::steady_clock::now();
  const int probe = llambda_npu_probe();
  if (probe != 1) {
    std::cerr << "VitisAI probe failed: " << llambda_npu_last_error() << '\n';
    return 1;
  }

  llambda_npu_session* session = nullptr;
  if (llambda_npu_session_create(argv[1], nullptr, nullptr, &session) != 0) {
    std::cerr << "Session creation failed: " << llambda_npu_last_error() << '\n';
    return 1;
  }
  const auto session_end = std::chrono::steady_clock::now();

  const size_t input_count =
      llambda_npu_session_input_element_count(session);
  const size_t output_count =
      llambda_npu_session_output_element_count(session);
  std::vector<float> input(input_count, 0.5f);
  std::vector<float> output(output_count);
  for (int index = 0; index < warmup_runs; ++index) {
    if (llambda_npu_session_run(session, input.data(), input.size(),
                                output.data(), output.size()) != 0) {
      std::cerr << "Warmup failed: " << llambda_npu_last_error() << '\n';
      llambda_npu_session_destroy(session);
      return 1;
    }
  }

  const auto run_start = std::chrono::steady_clock::now();
  for (int index = 0; index < timed_runs; ++index) {
    if (llambda_npu_session_run(session, input.data(), input.size(),
                                output.data(), output.size()) != 0) {
      std::cerr << "Inference failed: " << llambda_npu_last_error() << '\n';
      llambda_npu_session_destroy(session);
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
  std::cout << "VitisAI " << llambda_npu_runtime_version() << ": "
            << input_count << " inputs -> " << output_count
            << " outputs; session = " << compile_ms
            << " ms; warm run = " << run_ms
            << " ms; first output = "
            << (output.empty() ? 0.0f : output.front()) << '\n';
  llambda_npu_session_destroy(session);
  return 0;
}
