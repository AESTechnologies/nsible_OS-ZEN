# @nsible OS

## Mission
A bare-metal, high-performance operating system kernel written in Zig. 
Designed for direct hardware control, zero-dependency execution, and immediate TTY graphical interfaces.

## Architecture
* **Kernel:** Zig Native (No LibC, No Assembly Shim)
* **Target:** x86_64-linux-musl (Host-as-Bootloader) / Raw Metal (Future)
* **Graphics:** Direct /dev/fb0 Framebuffer Access (Crimson Engine)
* **Text:** Custom 8x8 Bitmap Glyph Engine (No Freetype)

### **v0.7 // RETINA: ACTIVE**
> *"Gravity is reversed. The system rises."*

**@nsible** has transitioned from a static terminal to a living host-environment.
* **Visuals:** Gravity-Inverted UI (Bottom-Up Flow).
* **Core:** Cortex v1 Command Processor (`cycle`, `clear`, `exit`).
* **Identity:** `高爪` (High Talon) Hard-Point Identity.
* **Ignition:** Single-stroke entry via `./nsible`.

## **Current State: v0.7 (Ghost in the Shell)**

The system operates in **Host Mode**, leveraging the Linux kernel as a biological scaffold while maintaining sovereign user-space logic.

### **// RETINA (UI)**
* **Gravity Inversion:** The interface anchors to the bottom (`y=600`) and expands upward, distinct from traditional top-down terminals.
* **Crimson/Void:** Strict `@NSIBLE-RED` (0x00DC143C) on Deep Black (0x00000000).
* **The Watcher:** Reactive "Eye" glyph (`< o` / `< -`) tracking input states.

### **// CORTEX (Logic)**
* **CycleTime:** Non-Gregorian temporal tracking (`1 cycle = 42.13 min`).
* **Command Dispatch:** Internal parser for system control, divorced from `bash`.

### **// IGNITION**
* **Key:** `./nsible`
* **Function:** Automated build-and-boot sequence. Compiles `src/*.zig` and injects the binary into a raw TTY in a single stroke.

## Build & Run
```bash
zig build
sudo ./zig-out/bin/nsible_os
```
*Note: Must be run from a TTY (Ctrl+Alt+F3) to bypass X11/Wayland compositors.*
## License
MIT
