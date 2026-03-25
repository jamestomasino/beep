#include <stddef.h>
#include <stdint.h>
#include <string.h>

#if defined(__APPLE__)

#include <AudioToolbox/AudioToolbox.h>
#include <pthread.h>
#include <stdatomic.h>

#define BEEP_STREAM_RING_FRAMES 262144u
#define BEEP_STREAM_BUFFER_FRAMES 2048u
#define BEEP_STREAM_BUFFER_COUNT 3u

static AudioQueueRef g_queue = NULL;
static AudioQueueBufferRef g_buffers[BEEP_STREAM_BUFFER_COUNT];
static float g_ring[BEEP_STREAM_RING_FRAMES];
static size_t g_read_idx = 0;
static size_t g_write_idx = 0;
static size_t g_count = 0;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static atomic_int g_active = 0;

static void beep_stream_read(float* out, size_t frames) {
  size_t i;
  pthread_mutex_lock(&g_lock);
  for (i = 0; i < frames; ++i) {
    if (g_count > 0) {
      out[i] = g_ring[g_read_idx];
      g_read_idx = (g_read_idx + 1u) % BEEP_STREAM_RING_FRAMES;
      g_count--;
    } else {
      out[i] = 0.0f;
    }
  }
  pthread_mutex_unlock(&g_lock);
}

static void beep_audio_output_cb(void* user_data, AudioQueueRef queue, AudioQueueBufferRef buffer) {
  (void)user_data;
  (void)queue;
  if (atomic_load_explicit(&g_active, memory_order_acquire) == 0) {
    memset(buffer->mAudioData, 0, buffer->mAudioDataBytesCapacity);
    buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
    return;
  }

  {
    size_t frames = (size_t)(buffer->mAudioDataBytesCapacity / sizeof(float));
    beep_stream_read((float*)buffer->mAudioData, frames);
    buffer->mAudioDataByteSize = (UInt32)(frames * sizeof(float));
  }

  AudioQueueEnqueueBuffer(g_queue, buffer, 0, NULL);
}

int beep_audio_stream_init(unsigned sample_rate) {
  AudioStreamBasicDescription fmt;
  UInt32 i;
  OSStatus st;

  if (atomic_load_explicit(&g_active, memory_order_acquire) != 0) {
    return 1;
  }

  memset(&fmt, 0, sizeof(fmt));
  fmt.mSampleRate = (Float64)sample_rate;
  fmt.mFormatID = kAudioFormatLinearPCM;
  fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  fmt.mBytesPerPacket = sizeof(float);
  fmt.mFramesPerPacket = 1;
  fmt.mBytesPerFrame = sizeof(float);
  fmt.mChannelsPerFrame = 1;
  fmt.mBitsPerChannel = 32;

  st = AudioQueueNewOutput(&fmt, beep_audio_output_cb, NULL, NULL, NULL, 0, &g_queue);
  if (st != noErr) {
    g_queue = NULL;
    return 0;
  }

  g_read_idx = 0;
  g_write_idx = 0;
  g_count = 0;

  for (i = 0; i < BEEP_STREAM_BUFFER_COUNT; ++i) {
    st = AudioQueueAllocateBuffer(g_queue, (UInt32)(BEEP_STREAM_BUFFER_FRAMES * sizeof(float)), &g_buffers[i]);
    if (st != noErr) {
      AudioQueueDispose(g_queue, true);
      g_queue = NULL;
      return 0;
    }
    memset(g_buffers[i]->mAudioData, 0, g_buffers[i]->mAudioDataBytesCapacity);
    g_buffers[i]->mAudioDataByteSize = g_buffers[i]->mAudioDataBytesCapacity;
    AudioQueueEnqueueBuffer(g_queue, g_buffers[i], 0, NULL);
  }

  st = AudioQueueStart(g_queue, NULL);
  if (st != noErr) {
    AudioQueueDispose(g_queue, true);
    g_queue = NULL;
    return 0;
  }

  atomic_store_explicit(&g_active, 1, memory_order_release);
  return 1;
}

int beep_audio_stream_write(const float* samples, unsigned frames) {
  size_t i;
  size_t needed;
  size_t drop;

  if (atomic_load_explicit(&g_active, memory_order_acquire) == 0 || samples == NULL || frames == 0u) {
    return 0;
  }

  needed = (size_t)frames;
  pthread_mutex_lock(&g_lock);

  if (needed >= BEEP_STREAM_RING_FRAMES) {
    samples += needed - (BEEP_STREAM_RING_FRAMES - 1u);
    needed = BEEP_STREAM_RING_FRAMES - 1u;
  }

  if (needed > (BEEP_STREAM_RING_FRAMES - g_count)) {
    drop = needed - (BEEP_STREAM_RING_FRAMES - g_count);
    g_read_idx = (g_read_idx + drop) % BEEP_STREAM_RING_FRAMES;
    g_count -= drop;
  }

  for (i = 0; i < needed; ++i) {
    g_ring[g_write_idx] = samples[i];
    g_write_idx = (g_write_idx + 1u) % BEEP_STREAM_RING_FRAMES;
  }
  g_count += needed;

  pthread_mutex_unlock(&g_lock);
  return 1;
}

void beep_audio_stream_shutdown(void) {
  if (atomic_load_explicit(&g_active, memory_order_acquire) == 0) {
    return;
  }

  atomic_store_explicit(&g_active, 0, memory_order_release);
  if (g_queue != NULL) {
    AudioQueueStop(g_queue, true);
    AudioQueueDispose(g_queue, true);
    g_queue = NULL;
  }

  pthread_mutex_lock(&g_lock);
  g_read_idx = 0;
  g_write_idx = 0;
  g_count = 0;
  pthread_mutex_unlock(&g_lock);
}

int beep_audio_stream_is_active(void) {
  return atomic_load_explicit(&g_active, memory_order_acquire);
}

#else

int beep_audio_stream_init(unsigned sample_rate) {
  (void)sample_rate;
  return 0;
}

int beep_audio_stream_write(const float* samples, unsigned frames) {
  (void)samples;
  (void)frames;
  return 0;
}

void beep_audio_stream_shutdown(void) {
}

int beep_audio_stream_is_active(void) {
  return 0;
}

#endif
