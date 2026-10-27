#include <stddef.h>
#include <stdint.h>
#include <string.h>

#if defined(__APPLE__)

#include <AudioToolbox/AudioQueue.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>

/*
 * Ring buffer sized to a few mixer chunks (8 x 512 = 4096 frames, ~93 ms).
 * AudioQueue buffers are 512 frames each (matching the mixer chunk size) so
 * the queue stays ahead of the reader without the writer ever needing to
 * block under normal operation.
 */
#define BEEP_STREAM_RING_FRAMES 4096u
#define BEEP_STREAM_BUFFER_FRAMES 512u
#define BEEP_STREAM_BUFFER_COUNT 8u

static AudioQueueRef g_queue = NULL;
static AudioQueueBufferRef g_buffers[BEEP_STREAM_BUFFER_COUNT];
static float g_ring[BEEP_STREAM_RING_FRAMES];
static size_t g_read_idx = 0;
static size_t g_write_idx = 0;
static size_t g_count = 0;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_cond = PTHREAD_COND_INITIALIZER;
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
  /* Wake a writer that may be blocked waiting for ring space. */
  pthread_cond_broadcast(&g_cond);
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

/*
 * Submit one chunk of float samples to the ring.
 *
 * Backpressure: if the ring is full the writer blocks on the condition
 * variable (guarded by g_lock) until the AudioQueue callback drains space,
 * or until shutdown signals.  This replaces the old drop-oldest-PCM
 * behavior: no queued PCM is silently lost under normal backpressure.
 *
 * Returns 1 on success, 0 if the stream is inactive (shutdown was called).
 */
int beep_audio_stream_write(const float* samples, unsigned frames) {
  size_t i;
  size_t needed = (size_t)frames;

  if (atomic_load_explicit(&g_active, memory_order_acquire) == 0 || samples == NULL || frames == 0u) {
    return 0;
  }

  /* A chunk larger than the whole ring can never be admitted; reject it
   * rather than spinning on the bounded wait and dropping it forever.
   * The Ada player always writes 512-frame chunks, well within the limit. */
  if ((size_t)frames > BEEP_STREAM_RING_FRAMES) {
    return 0;
  }

  pthread_mutex_lock(&g_lock);

  /* Wait until the ring has room for the full chunk, or shutdown signals.
   * The wait is bounded (20 ms) and re-checked in the loop (spurious-wakeup
   * safety): if the AudioQueue callback is paused and never drains the ring,
   * the writer drops the chunk rather than hanging, matching the Linux
   * EAGAIN-drop policy.  A blocked writer always wakes on shutdown. */
  for (;;) {
    if (atomic_load_explicit(&g_active, memory_order_acquire) == 0) {
      pthread_mutex_unlock(&g_lock);
      return 0;
    }
    if (g_count + needed <= BEEP_STREAM_RING_FRAMES) {
      break;
    }

    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_nsec += 20L * 1000L * 1000L;
    if (deadline.tv_nsec >= 1000000000L) {
      deadline.tv_sec += 1;
      deadline.tv_nsec -= 1000000000L;
    }
    if (pthread_cond_timedwait(&g_cond, &g_lock, &deadline) == ETIMEDOUT) {
      /* Space never freed: drop this chunk, the next chunk retries. */
      pthread_mutex_unlock(&g_lock);
      return 0;
    }
  }

  for (i = 0; i < needed; ++i) {
    g_ring[g_write_idx] = samples[i];
    g_write_idx = (g_write_idx + 1u) % BEEP_STREAM_RING_FRAMES;
  }
  g_count += needed;

  pthread_mutex_unlock(&g_lock);
  return 1;
}

/*
 * Shutdown: set the inactive flag, broadcast the condition variable (waking
 * any blocked writer), then dispose the AudioQueue and reset the ring.
 * A writer blocked in beep_audio_stream_write wakes, sees the inactive
 * flag, and returns 0 so the Ada player can exit.
 */
void beep_audio_stream_shutdown(void) {
  if (atomic_load_explicit(&g_active, memory_order_acquire) == 0) {
    return;
  }

  pthread_mutex_lock(&g_lock);
  atomic_store_explicit(&g_active, 0, memory_order_release);
  pthread_cond_broadcast(&g_cond);
  pthread_mutex_unlock(&g_lock);

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
