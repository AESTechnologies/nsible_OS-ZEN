# @nsible OS by Æ§ Tech

## Mission
A metabolic, high-performance operating system kernel written in Zig (0.15.2). 
Designed for direct hardware control, sovereign data ingestion, and zero-dependency execution.
It is not a browser; it is a **Data Metabolism Engine**.

## Architecture
* **Kernel:** Zig Native (No LibC, No Assembly Shim)
* **Target:** x86_64-linux-musl (Host-as-Bootloader)
* **Graphics:** Direct `/dev/fb0` Framebuffer Access (Crimson Engine)
* **Umbilical:** `HUNTER` Module (Curl Subprocess / Raw Pipe)
* **Memory:** `SCRIBE` Module (Immediate GZL-O Inscription)

### **v0.9.6 // WAKING STATE: ACTIVE**
> *"The Void remembers. The machine wakes."*

**@nsible** has evolved into a **Persistent Sovereign Environment**. It no longer resets; it resumes.
* **Waking State:** The system auto-fetches the last known timeline entry on boot.
* **Immediate Inscription:** History is written to disk (`nsible_history.gzl`) instantly upon creation. Crash-proof persistence.

## **Current State: v0.9.7 (The Refactored Core)**
* **refactor(core):** ACK cleanup codex/chronos
* **Centralized Time Law:** records CYCLE_S consolidation
* **Implemented GZL ident:** new cortex command.
* **Build Repairs & Ver Tags** necessary house work. ++zen();
The system operates in **Host Mode**, leveraging the Linux kernel as a biological scaffold while maintaining sovereign user-space logic.

### **// HUNTER (Metabolism)**
* **The Umbilical:** Pipes external data (Web) directly into the Void buffer.
* **Mastication:** Captures raw streams for internal GZL-O parsing.
* **Navigation:** `v` / `^` scroll commands mapped to physical **Arrow Keys**.

### **// TIMELINE (Visual Physics)**
* **The Red Stack:** History is visualized as a stack of Crimson tabs on the right rail.
* **Flex/Warp Engine:**
  * **Flex:** Selected tab expands (`+8px`) and glows White (Focus).
  * **Warp:** Unselected tabs contract based on **Philotic Weight** (Frequency of access).
  * **Pulse:** Active fetches burn Amber before locking to Crimson.
* **Traversal:** **Left/Right Arrows** navigate through time (History).

### **// REFLEX (Nervous System)**
* **Live Signal:** The kernel listens for micro-sequences (`.!XX-.`) at the top of the input loop for immediate, non-blocking execution.
* **GZL-O:** Direct hardware interrupt logic separate from the text parser.

## Commands
* `hunt <url>` : Fetch external data (e.g., `hunt dailyzen.com`).
* `exit` : Graceful shutdown.
* `clear` : Wipe the Void buffer.
* **Up/Down** : Scroll Content.
* **Left/Right** : Traverse Time (Timeline History).
* `.!XX-.` : **HARD KILL SIGNAL (Reflex).**

## Build & Run
```bash
zig build
sudo ./zig-out/bin/nsible_os
