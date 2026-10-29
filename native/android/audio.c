// <audio/device> on Android: an AAudio stream pulls stereo float frames from a ring the app
// fills (audio_native_write). AAudio (Android 8, API 26) is loaded with dlopen, since apps
// start at API 24; on an older system audio_open fails with a message. The ring is single
// producer (the app's thread), single consumer (the data callback), so the callback takes no
// lock and allocates nothing. When the output goes away (headphones unplugged) the stream is
// opened again on the new default output.
#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct AAudioStreamStruct AAudioStream;
typedef struct AAudioStreamBuilderStruct AAudioStreamBuilder;
typedef int32_t (*DataCallback)(AAudioStream *, void *, void *, int32_t);
typedef void (*ErrorCallback)(AAudioStream *, void *, int32_t);

static struct {
    int32_t (*create_builder)(AAudioStreamBuilder **);
    void (*set_format)(AAudioStreamBuilder *, int32_t);
    void (*set_channels)(AAudioStreamBuilder *, int32_t);
    void (*set_rate)(AAudioStreamBuilder *, int32_t);
    void (*set_performance)(AAudioStreamBuilder *, int32_t);
    void (*set_usage)(AAudioStreamBuilder *, int32_t);
    void (*set_content)(AAudioStreamBuilder *, int32_t);
    void (*set_data_callback)(AAudioStreamBuilder *, DataCallback, void *);
    void (*set_error_callback)(AAudioStreamBuilder *, ErrorCallback, void *);
    int32_t (*open)(AAudioStreamBuilder *, AAudioStream **);
    int32_t (*delete_builder)(AAudioStreamBuilder *);
    int32_t (*start)(AAudioStream *);
    int32_t (*pause)(AAudioStream *);
    int32_t (*stop)(AAudioStream *);
    int32_t (*close)(AAudioStream *);
    const char *(*text)(int32_t);
    int loaded;
} aa;

enum { FORMAT_FLOAT = 2, PERFORMANCE_LOW_LATENCY = 12, USAGE_MEDIA = 1, USAGE_GAME = 14, CONTENT_MUSIC = 2,
       CONTENT_SONIFICATION = 4 };

typedef struct {
    AAudioStream *stream;
    pthread_mutex_t lock;
    int rate;
    int game;
    int running;
    int closed;
    float *data;
    uint64_t capacity;
    _Atomic uint64_t head;
    _Atomic uint64_t tail;
    _Atomic int clear;
} EskAudio;

static char audio_error[256];

const char *audio_native_error(void) { return audio_error; }

static int load(void) {
    if (aa.loaded) return 1;
    void *lib = dlopen("libaaudio.so", RTLD_NOW);
    if (!lib) {
        snprintf(audio_error, sizeof audio_error, "audio: AAudio is not available (Android 8 or later)");
        return 0;
    }
#define SYM(field, name) *(void **)&aa.field = dlsym(lib, name)
    SYM(create_builder, "AAudio_createStreamBuilder");
    SYM(set_format, "AAudioStreamBuilder_setFormat");
    SYM(set_channels, "AAudioStreamBuilder_setChannelCount");
    SYM(set_rate, "AAudioStreamBuilder_setSampleRate");
    SYM(set_performance, "AAudioStreamBuilder_setPerformanceMode");
    SYM(set_usage, "AAudioStreamBuilder_setUsage");
    SYM(set_content, "AAudioStreamBuilder_setContentType");
    SYM(set_data_callback, "AAudioStreamBuilder_setDataCallback");
    SYM(set_error_callback, "AAudioStreamBuilder_setErrorCallback");
    SYM(open, "AAudioStreamBuilder_openStream");
    SYM(delete_builder, "AAudioStreamBuilder_delete");
    SYM(start, "AAudioStream_requestStart");
    SYM(pause, "AAudioStream_requestPause");
    SYM(stop, "AAudioStream_requestStop");
    SYM(close, "AAudioStream_close");
    SYM(text, "AAudio_convertResultToText");
#undef SYM
    if (!aa.create_builder || !aa.open || !aa.set_data_callback || !aa.start || !aa.close) {
        snprintf(audio_error, sizeof audio_error, "audio: AAudio is incomplete on this system");
        return 0;
    }
    aa.loaded = 1;
    return 1;
}

