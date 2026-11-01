#include <math.h>
#include <string.h>

__attribute__((target_clones("avx2", "default")))
void selective_scan(const float *u, const float *delta, const float *bias, const float *bc, long bc_stride, const float *z, long z_stride, const float *a, const float *skip, float *y, long batch, long length, long channels, long states)
{
#pragma omp parallel for schedule(static)
    for (long i = 0; i < batch; i++) {
        float h[channels * states], step[channels], gate[channels];
        memset(h, 0, sizeof h);
        for (long t = 0; t < length; t++) {
            long row = i * length + t;
            const float *ut = u + row * channels;
            const float *dt = delta + row * channels;
            const float *zt = z + row * z_stride;
            const float *bt = bc + row * bc_stride;
            const float *ct = bt + states;
            float *yt = y + row * channels;
#pragma omp simd
            for (long d = 0; d < channels; d++) {
                float v = dt[d] + bias[d];
                step[d] = v > 20 ? v : log1pf(expf(v));
                gate[d] = zt[d] / (1 + expf(-zt[d]));
            }
            for (long d = 0; d < channels; d++) {
                float x = step[d] * ut[d];
                float *hd = h + d * states;
                const float *ad = a + d * states;
                float acc = 0;
#pragma omp simd reduction(+ : acc)
                for (long n = 0; n < states; n++) {
                    hd[n] = expf(step[d] * ad[n]) * hd[n] + x * bt[n];
                    acc += hd[n] * ct[n];
                }
                yt[d] = (acc + skip[d] * ut[d]) * gate[d];
            }
        }
    }
}

__attribute__((target_clones("avx2", "default")))
void causal_conv(const float *input, long input_stride, const float *weight, const float *bias, float *output, long batch, long length, long channels, long width)
{
#pragma omp parallel for schedule(static)
    for (long row = 0; row < batch * length; row++) {
        long t = row % length;
        float *out = output + row * channels;
#pragma omp simd
        for (long d = 0; d < channels; d++) {
            float acc = bias[d];
            for (long k = 0; k < width; k++) {
                long back = width - 1 - k;
                if (t >= back) {
                    acc += weight[d * width + k] * input[(row - back) * input_stride + d];
                }
            }
            out[d] = acc / (1 + expf(-acc));
        }
    }
}
