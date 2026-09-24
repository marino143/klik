#include "klik_aec3.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

int main() {
  constexpr int sample_rate = 48000;
  constexpr size_t frame_size = sample_rate / 100;
  constexpr int frame_count = 600;
  constexpr size_t echo_delay = frame_size * 3;

  auto* processor = klik_aec3_create(sample_rate);
  if (!processor || klik_aec3_frame_size(processor) != frame_size) {
    std::cerr << "AEC3 initialization failed\n";
    return 1;
  }

  uint64_t random_state = 0x12345678;
  std::vector<float> history(echo_delay, 0.0f);
  size_t history_index = 0;
  double input_energy = 0.0;
  double output_energy = 0.0;
  size_t measured_samples = 0;

  for (int frame_index = 0; frame_index < frame_count; ++frame_index) {
    std::vector<float> render(frame_size, 0.0f);
    std::vector<float> capture(frame_size, 0.0f);
    std::vector<float> output(frame_size, 0.0f);

    for (size_t index = 0; index < frame_size; ++index) {
      random_state = random_state * 6364136223846793005ULL + 1;
      const auto signed_bits = static_cast<int32_t>(random_state >> 32);
      render[index] = static_cast<float>(signed_bits) /
                      static_cast<float>(INT32_MAX) * 0.25f;
      capture[index] = history[history_index] * 0.55f;
      history[history_index] = render[index];
      history_index = (history_index + 1) % echo_delay;
    }

    if (klik_aec3_process_frame(processor, render.data(), capture.data(),
                                output.data(), frame_size) != 1) {
      std::cerr << "AEC3 rejected a frame\n";
      klik_aec3_destroy(processor);
      return 1;
    }

    if (frame_index >= 300) {
      for (size_t index = 0; index < frame_size; ++index) {
        input_energy += capture[index] * capture[index];
        output_energy += output[index] * output[index];
        ++measured_samples;
      }
    }
  }

  klik_aec3_destroy(processor);
  const double input_rms = std::sqrt(input_energy / measured_samples);
  const double output_rms = std::sqrt(output_energy / measured_samples);
  std::cout << "input_rms=" << input_rms << " output_rms=" << output_rms << '\n';
  return output_rms < input_rms * 0.5 ? 0 : 2;
}