static int32_t pull(AAudioStream *stream, void *user, void *audio, int32_t frames) {
    EskAudio *a = user;
    float *out = audio;
    uint64_t head = atomic_load_explicit(&a->head, memory_order_acquire);
    uint64_t tail = atomic_load_explicit(&a->tail, memory_order_relaxed);
    if (atomic_exchange_explicit(&a->clear, 0, memory_order_acq_rel)) tail = head;
    uint64_t take = head - tail;
    if (take > (uint64_t)frames) take = (uint64_t)frames;
    for (uint64_t i = 0; i < take; i++) {
        uint64_t at = ((tail + i) & (a->capacity - 1)) * 2;
        out[i * 2] = a->data[at];
        out[i * 2 + 1] = a->data[at + 1];
    }
    if (take < (uint64_t)frames) memset(out + take * 2, 0, ((uint64_t)frames - take) * 8);
    atomic_store_explicit(&a->tail, tail + take, memory_order_release);
    return 0;
}

static void lost(AAudioStream *stream, void *user, int32_t error);

// Opens the stream; the caller holds a->lock.
static int open_stream(EskAudio *a) {
    AAudioStreamBuilder *builder = NULL;
    int32_t result = aa.create_builder(&builder);
    if (result != 0) goto failed;
    aa.set_format(builder, FORMAT_FLOAT);
    aa.set_channels(builder, 2);
    aa.set_rate(builder, a->rate);
    if (aa.set_performance) aa.set_performance(builder, PERFORMANCE_LOW_LATENCY);
    if (aa.set_usage) aa.set_usage(builder, a->game ? USAGE_GAME : USAGE_MEDIA);
    if (aa.set_content) aa.set_content(builder, a->game ? CONTENT_SONIFICATION : CONTENT_MUSIC);
    aa.set_data_callback(builder, pull, a);
    if (aa.set_error_callback) aa.set_error_callback(builder, lost, a);
    result = aa.open(builder, &a->stream);
    aa.delete_builder(builder);
    if (result != 0) goto failed;
    if (a->running) aa.start(a->stream);
    return 1;
failed:
    snprintf(audio_error, sizeof audio_error, "audio: %s", aa.text ? aa.text(result) : "cannot open the output");
    a->stream = NULL;
    return 0;
}

static void *reopen(void *user) {
    EskAudio *a = user;
    pthread_mutex_lock(&a->lock);
    if (!a->closed) {
        if (a->stream) { aa.stop(a->stream); aa.close(a->stream); a->stream = NULL; }
        open_stream(a);
    }
    pthread_mutex_unlock(&a->lock);
    return NULL;
}

// The output went away: AAudio asks for the stream to be closed and opened again on another
// thread than the callback's.
static void lost(AAudioStream *stream, void *user, int32_t error) {
    pthread_t thread;
    if (pthread_create(&thread, NULL, reopen, user) == 0) pthread_detach(thread);
}

// game: the stream is a game's (usage GAME), otherwise media. mix_with_others and ignore_silent
// are iOS's: on Android media always mixes and the ringer does not mute it.
void *audio_native_open(int rate, int buffer_frames, int mix_with_others, int ignore_silent, int game) {
    audio_error[0] = 0;
    if (!load()) return NULL;
    EskAudio *a = calloc(1, sizeof *a);
    pthread_mutex_init(&a->lock, NULL);
    a->rate = rate;
    a->game = game;
    a->running = 1;
    uint64_t capacity = 1024;
    while (capacity < (uint64_t)buffer_frames) capacity *= 2;
    a->capacity = capacity;
    a->data = calloc(capacity * 2, sizeof(float));
    pthread_mutex_lock(&a->lock);
    int ok = open_stream(a);
    pthread_mutex_unlock(&a->lock);
    if (!ok) {
        pthread_mutex_destroy(&a->lock);
        free(a->data);
        free(a);
        return NULL;
    }
    return a;
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
    pthread_mutex_lock(&a->lock);
    if (a->running && a->stream) aa.pause(a->stream);
    a->running = 0;
    pthread_mutex_unlock(&a->lock);
}

void audio_native_resume(void *handle) {
    EskAudio *a = handle;
    pthread_mutex_lock(&a->lock);
    if (!a->running && a->stream) aa.start(a->stream);
    a->running = 1;
    pthread_mutex_unlock(&a->lock);
}

void audio_native_clear(void *handle) { atomic_store_explicit(&((EskAudio *)handle)->clear, 1, memory_order_release); }

void audio_native_close(void *handle) {
    EskAudio *a = handle;
    pthread_mutex_lock(&a->lock);
    a->closed = 1;
    if (a->stream) { aa.stop(a->stream); aa.close(a->stream); a->stream = NULL; }
    pthread_mutex_unlock(&a->lock);
    // A reopen thread already waiting sees `closed`; the handle is kept for it rather than
    // freed under it.
    free(a->data);
    a->data = NULL;
}
