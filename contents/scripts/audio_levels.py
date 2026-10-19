#!/usr/bin/env python3
"""Emit normalized logarithmic audio bands from the PulseAudio monitor source."""
import json
import subprocess
import sys
import time
import os

import numpy as np


def read_frame(stream, size):
    """Read a full PCM frame even when the pipe returns short chunks."""
    chunks = []
    remaining = size
    while remaining:
        chunk = stream.read(remaining)
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def monitor_name(sink_name):
    if not sink_name:
        sink_name = subprocess.check_output(["pactl", "get-default-sink"], text=True, timeout=2).strip()
    sinks = json.loads(subprocess.check_output(["pactl", "-f", "json", "list", "sinks"], text=True, timeout=3))
    for sink in sinks:
        if sink.get("name") == sink_name:
            return sink.get("monitor_source") or (sink_name + ".monitor")
    raise RuntimeError("Audio output is no longer available: " + sink_name)


def main():
    bands = max(1, min(64, int(sys.argv[1]) if len(sys.argv) > 1 else 20))
    sink_name = sys.argv[2] if len(sys.argv) > 2 else ""
    output_path = sys.argv[3] if len(sys.argv) > 3 else ""
    source = monitor_name(sink_name)
    stream = subprocess.Popen(
        ["parec", "--raw", "--format=s16le", "--rate=22050", "--channels=1", "--latency-msec=5", "--process-time-msec=2", "--device=" + source],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0,
    )
    # Analyze a 2048-sample window every 128 samples: roughly 172 updates/sec
    # while retaining enough frequency resolution for the bass bands.
    window_size = 2048
    hop_size = 128
    size = hop_size * 2
    audio_window = np.zeros(window_size, dtype=np.float32)
    filled = 0
    window = np.hanning(window_size)
    edges = np.geomspace(55, 10000, bands + 1)
    sample_rate = 22050
    window_sum = float(np.sum(window))
    try:
        # Keep parec open for low-latency sampling. When an output file is
        # provided, QML polls the latest atomic snapshot independently of this
        # long-lived capture process.
        while True:
            raw = read_frame(stream.stdout, size)
            if len(raw) != size:
                error = stream.stderr.read().decode("utf-8", errors="replace").strip()
                if error:
                    print(json.dumps({"error": error}), flush=True)
                break
            incoming = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
            audio_window[:-hop_size] = audio_window[hop_size:]
            audio_window[-hop_size:] = incoming
            filled = min(window_size, filled + hop_size)
            if filled < window_size:
                continue
            power = np.abs(np.fft.rfft(audio_window * window))
            freqs = np.fft.rfftfreq(window_size, 1.0 / sample_rate)
            signal_active = float(np.sqrt(np.mean(audio_window * audio_window))) >= 0.001
            levels = []
            for i in range(bands):
                if not signal_active:
                    levels.append(0.0)
                    continue
                band = power[(freqs >= edges[i]) & (freqs < edges[i + 1])]
                # Convert spectral energy to an approximate band RMS dBFS.
                # Absolute dBFS avoids independently normalizing every band,
                # which made all active bands converge toward maximum height.
                rms = float(np.sqrt(np.sum(band * band)) * np.sqrt(2.0) / window_sum) if band.size else 0.0
                dbfs = 20.0 * np.log10(max(rms, 1e-6))
                # Music naturally carries less energy in upper octaves. Apply
                # a gentle pink-noise compensation so treble bands stay visible.
                center_hz = np.sqrt(edges[i] * edges[i + 1])
                dbfs += 3.0 * np.log2(center_hz / 1000.0)
                # The old cubic transfer produced values near 0.05 for
                # ordinary loud audio, so the QML height curve kept the
                # loudest bands around its center pivot. Use a wider dBFS
                # window and a gentle power curve instead: typical active
                # noise now reaches well above center, while the curve still
                # leaves visible room between near-peak bands.
                normalized = min(1.0, max(0.0, (dbfs + 55.0) / 55.0))
                levels.append(round(normalized ** 0.55, 4))
            frame = json.dumps({"levels": levels, "active": signal_active, "time": time.time()}, separators=(",", ":")) if output_path else json.dumps(levels, separators=(",", ":"))
            if output_path:
                temporary = output_path + "." + str(os.getpid()) + ".tmp"
                with open(temporary, "w", encoding="utf-8") as output:
                    output.write(frame)
                os.replace(temporary, output_path)
        
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        stream.terminate()


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.SubprocessError, ValueError, RuntimeError) as error:
        message = json.dumps({"error": str(error), "time": time.time()})
        if len(sys.argv) > 3 and sys.argv[3]:
            with open(sys.argv[3], "w", encoding="utf-8") as output:
                output.write(message)
        else:
            print(message, flush=True)
        time.sleep(0.1)
