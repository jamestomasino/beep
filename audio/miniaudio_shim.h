#ifndef BEEP_MINIAUDIO_SHIM_H
#define BEEP_MINIAUDIO_SHIM_H

#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#ifndef BEEP_MAX_VOICES
#define BEEP_MAX_VOICES 160
#endif

#ifndef BEEP_MAX_SAMPLES
#define BEEP_MAX_SAMPLES 64
#endif

typedef struct beep_sample_t {
	int loaded;
	float* data;
	int frame_count;
} beep_sample_t;

typedef struct beep_voice_t {
	int active;
	int waveform; // 0 sine, 1 square, 2 saw, 3 noise, 4 click, 5 sample
	float freq0;
	float freq1;
	float gain;
	float phase;
	int sample_index;
	int sample_cursor;
	int start_delay_frames;
	int total_frames;
	int remaining_frames;
	uint32_t noise;
	float lp;
} beep_voice_t;

typedef struct beep_audio_state_t {
	ma_device device;
	ma_device_config config;
	pthread_mutex_t mu;
	beep_voice_t voices[BEEP_MAX_VOICES];
	beep_sample_t samples[BEEP_MAX_SAMPLES];
	int initialized;
	int sample_rate;
} beep_audio_state_t;

static beep_audio_state_t g_beep = {0};

static inline float beep_rand01(uint32_t* x) {
	*x = (*x * 1664525u) + 1013904223u;
	return (float)((*x >> 8) & 0xFFFFFFu) / 16777215.0f;
}

static inline float beep_next_sample(beep_voice_t* v, int frame_idx) {
	float t = 0.0f;
	if (v->total_frames > 0) {
		t = (float)frame_idx / (float)v->total_frames;
		if (t < 0.0f) t = 0.0f;
		if (t > 1.0f) t = 1.0f;
	}
	float freq = v->freq0 + (v->freq1 - v->freq0) * t;
	int attack_frames = v->total_frames / 120;
	if (v->waveform != 5 && v->total_frames > g_beep.sample_rate * 4) {
		// Long ambient tones: strong fade-in over first third.
		attack_frames = v->total_frames / 3;
	}
	if (attack_frames < 8) attack_frames = 8;
	int max_attack = g_beep.sample_rate * 6;
	if (attack_frames > max_attack) attack_frames = max_attack;
	float attack = (float)frame_idx / (float)attack_frames;
	if (attack > 1.0f) attack = 1.0f;
	float env = attack;
	if (v->total_frames > g_beep.sample_rate * 4) {
		// Fade out mainly during the last third for pad/drone-like voices.
		float tail_start = 0.68f;
		float tail = 1.0f;
		if (t > tail_start) {
			tail = (1.0f - t) / (1.0f - tail_start);
			if (tail < 0.0f) tail = 0.0f;
		}
		env *= tail * tail;
	} else {
		float release = 1.0f - t;
		if (release < 0.0f) release = 0.0f;
		env *= release * release;
	}
	float sample = 0.0f;

	switch (v->waveform) {
		case 0:
			sample = sinf(v->phase * 2.0f * 3.1415926535f);
			break;
		case 1:
			sample = (v->phase < 0.5f) ? 1.0f : -1.0f;
			break;
		case 2:
			sample = (2.0f * v->phase) - 1.0f;
			break;
		case 3:
			sample = beep_rand01(&v->noise) * 2.0f - 1.0f;
			break;
		case 4:
			sample = expf(-0.045f * (float)frame_idx);
			env *= 0.9f;
			break;
		case 5: {
			if (v->sample_index >= 0 && v->sample_index < BEEP_MAX_SAMPLES) {
				beep_sample_t* s = &g_beep.samples[v->sample_index];
				if (s->loaded && v->sample_cursor >= 0 && v->sample_cursor < s->frame_count) {
					sample = s->data[v->sample_cursor];
					v->sample_cursor++;
				}
			}
		} break;
		default:
			sample = 0.0f;
			break;
	}

	if (v->waveform != 5) {
		float step = freq / (float)g_beep.sample_rate;
		v->phase += step;
		if (v->phase >= 1.0f) {
			v->phase -= floorf(v->phase);
		}
	}
	float raw = sample * v->gain * env;
	float alpha = 0.30f;
	if (v->waveform == 1 || v->waveform == 2) alpha = 0.18f;
	if (v->waveform == 3 || v->waveform == 4) alpha = 0.12f;
	v->lp += alpha * (raw - v->lp);
	return v->lp;
}

