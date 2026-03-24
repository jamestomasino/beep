# Config

Default path: `~/.config/beep/config.conf`

Format is simple `key=value` lines (`#` comments supported).

## Example

```conf
# profile: calm | normal | noisy
profile=normal

debug_fake_input=false
enable_cpu=true
enable_system=true
enable_network=true
log_events=false
debug_cpu=false
audio_backend=miniaudio
master_volume=1.00
ambient_level=1.00
burst_density=1.00

keyboard_threshold=0.25
mouse_threshold=0.20
cpu_active_cutoff=0.35
cpu_busy_cutoff=0.75
process_threshold=0.15
memory_threshold=0.18
system_threshold=0.20
network_threshold=0.16

# motif behavior tuning
keyboard_yip_intensity=0.72
keyboard_yip_chance=0.38
keyboard_chirp_chance=0.20
mouse_flick_intensity=0.65
mouse_flick_chance=0.33
mouse_click_zap_chance=1.00

# hum/drone and cpu modulation
hum_active_max=0.68
hum_base_chance=0.74
hum_gain_scale=0.58
cpu_warble_active_chance=0.18
cpu_warble_busy_chance=0.44

# synth voice shaping (runtime motif synthesis)
hum_freq_min=68
hum_freq_max=118
drone_freq_min=52
drone_freq_max=92
wobble_freq_min=84
wobble_freq_max=140
ambient_noise_chance=0.40
ambient_noise_gain=0.08
ambient_blip_chance=0.36
ambient_blip_gain=0.10
cluster_steps_min=3
cluster_steps_max=8
cluster_spacing_min_ms=6
cluster_spacing_max_ms=16
stutter_steps_min=2
stutter_steps_max=5
stutter_spacing_min_ms=12
stutter_spacing_max_ms=26

# burst motif thresholds/chances
process_stutter_intensity=0.55
process_stutter_chance=0.35
memory_warble_intensity=0.44
memory_warble_chance=0.28
system_stutter_intensity=0.50
system_stutter_chance=0.42
network_chirp_intensity=0.60
network_chirp_chance=0.46
network_stutter_intensity=0.72
network_stutter_chance=0.30

min_gap_ms=70
cooldown_ms=180
```

## CLI override examples

```bash
v run . --profile=noisy --debug-events
v run . --config=/tmp/beep.conf --audio-null
v run . --debug-fake-input --no-cpu --no-system --no-net
v -d x11_input run . --x11-input
v -d x11_input -d x11_xi2 run . --x11-input --x11-mode=xi2
```
