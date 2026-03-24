# Reference WAV Analyzer

Use this to analyze vintage sci-fi reference WAV files and produce suggested `beep` tuning values.

## What It Does

- Reads `.wav` files (8/16/24/32-bit PCM, mono or stereo).
- Extracts lightweight features: duration, dominant frequency, frequency drift, onset density, transientness, sustainedness.
- Assigns a rough motif class (`hum`, `drone`, `wobble`, `cluster`, `tick`, `chirp`, `yip`, etc.).
- Emits a `config.conf` snippet for engine knobs such as:
  - `hum_base_chance`, `hum_gain_scale`, `hum_active_max`
  - `*_stutter_chance`, `*_chirp_chance`
  - `min_gap_ms`, `cooldown_ms`
- Emits synth-shaping keys that now map directly into runtime motifs:
  - `hum_freq_*`, `drone_freq_*`, `wobble_freq_*`
  - `ambient_noise_*`, `ambient_blip_*`
  - `cluster_*`, `stutter_*`

## Run

```bash
python3 tools/reference_analyzer.py /path/to/wavs
```

Directory mode (recursive):

```bash
python3 tools/reference_analyzer.py ./refs/vintage_scifi
```

Print config snippet only:

```bash
python3 tools/reference_analyzer.py ./refs --only-config
```

Keep silence (disable auto trim):

```bash
python3 tools/reference_analyzer.py ./refs --no-trim
```

## Apply Result

1. Copy emitted key/value lines into `~/.config/beep/config.conf`.
2. Start beep with your normal run command.
3. Iterate by adding/removing reference WAVs and re-running analyzer.

## Notes

- This is heuristic analysis, not sample cloning.
- It is intended to bootstrap style matching, then you refine by ear.
- For best results, use a reference set with varied short events plus sustained ambients.
