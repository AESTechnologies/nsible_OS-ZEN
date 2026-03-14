// [@://nsible_os/docs/d_angel.md/.-={
// module: "docs"
// version: "2.0.5"
// description: "Updated Architecture and Keymap for d_angel"
// changes: "Reflects State-Machine architecture, multi-band math, queued playback, and zero-latency keymaps."
// philotic_inferences: "Documentation must evolve symmetrically with the executable to maintain structural integrity."

# 高爪 d_angel // @nsible Audio TUI

**d_angel** is a terminal-based, zero-latency volumetric waveform visualizer and state-driven media browser. Designed for execution within the `@nsible` hybrid architecture, it bypasses bloated GUI abstractions to render real-time PCM frame data and filesystem navigation directly to the TTY in strict @NSIBLE-RED aesthetics.

## ⌗ CORE ARCHITECTURE

Built in Zig `0.15.2` and utilizing a single-header C-ABI drop of `miniaudio`, `d_angel` operates as a dual-state machine (`AppMode.BROWSER` and `AppMode.PLAYER`). It bypasses managed `ArrayList` initializers in favor of explicit, unmanaged memory allocation (`.empty`) to guarantee resilience against strict compiler version drift. 

The engine operates in a hosted Linux environment (`native-linux-gnu`), severing Canonical Mode (`ICANON`) and Terminal Echo (`ECHO`) at the POSIX layer. This creates a raw, zero-latency conduit mimicking the instant hardware interrupt polling intended for bare-metal deployment.

## ⌗ THE MATH (Multi-Band Matrix & Sync)

* **Absolute Synchronization:** The visualizer's decoder sample rate is explicitly locked to the engine's playback sample rate, and hard-seeks directly to the `cursor_pcm` on every frame. It is mathematically required to eliminate synchronization drift across Variable Bit Rate (VBR) files.
* **Time-Domain Band Extraction:** Bypasses heavy FFT operations by utilizing fast time-domain math (low-pass filtering and sample-difference high-pass filtering) to extract distinct Bass, Mid, and Treble reactive buckets natively.
* **Depth of Silence:** Empty terminal space is overridden with a configured noise floor (`░` shallow, `·` deep), providing structural contrast for high-amplitude transients without relying on deep blacks.
* **Multi-Model Geometry:** The matrix actively routes the frequency buckets through four distinct geometrical visualizers: `SINE WAVE`, `PULSE CENTER`, `CHAOS BANDS`, and `HORIZON`.

## ⌗ KEYMAP (Zero-Latency Intercept)

Input buffering is obliterated. The matrix reacts the millisecond the circuit closes.

### [ BROWSER STATE ]
| Key | Action | Engine Logic |
| :--- | :--- | :--- |
| `[ w / s ]` | **Navigate** | Shifts the indexer cursor up and down the active directory limit. |
| `[ Ent ]` | **Drill / Play** | Enters a directory or pushes a single `.mp3` into the active queue and transitions to PLAYER. |
| `[ p ]` | **Play All** | Ingests the entire active directory into the playlist array for continuous playback. |
| `[ x ]` | **Shuffle All** | Ingests the directory and executes a fast cryptographic shuffle before playback. |
| `[ m ]` | **Media Jump** | Instantly vectors the absolute path to `/media` to access mounted external blocks. |
| `[ b ]` | **Back Dir** | Steps the path up to the parent directory. |
| `[ q ]` | **Quit** | Graceful exit. Restores canonical terminal state. |

### [ PLAYER STATE ]
| Key | Action | Engine Logic |
| :--- | :--- | :--- |
| `[ + / - ]` | **Master Vol** | Mutates the global float scale applied directly to the audio engine. |
| `[ Space ]` | **Play / Pause** | Halts the decoder and smooths the visual matrix to a flatline. |
| `[ r ]` | **Restart** | Seeks the active PCM cursor back to `0` seamlessly. |
| `[ z ]` | **Cycle Vis** | Hot-swaps the underlying mathematical model of the visualizer. |
| `[ Ent ]` | **Skip Track** | Kills the current thread and advances to the next track in the queued playlist. |
| `[ b ]` | **Browse** | Halts playback, clears the queue, and returns context to the `BROWSER` state. |
| `[ q ]` | **Quit** | Graceful exit. Restores canonical terminal state. |

## ⌗ EXECUTION / BUILD TARGET

To compile `d_angel` on the Linux host with full optimization:

```bash
zig build-exe d_angel.zig ma_x.c -I. -lc -lm -lpthread -ldl -lrt -target native-linux-gnu -O ReleaseFast
// }-.]
