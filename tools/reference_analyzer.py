#!/usr/bin/env python3
"""Analyze reference WAV files and suggest beep engine config values.

No third-party dependencies required.
"""

from __future__ import annotations

import argparse
import math
import struct
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass
class Features:
    path: str
    duration_s: float
    rms: float
    peak: float
    crest: float
    zcr: float
    onset_rate: float
    dom_freq_hz: float
    freq_drift: float
    transientness: float
    sustainedness: float
    brightness: float
    motif: str


def clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else hi if v > hi else v


def discover_wavs(paths: list[str]) -> list[Path]:
    out: list[Path] = []
    for p in paths:
        path = Path(p)
        if path.is_dir():
            out.extend(sorted(x for x in path.rglob("*.wav") if x.is_file()))
        elif path.is_file() and path.suffix.lower() == ".wav":
            out.append(path)
    return out


def decode_pcm(raw: bytes, width: int, channels: int) -> list[float]:
    if width == 1:
        vals = [(b - 128) / 128.0 for b in raw]
    elif width == 2:
        n = len(raw) // 2
        ints = struct.unpack("<" + "h" * n, raw)
        vals = [x / 32768.0 for x in ints]
    elif width == 3:
        vals = []
        for i in range(0, len(raw), 3):
            b0 = raw[i]
            b1 = raw[i + 1]
            b2 = raw[i + 2]
            signed = b0 | (b1 << 8) | (b2 << 16)
            if signed & 0x800000:
                signed -= 0x1000000
            vals.append(signed / 8388608.0)
    elif width == 4:
        n = len(raw) // 4
        ints = struct.unpack("<" + "i" * n, raw)
        vals = [x / 2147483648.0 for x in ints]
    else:
        raise ValueError(f"unsupported sample width: {width} bytes")

    if channels == 1:
        return vals

    mono = []
    for i in range(0, len(vals), channels):
        frame = vals[i : i + channels]
        mono.append(sum(frame) / len(frame))
    return mono


def trim_silence(samples: list[float], threshold: float = 0.01) -> list[float]:
    if not samples:
        return samples
    start = 0
    end = len(samples) - 1
    while start < len(samples) and abs(samples[start]) < threshold:
        start += 1
    while end > start and abs(samples[end]) < threshold:
        end -= 1
    return samples[start : end + 1] if end >= start else samples


def envelope(samples: list[float], win: int, hop: int) -> list[float]:
    out = []
    if win <= 0 or hop <= 0 or len(samples) < win:
        return out
    for i in range(0, len(samples) - win + 1, hop):
        chunk = samples[i : i + win]
        rms = math.sqrt(sum(x * x for x in chunk) / win)
        out.append(rms)
    return out


def count_onsets(env: list[float]) -> int:
    if len(env) < 3:
        return 0
    diffs = [env[i] - env[i - 1] for i in range(1, len(env))]
    pos = [d for d in diffs if d > 0]
    if not pos:
        return 0
    threshold = max(0.01, (sum(pos) / len(pos)) * 2.0)
    count = 0
    refractory = 0
    for d in diffs:
        if refractory > 0:
            refractory -= 1
            continue
        if d > threshold:
            count += 1
            refractory = 2
    return count


def zero_cross_rate(samples: list[float]) -> float:
    if len(samples) < 2:
        return 0.0
    z = 0
    prev = samples[0]
    for s in samples[1:]:
        if (prev <= 0 < s) or (prev >= 0 > s):
            z += 1
        prev = s
    return z / (len(samples) - 1)


def goertzel_power(samples: list[float], sr: int, freq: float) -> float:
    if not samples:
        return 0.0
    w = 2.0 * math.pi * freq / sr
    coeff = 2.0 * math.cos(w)
    s0 = 0.0
    s1 = 0.0
    s2 = 0.0
    for x in samples:
        s0 = x + coeff * s1 - s2
        s2 = s1
        s1 = s0
    return s1 * s1 + s2 * s2 - coeff * s1 * s2


def dominant_freq(samples: list[float], sr: int) -> float:
    if len(samples) < 64:
        return 0.0
    candidates = []
    for i in range(36):
        # log-spaced from 60Hz to ~4.2kHz
        candidates.append(60.0 * (1.12**i))
    best_f = 0.0
    best_p = -1.0
    for f in candidates:
        if f >= sr / 2:
            continue
        p = goertzel_power(samples, sr, f)
        if p > best_p:
            best_p = p
            best_f = f
    return best_f


