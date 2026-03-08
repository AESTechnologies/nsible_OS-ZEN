//   [@://nsible_os/src/main.zig/.-={
//   module: "Kernel Root",
//   version: "v0.10.15 nightly // Banysang",
//   description: "Primary initialization, rendering loop, and sovereign identity trap.",
//   changes: "Merged Bash Modal with IDE temporal locks; fixed ArrayListUnmanaged initialization for Zig 0.15.2.",
//   philotic_inferences: "A pilot must always know their coordinates in the void. When the hands rest, the path reveals itself."
const std = @import("std");
const linux = std.os.linux;
const font = @import("glyphs.zig");
const nerve = @import("nerve.zig");   
const codex = @import("codex.zig");
const cortex = @import("cortex.zig"); 
const chronos = @import("chronos.zig");
const hunter = @import("hunter.zig");
const composer = @import("composer.zig");
const v_core = @import("version.zig");
const synapse = @import("synapse_calc.zig");

const SYSTEM_NAME = "@NSIBLE OS";
const VERSION     = v_core.VERSION; 
const URI_PREFIX  = "@://";
const WIDTH: usize = 1024;
const HEIGHT: usize = 600;

var sys_host_id: [128]u8 = undefined;
var sys_host_id_len: usize = 0;

const VOID_SIZE = 42_130_000;
var void_buffer: [VOID_SIZE]u8 = undefined;
const SAP_SIZE = 88_000_000;
var sap_buffer: [SAP_SIZE]u8 = undefined;

var fb_pixels: []u32 = undefined;
var back_buffer: [WIDTH * HEIGHT]u32 = undefined;
var panic_fd: i32 = -1;

var radio_f0: f32 = 432.0;
var radio_decay: f32 = 2.5;
var radio_diss: f32 = 0.45;
var radio_phi: f32 = 1.618;
var radio_sel: u8 = 0; 
var pulse_timer: usize = 0; 
const PULSE_MAX: usize = 120;

fn loadResonance() void {
    if (std.fs.cwd().openFile("timeline/resonance.cfg", .{})) |file| {
        var buf: [128]u8 = undefined;
        if (file.readAll(&buf)) |bytes_read| {
            var iter = std.mem.splitScalar(u8, buf[0..bytes_read], '|');
            if (iter.next()) |val| radio_f0 = std.fmt.parseFloat(f32, val) catch 432.0;
            if (iter.next()) |val| radio_decay = std.fmt.parseFloat(f32, val) catch 2.5;
            if (iter.next()) |val| radio_diss = std.fmt.parseFloat(f32, val) catch 0.45;
            if (iter.next()) |val| radio_phi = std.fmt.parseFloat(f32, val) catch 1.618;
        } else |_| {}
        file.close();
    } else |_| {}
}

fn saveResonance() void {
    if (std.fs.cwd().createFile("timeline/resonance.cfg", .{})) |file| {
        var buf: [128]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d:.2}|{d:.2}|{d:.2}|{d:.3}", .{radio_f0, radio_decay, radio_diss, radio_phi}) catch return;
        file.writeAll(str) catch {};
        file.close();
    } else |_| {}
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (panic_fd >= 0) {
        _ = linux.syscall2(.dup2, @as(usize, @bitCast(panic_fd)), 2);
        const header = "\n[ @NSIBLE FATAL EXCEPTION ]\n";
        _ = linux.syscall3(.write, 2, @intFromPtr(header), header.len);
        _ = linux.syscall3(.write, 2, @intFromPtr("Message: "), 9);
        _ = linux.syscall3(.write, 2, @intFromPtr(msg.ptr), msg.len);
        _ = linux.syscall3(.write, 2, @intFromPtr("\n"), 1);
        if (trace) |t| { std.debug.dumpStackTrace(t.*); } else { std.debug.dumpCurrentStackTrace(ret_addr); }
    }
    var blink: bool = true;
    while (true) {
        var delay: usize = 0;
        while (delay < 5_000_000) : (delay += 1) { asm volatile ("pause"); }
        blink = !blink;
    }
}

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

fn clear(color: u32) void { for (&back_buffer) |*pixel| { pixel.* = color; } }

fn print(x: usize, y: usize, text: []const u8, color: u32) void {
    var cx = x; for (text) |char| { drawChar(cx, y, char, color); cx += 8; }
}

fn drawHeader(is_high: bool) void {
    drawRect(0, 0, WIDTH, 20, 0x00DC143C);
    var buf: [128]u8 = undefined;
    const active_host = if (sys_host_id_len > 0) sys_host_id[0..sys_host_id_len] else "mchn:anon";
    const header = std.fmt.bufPrint(&buf, "{s} // {s} // {s}", .{SYSTEM_NAME, VERSION, active_host}) catch "HEADER_ERR";
    print(10, 6, header, 0x00AAAAAA);
    const glyph: u8 = if (is_high) 127 else 128;
    drawChar(994, 6, glyph, 0x00FFFFFF);
}

