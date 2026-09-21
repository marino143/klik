#ifndef KLIK_AEC3_H
#define KLIK_AEC3_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KlikAEC3Processor KlikAEC3Processor;

// AEC3 processes one 10 ms mono frame at a time. Supported sample rates are
// 16, 32, and 48 kHz. Samples use Klik's normalized float range [-1, 1].
KlikAEC3Processor *klik_aec3_create(int sample_rate_hz);
void klik_aec3_destroy(KlikAEC3Processor *processor);
size_t klik_aec3_frame_size(const KlikAEC3Processor *processor);
int klik_aec3_process_frame(KlikAEC3Processor *processor,
                            const float *render,
                            const float *capture,
                            float *output,
                            size_t sample_count);

#ifdef __cplusplus
}
#endif

#endif
