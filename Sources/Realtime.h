// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <CoreAudio/CoreAudio.h>

typedef struct MacamMeter MacamMeter;
typedef struct {
    uint64_t callbacks, frames, samples, nonzero, discontinuities;
    float peak, rms, maximumPeak;
} MacamReading;
MacamMeter * _Nullable macam_meter_create(void);
void macam_meter_destroy(MacamMeter * _Nonnull meter);
MacamReading macam_meter_read(const MacamMeter * _Nonnull meter);
OSStatus macam_input_callback(AudioObjectID device, const AudioTimeStamp * _Nonnull now,
    const AudioBufferList * _Nonnull input, const AudioTimeStamp * _Nonnull inputTime,
    AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime, void * _Nullable context);
pid_t macam_parent_pid(pid_t pid);
pid_t macam_responsible_pid(pid_t pid);
int macam_process_path(pid_t pid, char * _Nonnull path, uint32_t size);
