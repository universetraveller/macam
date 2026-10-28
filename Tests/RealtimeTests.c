// SPDX-License-Identifier: GPL-3.0-only
#include "Realtime.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    MacamMeter *meter = macam_meter_create(); assert(meter);
    float stereo[] = {0.25f, -0.5f, 0, 0.75f, NAN, INFINITY};
    AudioBufferList input = { .mNumberBuffers = 1,
        .mBuffers = {{ .mNumberChannels = 2, .mDataByteSize = sizeof(stereo), .mData = stereo }} };
    float sentinel = 0.123f;
    AudioBufferList output = { .mNumberBuffers = 1,
        .mBuffers = {{ .mNumberChannels = 1, .mDataByteSize = sizeof(sentinel), .mData = &sentinel }} };
    AudioTimeStamp time = { .mSampleTime = 0, .mFlags = kAudioTimeStampSampleTimeValid };
    assert(macam_input_callback(0, &time, &input, &time, &output, &time, meter) == noErr);
    MacamReading r = macam_meter_read(meter);
    assert(r.frames == 3 && r.samples == 6 && r.nonzero == 3 && r.callbacks == 1);
    assert(r.peak == 0.75f && r.maximumPeak == 0.75f && isfinite(r.rms));
    assert(fabsf(r.rms - sqrtf((0.0625f + 0.25f + 0.5625f) / 6)) < 0.00001f);
    assert(sentinel == 0.123f); // Input metering must never replay audio.
    time.mSampleTime = 3;
    macam_input_callback(0, &time, &input, &time, &output, &time, meter);
    assert(macam_meter_read(meter).discontinuities == 0);
    time.mSampleTime = 10; // Four missing sample frames.
    macam_input_callback(0, &time, &input, &time, &output, &time, meter);
    assert(macam_meter_read(meter).discontinuities == 1);
    macam_meter_destroy(meter);

    // Two non-interleaved stereo buffers count frames once, not once per channel.
    struct { UInt32 mNumberBuffers; AudioBuffer mBuffers[2]; } planar;
    float left[] = {0.1f, 0.2f}, right[] = {0.3f, 0.4f};
    planar.mNumberBuffers = 2;
    planar.mBuffers[0] = (AudioBuffer){1, sizeof(left), left};
    planar.mBuffers[1] = (AudioBuffer){1, sizeof(right), right};
    meter = macam_meter_create();
    time.mSampleTime = 0;
    macam_input_callback(0, &time, (AudioBufferList *)&planar, &time, &output, &time, meter);
    r = macam_meter_read(meter);
    assert(r.frames == 2 && r.samples == 4 && r.nonzero == 4 && r.maximumPeak == 0.4f);
    planar.mBuffers[0].mData = NULL; planar.mBuffers[1].mData = NULL;
    time.mFlags = 0;
    macam_input_callback(0, &time, (AudioBufferList *)&planar, &time, &output, &time, meter);
    r = macam_meter_read(meter);
    assert(r.peak == 0 && r.rms == 0 && r.maximumPeak == 0.4f);
    macam_meter_destroy(meter);
    puts("Realtime meter tests passed (stereo, formats, non-finite data, gaps, no replay).");
}
