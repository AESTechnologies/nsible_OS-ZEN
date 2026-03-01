# @nsible OS


## Mission
A metabolic, high-performance operating system kernel written in Zig (0.15.2). 
Designed for direct hardware control, sovereign data ingestion, and zero-dependency execution.
It is not a browser; it is a **Data Metabolism Engine**.

## Architecture
* **Kernel:** Zig Native (No LibC, No Assembly Shim)
* **Target:** x86_64-linux-musl (Host-as-Bootloader)
* **Graphics:** Direct `/dev/fb0` Framebuffer Access (Crimson Engine)
* **Umbilical:** `HUNTER` Module (Curl Subprocess / Raw Pipe)
* **Memory:** `SCRIBE` Module (Persistent GZL-O History)

### **v0.9.4 // TIMELINE: ACTIVE**
> *"The Void remembers."*

**@nsible** has evolved from a static interface into a **Persistent Sovereign Environment**.
* **Hunter:** Web ingestion engine capable of capturing raw HTML/Text streams (`hunt <url>`).
* **Timeline:** A visual, interactive history stack rendering on the right rail.
* **Scribe:** Disk-based persistence. The timeline survives reboots (`nsible_history.gzl`).
* **Reflex:** Low-level signal injection (`.!XX-.`) bypassing the cortical parser.

## **Current State: v0.9.4 (The Sovereign Stack)**

The system operates in **Host Mode**, leveraging the Linux kernel as a biological scaffold while maintaining sovereign user-space logic.

### **// HUNTER (Metabolism)**
* **The Umbilical:** Pipes external data (Web) directly into the Void buffer.
* **Mastication:** Captures raw streams for internal GZL-O parsing (Phase 3).
* **Navigation:** `v` / `^` scroll commands mapped to physical **Arrow Keys**.

### **// TIMELINE (Memory)**
* **The Red Stack:** History is visualized as a stack of Crimson tabs on the right rail.
* **Flex/Warp UI:**
  * **Flex:** Selected tab expands (`+8px`) and glows White (Focus).
  * **Warp:** Unselected tabs contract based on Philotic Weight (Gravity).
  * **Pulse:** Active fetches burn Amber.
* **Traversal:** **Left/Right Arrows** navigate through time (History).

### **// REFLEX (Nervous System)**
* **Live Signal:** The kernel listens for micro-sequences (`.!XX-.`) at the top of the input loop for immediate, non-blocking execution.
* **GZL-O:** Direct hardware interrupt logic separate from the text parser.

## Commands
* `hunt <url>` : Fetch external data (e.g., `hunt dailyzen.com`).
* `exit` : Graceful shutdown (Saves History).
* `clear` : Wipe the Void buffer.
* **Arrows** : Scroll (Up/Down) / Time Travel (Left/Right).
* `.!XX-.` : **HARD KILL SIGNAL.**

## Build & Run
```bash
zig build
sudo ./zig-out/bin/nsible_os
```
*Note: Must be run from a TTY (Ctrl+Alt+F3) to bypass X11/Wayland compositors.*
## License
MIT