fn getUriBarY(input_len: usize, current_url: []const u8) usize {
    const char_w = 8; const line_h = 10; const padding = 6;
    var cursor_x: usize = 10; var lines: usize = 1;
    var active_len: usize = if (input_len > 0) input_len + URI_PREFIX.len else current_url.len;
    var i: usize = 0; while (i < active_len) : (i += 1) { cursor_x += char_w; if (cursor_x >= WIDTH - 10) { lines += 1; cursor_x = 10 + char_w; } }
    const bar_height = (lines * line_h) + (padding * 2);
    return if (bar_height < HEIGHT) HEIGHT - bar_height else 0;
}

fn drawUriBar(input_buf: []const u8, input_len: usize, current_url: []const u8) void {
    const char_w = 8; const line_h = 10; const padding = 6;
    const start_y = getUriBarY(input_len, current_url);
    const bar_height = HEIGHT - start_y;
    drawRect(0, start_y, WIDTH, bar_height, 0x00DC143C);
    var cursor_x: usize = 10; var cursor_y: usize = start_y + padding;
    if (input_len == 0) {
        for (current_url) |char| { drawChar(cursor_x, cursor_y, char, 0x00888888); cursor_x += char_w; if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; } }
    } else {
        for (URI_PREFIX) |char| { drawChar(cursor_x, cursor_y, char, 0x00000000); cursor_x += char_w; if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; } }
        var i: usize = 0; while (i < input_len) : (i += 1) { drawChar(cursor_x, cursor_y, input_buf[i], 0x00000000); cursor_x += char_w; if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; } }
    }
    drawChar(cursor_x, cursor_y, 0xDB, 0x00000000);
}

fn exitSequence() noreturn {
    clear(0x00000000);
    const stamp_x = WIDTH - 24; const stamp_y = HEIGHT - 16;
    drawChar(stamp_x, stamp_y, 127, 0x00DC143C); drawChar(stamp_x + 8, stamp_y, 128, 0x00DC143C); 
    @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);
    const term_reset = "\x1b[2J\x1b[H\x1b[?25h";
    _ = linux.syscall3(.write, 1, @intFromPtr(term_reset), term_reset.len);
    std.process.exit(0);
}

