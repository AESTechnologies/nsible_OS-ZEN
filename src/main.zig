const std = @import("std");
const linux = std.os.linux;
const font = @import("glyphs.zig");
const nerve = @import("nerve.zig");   // [.:] MOTOR
const percept = @import("percept.zig"); // [<] SENSOR
const cortex = @import("cortex.zig");   // [^] BRAIN

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
    
    // 1. Calculate Text Flow
    var cursor_x: usize = 10;
    var lines: usize = 1;
    
    cursor_x += prefix.len * char_w;
    
    var i: usize = 0;
    while (i < input_len) : (i += 1) {
        cursor_x += char_w;
        if (cursor_x >= WIDTH - 10) {
            lines += 1;
            cursor_x = 10 + char_w;
        }
    }
    
    const bar_height = (lines * line_h) + (padding * 2);
    const start_y = if (bar_height < HEIGHT) HEIGHT - bar_height else 0;
    
    // 2. Draw Bar (Crimson)
    drawRect(0, start_y, WIDTH, bar_height, 0x00DC143C);
    
    // 3. Draw Text (Black)
    cursor_x = 10;
    var cursor_y: usize = start_y + padding;
    
    for (prefix) |char| {
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
    
    // Static Cursor Block
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
    
    // GZL Exit Buffer (Keeping as secondary safety)
    var seq_buf: [6]u8 = .{0, 0, 0, 0, 0, 0};
    const exit_key = ".!XX-.";

    // Eye Position
    const eye_x = 900;
    const eye_y = 50;

    // 5. THE LOOP
    while (true) {
        if (percept.sense()) |byte| {
            
            // [!] PROCESS INPUT
            if (byte == '\n' or byte == '\r') {
                // [Enter] -> CORTEX DISPATCH
                const cmd_slice = journal[0..journal_len];
                const response = cortex.dispatch(cmd_slice);
                
                // Reset Buffer immediately
                journal_len = 0;
                
                // EXECUTE RESPONSE
                switch (response.action) {
                    .CLEAR => {
                        // Just redraw blank frame
                    },
                    .EXIT => {
                        break;
                    },
                    .PRINT => {
                        // Inject response into buffer so user sees it
                        for (response.text) |c| {
                            if (journal_len < 4096) {
                                journal[journal_len] = c;
                                journal_len += 1;
                            }
                        }
                    },
                    .NONE => {}
                }

            } else if (byte == 127 or byte == 8) {
                // Backspace
                if (journal_len > 0) journal_len -= 1;
            } else {
                // Typing
                if (journal_len < 4096) {
                    journal[journal_len] = byte;
                    journal_len += 1;
                }
            }

            // [!] SEQUENCE CHECK (Hardware Exit)
            var i: usize = 0;
            while (i < 5) : (i += 1) { seq_buf[i] = seq_buf[i+1]; }
            seq_buf[5] = byte;
            if (std.mem.eql(u8, &seq_buf, exit_key)) break;

            // [!] DRAW FRAME (BLINK)
            clear(0x00000000);
            print(20, 50, "SYSTEM: \x7F \x80", 0x00DC143C);
            drawUriBar(journal[0..journal_len], journal_len);
            drawChar(eye_x, eye_y, '<', 0x00DC143C);
            drawChar(eye_x + 16, eye_y, '-', 0x00DC143C); // Blink

            var delay: usize = 0;
            while (delay < 3000000) : (delay += 1) { asm volatile("pause"); }

            // [!] DRAW FRAME (WATCH)
            clear(0x00000000);
            print(20, 50, "SYSTEM: \x7F \x80", 0x00DC143C);
            drawUriBar(journal[0..journal_len], journal_len);
            drawChar(eye_x, eye_y, '<', 0x00FFFFFF);
            drawChar(eye_x + 16, eye_y, 'o', 0x00FFFFFF); // Open
        }
    }
    
    _ = linux.syscall1(.exit, 0);
}