def freq_drift(samples: list[float], sr: int) -> float:
    if len(samples) < sr // 5:
        return 0.0
    parts = 4
    step = len(samples) // parts
    freqs = []
    for i in range(parts):
        seg = samples[i * step : (i + 1) * step]
        if len(seg) < 64:
            continue
        freqs.append(dominant_freq(seg, sr))
    if len(freqs) < 2:
        return 0.0
    base = max(1.0, sum(freqs) / len(freqs))
    drift = abs(freqs[-1] - freqs[0]) / base
    return clamp(drift, 0.0, 1.0)


def classify_motif(duration_s: float, dom_freq: float, zcr: float, onset_rate: float, drift: float,
                   transientness: float, sustainedness: float, brightness: float) -> str:
    if duration_s < 0.045 and transientness > 0.6:
        return "tick"
    if duration_s < 0.09 and onset_rate > 20:
        return "cluster"
    if duration_s < 0.16 and drift > 0.22 and dom_freq > 450:
        return "yip"
    if duration_s < 0.20 and drift > 0.15 and brightness > 0.45:
        return "chirp"
    if duration_s < 0.22 and dom_freq > 1200 and zcr > 0.08:
        return "tsk"
    if duration_s > 0.45 and dom_freq < 120 and sustainedness > 0.5:
        return "drone"
    if duration_s > 0.28 and dom_freq < 180 and sustainedness > 0.45:
        return "hum"
    if duration_s > 0.18 and drift > 0.22 and dom_freq < 300:
        return "wobble"
    if duration_s > 0.16 and drift > 0.2 and brightness > 0.35:
        return "warble"
    if duration_s > 0.12 and dom_freq < 500:
        return "bloop"
    if duration_s > 0.12 and dom_freq >= 500:
        return "bip"
    return "bip"


def analyze_file(path: Path, trim: bool) -> Features:
    with wave.open(str(path), "rb") as wf:
        sr = wf.getframerate()
        channels = wf.getnchannels()
        width = wf.getsampwidth()
        nframes = wf.getnframes()
        raw = wf.readframes(nframes)

    samples = decode_pcm(raw, width, channels)
    if trim:
        samples = trim_silence(samples)
    if not samples:
        samples = [0.0]

    dur = len(samples) / float(sr)
    sq = [x * x for x in samples]
    rms = math.sqrt(sum(sq) / len(sq))
    peak = max(abs(x) for x in samples)
    crest = peak / max(rms, 1e-7)
    zcr = zero_cross_rate(samples)

    win = max(32, int(sr * 0.010))
    hop = max(16, int(sr * 0.005))
    env = envelope(samples, win, hop)
    onset_count = count_onsets(env)
    onset_rate = onset_count / max(dur, 1e-6)

    dom = dominant_freq(samples[: min(len(samples), sr)], sr)
    drift = freq_drift(samples, sr)

    if env:
        env_max = max(env)
        env_mean = sum(env) / len(env)
        transientness = clamp((env_max - env_mean) / max(env_max, 1e-7), 0.0, 1.0)
        sustainedness = clamp(env_mean / max(env_max, 1e-7), 0.0, 1.0)
    else:
        transientness = 0.0
        sustainedness = 0.0

    brightness = clamp((dom - 120.0) / 2000.0, 0.0, 1.0)

    motif = classify_motif(dur, dom, zcr, onset_rate, drift, transientness, sustainedness, brightness)

    return Features(
        path=str(path),
        duration_s=dur,
        rms=rms,
        peak=peak,
        crest=crest,
        zcr=zcr,
        onset_rate=onset_rate,
        dom_freq_hz=dom,
        freq_drift=drift,
        transientness=transientness,
        sustainedness=sustainedness,
        brightness=brightness,
        motif=motif,
    )


def mean(xs: Iterable[float], default: float = 0.0) -> float:
    vals = list(xs)
    if not vals:
        return default
    return sum(vals) / len(vals)


def percentile(xs: list[float], p: float, default: float) -> float:
    if not xs:
        return default
    vals = sorted(xs)
    if len(vals) == 1:
        return vals[0]
    pos = clamp(p, 0.0, 1.0) * (len(vals) - 1)
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return vals[lo]
    frac = pos - lo
    return vals[lo] * (1.0 - frac) + vals[hi] * frac


