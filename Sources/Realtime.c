// SPDX-License-Identifier: GPL-3.0-only
#include "Realtime.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <libproc.h>
#include <dlfcn.h>

// Helper-resolution direction adapted from FineTune's AudioProcessMonitor,
// Copyright (C) 2026 Ronit Singh, GPL-3.0. See THIRD_PARTY_NOTICES.md.
pid_t macam_parent_pid(pid_t pid) {
    struct proc_bsdinfo info = {0};
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info) ? (pid_t)info.pbi_ppid : 0;
}
pid_t macam_responsible_pid(pid_t pid) {
    // Optional private API, invoked only on the control thread. No hard link or
    // correctness dependency: ancestry/path/bundle matching remain available.
    typedef pid_t (*Responsible)(pid_t);
    Responsible fn = (Responsible)dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid");
    return fn ? fn(pid) : 0;
}
int macam_process_path(pid_t pid, char *path, uint32_t size) { return proc_pidpath(pid, path, size); }

// One HAL writer; UI/diagnostics readers. All shared fields use lock-free atomics.
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2 && ATOMIC_INT_LOCK_FREE == 2,
               "Macam requires lock-free meter atomics");
struct MacamMeter {
    _Atomic uint64_t callbacks, frames, samples, nonzero, discontinuities;
    _Atomic uint32_t peakBits, rmsBits, maximumPeakBits;
    double previousEnd;
    bool hasTime;
};
MacamMeter *macam_meter_create(void) { return calloc(1, sizeof(MacamMeter)); }
void macam_meter_destroy(MacamMeter *m) { free(m); }
static float floatValue(uint32_t v) { float f; memcpy(&f, &v, 4); return f; }
static uint32_t floatBits(float f) { uint32_t v; memcpy(&v, &f, 4); return v; }
MacamReading macam_meter_read(const MacamMeter *m) {
    return (MacamReading){
        atomic_load_explicit(&m->callbacks, memory_order_relaxed),
        atomic_load_explicit(&m->frames, memory_order_relaxed),
        atomic_load_explicit(&m->samples, memory_order_relaxed),
        atomic_load_explicit(&m->nonzero, memory_order_relaxed),
        atomic_load_explicit(&m->discontinuities, memory_order_relaxed),
        floatValue(atomic_load_explicit(&m->peakBits, memory_order_relaxed)),
        floatValue(atomic_load_explicit(&m->rmsBits, memory_order_relaxed)),
        floatValue(atomic_load_explicit(&m->maximumPeakBits, memory_order_relaxed))
    };
}
OSStatus macam_input_callback(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    MacamMeter *m = context;
    float peak = 0; double energy = 0;
    uint64_t count = 0, nonzero = 0, frames = 0;
    // Setup validates Float32 PCM before installing this callback. No ObjC/Swift,
    // allocation, locks, property queries, dispatch, logging, or output writes.
    for (UInt32 b = 0; b < input->mNumberBuffers; ++b) {
        const AudioBuffer *buffer = &input->mBuffers[b];
        if (!buffer->mData || !buffer->mNumberChannels) continue;
        const float *data = buffer->mData;
        uint64_t n = buffer->mDataByteSize / sizeof(float);
        uint64_t f = n / buffer->mNumberChannels;
        if (f > frames) frames = f;
        for (uint64_t i = 0; i < n; ++i) {
            float v = data[i];
            if (!isfinite(v)) continue;
            float a = fabsf(v);
            if (a > peak) peak = a;
            energy += (double)v * v;
            if (a > 0.000001f) ++nonzero;
        }
        count += n;
    }
    if (inputTime->mFlags & kAudioTimeStampSampleTimeValid) {
        if (m->hasTime && fabs(inputTime->mSampleTime - m->previousEnd) > 1)
            atomic_fetch_add_explicit(&m->discontinuities, 1, memory_order_relaxed);
        m->previousEnd = inputTime->mSampleTime + frames;
        m->hasTime = true;
    }
    atomic_fetch_add_explicit(&m->callbacks, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&m->frames, frames, memory_order_relaxed);
    atomic_fetch_add_explicit(&m->samples, count, memory_order_relaxed);
    atomic_fetch_add_explicit(&m->nonzero, nonzero, memory_order_relaxed);
    atomic_store_explicit(&m->peakBits, floatBits(peak), memory_order_relaxed);
    atomic_store_explicit(&m->rmsBits, floatBits(count ? sqrt(energy / count) : 0), memory_order_relaxed);
    float maximum = floatValue(atomic_load_explicit(&m->maximumPeakBits, memory_order_relaxed));
    if (peak > maximum) atomic_store_explicit(&m->maximumPeakBits, floatBits(peak), memory_order_relaxed);
    return noErr;
}
