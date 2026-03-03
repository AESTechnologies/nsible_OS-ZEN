const std = @import("std");
const linux = std.os.linux;
const font = @import("glyphs.zig");
const nerve = @import("nerve.zig");   
const codex = @import("codex.zig");
const cortex = @import("cortex.zig"); 
const chronos = @import("chronos.zig");
const hunter = @import("hunter.zig");

// --- UNIVERSAL CONSTANTS ---
const SYSTEM_NAME = "@NSIBLE OS";
const VERSION     = "v0.10.1 // Banyan";
const HOST_ID     = "dataDESK:archX";
const URI_PREFIX  = "@://0.10.1/x8_64-li-mu/";

const WIDTH: usize = 1024;
const HEIGHT: usize = 600;

// --- MEMORY ARCHITECTURE ---
const VOID_SIZE = 42_130_000;
var void_buffer: [VOID_SIZE]u8 = undefined;

const SAP_SIZE = 88_000_000;
var sap_buffer: [SAP_SIZE]u8 = undefined;

var fb_pixels: []u32 = undefined;
var back_buffer: [WIDTH * HEIGHT]u32 = undefined;

// [!] THE BLACK BOX FILE DESCRIPTOR
var panic_fd: i32 = -1;

// .-*-. BLACK BOX RECORDER (PANIC HANDLER) .-*-.
pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (panic_fd >= 0) {
        _ = linux.syscall2(.dup2, @as(usize, @bitCast(panic_fd)), 2);
        
        const header = "\n[ @NSIBLE FATAL EXCEPTION ]\n";
        _ = linux.syscall3(.write, 2, @intFromPtr(header), header.len);
        
        const msg_prefix = "Message: ";
        _ = linux.syscall3(.write, 2, @intFromPtr(msg_prefix), msg_prefix.len);
        _ = linux.syscall3(.write, 2, @intFromPtr(msg.ptr), msg.len);
        const newline = "\n";
        _ = linux.syscall3(.write, 2, @intFromPtr(newline), newline.len);

        if (trace) |t| {
            std.debug.dumpStackTrace(t.*);
        } else {
            std.debug.dumpCurrentStackTrace(ret_addr);
        }
    }

    var blink: bool = true;
    while (true) {
        var delay: usize = 0;
        while (delay < 5_000_000) : (delay += 1) { asm volatile ("pause"); }
        blink = !blink;
    }
}

// --- CORE DRAWING ---
fn drawChar(px: usize, py: usize, char: u8, color: u32) void {
    const bitmap = font.getBitmap(char);
    var y: usize = 0;
    while (y < 8) : (y += 1) {
        var x: usize = 0;
        while (x < 8) : (x += 1) {
            if ((bitmap[y] & (@as(u8, 1) << @intCast(7 - x))) != 0) {
                const sx = px + x;
                const sy = py + y;
                if (sx < WIDTH and sy < HEIGHT) back_buffer[sy * WIDTH + sx] = color;
            }
        }
    }
}

fn drawRect(x: usize, y: usize, w: usize, h: usize, color: u32) void {
    var dy: usize = 0;
    while (dy < h) : (dy += 1) {
        var dx: usize = 0;
        while (dx < w) : (dx += 1) {
            const sx = x + dx;
            const sy = y + dy;
            if (sx < WIDTH and sy < HEIGHT) back_buffer[sy * WIDTH + sx] = color;
        }
    }
}

fn clear(color: u32) void {
    for (&back_buffer) |*pixel| { pixel.* = color; }
}

fn print(x: usize, y: usize, text: []const u8, color: u32) void {
    var cx = x;
    for (text) |char| { 
        drawChar(cx, y, char, color); 
        cx += 8;
    }
}

fn drawHeader(is_high: bool) void {
    drawRect(0, 0, WIDTH, 20, 0x00DC143C);
    var buf: [128]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "{s} // {s} // {s}", .{SYSTEM_NAME, VERSION, HOST_ID}) catch "HEADER_ERR";
    print(10, 6, header, 0x00FFFFFF);
    const glyph: u8 = if (is_high) 127 else 128;
    drawChar(962, 6, glyph, 0x00FFFFFF);
}

