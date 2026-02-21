const std = @import("std");
const linux = std.os.linux;
const font = @import("glyphs.zig"); // LINKED: Your glyphs library
 
// --- HARDWARE CONFIGURATION ---
const WIDTH: usize = 1024;
const HEIGHT: usize = 600;
 
// .-*-. HARD CONSTRAINT: Panic Handler .-*-.
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    while (true) {}
}
 
// Global pointer to framebuffer (so helper functions can access it)
var fb_pixels: []u32 = undefined;
 
// --- GRAPHICS ENGINE ---
 
// Draw a single character at (px, py)
fn drawChar(px: usize, py: usize, char: u8, color: u32) void {
    const bitmap = font.getBitmap(char);
    
    // Iterate over the 8x8 grid of the font char
    var y: usize = 0;
    while (y < 8) : (y += 1) {
        var x: usize = 0;
        while (x < 8) : (x += 1) {
            // Check if the bit is set in the font map
            // We shift 1 to the left (7-x) to check bits from MSB to LSB
            if ((bitmap[y] & (@as(u8, 1) << @intCast(7 - x))) != 0) {
                // Calculate screen position
                const screen_x = px + x;
                const screen_y = py + y;
                
                // Bounds check
                if (screen_x < WIDTH and screen_y < HEIGHT) {
                    const index = screen_y * WIDTH + screen_x;
                    fb_pixels[index] = color;
                }
            }
        }
    }
}
 
// Print a string starting at (x, y) with Line Wrapping
fn print(start_x: usize, start_y: usize, text: []const u8, color: u32) void {
    var cursor_x = start_x;
    var cursor_y = start_y; // Mutable for wrapping logic
 
    for (text) |char| {
        drawChar(cursor_x, cursor_y, char, color);
        cursor_x += 8; // Move cursor right by 8 pixels
 
        // LOGIC FIX: Check for Screen Edge
        // If we hit the edge, wrap to next line.
        if (cursor_x + 8 >= WIDTH) {
            cursor_x = start_x; // Carriage Return
            cursor_y += 10;     // Line Feed (8px char + 2px padding)
        }
    }
}
 
// Clear screen with a color
fn clear(color: u32) void {
    for (fb_pixels) |*pixel| {
        pixel.* = color;
    }
}
 
pub fn main() !void {
    // --- STEP 1: MOUNT FILESYSTEMS ---
    _ = linux.syscall5(.mount, @intFromPtr("proc"), @intFromPtr("/proc"), @intFromPtr("proc"), 0, 0);
    _ = linux.syscall5(.mount, @intFromPtr("sysfs"), @intFromPtr("/sys"), @intFromPtr("sysfs"), 0, 0);
    _ = linux.syscall5(.mount, @intFromPtr("devtmpfs"), @intFromPtr("/dev"), @intFromPtr("devtmpfs"), 0, 0);
 
    // --- STEP 2: OPEN FRAMEBUFFER ---
    const fd_res = linux.syscall3(.open, @intFromPtr("/dev/fb0"), 2, 0);
    const fb_fd: i32 = @bitCast(@as(u32, @truncate(fd_res)));
 
    if (fb_fd < 0) { while (true) { asm volatile ("pause"); } }
 
    // --- STEP 3: MEMORY MAPPING ---
    const map_len = WIDTH * HEIGHT * 4;
    const map_res = linux.syscall6(.mmap2, 0, map_len, 3, 1, @as(usize, @bitCast(fb_fd)), 0);
    
    // Initialize global framebuffer pointer
    const fb_ptr = @as([*]u32, @ptrFromInt(map_res));
    fb_pixels = fb_ptr[0..(WIDTH * HEIGHT)];
 
    // --- STEP 4: RENDER UI ---
    
    // Clear screen to Deep Black
    clear(0x00000000);
 
    // Draw Status Bar (Crimson Background)
    var bar_x: usize = 0;
    while (bar_x < WIDTH) : (bar_x += 1) {
        var bar_y: usize = 0;
        while (bar_y < 20) : (bar_y += 1) {
            fb_pixels[bar_y * WIDTH + bar_x] = 0x00DC143C;
        }
    }
 
    // Print Header
    // 0xFFFFFFFF = White
    print(10, 6, "@NSIBLE OS // v0.2 // VOID_LINK: ACTIVE", 0x00FFFFFF);
 
    // Print Main Body Text
    print(10, 40, "SYSTEM INITIALIZED.", 0x00DC143C); // Crimson Text
    print(10, 52, "KERNEL: ZIG NATIVE", 0x00AAAAAA);
    print(10, 64, "ARCH: x86 (ASPIRE ONE)", 0x00AAAAAA);
    print(10, 88, "WAITING FOR INPUT...", 0x00FFFFFF);
 
    // --- STEP 5: THE ETERNAL LOOP ---
    while (true) {
        asm volatile ("pause");
    }
}
