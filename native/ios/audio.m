// <audio/device> on iOS: a RemoteIO audio unit pulls stereo float frames from a ring the app
// fills (audio_native_write). The ring is single producer (the app's thread), single consumer
// (the render callback), so the callback takes no lock and allocates nothing.
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    AudioUnit unit;
    float *data;
    uint64_t capacity;
    _Atomic uint64_t head;
    _Atomic uint64_t tail;
    _Atomic int clear;
    int running;
} EskAudio;

static char audio_error[256];

static const char *fail(const char *what, OSStatus status) {
    snprintf(audio_error, sizeof audio_error, "%s (OSStatus %d)", what, (int)status);
    return audio_error;
}

const char *audio_native_error(void) { return audio_error; }

static OSStatus render(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *stamp, UInt32 bus,
                       UInt32 frames, AudioBufferList *io) {
    EskAudio *a = ref;
    float *out = io->mBuffers[0].mData;
    uint64_t head = atomic_load_explicit(&a->head, memory_order_acquire);
    uint64_t tail = atomic_load_explicit(&a->tail, memory_order_relaxed);
    if (atomic_exchange_explicit(&a->clear, 0, memory_order_acq_rel)) tail = head;
    uint64_t take = head - tail;
    if (take > frames) take = frames;
    for (uint64_t i = 0; i < take; i++) {
        uint64_t at = ((tail + i) & (a->capacity - 1)) * 2;
        out[i * 2] = a->data[at];
        out[i * 2 + 1] = a->data[at + 1];
    }
    if (take < frames) memset(out + take * 2, 0, (frames - take) * 8);
    atomic_store_explicit(&a->tail, tail + take, memory_order_release);
    return noErr;
}

// The session: mix_with_others lets other apps' sound go on; ignore_silent plays with the
// ringer switch on silent (the Playback category) instead of muting (Ambient / SoloAmbient).
static void configure_session(int rate, int mix_with_others, int ignore_silent) {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    AVAudioSessionCategory category = ignore_silent ? AVAudioSessionCategoryPlayback
        : (mix_with_others ? AVAudioSessionCategoryAmbient : AVAudioSessionCategorySoloAmbient);
    AVAudioSessionCategoryOptions options = ignore_silent && mix_with_others ? AVAudioSessionCategoryOptionMixWithOthers : 0;
    [session setCategory:category withOptions:options error:nil];
    [session setPreferredSampleRate:rate error:nil];
    [session setActive:YES error:nil];
}

// game (the stream's Android usage) has no iOS counterpart.
void *audio_native_open(int rate, int buffer_frames, int mix_with_others, int ignore_silent, int game) {
    audio_error[0] = 0;
    configure_session(rate, mix_with_others, ignore_silent);
    EskAudio *a = calloc(1, sizeof *a);
    uint64_t capacity = 1024;
    while (capacity < (uint64_t)buffer_frames) capacity *= 2;
    a->capacity = capacity;
    a->data = calloc(capacity * 2, sizeof(float));
    AudioComponentDescription desc = {kAudioUnitType_Output, kAudioUnitSubType_RemoteIO, kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    OSStatus status = component ? AudioComponentInstanceNew(component, &a->unit) : -1;
    if (status != noErr) { fail("audio: no output unit", status); goto failed; }
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = rate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 32;
    format.mBytesPerFrame = 8;
    format.mFramesPerPacket = 1;
    format.mBytesPerPacket = 8;
    status = AudioUnitSetProperty(a->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format);
    if (status != noErr) { fail("audio: stream format", status); goto failed; }
    AURenderCallbackStruct callback = {render, a};
    status = AudioUnitSetProperty(a->unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof callback);
    if (status != noErr) { fail("audio: render callback", status); goto failed; }
    status = AudioUnitInitialize(a->unit);
    if (status != noErr) { fail("audio: initialize", status); goto failed; }
    status = AudioOutputUnitStart(a->unit);
    if (status != noErr) { fail("audio: start", status); goto failed; }
    a->running = 1;
    return a;
failed:
    if (a->unit) AudioComponentInstanceDispose(a->unit);
    free(a->data);
    free(a);
    return NULL;
}

int audio_native_write(void *handle, const float *samples, int frames) {
    EskAudio *a = handle;
    uint64_t head = atomic_load_explicit(&a->head, memory_order_relaxed);
    uint64_t tail = atomic_load_explicit(&a->tail, memory_order_acquire);
    uint64_t room = a->capacity - (head - tail);
    uint64_t put = (uint64_t)frames < room ? (uint64_t)frames : room;
    for (uint64_t i = 0; i < put; i++) {
        uint64_t at = ((head + i) & (a->capacity - 1)) * 2;
        a->data[at] = samples[i * 2];
        a->data[at + 1] = samples[i * 2 + 1];
    }
    atomic_store_explicit(&a->head, head + put, memory_order_release);
    return (int)put;
}

int audio_native_queued(void *handle) {
    EskAudio *a = handle;
    if (atomic_load_explicit(&a->clear, memory_order_acquire)) return 0;
    return (int)(atomic_load_explicit(&a->head, memory_order_acquire) - atomic_load_explicit(&a->tail, memory_order_acquire));
}

int audio_native_capacity(void *handle) { return (int)((EskAudio *)handle)->capacity; }

void audio_native_pause(void *handle) {
    EskAudio *a = handle;
    if (a->running) { AudioOutputUnitStop(a->unit); a->running = 0; }
}

void audio_native_resume(void *handle) {
    EskAudio *a = handle;
    if (!a->running) {
        [AVAudioSession.sharedInstance setActive:YES error:nil];
        if (AudioOutputUnitStart(a->unit) == noErr) a->running = 1;
    }
}

void audio_native_clear(void *handle) { atomic_store_explicit(&((EskAudio *)handle)->clear, 1, memory_order_release); }

void audio_native_close(void *handle) {
    EskAudio *a = handle;
    AudioOutputUnitStop(a->unit);
    AudioUnitUninitialize(a->unit);
    AudioComponentInstanceDispose(a->unit);
    free(a->data);
    free(a);
}