static void beep_audio_callback(ma_device* device, void* output, const void* input, ma_uint32 frame_count) {
	(void)input;
	beep_audio_state_t* s = (beep_audio_state_t*)device->pUserData;
	float* out = (float*)output;

	pthread_mutex_lock(&s->mu);
	for (ma_uint32 i = 0; i < frame_count; i++) {
		float mix = 0.0f;
		for (int v = 0; v < BEEP_MAX_VOICES; v++) {
			beep_voice_t* voice = &s->voices[v];
			if (!voice->active || voice->remaining_frames <= 0) {
				voice->active = 0;
				continue;
			}
			if (voice->start_delay_frames > 0) {
				voice->start_delay_frames--;
				continue;
			}
			int frame_idx = voice->total_frames - voice->remaining_frames;
			mix += beep_next_sample(voice, frame_idx);
			voice->remaining_frames--;
			if (voice->remaining_frames <= 0) {
				voice->active = 0;
			}
		}
		mix = tanhf(mix * 0.85f);
		out[(i * 2) + 0] = mix;
		out[(i * 2) + 1] = mix;
	}
	pthread_mutex_unlock(&s->mu);
}

static inline int beep_audio_init(void) {
	if (g_beep.initialized) {
		return 1;
	}
	g_beep.sample_rate = 48000;
	if (pthread_mutex_init(&g_beep.mu, NULL) != 0) {
		return 0;
	}
	g_beep.config = ma_device_config_init(ma_device_type_playback);
	g_beep.config.playback.format = ma_format_f32;
	g_beep.config.playback.channels = 2;
	g_beep.config.sampleRate = (ma_uint32)g_beep.sample_rate;
	g_beep.config.dataCallback = beep_audio_callback;
	g_beep.config.pUserData = &g_beep;

	if (ma_device_init(NULL, &g_beep.config, &g_beep.device) != MA_SUCCESS) {
		return 0;
	}
	if (ma_device_start(&g_beep.device) != MA_SUCCESS) {
		ma_device_uninit(&g_beep.device);
		return 0;
	}
	g_beep.initialized = 1;
	return 1;
}

static inline void beep_audio_shutdown(void) {
	if (!g_beep.initialized) {
		return;
	}
	for (int i = 0; i < BEEP_MAX_SAMPLES; i++) {
		if (g_beep.samples[i].loaded && g_beep.samples[i].data != NULL) {
			free(g_beep.samples[i].data);
			g_beep.samples[i].data = NULL;
			g_beep.samples[i].loaded = 0;
			g_beep.samples[i].frame_count = 0;
		}
	}
	ma_device_uninit(&g_beep.device);
	pthread_mutex_destroy(&g_beep.mu);
	g_beep.initialized = 0;
}

static inline int beep_find_voice_slot(void) {
	int slot = -1;
	for (int i = 0; i < BEEP_MAX_VOICES; i++) {
		if (!g_beep.voices[i].active) {
			return i;
		}
	}

	// If saturated, steal the least-audible voice rather than dropping the new layer.
	float best_score = 999999.0f;
	for (int i = 0; i < BEEP_MAX_VOICES; i++) {
		beep_voice_t* v = &g_beep.voices[i];
		if (!v->active || v->total_frames <= 0) {
			return i;
		}
		float life = (float)v->remaining_frames / (float)v->total_frames;
		if (life < 0.0f) life = 0.0f;
		if (life > 1.0f) life = 1.0f;
		float delay_penalty = (v->start_delay_frames > 0) ? 0.20f : 0.0f;
		float score = (v->gain * (0.30f + life)) + delay_penalty;
		if (score < best_score) {
			best_score = score;
			slot = i;
		}
	}
	return slot;
}