def suggest_config(feats: list[Features]) -> dict[str, float | int]:
    total = len(feats)
    motif_count: dict[str, int] = {}
    for f in feats:
        motif_count[f.motif] = motif_count.get(f.motif, 0) + 1

    def ratio(*names: str) -> float:
        if total == 0:
            return 0.0
        return sum(motif_count.get(n, 0) for n in names) / total

    ambient_ratio = ratio("hum", "drone", "wobble")
    cluster_ratio = ratio("cluster", "stutter", "tick", "tsk")
    sweep_ratio = ratio("yip", "chirp", "warble", "wobble")

    avg_brightness = mean((f.brightness for f in feats), 0.3)
    avg_sustained = mean((f.sustainedness for f in feats), 0.4)
    avg_drift = mean((f.freq_drift for f in feats), 0.15)
    avg_transient = mean((f.transientness for f in feats), 0.45)
    avg_onsets = mean((f.onset_rate for f in feats), 8.0)

    hum_base = clamp(0.45 + ambient_ratio * 0.65 + avg_sustained * 0.15, 0.20, 0.95)
    hum_gain = clamp(0.35 + ambient_ratio * 0.45, 0.25, 0.85)
    hum_active_max = clamp(0.50 + ambient_ratio * 0.35, 0.45, 0.90)

    min_gap = int(round(clamp(85.0 - cluster_ratio * 55.0, 18.0, 120.0)))
    cooldown = int(round(clamp(190.0 - cluster_ratio * 120.0, 35.0, 260.0)))

    keyboard_yip_chance = clamp(0.18 + sweep_ratio * 0.45, 0.10, 0.90)
    keyboard_chirp_chance = clamp(0.12 + avg_brightness * 0.50, 0.08, 0.80)
    process_stutter_chance = clamp(0.18 + cluster_ratio * 0.60, 0.12, 0.92)
    system_stutter_chance = clamp(0.22 + cluster_ratio * 0.52, 0.15, 0.90)
    network_chirp_chance = clamp(0.22 + avg_brightness * 0.55, 0.15, 0.92)
    network_stutter_chance = clamp(0.12 + cluster_ratio * 0.62, 0.10, 0.92)
    cpu_warble_active_chance = clamp(0.08 + avg_drift * 0.70, 0.04, 0.72)
    cpu_warble_busy_chance = clamp(cpu_warble_active_chance + 0.20, 0.18, 0.92)

    ambient_feats = [f for f in feats if f.motif in {"hum", "drone", "wobble"}]
    if not ambient_feats:
        ambient_feats = feats
    amb_freqs = [f.dom_freq_hz for f in ambient_feats if f.dom_freq_hz > 10]
    p20 = percentile(amb_freqs, 0.20, 70.0)
    p50 = percentile(amb_freqs, 0.50, 100.0)
    p80 = percentile(amb_freqs, 0.80, 150.0)

    hum_min = clamp(p20 * 0.85, 42.0, 180.0)
    hum_max = clamp(max(hum_min + 8.0, p50 * 1.18), 60.0, 260.0)
    drone_min = clamp(hum_min * 0.76, 30.0, 140.0)
    drone_max = clamp(min(hum_max * 0.84, hum_max - 6.0), 42.0, 220.0)
    wobble_min = clamp(max(hum_min * 1.12, p50 * 0.95), 60.0, 240.0)
    wobble_max = clamp(max(wobble_min + 10.0, p80 * 1.25), 90.0, 340.0)
    # If corpus has little ambient material, keep a safer low-frequency baseline.
    if ambient_ratio < 0.25:
        hum_min = clamp((hum_min * 0.35) + 42.0, 48.0, 90.0)
        hum_max = clamp((hum_max * 0.35) + 70.0, 78.0, 130.0)
        drone_min = clamp((drone_min * 0.35) + 30.0, 34.0, 72.0)
        drone_max = clamp((drone_max * 0.35) + 50.0, 52.0, 100.0)
        wobble_min = clamp((wobble_min * 0.40) + 44.0, 56.0, 110.0)
        wobble_max = clamp((wobble_max * 0.40) + 60.0, 78.0, 160.0)

    ambient_noise_chance = clamp(0.22 + avg_transient * 0.50, 0.16, 0.88)
    ambient_noise_gain = clamp(0.05 + avg_transient * 0.10, 0.04, 0.22)
    ambient_blip_chance = clamp(0.20 + (1.0 - avg_transient) * 0.40 + ambient_ratio * 0.20, 0.15, 0.90)
    ambient_blip_gain = clamp(0.06 + (1.0 - avg_brightness) * 0.08, 0.05, 0.20)

    dense = clamp(avg_onsets / 22.0, 0.0, 1.0)
    cluster_steps_min = int(round(clamp(3.0 + dense * 2.5, 2.0, 7.0)))
    cluster_steps_max = int(round(clamp(cluster_steps_min + 3.0 + dense * 2.5, 5.0, 14.0)))
    cluster_spacing_min = int(round(clamp(8.0 - dense * 4.0, 3.0, 12.0)))
    cluster_spacing_max = int(round(clamp(18.0 - dense * 6.0, cluster_spacing_min + 2.0, 28.0)))
    stutter_steps_min = int(round(clamp(2.0 + dense * 1.8, 2.0, 5.0)))
    stutter_steps_max = int(round(clamp(stutter_steps_min + 2.0 + dense * 2.0, 4.0, 10.0)))
    stutter_spacing_min = int(round(clamp(14.0 - dense * 5.0, 6.0, 18.0)))
    stutter_spacing_max = int(round(clamp(26.0 - dense * 6.0, stutter_spacing_min + 3.0, 34.0)))

    return {
        "hum_base_chance": hum_base,
        "hum_gain_scale": hum_gain,
        "hum_active_max": hum_active_max,
        "keyboard_yip_chance": keyboard_yip_chance,
        "keyboard_chirp_chance": keyboard_chirp_chance,
        "process_stutter_chance": process_stutter_chance,
        "system_stutter_chance": system_stutter_chance,
        "network_chirp_chance": network_chirp_chance,
        "network_stutter_chance": network_stutter_chance,
        "cpu_warble_active_chance": cpu_warble_active_chance,
        "cpu_warble_busy_chance": cpu_warble_busy_chance,
        "hum_freq_min": hum_min,
        "hum_freq_max": hum_max,
        "drone_freq_min": drone_min,
        "drone_freq_max": drone_max,
        "wobble_freq_min": wobble_min,
        "wobble_freq_max": wobble_max,
        "ambient_noise_chance": ambient_noise_chance,
        "ambient_noise_gain": ambient_noise_gain,
        "ambient_blip_chance": ambient_blip_chance,
        "ambient_blip_gain": ambient_blip_gain,
        "cluster_steps_min": cluster_steps_min,
        "cluster_steps_max": cluster_steps_max,
        "cluster_spacing_min_ms": cluster_spacing_min,
        "cluster_spacing_max_ms": cluster_spacing_max,
        "stutter_steps_min": stutter_steps_min,
        "stutter_steps_max": stutter_steps_max,
        "stutter_spacing_min_ms": stutter_spacing_min,
        "stutter_spacing_max_ms": stutter_spacing_max,
        "min_gap_ms": min_gap,
        "cooldown_ms": cooldown,
    }


