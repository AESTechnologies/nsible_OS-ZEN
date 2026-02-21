# @nsible OS

## Mission
A bare-metal, high-performance operating system kernel written in Zig. 
Designed for direct hardware control, zero-dependency execution, and immediate TTY graphical interfaces.

## Architecture
* **Kernel:** Zig Native (No LibC, No Assembly Shim)
* **Target:** x86_64-linux-musl (Host-as-Bootloader) / Raw Metal (Future)
* **Graphics:** Direct /dev/fb0 Framebuffer Access (Crimson Engine)
* **Text:** Custom 8x8 Bitmap Glyph Engine (No Freetype)

## Status: v0.2 (Zen)
* [x] Direct Hardware Access
* [x] Crimson Tide Video Output
* [x] Glyph Rendering Engine
* [ ] Keyboard Interrupts (Next)

## Build & Run
```bash
zig build
sudo ./zig-out/bin/nsible_os
```
*Note: Must be run from a TTY (Ctrl+Alt+F3) to bypass X11/Wayland compositors.*
## License
MIT