fn drawUriBar(input_buf: []const u8, input_len: usize) void {
    const char_w = 8;
    const line_h = 10;
    const padding = 6;
    var cursor_x: usize = 10;
    var lines: usize = 1;
    cursor_x += URI_PREFIX.len * char_w;

    var i: usize = 0;
    while (i < input_len) : (i += 1) {
        cursor_x += char_w;
        if (cursor_x >= WIDTH - 10) { lines += 1; cursor_x = 10 + char_w; }
    }
    
    const bar_height = (lines * line_h) + (padding * 2);
    const start_y = if (bar_height < HEIGHT) HEIGHT - bar_height else 0;
    drawRect(0, start_y, WIDTH, bar_height, 0x00DC143C);
    
    cursor_x = 10;
    var cursor_y: usize = start_y + padding;
    for (URI_PREFIX) |char| { 
        drawChar(cursor_x, cursor_y, char, 0x00000000); 
        cursor_x += char_w;
        if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; } 
    }
    
    i = 0;
    while (i < input_len) : (i += 1) {
        const char = input_buf[i];
        drawChar(cursor_x, cursor_y, char, 0x00000000);
        cursor_x += char_w;
        if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; }
    }
    drawChar(cursor_x, cursor_y, 0xDB, 0x00000000);
}

// [!] EXIT SEQUENCE (Matrix & Stamp)
fn exitSequence() noreturn {
    // 1. Blackout
    clear(0x00000000);
    
    // 2. HighClaw Stamp [Bottom Right Marker]
    const stamp_x = WIDTH - 24;
    const stamp_y = HEIGHT - 16;
    drawChar(stamp_x, stamp_y, 127, 0x00DC143C); // 高
    drawChar(stamp_x + 8, stamp_y, 128, 0x00DC143C); // 爪
    
    // 3. Flush to screen
    @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);
    
    // 4. Clean Host TTY (ANSI: Clear Screen, Home Cursor, Show Cursor)
    const term_reset = "\x1b[2J\x1b[H\x1b[?25h";
    _ = linux.syscall3(.write, 1, @intFromPtr(term_reset), term_reset.len);
    
    std.process.exit(0);
}

// [!] IGNITION SEQUENCE & AUDIO RESONATOR
fn bootSplash(allocator: std.mem.Allocator) void {
    clear(0x00000000);
    
    const center_y = HEIGHT / 2;
    drawRect(0, center_y, WIDTH, 1, 0x00444444);
    
    // 1. Establish State Seed
    var state_seed: usize = 42;
    if (std.fs.cwd().statFile("aiua.tome")) |stat| {
        state_seed = @as(usize, @intCast(stat.size));
    } else |_| {}

    // 2. Prepare 8-bit PCM Output Buffer (8000 Hz for ~4 seconds)
    const sample_rate = 8000;
    const buffer_size = 32000; // Adjusted buffer down slightly to match the faster execution speed naturally
    var pcm = allocator.alloc(u8, buffer_size) catch return;
    defer allocator.free(pcm);

    // 3. Modulate Visual & Audio Waveform Concurrently
    var x: usize = 100;
    var step: usize = 0;
    var sample_idx: usize = 0;
    
    while (x < WIDTH - 100) : (x += 12) {
        const amplitude = if (step % 5 == 0) @as(usize, 30) 
                          else if (step % 3 == 0) @as(usize, 14) 
                          else if (step % 2 == 0) @as(usize, 8) 
                          else @as(usize, 2);
                          
        const y = center_y - amplitude;
        drawRect(x, y, 6, amplitude * 2, 0x00DC143C);

        // Mathematical Translation to Audio
        var freq: f32 = 0.0;
        if (amplitude == 30) {
            freq = 2000.0 + @as(f32, @floatFromInt(state_seed % 500));
        } else if (amplitude == 14) {
            freq = 1200.0 + @as(f32, @floatFromInt(state_seed % 300));
        } else if (amplitude == 8) {
            freq = 800.0 + @as(f32, @floatFromInt(state_seed % 100));
        }
        
        const chunk_size = 470; // Adjusted samples per visual rendering step for the 2x speedup
        var chunk: usize = 0;
        
        while (chunk < chunk_size and sample_idx < buffer_size) : (chunk += 1) {
            if (freq == 0.0) {
                pcm[sample_idx] = 128; // Silence baseline
            } else {
                const t = @as(f32, @floatFromInt(sample_idx)) / @as(f32, sample_rate);
                const period = 1.0 / freq;
                const phase = @mod(t, period) / period;
                var wave_f = phase;
                if (phase > 0.5) wave_f = 1.0 - phase;
                wave_f *= 2.0; 
                
                const vol = @as(f32, @floatFromInt(amplitude)) / 30.0;
                const out = (wave_f * 127.0 * vol) + 128.0;
                pcm[sample_idx] = @as(u8, @intFromFloat(out));
            }
            sample_idx += 1;
        }
        step += 1;
    }

    // 4. Print Typography
    print(WIDTH / 2 - 80, center_y - 60, "A E S   T E C H N O L O G I E S", 0x00FFFFFF);
    print(WIDTH / 2 - 40, center_y + 30, "SYSTEM WAKING...", 0x00AAAAAA);
    
    var time_buf: [64]u8 = undefined;
    const time_str = chronos.getCycleString(&time_buf);
    const time_x = WIDTH / 2 - ((time_str.len * 8) / 2);
    print(time_x, center_y + 45, time_str, 0x00FFBF00);
    @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);

    // 5. Strike the Resonator File
    if (std.fs.cwd().createFile("resonator.raw", .{})) |file| {
        file.writeAll(pcm) catch {};
        file.close();
        
        // 6. Spawn Async Audio Vector
        const argv = [_][]const u8{ "aplay", "-q", "-f", "U8", "-r", "8000", "-c", "1", "resonator.raw" };
        var agent = std.process.Child.init(&argv, allocator);
        agent.stdout_behavior = .Ignore;
        agent.stderr_behavior = .Ignore;
        _ = agent.spawn() catch {};
    } else |_| {} 
    
    // [!] CALIBRATED TIMING: Hold frame for exactly 0.00158 cycles (~4 seconds) while audio plays
    codex.zen(0.00158); 
}