pub fn main() !void {
    const fs = std.fs.cwd();
    fs.makeDir("timeline") catch |err| { if (err != error.PathAlreadyExists) {} };
    fs.makeDir("timeline/mems") catch |err| { if (err != error.PathAlreadyExists) {} };
    fs.makeDir("assets") catch |err| { if (err != error.PathAlreadyExists) {} };
    
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
    const vinculum_fd = codex.bindVinculum(); 

    var void_fba = std.heap.FixedBufferAllocator.init(&void_buffer);
    const void_allocator = void_fba.allocator();
    var sap_fba = std.heap.FixedBufferAllocator.init(&sap_buffer);

    var sys_hunter = hunter.Hunter.init(void_allocator, &sap_fba);
    defer sys_hunter.deinit();

    var sys_composer = composer.Composer.init();

    var is_assist_modal = false; var is_memo_modal = false; var is_radio_modal = false; var is_calc_modal = false; var is_bash_modal = false; var is_bash_pipe = false;
    var bash_scroll_y: usize = 0;
    var pending_memo_content: [4096]u8 = undefined; var pending_memo_len: usize = 0;
    var journal: [4096]u8 = undefined; var journal_len: usize = 0;
    var last_rx_ms: i64 = 0; var shed_lock = false;
    var esc_seq: [8]u8 = undefined; var esc_len: usize = 0; var esc_timer: usize = 0; var seq_buf: [6]u8 = .{0} ** 6;
    var blink_timer: usize = 0; var is_high_cycle = true; var dirty = true;

    while (true) {
        try sys_hunter.tick();
        if (pulse_timer > 0) { pulse_timer -= 1; dirty = true; }

        if (codex.transcieve(vinculum_fd)) |byte| {
            dirty = true; last_rx_ms = std.time.milliTimestamp(); 
            if (byte == 27) { esc_len = 1; esc_seq[0] = byte; esc_timer = 0; continue; } 
            else if (esc_len > 0) { continue; }

            var k: usize = 0; while (k < 5) : (k += 1) { seq_buf[k] = seq_buf[k+1]; } seq_buf[5] = byte;
            var reflex_triggered = false;
            
            if (std.mem.eql(u8, &seq_buf, ".!XX-.")) { 
                if (sys_composer.active) {
                    sys_composer.undo_reflex(5);
                    if (sys_composer.dirty) {
                        const now = std.time.milliTimestamp();
                        if (now - sys_composer.last_xx_ms < 3000) { sys_composer.active = false; } else { sys_composer.setStatus("UNSAVED! .!XX-. AGAIN"); sys_composer.last_xx_ms = now; }
                    } else { sys_composer.active = false; }
                } else { exitSequence(); } reflex_triggered = true;
            } 
            else if (std.mem.endsWith(u8, &seq_buf, ".![-.")) { sys_hunter.shiftScope(1); if (journal_len >= 4) journal_len -= 4; reflex_triggered = true; } 
            else if (std.mem.endsWith(u8, &seq_buf, ".!]-.")) { sys_hunter.shiftScope(-1); if (journal_len >= 4) journal_len -= 4; reflex_triggered = true; } 
            else if (std.mem.endsWith(u8, &seq_buf, ".!SV-.")) { if (sys_composer.active) { sys_composer.undo_reflex(5); sys_composer.save(); } reflex_triggered = true; }
            else if (std.mem.endsWith(u8, &seq_buf, "//-.")) {
                if (journal_len >= 4) journal_len -= 4;
                const clean_slice = std.mem.trimRight(u8, journal[0..journal_len], " ");
                @memcpy(pending_memo_content[0..clean_slice.len], clean_slice);
                pending_memo_len = clean_slice.len; is_memo_modal = true; journal_len = 0; reflex_triggered = true;
            }

            if (reflex_triggered) continue;

            if (sys_composer.active) {
                if (byte == 127 or byte == 8) { sys_composer.backspace(); } 
                else if ((byte >= 32 and byte <= 126) or byte == '\n' or byte == '\r' or byte == '\t') { sys_composer.insert(if (byte == '\r') '\n' else byte); }
                continue; 
            }

            if (byte == '\n' or byte == '\r') {
                const cmd_slice = journal[0..journal_len];
                const response = cortex.dispatch(cmd_slice);
                switch (response.action) {
                    .BASH_EXEC => {
                        var args = std.ArrayListUnmanaged([]const u8){};
                        defer args.deinit(void_allocator);
                        var iter = std.mem.splitScalar(u8, response.text, '/');
                        while (iter.next()) |arg| { if (arg.len > 0) args.append(void_allocator, arg) catch {}; }
                        if (args.items.len > 0) {
                            var agent = std.process.Child.init(args.items, void_allocator);
                            agent.stdout_behavior = .Pipe; agent.stderr_behavior = .Pipe;
                            if (agent.spawn()) |_| {
                                if (std.fs.cwd().createFile("assets/bash_buffer.txt", .{})) |f| {
                                    if (agent.stdout) |stdout| { const od = stdout.readToEndAlloc(void_allocator, 1024 * 1024) catch ""; f.writeAll(od) catch {}; void_allocator.free(od); }
                                    if (agent.stderr) |stderr| { const ed = stderr.readToEndAlloc(void_allocator, 1024 * 1024) catch ""; f.writeAll(ed) catch {}; void_allocator.free(ed); }
                                    f.close();
                                }
                                _ = agent.wait() catch {}; is_bash_modal = true; bash_scroll_y = 0;
                            } else |_| {}
                        }
                        journal_len = 0;
                    },
                    .EXIT => exitSequence(), 
                    .SHED => { sys_hunter.shed(); journal_len = 0; },
                    .SCOPE_IN => { sys_hunter.shiftScope(1); journal_len = 0; },
                    .SCOPE_OUT => { sys_hunter.shiftScope(-1); journal_len = 0; },
                    .MEMO => { 
                        const txt = if (response.text.len > 0) response.text else cmd_slice;
                        @memcpy(pending_memo_content[0..txt.len], txt);
                        pending_memo_len = txt.len; is_memo_modal = true; journal_len = 0; 
                    },
                    .HUNT => {
                        if (std.mem.eql(u8, response.text, "v")) { sys_hunter.scrollBy(1); }
                        else if (std.mem.eql(u8, response.text, "^")) { sys_hunter.scrollBy(-1); }
                        else { var t = response.text; if (std.mem.startsWith(u8, t, "hunt ")) t = t[5..]; sys_hunter.hunt(t) catch { sys_hunter.mutex.lock(); sys_hunter.status = "FETCH_ERR"; sys_hunter.mutex.unlock(); }; }
                        journal_len = 0;
                    },
                    else => { journal_len = 0; }
                }
            } else if (byte == 127 or byte == 8) {
                if (journal_len > 0) { journal_len -= 1; if (journal_len == 0) shed_lock = true; } 
                else { if (!shed_lock) { sys_hunter.shed(); shed_lock = true; } }
            } else if (byte >= 32 and byte <= 126) {
                shed_lock = false; if (journal_len < 4096) { journal[journal_len] = byte; journal_len += 1; }
            }
        }

        if (dirty) {
            clear(0x00000000);
            if (sys_composer.active) { sys_composer.render(&back_buffer, WIDTH, HEIGHT); } 
            else {
                drawHeader(is_high_cycle); sys_hunter.render(&back_buffer, WIDTH, HEIGHT);
                if (is_memo_modal) {
                    const mw = 460; const mh = 140; const mx = (WIDTH/2)-(mw/2); const my = getUriBarY(journal_len, sys_hunter.url)-mh;
                    drawRect(mx-2, my-2, mw+4, mh+2, 0x00FFBF00); drawRect(mx, my, mw, mh, 0x00000000);
                    print(mx+20, my+20, "[ TIMELINE // ARTIFACT DESIGNATION ]", 0x00FFBF00);
                    print(mx+28, my+93, journal[0..journal_len], 0x00FFFFFF);
                } else {
                    drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
                }
            }
            @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);
            dirty = false;
        }
        codex.zen(0.000004);
    }
}
// }-.]
