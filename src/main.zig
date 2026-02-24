const std = @import("std");
const linux = std.os.linux;
const font = @import("glyphs.zig");
const nerve = @import("nerve.zig");   // [.:] MOTOR
const percept = @import("percept.zig"); // [<] SENSOR

// --- HARDWARE CONFIGURATION ---
const WIDTH: usize = 1024;
const HEIGHT: usize = 600;

// .-*-. HARD CONSTRAINT: Panic Handler .-*-.
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    while (true) {}
}

var fb_pixels: []u32 = undefined;

// --- GRAPHICS ENGINE ---

fn drawChar(px: usize, py: usize, char: u8, color: u32) void {
    const bitmap = font.getBitmap(char);
    var y: usize = 0;
    while (y < 8) : (y += 1) {
        var x: usize = 0;
        while (x < 8) : (x += 1) {
            if ((bitmap[y] & (@as(u8, 1) << @intCast(7 - x))) != 0) {
                const screen_x = px + x;
                const screen_y = py + y;
                if (screen_x < WIDTH and screen_y < HEIGHT) {
                    const index = screen_y * WIDTH + screen_x;
                    fb_pixels[index] = color;
                }
            }
        }
    }
}

// Draw a filled rectangle
fn drawRect(x: usize, y: usize, w: usize, h: usize, color: u32) void {
    var dy: usize = 0;
    while (dy < h) : (dy += 1) {
        var dx: usize = 0;
        while (dx < w) : (dx += 1) {
            const sx = x + dx;
            const sy = y + dy;
            if (sx < WIDTH and sy < HEIGHT) {
                fb_pixels[sy * WIDTH + sx] = color;
            }
        }
    }
}

// Clear screen to a specific color
fn clear(color: u32) void {
    for (fb_pixels) |*pixel| {
        pixel.* = color;
    }
}

// --- UI COMPONENTS ---

// Render the Dynamic URI Bar (Bottom-Up)
fn drawUriBar(input_buf: []const u8, input_len: usize) void {
    const prefix = "@://v0.5.os/state/retina:active/";
    const char_w = 8;
    const line_h = 10;
    const padding = 6;
    
    // 1. Calculate Text Flow to determine Bar Height
    var cursor_x: usize = 10;
    var lines: usize = 1;
    
    // Measure Prefix
    cursor_x += prefix.len * char_w;
    
    // Measure Input
    var i: usize = 0;
    while (i < input_len) : (i += 1) {
        cursor_x += char_w;
        if (cursor_x >= WIDTH - 10) {
            lines += 1;
            cursor_x = 10 + char_w; // Reset + 1 char
        }
    }
    
    const bar_height = (lines * line_h) + (padding * 2);
    
    // 2. Calculate Start Y (Bottom Anchor)
    // If bar_height > HEIGHT, we clamp (or scroll, but clamp for now)
    const start_y = if (bar_height < HEIGHT) HEIGHT - bar_height else 0;
    
    // 3. Draw The Bar Background (Crimson)
    drawRect(0, start_y, WIDTH, bar_height, 0x00DC143C);
    
    // 4. Draw The Text (Deep Black) inside the Bar
    cursor_x = 10;
    var cursor_y: usize = start_y + padding;
    
    // Draw Prefix
    for (prefix) |char| {
        drawChar(cursor_x, cursor_y, char, 0x00000000);
        cursor_x += char_w;
        if (cursor_x >= WIDTH - 10) {
            cursor_x = 10;
            cursor_y += line_h;
        }
    }
    
    // Draw Input
    i = 0;
    while (i < input_len) : (i += 1) {
        const char = input_buf[i];
        drawChar(cursor_x, cursor_y, char, 0x00000000);
        cursor_x += char_w;
        if (cursor_x >= WIDTH - 10) {
            cursor_x = 10;
            cursor_y += line_h;
        }
    }
    
    // Draw Cursor Block (Blinking Effect handled by loop logic, this is static pos)
    drawChar(cursor_x, cursor_y, 0xDB, 0x00000000); 
}