// --- MAIN ENTRY ---
pub fn main() !void {
    const fs = std.fs.cwd();
    if (fs.access("aiua.tome", .{})) |_| {} else |_| {
        if (fs.createFile("aiua.tome", .{})) |f| { f.close(); } else |_| {}
    }
    
    if (fs.createFile("trail.tome", .{})) |f| {
        panic_fd = f.handle;
    } else |_| {}

    _ = linux.syscall5(.mount, @intFromPtr("proc"), @intFromPtr("/proc"), @intFromPtr("proc"), 0, 0);
    _ = linux.syscall5(.mount, @intFromPtr("sysfs"), @intFromPtr("/sys"), @intFromPtr("sysfs"), 0, 0);
    
    const fd_res = linux.syscall3(.open, @intFromPtr("/dev/fb0"), 2, 0);
    const fb_fd: i32 = @bitCast(@as(u32, @truncate(fd_res)));
    const map_len = WIDTH * HEIGHT * 4;
    const map_res = linux.syscall6(.mmap2, 0, map_len, 3, 1, @as(usize, @bitCast(fb_fd)), 0);
    const fb_ptr = @as([*]u32, @ptrFromInt(map_res));
    fb_pixels = fb_ptr[0..(WIDTH * HEIGHT)];

    nerve.init();
    codex.tuneIn();
    const net_fd = codex.bindUmbilical(); 

    // [!] INSTANTIATE MEMORY PARTITIONS FIRST FOR AUDIO GENERATION
    var void_fba = std.heap.FixedBufferAllocator.init(&void_buffer);
    const void_allocator = void_fba.allocator();

    var sap_fba = std.heap.FixedBufferAllocator.init(&sap_buffer);

    bootSplash(void_allocator);
    
    var sys_hunter = hunter.Hunter.init(void_allocator, &sap_fba);
    defer sys_hunter.deinit();

    var journal: [4096]u8 = undefined;
    var journal_len: usize = 0;
    var esc_seq: [8]u8 = undefined; 
    var esc_len: usize = 0;
    var seq_buf: [6]u8 = .{0} ** 6;
    var blink_timer: usize = 0;
    var is_high_cycle: bool = true;
    var dirty: bool = true;

    while (true) {
        try sys_hunter.tick();

        if (codex.transcieve(net_fd)) |byte| {
            dirty = true;
            
            // 1. HARDWARE REFLEX SEQUENCE
            var k: usize = 0;
            while (k < 5) : (k += 1) { seq_buf[k] = seq_buf[k+1]; }
            seq_buf[5] = byte;

            var reflex_triggered = false;

            if (std.mem.eql(u8, &seq_buf, ".!XX-.")) {
                exitSequence(); // [!] CLEAN MATRIX TERMINATION
            } 
            else if (std.mem.endsWith(u8, &seq_buf, ".![-.")) {
                sys_hunter.lens.shiftScope(1);
                if (journal_len >= 4) journal_len -= 4;
                reflex_triggered = true;
            } 
            else if (std.mem.endsWith(u8, &seq_buf, ".!]-.")) {
                sys_hunter.lens.shiftScope(-1);
                if (journal_len >= 4) journal_len -= 4;
                reflex_triggered = true;
            } 
            else if (std.mem.endsWith(u8, &seq_buf, "//-.")) {
                if (journal_len >= 3) journal_len -= 3;
                const cmd_slice = journal[0..journal_len];
                const clean_slice = std.mem.trimRight(u8, cmd_slice, " ");
                sys_hunter.createMemo(clean_slice) catch {};
                journal_len = 0;
                reflex_triggered = true;
            }

            if (!reflex_triggered) {
                // 2. ANSI
                if (byte == 27) { 
                    esc_len = 1; esc_seq[0] = byte;
                } else if (esc_len > 0) {
                    if (esc_len < 8) {
                        esc_seq[esc_len] = byte; esc_len += 1;
                        if (esc_len == 3 and esc_seq[1] == '[') {
                            if (byte == 'A') { if (sys_hunter.scroll_y > 0) sys_hunter.scroll_y -= 1; esc_len = 0; }
                            else if (byte == 'B') { sys_hunter.scroll_y += 1; esc_len = 0; }
                            else if (byte == 'C') { sys_hunter.navigateHistory(1) catch {}; esc_len = 0; }
                            else if (byte == 'D') { sys_hunter.navigateHistory(-1) catch {}; esc_len = 0; }
                        } else if (byte == '~') {
                             if (esc_len >= 4 and esc_seq[1] == '[') {
                                const digit = esc_seq[2];
                                if (digit == '5') { if (sys_hunter.scroll_y >= 15) sys_hunter.scroll_y -= 15 else sys_hunter.scroll_y = 0; }
                                else if (digit == '6') { sys_hunter.scroll_y += 15; }
                            }
                            esc_len = 0;
                        }
                    } else { esc_len = 0; }
                } 
                // 3. CORTEX
                else {
                     if (byte == '\n' or byte == '\r') {
                        const cmd_slice = journal[0..journal_len];
                        const response = cortex.dispatch(cmd_slice);
                        switch (response.action) {
                            .CLEAR => {}, 
                            .EXIT => exitSequence(), // [!] CLEAN MATRIX TERMINATION
                            .SHED => { sys_hunter.shed(); journal_len = 0; },
                            .SCOPE_IN => { sys_hunter.lens.shiftScope(1); journal_len = 0; },
                            .SCOPE_OUT => { sys_hunter.lens.shiftScope(-1); journal_len = 0; },
                            .MEMO => { 
                                const txt = if (response.text.len > 0) response.text else cmd_slice;
                                sys_hunter.createMemo(txt) catch {}; journal_len = 0; 
                            },
                            .PRINT => {
                                journal_len = 0;
                                for (response.text) |c| {
                                    if (journal_len < 4096) { journal[journal_len] = c; journal_len += 1; }
                                }
                            },
                            .HUNT => {
                                 if (std.mem.eql(u8, response.text, "v")) { sys_hunter.scroll_y += 1; }
                                 else if (std.mem.eql(u8, response.text, "^")) { if (sys_hunter.scroll_y > 0) sys_hunter.scroll_y -= 1; }
                                 else {
                                    var target = response.text;
                                    if (std.mem.startsWith(u8, target, "hunt ")) target = target[5..];
                                    sys_hunter.hunt(target) catch { sys_hunter.status = "FETCH_ERR"; };
                                }
                                journal_len = 0;
                            },
                            .NONE => { journal_len = 0; }
                        }
                    } else if (byte == 127 or byte == 8) {
                        if (journal_len > 0) journal_len -= 1;
                    } else if (byte >= 32 and byte <= 126) {
                        if (journal_len < 4096) { journal[journal_len] = byte; journal_len += 1; }
                    }
                }
            }
        }

        blink_timer += 1;
        if (blink_timer > 35) { is_high_cycle = !is_high_cycle; blink_timer = 0; dirty = true; }

        if (dirty) {
            clear(0x00000000);
            drawHeader(is_high_cycle);
            if (sys_hunter.active) { sys_hunter.render(&back_buffer, WIDTH, HEIGHT); } 
            else { print(20, 50, "TIMELINE Terminal. [NO_FOCUS][ZEN]", 0x00555555); }
            drawUriBar(journal[0..journal_len], journal_len);
            @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);
            dirty = false;
        }
        codex.zen(0.000004);
    }
}