def print_report(feats: list[Features], cfg: dict[str, float | int], only_config: bool) -> None:
    if not only_config:
        print(f"analyzed_files={len(feats)}")
        print("\n# per-file summary")
        for f in feats:
            print(
                f"- {f.path}: motif={f.motif} dur={f.duration_s:.3f}s "
                f"dom={f.dom_freq_hz:.1f}Hz drift={f.freq_drift:.2f} "
                f"onsets={f.onset_rate:.1f}/s sustain={f.sustainedness:.2f}"
            )

        counts: dict[str, int] = {}
        for f in feats:
            counts[f.motif] = counts.get(f.motif, 0) + 1
        print("\n# motif histogram")
        for k in sorted(counts):
            print(f"{k}={counts[k]}")

    print("\n# suggested config.conf snippet")
    order = [
        "hum_base_chance",
        "hum_gain_scale",
        "hum_active_max",
        "cpu_warble_active_chance",
        "cpu_warble_busy_chance",
        "keyboard_yip_chance",
        "keyboard_chirp_chance",
        "process_stutter_chance",
        "system_stutter_chance",
        "network_chirp_chance",
        "network_stutter_chance",
        "hum_freq_min",
        "hum_freq_max",
        "drone_freq_min",
        "drone_freq_max",
        "wobble_freq_min",
        "wobble_freq_max",
        "ambient_noise_chance",
        "ambient_noise_gain",
        "ambient_blip_chance",
        "ambient_blip_gain",
        "cluster_steps_min",
        "cluster_steps_max",
        "cluster_spacing_min_ms",
        "cluster_spacing_max_ms",
        "stutter_steps_min",
        "stutter_steps_max",
        "stutter_spacing_min_ms",
        "stutter_spacing_max_ms",
        "min_gap_ms",
        "cooldown_ms",
    ]
    for key in order:
        value = cfg[key]
        if isinstance(value, int):
            print(f"{key}={value}")
        else:
            print(f"{key}={value:.2f}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze WAV references and suggest beep config tuning")
    parser.add_argument("paths", nargs="+", help="WAV files or directories")
    parser.add_argument("--no-trim", action="store_true", help="do not trim leading/trailing silence")
    parser.add_argument("--only-config", action="store_true", help="print only suggested config snippet")
    args = parser.parse_args()

    wavs = discover_wavs(args.paths)
    if not wavs:
        print("no .wav files found")
        return 1

    feats: list[Features] = []
    for path in wavs:
        try:
            feats.append(analyze_file(path, trim=not args.no_trim))
        except Exception as exc:  # keep batch running
            print(f"[warn] failed to analyze {path}: {exc}")

    if not feats:
        print("no analyzable wav files")
        return 1

    cfg = suggest_config(feats)
    print_report(feats, cfg, args.only_config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