static inline int beep_audio_enqueue_ex(int waveform, float freq0, float freq1, float gain, int duration_ms, int delay_ms, uint32_t seed) {
	if (!g_beep.initialized) {
		return 0;
	}
	if (duration_ms < 10) duration_ms = 10;
	if (delay_ms < 0) delay_ms = 0;
	if (gain < 0.01f) gain = 0.01f;
	if (gain > 1.0f) gain = 1.0f;

	int frames = (g_beep.sample_rate * duration_ms) / 1000;
	if (frames < 1) frames = 1;
	int delay_frames = (g_beep.sample_rate * delay_ms) / 1000;
	if (delay_frames < 0) delay_frames = 0;

	pthread_mutex_lock(&g_beep.mu);
	int slot = beep_find_voice_slot();
	if (slot == -1) {
		pthread_mutex_unlock(&g_beep.mu);
		return 0;
	}

	beep_voice_t* v = &g_beep.voices[slot];
	v->active = 1;
	v->waveform = waveform;
	v->freq0 = freq0;
	v->freq1 = freq1;
	v->gain = gain;
	v->phase = 0.0f;
	v->sample_index = -1;
	v->sample_cursor = 0;
	v->start_delay_frames = delay_frames;
	v->total_frames = frames;
	v->remaining_frames = frames;
	v->noise = seed ? seed : 0xA5A5A5A5u;
	v->lp = 0.0f;
	pthread_mutex_unlock(&g_beep.mu);
	return 1;
}

static inline int beep_audio_enqueue(int waveform, float freq0, float freq1, float gain, int duration_ms, uint32_t seed) {
	return beep_audio_enqueue_ex(waveform, freq0, freq1, gain, duration_ms, 0, seed);
}

static inline int beep_audio_load_sample(const char* path) {
	if (!g_beep.initialized || path == NULL || path[0] == '\0') {
		return -1;
	}

	int slot = -1;
	for (int i = 0; i < BEEP_MAX_SAMPLES; i++) {
		if (!g_beep.samples[i].loaded) {
			slot = i;
			break;
		}
	}
	if (slot < 0) {
		return -1;
	}

	ma_decoder decoder;
	ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 1, (ma_uint32)g_beep.sample_rate);
	if (ma_decoder_init_file(path, &cfg, &decoder) != MA_SUCCESS) {
		return -1;
	}

	ma_uint64 length = 0;
	if (ma_decoder_get_length_in_pcm_frames(&decoder, &length) != MA_SUCCESS || length == 0) {
		ma_decoder_uninit(&decoder);
		return -1;
	}
	if (length > (ma_uint64)g_beep.sample_rate * 15) {
		length = (ma_uint64)g_beep.sample_rate * 15;
	}

	float* data = (float*)malloc((size_t)length * sizeof(float));
	if (data == NULL) {
		ma_decoder_uninit(&decoder);
		return -1;
	}

	ma_uint64 read = 0;
	ma_result rr = ma_decoder_read_pcm_frames(&decoder, data, length, &read);
	ma_decoder_uninit(&decoder);
	if (rr != MA_SUCCESS || read == 0) {
		free(data);
		return -1;
	}

	g_beep.samples[slot].loaded = 1;
	g_beep.samples[slot].data = data;
	g_beep.samples[slot].frame_count = (int)read;
	return slot;
}

static inline int beep_audio_enqueue_sample_ex(int sample_index, float gain, int delay_ms) {
	if (!g_beep.initialized) {
		return 0;
	}
	if (sample_index < 0 || sample_index >= BEEP_MAX_SAMPLES) {
		return 0;
	}
	beep_sample_t* sample = &g_beep.samples[sample_index];
	if (!sample->loaded || sample->frame_count <= 0) {
		return 0;
	}
	if (delay_ms < 0) delay_ms = 0;
	if (gain < 0.01f) gain = 0.01f;
	if (gain > 1.0f) gain = 1.0f;
	int delay_frames = (g_beep.sample_rate * delay_ms) / 1000;
	if (delay_frames < 0) delay_frames = 0;

	pthread_mutex_lock(&g_beep.mu);
	int slot = beep_find_voice_slot();
	if (slot == -1) {
		pthread_mutex_unlock(&g_beep.mu);
		return 0;
	}

	beep_voice_t* v = &g_beep.voices[slot];
	v->active = 1;
	v->waveform = 5;
	v->freq0 = 0.0f;
	v->freq1 = 0.0f;
	v->gain = gain;
	v->phase = 0.0f;
	v->sample_index = sample_index;
	v->sample_cursor = 0;
	v->start_delay_frames = delay_frames;
	v->total_frames = sample->frame_count;
	v->remaining_frames = sample->frame_count;
	v->noise = 0xA5A5A5A5u;
	v->lp = 0.0f;
	pthread_mutex_unlock(&g_beep.mu);
	return 1;
}

#endif
