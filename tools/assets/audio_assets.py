"""Original non-verbal effects and four circular, two-minute game scores."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf
import imageio_ffmpeg
from scipy import signal

from catalog import load_catalog, resource_plan, write_json

RATE = 48000
MASTER_PEAK = 0.70
MAX_TRUE_PEAK = 10 ** (-1.0 / 20.0)


def seed_for(identity: str) -> int:
    return int.from_bytes(hashlib.sha256(identity.encode("utf-8")).digest()[:8], "big")


def smooth_envelope(count: int, attack=0.012, release=0.06) -> np.ndarray:
    envelope = np.ones(count, dtype=np.float32)
    a, r = min(count // 2, int(attack * RATE)), min(count // 2, int(release * RATE))
    if a:
        envelope[:a] = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    if r:
        envelope[-r:] = np.cos(np.linspace(0, np.pi / 2, r)) ** 2
    return envelope


def note(midi: float, seconds: float, instrument: str, velocity=1.0) -> np.ndarray:
    count = max(8, round(seconds * RATE))
    t = np.arange(count, dtype=np.float32) / RATE
    frequency = 440.0 * 2.0 ** ((midi - 69.0) / 12.0)
    if instrument == "pad":
        harmonics = ((1.0, 1.0), (2.0, .13), (3.0, .055))
        envelope = np.sin(np.pi * np.arange(count) / count) ** 1.5
    elif instrument == "bell":
        harmonics = ((1.0, 1.0), (2.0, .22), (3.01, .07))
        envelope = np.exp(-t * 3.1 / max(seconds, .2)) * smooth_envelope(count, .004, .05)
    elif instrument == "bass":
        harmonics = ((1.0, 1.0), (2.0, .16))
        envelope = np.exp(-t * 2.5 / max(seconds, .2)) * smooth_envelope(count, .016, .08)
    else:
        harmonics = ((1.0, 1.0), (2.0, .16), (4.0, .035))
        envelope = np.exp(-t * 4.5 / max(seconds, .15)) * smooth_envelope(count, .004, .035)
    wave = sum(weight * np.sin(2 * np.pi * frequency * ratio * t)
               for ratio, weight in harmonics)
    return (wave * envelope * velocity).astype(np.float32)


def band_noise(rng, count, low, high):
    white = rng.normal(0, 1, count).astype(np.float32)
    if low > 0:
        sos = signal.butter(2, (low, high), btype="bandpass", fs=RATE, output="sos")
    else:
        sos = signal.butter(2, high, fs=RATE, output="sos")
    return signal.sosfilt(sos, white).astype(np.float32)


def material_kind(text: str, identity: str) -> str:
    choices = (
        ("air", "风气雾喷吹"),
        ("paper", "纸页书卡折标签"),
        ("water", "水泡雨滴液"),
        ("cloth", "布棉毛线绒"),
        ("metal", "螺钟齿轮磁机甲"),
        ("wood", "木梳拼扣枝"),
        ("bell", "铃音节拍星光梦"),
    )
    for kind, words in choices:
        if any(word in text for word in words):
            return kind
    return ("wood", "bell", "paper", "cloth")[seed_for(identity) % 4]


def effect(identity: str, group: str, phase: str, name: str) -> tuple[np.ndarray, dict]:
    rng = np.random.default_rng(seed_for(identity))
    loop = phase in ("process", "move")
    duration = 1.6 if loop else (.28 if group == "ui" else .72)
    count = round(duration * RATE)
    t = np.arange(count, dtype=np.float32) / RATE
    kind = material_kind(name, identity)
    noise = band_noise(rng, count, 180 if kind in ("metal", "paper") else 0,
                       3800 if kind == "paper" else 1800)
    wave = np.zeros(count, dtype=np.float32)
    if kind in ("air", "cloth", "paper"):
        modulation = .55 + .35 * np.sin(2 * np.pi * (2.5 if kind == "paper" else 1.25) * t)
        wave += noise * modulation * (.10 if kind == "air" else .17)
    elif kind == "water":
        wave += noise * .035
    base = 55 + seed_for(identity) % 16
    events = [0.03, .43, .83, 1.23] if loop else [.018, .14, .30]
    if group == "ui":
        events = [.008, .10] if any(k in identity for k in ("confirm", "complete", "save")) else [.008]
        kind = "bell" if "complete" in identity else "wood"
    for index, when in enumerate(events):
        start = round(when * RATE)
        if start >= count:
            continue
        tone = note(base + (0, 4, 7, 4)[index % 4],
                    .23 if loop else .27, "bell" if kind in ("bell", "water") else "mallet", .18)
        end = min(count, start + len(tone))
        wave[start:end] += tone[:end - start]
        if kind in ("wood", "metal"):
            length = min(count - start, round(.055 * RATE))
            click = band_noise(rng, length, 0, 900 if kind == "wood" else 2500)
            wave[start:start + length] += .11 * click * np.exp(-np.arange(length) / (RATE * .014))
    if phase in ("safe_finish", "resolve"):
        wave *= .65
    wave *= smooth_envelope(count, .015, .045)
    return wave, {"material": kind, "loop": loop, "duration": duration,
                  "offline_seed": seed_for(identity)}


def add_circular(destination: np.ndarray, wave: np.ndarray, start_seconds: float,
                 pan: float, gain: float) -> None:
    start = round(start_seconds * RATE) % len(destination)
    left, right = math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)
    # Splitting the wrapped note preserves the same continuous note at the loop join.
    offset = 0
    while offset < len(wave):
        length = min(len(wave) - offset, len(destination) - start)
        destination[start:start + length, 0] += wave[offset:offset + length] * gain * left
        destination[start:start + length, 1] += wave[offset:offset + length] * gain * right
        offset += length
        start = 0


def score(theme: str) -> tuple[np.ndarray, dict]:
    settings = {
        "lobby": (80, 40, 60, (0, 5, 7, 9), "mallet"),
        "garden": (72, 36, 62, (0, 7, 5, 2), "bell"),
        "night": (60, 32, 57, (0, 5, 2, 7), "mallet"),
        "celebration": (96, 48, 60, (0, 7, 9, 5), "bell"),
    }
    bpm, bars, tonic, roots, lead = settings[theme]
    beat = 60 / bpm
    seconds = bars * 4 * beat
    destination = np.zeros((round(seconds * RATE), 2), dtype=np.float32)
    events = []
    motif = (0, 4, 7, 9, 7, 4, 2, 4)
    for bar in range(bars):
        root = tonic + roots[bar % len(roots)]
        when = bar * 4 * beat
        minor = roots[bar % len(roots)] in (2, 9)
        chord = (0, 3 if minor else 4, 7, 9)
        for index, interval in enumerate(chord):
            add_circular(destination, note(root - 12 + interval, 4.6 * beat, "pad"),
                         when - .3 * beat, -.55 + index * .36, .025)
        add_circular(destination, note(root - 24, 2.8 * beat, "bass"),
                     when, -.1, .085)
        if bar % 2 == 0:
            add_circular(destination, note(root - 17, 1.8 * beat, "bass"),
                         when + 2 * beat, .1, .045)
        for step, at in enumerate((.5, 1.5, 2.5, 3.5)):
            if theme == "night" and (step + bar) % 3:
                continue
            interval = motif[(bar * 3 + step) % len(motif)]
            pitch = tonic + 12 + interval
            length = (1.35 if theme == "night" else .85) * beat
            add_circular(destination, note(pitch, length, lead),
                         when + at * beat, (-.35, .28, -.12, .38)[step], .055)
            events.append({"bar": bar, "beat": at, "midi": pitch,
                           "length_beats": length / beat, "instrument": lead})
        if theme in ("lobby", "celebration"):
            for at in (0, 2):
                add_circular(destination, note(43 if at == 0 else 50, .12, "mallet"),
                             when + at * beat, -.15 if at == 0 else .15, .022)
    return destination, {"bpm": bpm, "bars": bars, "beats_per_bar": 4,
                         "tonic_midi": tonic, "harmonic_roots": list(roots),
                         "events": events, "composition": "original circular event score"}


def true_peak(samples: np.ndarray) -> float:
    peak = 0.0
    for start in range(0, len(samples), RATE * 5):
        chunk = samples[max(0, start - 32):min(len(samples), start + RATE * 5 + 32)]
        peak = max(peak, float(np.max(np.abs(signal.resample_poly(chunk, 4, 1, axis=0)))))
    return peak


def publish(root: Path, requirement: dict, samples: np.ndarray, recipe: dict) -> dict:
    samples = samples - np.mean(samples, axis=0)
    peak = float(np.max(np.abs(samples)))
    if not math.isfinite(peak) or peak <= 0:
        raise ValueError("Empty/non-finite audio: " + requirement["id"])
    samples = (samples * MASTER_PEAK / peak).astype(np.float32)
    encoded, source = (root / value for value in requirement["required_paths"])
    encoded.parent.mkdir(parents=True, exist_ok=True)
    source.parent.mkdir(parents=True, exist_ok=True)
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    channels = 1 if samples.ndim == 1 else samples.shape[1]
    # FFmpeg supplies the encoder; chunked verification bounds authoring memory.
    for _ in range(3):
        sf.write(source, samples, RATE, format="WAV", subtype="PCM_16")
        subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(source),
                        "-c:a", "libvorbis", "-q:a", "3", str(encoded)], check=True)
        decoded, decoded_rate = sf.read(encoded, dtype="float32", always_2d=True)
        measured = true_peak(decoded)
        if measured <= MAX_TRUE_PEAK:
            break
        samples *= .94 * MAX_TRUE_PEAK / measured
    else:
        raise ValueError("True peak could not be bounded: " + requirement["id"])
    duration = len(decoded) / RATE
    if requirement["kind"] == "music" and not (
            requirement["min_duration"] <= duration <= requirement["max_duration"]):
        raise ValueError("Music duration outside specification")
    if decoded_rate != RATE or len(decoded) != len(samples):
        raise ValueError("Audio round-trip changed sample count or sample rate")
    return {
        "id": requirement["id"], "kind": requirement["kind"],
        "path": str(encoded.relative_to(root)).replace("\\", "/"),
        "source_path": str(source.relative_to(root)).replace("\\", "/"),
        "sha256": hashlib.sha256(encoded.read_bytes()).hexdigest(),
        "sample_rate": RATE, "channels": channels,
        "frames": len(decoded), "duration_seconds": duration,
        "loop": requirement["kind"] == "music" or recipe.get("loop", False),
        "encoded_bytes": encoded.stat().st_size,
        "source_pcm_bytes": len(samples) * channels * 2,
        "decoded_true_peak_dbfs": 20 * math.log10(max(measured, 1e-12)),
        "loop_boundary_delta": float(np.max(np.abs(decoded[0] - decoded[-1]))),
        "source_definition": requirement["source"], "recipe": recipe,
        "license_source": "project-original; authored synthesis, no voice or sampled recording",
        "godot_import_status": "pending", "runtime_buffer_measurement": "pending",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--kind", choices=("all", "sound", "music"), default="all")
    parser.add_argument("--ids", default="")
    args = parser.parse_args()
    root = args.root.resolve()
    wanted = set(args.ids.split(",")) if args.ids else None
    plan = resource_plan(load_catalog(root))
    requirements = [item for item in plan["requirements"]
                    if item["kind"] in ("sound", "music")
                    and (args.kind == "all" or item["kind"] == args.kind)
                    and (wanted is None or item["id"] in wanted)]
    index_path = root / "assets/audio/index.json"
    previous = json.loads(index_path.read_text(encoding="utf-8")) if index_path.exists() else {"clips": []}
    records = {item["id"]: item for item in previous["clips"]}
    for number, requirement in enumerate(requirements, 1):
        if requirement["kind"] == "music":
            wave, recipe = score(requirement["id"])
        else:
            wave, recipe = effect(requirement["id"], requirement["group"],
                                  requirement["phase"], requirement["name"])
        record = publish(root, requirement, wave, recipe)
        records[record["id"]] = record
        write_json(index_path, {
            "schema": 1, "sample_rate": RATE,
            "license_source": "project-original; see repository LICENSE",
            "clips": sorted(records.values(), key=lambda item: item["id"]),
        })
        print(f"AUDIO {number}/{len(requirements)} {record['id']} "
              f"{record['duration_seconds']:.2f}s {record['encoded_bytes']}B "
              f"{record['decoded_true_peak_dbfs']:.2f}dBTP", flush=True)
    print(json.dumps({"audio_files": len(records), "index": str(index_path)}))


if __name__ == "__main__":
    main()

