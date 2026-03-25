module audio

pub struct SynthConfig {
pub:
	hum_freq_min           f32 = 68
	hum_freq_max           f32 = 118
	drone_freq_min         f32 = 52
	drone_freq_max         f32 = 92
	wobble_freq_min        f32 = 84
	wobble_freq_max        f32 = 140
	ambient_noise_chance   f32 = 0.40
	ambient_noise_gain     f32 = 0.08
	ambient_blip_chance    f32 = 0.36
	ambient_blip_gain      f32 = 0.10
	cluster_steps_min      int = 3
	cluster_steps_max      int = 12
	cluster_spacing_min_ms int = 6
	cluster_spacing_max_ms int = 16
	stutter_steps_min      int = 2
	stutter_steps_max      int = 5
	stutter_spacing_min_ms int = 12
	stutter_spacing_max_ms int = 26
}
