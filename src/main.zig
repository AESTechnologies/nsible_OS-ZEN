const std = @import("std");
const linux = std.os.linux;
const font = @import("glyphs.zig");
const nerve = @import("nerve.zig");   
const codex = @import("codex.zig");
const cortex = @import("cortex.zig"); 
const chronos = @import("chronos.zig");

// --- HARDWARE CONFIGURATION ---
const WIDTH: usize = 1024;
const HEIGHT: usize = 600;

// .-*-. HARD CONSTRAINT: Panic Handler .-*-.
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    while (true) {}
}

var fb_pixels: []u32 = undefined;
// THE BACKBUFFER: Eliminates refresh-flicker
var back_buffer: [WIDTH * HEIGHT]u32 = undefined;

// --- THE VOID (42.13 MB GHOST HARDDRIVE) ---
const VOID_SIZE = 42_130_000;
var void_buffer: [VOID_SIZE]u8 = undefined;
var void_head: usize = 0;

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
                    back_buffer[index] = color;
                }
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
            if (sx < WIDTH and sy < HEIGHT) {
                back_buffer[sy * WIDTH + sx] = color;
            }
        }
    }
}

fn clear(color: u32) void {
    for (&back_buffer) |*pixel| {
        pixel.* = color;
    }
}

fn print(x: usize, y: usize, text: []const u8, color: u32) void {
    var cx = x;
    for (text) |char| {
        drawChar(cx, y, char, color);
        cx += 8;
    }
}

// --- UI COMPONENTS ---

fn drawUriBar(input_buf: []const u8, input_len: usize) void {
    const prefix = "@://v0.8.osx/state/hal_dsl:active/";
    const char_w = 8;
    const line_h = 10;
    const padding = 6;
    
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
    
    drawRect(0, start_y, WIDTH, bar_height, 0x00DC143C);
    
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
    
    drawChar(cursor_x, cursor_y, 0xDB, 0x00000000);
}

// Helper to save data to the Void Buffer
fn saveToVoid(data: []const u8) void {
    if (void_head + data.len + 2 >= VOID_SIZE) {
        void_head = 0; 
    }
    const sep = " :: ";
    @memcpy(void_buffer[void_head..void_head+4], sep);
    void_head += 4;
    @memcpy(void_buffer[void_head..void_head+data.len], data);
    void_head += data.len;
}

// « ENTRY POINT
pub fn main() !void {
    _ = linux.syscall5(.mount, @intFromPtr("proc"), @intFromPtr("/proc"), @intFromPtr("proc"), 0, 0);
    _ = linux.syscall5(.mount, @intFromPtr("sysfs"), @intFromPtr("/sys"), @intFromPtr("sysfs"), 0, 0);
    _ = linux.syscall5(.mount, @intFromPtr("devtmpfs"), @intFromPtr("/dev"), @intFromPtr("devtmpfs"), 0, 0);
    
    const fd_res = linux.syscall3(.open, @intFromPtr("/dev/fb0"), 2, 0);
    const fb_fd: i32 = @bitCast(@as(u32, @truncate(fd_res)));
    
    if (fb_fd < 0) { while (true) { codex.zen(0.00004); } }

    const map_len = WIDTH * HEIGHT * 4;
    const map_res = linux.syscall6(.mmap2, 0, map_len, 3, 1, @as(usize, @bitCast(fb_fd)), 0);
    const fb_ptr = @as([*]u32, @ptrFromInt(map_res));
    fb_pixels = fb_ptr[0..(WIDTH * HEIGHT)];

    nerve.init();
    codex.tuneIn();
    
    const net_fd = codex.bindUmbilical(); 
    
    var journal: [4096]u8 = undefined;
    var journal_len: usize = 0;
    var seq_buf: [6]u8 = .{0, 0, 0, 0, 0, 0};
    const exit_key = ".!XX-.";

    //[!]UPDATED: Moved to TopRight (Bezel Layer) to clear the Black Space
    const pulse_x = 962;
    const pulse_y = 6;
    
    var blink_timer: usize = 0;
    var is_high_cycle: bool = true;
    var dirty: bool = true;
    
    while (true) {
        if (codex.transcieve(net_fd)) |byte| {
            dirty = true;
            
            if (byte == '\n' or byte == '\r') {
                const cmd_slice = journal[0..journal_len];
                const response = cortex.dispatch(cmd_slice);
                
                switch (response.action) {
                    .CLEAR => {}, 
                    .EXIT => break,
                    .PRINT => {
                        journal_len = 0; 
                        for (response.text) |c| {
                            if (journal_len < 4096) {
                                journal[journal_len] = c;
                                journal_len += 1;
                            }
                        }
                    },
                    .NONE => {
                        if (journal_len > 0) {
                            saveToVoid(cmd_slice);
                        }
                        journal_len = 0;
                    }
                }
            } else if (byte == 127 or byte == 8) {
                if (journal_len > 0) journal_len -= 1;
            } else {
                if (journal_len < 4096) {
                    journal[journal_len] = byte;
                    journal_len += 1;
                }
            }

            var i: usize = 0;
            while (i < 5) : (i += 1) { seq_buf[i] = seq_buf[i+1]; }
            seq_buf[5] = byte;
            if (std.mem.eql(u8, &seq_buf, exit_key)) break;
        }

        blink_timer += 1;
        if (blink_timer > 35) {
            is_high_cycle = !is_high_cycle;
            blink_timer = 0;
            dirty = true;
        }

        if (dirty) {
            clear(0x00000000);
            
            var bar_x: usize = 0;
            while (bar_x < WIDTH) : (bar_x += 1) {
                var bar_y: usize = 0;
                while (bar_y < 20) : (bar_y += 1) {
                    back_buffer[bar_y * WIDTH + bar_x] = 0x00DC143C;
                }
            }
 
            print(10, 6, "@NSIBLE OS // v0.8 // VOID_LINK: LISTENING (4213)", 0x00FFFFFF);
            
            // [!] FIXED: Explicit type 'u32' for runtime if/else
            const pulse_color: u32 = if (journal_len > 0) 0x00DC143C else 0x00C0C0C0;

            // [!] UPDATED: Rendering logic for TopRight alignment
            // Text Label
            print(pulse_x, pulse_y, ":|", 0x00DC143C); //Optimized into an @nsible link format

            //The Glyph (127=High, 128=Claw)
            const glyph = if (is_high_cycle) @as(u8, 127) else @as(u8, 128);
            drawChar(pulse_x + 32, pulse_y, glyph, pulse_color); // Adjusted offset (+32)

            drawUriBar(journal[0..journal_len], journal_len);
            
            @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);
            dirty = false;
        }
        
        codex.zen(0.000004);
    }
    
    _ = linux.syscall1(.exit, 0);
}
