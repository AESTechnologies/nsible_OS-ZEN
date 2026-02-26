const std = @import("std");
const linux = std.os.linux;
const font = @import("glyphs.zig");
const nerve = @import("nerve.zig");   
const codex = @import("codex.zig");   // [ARCH] CODEX
const cortex = @import("cortex.zig"); 

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

// Print text
fn print(x: usize, y: usize, text: []const u8, color: u32) void {
    var cx = x;
    for (text) |char| {
        drawChar(cx, y, char, color);
        cx += 8;
    }
}

// --- UI COMPONENTS ---

fn drawUriBar(input_buf: []const u8, input_len: usize) void {
    const prefix = "@://v0.7.osx/state/hal_dsl:active/";
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

// « ENTRY POINT
pub fn main() !void {
    // 1. MOUNT
    _ = linux.syscall5(.mount, @intFromPtr("proc"), @intFromPtr("/proc"), @intFromPtr("proc"), 0, 0);
    _ = linux.syscall5(.mount, @intFromPtr("sysfs"), @intFromPtr("/sys"), @intFromPtr("sysfs"), 0, 0);
    _ = linux.syscall5(.mount, @intFromPtr("devtmpfs"), @intFromPtr("/dev"), @intFromPtr("devtmpfs"), 0, 0);

    // 2. FRAMEBUFFER
    const fd_res = linux.syscall3(.open, @intFromPtr("/dev/fb0"), 2, 0);
    const fb_fd: i32 = @bitCast(@as(u32, @truncate(fd_res)));
    if (fb_fd < 0) { while (true) { codex.zen(100_000); } }

    // 3. MAP
    const map_len = WIDTH * HEIGHT * 4;
    const map_res = linux.syscall6(.mmap2, 0, map_len, 3, 1, @as(usize, @bitCast(fb_fd)), 0);
    const fb_ptr = @as([*]u32, @ptrFromInt(map_res));
    fb_pixels = fb_ptr[0..(WIDTH * HEIGHT)];

    // 4. ALIGN FREQUENCY
    nerve.init();
    codex.tuneIn();

    // 5. STORAGE & STATE
    var journal: [4096]u8 = undefined;
    var journal_len: usize = 0;
    var seq_buf: [6]u8 = .{0, 0, 0, 0, 0, 0};
    const exit_key = ".!XX-.";

    // Eye Position
    const eye_x = 987;
    const eye_y = 8;
    
    var blink_timer: usize = 0;
    var is_blinking: bool = false;
    var dirty: bool = true;

    // 6. THE ETERNAL LOOP
    while (true) {
        // [A] TRANSCIEVE (Input)
        if (codex.transcieve()) |byte| {
            dirty = true;

            // [!] PROCESS INPUT
            if (byte == '\n' or byte == '\r') {
                const cmd_slice = journal[0..journal_len];
                const response = cortex.dispatch(cmd_slice);
                journal_len = 0;
                
                switch (response.action) {
                    .CLEAR => {}, 
                    .EXIT => break,
                    .PRINT => {
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
                if (journal_len > 0) journal_len -= 1;
            } else {
                if (journal_len < 4096) {
                    journal[journal_len] = byte;
                    journal_len += 1;
                }
            }

            // [!] SEQUENCE CHECK
            var i: usize = 0;
            while (i < 5) : (i += 1) { seq_buf[i] = seq_buf[i+1]; }
            seq_buf[5] = byte;
            if (std.mem.eql(u8, &seq_buf, exit_key)) break;
        }

        // [B] AUTONOMIC FUNCTIONS (Blink)
        blink_timer += 1;
        
        if (blink_timer > 50) {
            is_blinking = true;
            dirty = true;
        }
        
        if (blink_timer > 52) {
            is_blinking = false;
            blink_timer = 0;
            dirty = true;
        }

        // [C] RENDER (Only if Dirty)
        if (dirty) {
            clear(0x00000000);
            
            // Draw Status Bar
            var bar_x: usize = 0;
            while (bar_x < WIDTH) : (bar_x += 1) {
                var bar_y: usize = 0;
                while (bar_y < 20) : (bar_y += 1) {
                    fb_pixels[bar_y * WIDTH + bar_x] = 0x00DC143C;
                }
            }
 
            // Print Header
            print(10, 6, "@NSIBLE OS // v0.7 // VOID_LINK: ACTIVE", 0x00FFFFFF);
            
            // Draw Main Body (Status)
            // FIXED: We now render the High Claw glyphs (127, 128) regardless of blinking.
            print(20, 50, "SYSTEM: \x7F \x80", 0x00DC143C);

            drawUriBar(journal[0..journal_len], journal_len);
            
            // Draw Eye
            if (is_blinking) {
                drawChar(eye_x, eye_y, '<', 0x00DC143C);
                drawChar(eye_x + 16, eye_y, '-', 0x00DC143C);
            } else {
                drawChar(eye_x, eye_y, '<', 0x00FFFFFF);
                drawChar(eye_x + 16, eye_y, 'o', 0x00FFFFFF);
            }
            
            dirty = false;
        }
        
        // [D] ZEN (wait++)
        codex.zen(10_000);
    }
    
    _ = linux.syscall1(.exit, 0);
}
