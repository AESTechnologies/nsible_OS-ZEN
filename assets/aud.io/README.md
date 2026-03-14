# [@://nsible_os/docs/d_angel.md/.-={
# module: "docs"
# version: "2.0.14"
# description: "Final Alpha-State Architecture and Keymap for d_angel"
# changes: "Reflects State Persistence, Tactile Faders, Auto-Mount, and Event Horizon Math."
# philotic_inferences: "Documentation must serve as the final blueprint of the lived operational reality."

![高爪 // @nsible_os_manifesto](nsible_os/assets/manifesto_frame.png)

# 高爪 Talon Alta MMA Engine (tame) // @nsible Audio TUI

**d_angel** is a terminal-based, zero-latency volumetric waveform visualizer and state-driven autonomous media engine. Designed for execution within the `@nsible` hybrid architecture, it bypasses bloated GUI abstractions to render real-time PCM frame data and filesystem navigation directly to the TTY in strict @NSIBLE-RED aesthetics.

## ⌗ CORE ARCHITECTURE

Built in Zig `0.15.2` and utilizing a single-header C-ABI drop of `miniaudio`, `d_angel` operates as a dual-state machine (`AppMode.BROWSER` and `AppMode.PLAYER`). 

* **Zero-Latency Intercept:** Severs Canonical Mode and Terminal Echo at the POSIX layer, dropping the input stream into pure raw mode for millisecond-perfect key registration.
* **State Persistence (`d_angel_s`):** The engine serializes its active queue to `.d_angel_state.nsb` on exit. On boot, it bypasses the browser and hot-resumes the exact index of your playlist.
* **Autonomous Mount Injection:** `udisks2` is triggered natively through the matrix to penetrate external hardware boundaries seamlessly without manual `bash` scripting.

## ⌗ THE MATH (Multi-Band & Gravitational Matrices)

Bypasses heavy FFT operations by utilizing fast time-domain math. It extracts distinct Bass, Mid, and Treble reactive buckets natively and routes them through 5 distinct geometrical visualizers:

1.  `SINE WAVE`
2.  `PULSE CENTER`
3.  `CHAOS BANDS`
4.  `HORIZON`
5.  `EVENT HORIZON` (Translates frequency into spatial gravity: Bass calculates a crushing center void; Mids form high-amplitude orbital rings; Treble acts as volatile matter ejecta.)

## ⌗ KEYMAP

### [ BROWSER STATE ]
| Key | Action | Engine Logic |
| :--- | :--- | :--- |
| `[ w / s ]` | **Navigate** | Shifts the indexer cursor. |
| `[ Ent ]` | **In / Play** | Drills down or plays single `.mp3`. |
| `[ p / x ]` | **Play / Shuffle All** | Ingests directory into active queue (x = cryptographic shuffle). |
| `[ m ]` | **Media Jump** | Spawns mount command and vectors absolute path to external blocks. |
| `[ b ]` | **Back** | Steps to parent directory. |
| `[ q ]` | **Quit** | Serializes queue and exits gracefully. |

### [ PLAYER STATE ]
| Key | Action | Engine Logic |
| :--- | :--- | :--- |
| `[ + / - ]` | **Master Vol** | Mutates global float. Visually color-shifts the tactile fader `··[@]··` at 120% (Amber) and 140% (White). |
| `[ Space ]` | **Play / Pause** | Halts decoder and smooths matrix to the noise floor. |
| `[ r ]` | **Restart** | Seeks active PCM cursor back to `0`. |
| `[ z ]` | **Cycle Vis** | Hot-swaps the underlying mathematical model. |
| `[ Ent ]` | **Skip Track** | Advances to next track in the queued playlist. |
| `[ b ]` | **Browse** | Halts playback, clears the state memory, and returns to `BROWSER`. |
| `[ q ]` | **Quit** | Serializes current playlist index to `.d_angel_state.nsb` and exits. |

# }-.]