// Helper to draw string
fn print(x: usize, y: usize, text: []const u8, color: u32) void {
    var cx = x;
    for (text) |char| {
        drawChar(cx, y, char, color);
        cx += 8;
    }
}

// « ENTRY POINT
pub fn main() !void {
    // 1. MOUNT
    _ = linux.syscall5(.mount, @intFromPtr("proc"), @intFromPtr("/proc"), @intFromPtr("proc"), 0, 0);
    _ = linux.syscall5(.mount, @intFromPtr("sysfs"), @intFromPtr("/sys"), @intFromPtr("sysfs"), 0, 0);
    _ = linux.syscall5(.mount, @intFromPtr("devtmpfs"), @intFromPtr("/dev"), @intFromPtr("devtmpfs"), 0, 0);

    // 2. FRAMEBUFFER
    const fd_res = linux.syscall3(.open, @intFromPtr("/dev/fb0"), 2, 0);
    const fb_fd: i32 = @bitCast(@as(u32, @truncate(fd_res)));
    if (fb_fd < 0) { while (true) { asm volatile ("pause"); } }

    // 3. MAP
    const map_len = WIDTH * HEIGHT * 4;
    const map_res = linux.syscall6(.mmap2, 0, map_len, 3, 1, @as(usize, @bitCast(fb_fd)), 0);
    const fb_ptr = @as([*]u32, @ptrFromInt(map_res));
    fb_pixels = fb_ptr[0..(WIDTH * HEIGHT)];

    // 4. STORAGE
    var journal: [4096]u8 = undefined;
    var journal_len: usize = 0;
    var seq_buf: [6]u8 = .{0, 0, 0, 0, 0, 0};
    const exit_key = ".!XX-.";

    // Eye Position (Top Right)
    const eye_x = 900;
    const eye_y = 50;

    // 5. THE LOOP
    while (true) {
        // [!] RENDER FRAME (Refresh every cycle or only on input? Input driven + blink loop)
        // For simplicity in this structure, we redraw on input or timeout. 
        // But to make blink work, we loop.
        
        // SENSE (Non-blocking check would be ideal for smooth anim, 
        // but 'percept.sense' is currently blocking/raw. 
        // We will assume blocking for typing, then animate.)
        
        if (percept.sense()) |byte| {
            
            // [!] JOURNALING
            if (journal_len < 4096) {
                if (byte == 127 or byte == 8) {
                    if (journal_len > 0) journal_len -= 1;
                } else {
                    journal[journal_len] = byte;
                    journal_len += 1;
                }
            }

            // [!] SEQUENCE CHECK
            var i: usize = 0;
            while (i < 5) : (i += 1) { seq_buf[i] = seq_buf[i+1]; }
            seq_buf[5] = byte;
            if (std.mem.eql(u8, &seq_buf, exit_key)) break;

            // [!] DRAW FRAME: BLINK STATE
            clear(0x00000000);
            
            // 1. Hard-Point Identity (Top Left, Red)
            // Using \x7F (高) and \x80 (爪)
            print(20, 50, "SYSTEM: \x7F \x80", 0x00DC143C);

            // 2. Draw Bar (Bottom Up)
            drawUriBar(journal[0..journal_len], journal_len);

            // 3. Draw Eye (Red Blink)
            drawChar(eye_x, eye_y, '<', 0x00DC143C);
            drawChar(eye_x + 16, eye_y, '-', 0x00DC143C);

            // Hold Blink
            var delay: usize = 0;
            while (delay < 3000000) : (delay += 1) { asm volatile("pause"); }

            // [!] DRAW FRAME: WATCH STATE
            // We redraw to restore white eye immediately
            // (In a real game loop we'd just update state, but this works for direct framebuffer)
            
            clear(0x00000000);
            print(20, 50, "SYSTEM: \x7F \x80", 0x00DC143C);
            drawUriBar(journal[0..journal_len], journal_len);
            
            // Draw Eye (White Open)
            drawChar(eye_x, eye_y, '<', 0x00FFFFFF);
            drawChar(eye_x + 16, eye_y, 'o', 0x00FFFFFF);
        }
    }
    
    _ = linux.syscall1(.exit, 0);
}
