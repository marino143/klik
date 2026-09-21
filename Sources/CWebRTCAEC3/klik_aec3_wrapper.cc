#include "include/klik_aec3.h"

#include <algorithm>
#include <cmath>
#include <memory>

#include "api/echo_canceller3_config.h"
#include "api/echo_canceller3_factory.h"
#include "api/echo_control.h"
#include "api/environment.h"
#include "audio_processing/audio_buffer.h"

struct KlikAEC3Processor {
  explicit KlikAEC3Processor(int rate)
      : sample_rate_hz(rate),
        frame_size(static_cast<size_t>(rate / 100)),
        render_buffer(rate, 1, rate, 1, rate, 1),
        capture_buffer(rate, 1, rate, 1, rate, 1) {
    webrtc::EchoCanceller3Config config;
    config.filter.initial_state_seconds = 0.5f;
    config.filter.conservative_initial_phase = false;
    webrtc::EchoCanceller3Factory factory(config);
    echo_control = factory.Create(environment, rate, 1, 1);
    echo_control->SetCaptureOutputUsage(true);
  }

  int sample_rate_hz;
  size_t frame_size;
  webrtc::Environment environment;
  std::unique_ptr<webrtc::EchoControl> echo_control;
  webrtc::AudioBuffer render_buffer;
  webrtc::AudioBuffer capture_buffer;
};

KlikAEC3Processor *klik_aec3_create(int sample_rate_hz) {
  if (sample_rate_hz != 16000 && sample_rate_hz != 32000 &&
      sample_rate_hz != 48000) {
    return nullptr;
  }

  try {
    return new KlikAEC3Processor(sample_rate_hz);
  } catch (...) {
    return nullptr;
  }
}

void klik_aec3_destroy(KlikAEC3Processor *processor) { delete processor; }

size_t klik_aec3_frame_size(const KlikAEC3Processor *processor) {
  return processor ? processor->frame_size : 0;
}

int klik_aec3_process_frame(KlikAEC3Processor *processor,
                            const float *render,
                            const float *capture,
                            float *output,
                            size_t sample_count) {
  if (!processor || !render || !capture || !output ||
      sample_count != processor->frame_size) {
    return 0;
  }

  float *render_channel = processor->render_buffer.channels()[0];
  float *capture_channel = processor->capture_buffer.channels()[0];
  for (size_t i = 0; i < sample_count; ++i) {
    render_channel[i] = std::clamp(render[i], -1.0f, 1.0f) * 32767.0f;
    capture_channel[i] = std::clamp(capture[i], -1.0f, 1.0f) * 32767.0f;
  }

  processor->render_buffer.SplitIntoFrequencyBands();
  processor->capture_buffer.SplitIntoFrequencyBands();
  processor->echo_control->AnalyzeRender(&processor->render_buffer);
  processor->echo_control->AnalyzeCapture(&processor->capture_buffer);
  processor->echo_control->ProcessCapture(&processor->capture_buffer, false);
  processor->capture_buffer.MergeFrequencyBands();

  const float *clean_channel = processor->capture_buffer.channels_const()[0];
  for (size_t i = 0; i < sample_count; ++i) {
    output[i] = std::clamp(clean_channel[i] / 32767.0f, -1.0f, 1.0f);
  }
  return 1;
}
