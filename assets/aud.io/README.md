# 高爪 d_angel // @nsible Audio TUI

**d_angel** is a terminal-based, zero-latency volumetric waveform simulator and audio engine prototype. Designed for execution within the `@nsible` hybrid architecture, it bypasses bloated GUI abstractions to render real-time PCM frame data directly to the TTY.

## ⌗ CORE ARCHITECTURE

Built in Zig `0.15.2` and utilizing a single-header C-ABI drop of `miniaudio`, `d_angel` executes a direct mathematical translation of audio amplitude into a visual matrix. It currently operates in a hosted Linux environment (`native-linux-gnu`) using POSIX Raw Mode to simulate the instant hardware interrupt polling intended for the final x86 Atom N270 bare-metal OS.

### ⌗ THE MATH (Zero-Latency Matrix)
* **Dependency Ablation:** Zero `std.crypto.random` baseline noise. The matrix flatlines to absolute zero during silence.
* **Squared Dynamic Range:** Matrix reactivity is bound to an exponential curve (`audio_level * audio_level`), forcing aggressive punch on kick drums and instant decay on drops.
* **Spatial Smoothing:** Visual width is driven by a center-weighted frequency reaction paired with a wide, slow-rolling sine wave to eliminate artificial visual stutter.

## ⌗ KEYMAP (POSIX Raw Mode Trapping)

Input buffering is completely bypassed. Keystrokes are intercepted the millisecond the circuit closes.

| Key | Action | Engine Logic |
| :--- | :--- | :--- |
| `[ + ]` | **Volume Up** | Increments global float. |
| `[ - ]` | **Volume Down** | Decrements global float. |
| `[ Space ]` | **Play / Pause** | Hard toggles `ma_sound_start/stop`. Halts the matrix instantly. |
| `[ Enter ]` | **Skip Track** | Kills the current sound thread and advances the playlist pointer. |
| `[ q ]` | **Quit** | Graceful exit. Restores the canonical terminal state. |

## ⌗ EXECUTION / BUILD TARGET

To compile `d_angel` on the Linux host with full optimization:

```bash
zig build-exe d_angel.zig ma_x.c -I. -lc -lm -lpthread -ldl -lrt -target native-linux-gnu -O ReleaseFast
