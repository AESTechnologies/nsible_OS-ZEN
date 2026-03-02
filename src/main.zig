const std = @import("std");
const linux = std.os.linux;
const font = @import("glyphs.zig");
const nerve = @import("nerve.zig");   
const codex = @import("codex.zig");
const cortex = @import("cortex.zig"); 
const chronos = @import("chronos.zig"); // Keeping import if needed later, but removing clock UI.
const hunter = @import("hunter.zig");

// --- UNIVERSAL CONSTANTS ---
const SYSTEM_NAME = "@NSIBLE OS";
const VERSION     = "v0.10.1 // Banyan";
const HOST_ID     = "dataDESK:archX";
const URI_PREFIX  = "@://0.10.1/x8_64-li-mu/";

const WIDTH: usize = 1024;
const HEIGHT: usize = 600;

var fb_pixels: []u32 = undefined;
var back_buffer: [WIDTH * HEIGHT]u32 = undefined;

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

// [!] RESTORED: High-Claw Indicator (No Clock)
fn drawHeader(high_cycle: bool) void {
    // 1. Top Bar Background (Crimson)
    drawRect(0, 0, WIDTH, 20, 0x00DC143C);

    // 2. Left: System Info
    var buf: [128]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "{s} // {s} // {s}", .{SYSTEM_NAME, VERSION, HOST_ID}) catch "HEADER_ERR";
    print(10, 6, header, 0x00FFFFFF);

    // 3. Right: High/Claw Heartbeat [958x6]
    // Alternates between 高 (127) and 爪 (128) based on cycle state.
    const indicator: u8 = if (high_cycle) 127 else 128;
    drawChar(958, 6, indicator, 0x00FFFFFF);
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

// --- MAIN ENTRY ---
pub fn main() !void {
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

    // [!] MEMORY OPTIMIZATION: Use C Allocator (Malloc)
    const allocator = std.heap.c_allocator;

    var sys_hunter = hunter.Hunter.init(allocator);
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
            // 1. REFLEX (GZL)
            var k: usize = 0;
            while (k < 5) : (k += 1) { seq_buf[k] = seq_buf[k+1]; }
            seq_buf[5] = byte;
            
            if (std.mem.eql(u8, &seq_buf, ".!XX-.")) std.process.exit(0);
            
            // GZL Lens Controls
            if (std.mem.eql(u8, &seq_buf, ".![-.")) { sys_hunter.lens.shiftScope(1); esc_len = 0; }
            if (std.mem.eql(u8, &seq_buf, ".!]-.")) { sys_hunter.lens.shiftScope(-1); esc_len = 0; }

            // 2. ANSI (MOTOR)
            if (byte == 27) { 
                esc_len = 1;
                esc_seq[0] = byte;
            } else if (esc_len > 0) {
                if (esc_len < 8) {
                    esc_seq[esc_len] = byte;
                    esc_len += 1;
                    
                    // Detect Arrows
                    if (esc_len == 3 and esc_seq[1] == '[') {
                        if (byte == 'A') { if (sys_hunter.scroll_y > 0) sys_hunter.scroll_y -= 1; esc_len = 0; }
                        else if (byte == 'B') { sys_hunter.scroll_y += 1; esc_len = 0; }
                        else if (byte == 'C') { sys_hunter.navigateHistory(1) catch {}; esc_len = 0; }
                        else if (byte == 'D') { sys_hunter.navigateHistory(-1) catch {}; esc_len = 0; }
                    } else if (byte == '~') {
                        // Detect PgUp/Dn (5~, 6~)
                        if (esc_len >= 4 and esc_seq[1] == '[') {
                            const digit = esc_seq[2];
                            if (digit == '5') { // PgUp
                                if (sys_hunter.scroll_y >= 15) { sys_hunter.scroll_y -= 15; } else { sys_hunter.scroll_y = 0; }
                            } else if (digit == '6') { // PgDn
                                sys_hunter.scroll_y += 15;
                            }
                        }
                        esc_len = 0;
                    }
                } else { esc_len = 0; }
            } 
            // 3. CORTEX (TYPING)
            else {
                 if (byte == '\n' or byte == '\r') {
                    const cmd_slice = journal[0..journal_len];
                    const response = cortex.dispatch(cmd_slice);
                    
                    switch (response.action) {
                        .CLEAR => {}, 
                        .EXIT => std.process.exit(0),
                        .SHED => { sys_hunter.shed(); journal_len = 0; },
                        .SCOPE_IN => { sys_hunter.lens.shiftScope(1); journal_len = 0; },
                        .SCOPE_OUT => { sys_hunter.lens.shiftScope(-1); journal_len = 0; },
                        .MEMO => { 
                            const txt = if (response.text.len > 0) response.text else cmd_slice;
                            sys_hunter.createMemo(txt) catch {}; 
                            journal_len = 0; 
                        },
                        .PRINT => {
                            journal_len = 0;
                            for (response.text) |c| {
                                if (journal_len < 4096) { journal[journal_len] = c; journal_len += 1; }
                            }
                        },
                        .HUNT => {
                             if (std.mem.eql(u8, response.text, "v")) {
                                sys_hunter.scroll_y += 1;
                            } else if (std.mem.eql(u8, response.text, "^")) {
                                if (sys_hunter.scroll_y > 0) sys_hunter.scroll_y -= 1;
                            } else {
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

        blink_timer += 1;
        if (blink_timer > 35) { is_high_cycle = !is_high_cycle; blink_timer = 0; dirty = true; }

        if (dirty) {
            clear(0x00000000);
            drawHeader(is_high_cycle); // [!] Passing State
            
            if (sys_hunter.active) {
                sys_hunter.render(&back_buffer, WIDTH, HEIGHT);
            } else {
                print(20, 50, "TIMELINE Terminal. [NO_FOCUS][ZEN]", 0x00555555);
            }

            drawUriBar(journal[0..journal_len], journal_len);
            @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);
            dirty = false;
        }
        codex.zen(0.000004);
    }
}
