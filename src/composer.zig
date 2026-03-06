// [@://nsible_os/src/composer.zig/.-={
//   module: "The Composer Lobe",
//   version: "0.10.15-nightly // Banysang",
//   description: "Native, full-screen text editor lobe operating in a dedicated 64KB RAM buffer.",
//   changes: "Fixed Issue #7 & #8: Enforced explicit []const u8 casting for path strings and usize typing for render coordinates.",
//   philotic_inferences: "The matrix requires absolute structural clarity. Ambiguity is the enemy of the physical machine."

const std = @import("std");
const font = @import("glyphs.zig");

const COMPOSER_SIZE = 65536;

pub const Composer = struct {
    buffer: [COMPOSER_SIZE]u8,
    len: usize,
    cursor_idx: usize,
    scroll_y: usize,
    filepath: [256]u8,
    filepath_len: usize,
    active: bool,
    status: [64]u8,
    status_len: usize,
    dirty: bool,

    pub fn init() Composer {
        return .{
            .buffer = .{0} ** COMPOSER_SIZE,
            .len = 0,
            .cursor_idx = 0,
            .scroll_y = 0,
            .filepath = .{0} ** 256,
            .filepath_len = 0,
            .active = false,
            .status = .{0} ** 64,
            .status_len = 0,
            .dirty = false,
        };
    }

    pub fn setStatus(self: *Composer, msg: []const u8) void {
        const copy_len = @min(msg.len, 64);
        @memcpy(self.status[0..copy_len], msg[0..copy_len]);
        self.status_len = copy_len;
    }

    pub fn open(self: *Composer, path: []const u8) void {
        self.active = true;
        self.len = 0;
        self.cursor_idx = 0;
        self.scroll_y = 0;
        self.dirty = false;
        
        const p_len = @min(path.len, 256);
        @memcpy(self.filepath[0..p_len], path[0..p_len]);
        self.filepath_len = p_len;

        // [!] ISSUE #7 FIX: Explicitly defined as constant slice
        var clean_path: []const u8 = path;
        if (std.mem.startsWith(u8, path, "@://mchn/")) {
            clean_path = path[9..];
        } else if (std.mem.startsWith(u8, path, "@://")) {
            if (std.mem.indexOfScalar(u8, path[4..], '/')) |idx| {
                clean_path = path[4 + idx + 1..];
            }
        }

        if (clean_path.len == 0) clean_path = "untitled.txt";

        if (std.fs.cwd().openFile(clean_path, .{})) |file| {
            self.len = file.readAll(&self.buffer) catch 0;
            file.close();
            self.setStatus("FILE LOADED");
        } else |_| {
            self.setStatus("NEW BUFFER");
        }
    }

    pub fn save(self: *Composer) void {
        // [!] ISSUE #7 FIX: Explicitly defined as constant slice
        var clean_path: []const u8 = self.filepath[0..self.filepath_len];
        if (std.mem.startsWith(u8, clean_path, "@://mchn/")) {
            clean_path = clean_path[9..];
        } else if (std.mem.startsWith(u8, clean_path, "@://")) {
            if (std.mem.indexOfScalar(u8, clean_path[4..], '/')) |idx| {
                clean_path = clean_path[4 + idx + 1..];
            }
        }

        if (clean_path.len == 0) clean_path = "untitled.txt";

        if (std.fs.cwd().createFile(clean_path, .{})) |file| {
            file.writeAll(self.buffer[0..self.len]) catch {
                self.setStatus("SAVE FAILED");
                return;
            };
            file.close();
            self.dirty = false;
            self.setStatus("FILE SAVED");
        } else |_| {
            self.setStatus("SAVE FAILED: IO ERR");
        }
    }

    pub fn close(self: *Composer) void {
        self.active = false;
    }

    pub fn insert(self: *Composer, c: u8) void {
        if (self.len >= COMPOSER_SIZE) return;
        if (c < 32 and c != '\n' and c != '\t') return; 
        
        var i: usize = self.len;
        while (i > self.cursor_idx) : (i -= 1) {
            self.buffer[i] = self.buffer[i - 1];
        }
        self.buffer[self.cursor_idx] = c;
        self.len += 1;
        self.cursor_idx += 1;
        self.dirty = true;
    }

    pub fn backspace(self: *Composer) void {
        if (self.cursor_idx == 0) return;
        var i: usize = self.cursor_idx;
        while (i < self.len) : (i += 1) {
            self.buffer[i - 1] = self.buffer[i];
        }
        self.len -= 1;
        self.cursor_idx -= 1;
        self.dirty = true;
    }
    
    pub fn deleteChar(self: *Composer) void {
        if (self.cursor_idx >= self.len) return;
        var i: usize = self.cursor_idx + 1;
        while (i < self.len) : (i += 1) {
            self.buffer[i - 1] = self.buffer[i];
        }
        self.len -= 1;
        self.dirty = true;
    }

    pub fn moveCursor(self: *Composer, dx: isize, dy: isize) void {
        if (dx < 0 and self.cursor_idx > 0) self.cursor_idx -= 1;
        if (dx > 0 and self.cursor_idx < self.len) self.cursor_idx += 1;
        
        if (dy < 0) {
            var jumps: usize = 0;
            var found_nl = false;
            var i = self.cursor_idx;
            while (i > 0) : (i -= 1) {
                if (self.buffer[i-1] == '\n') {
                    if (found_nl) {
                        self.cursor_idx = i;
                        return;
                    }
                    found_nl = true;
                }
                jumps += 1;
                if (jumps > 120) { self.cursor_idx = i; return; } 
            }
            self.cursor_idx = 0;
        }
        if (dy > 0) {
            var i = self.cursor_idx;
            var jumps: usize = 0;
            while (i < self.len) : (i += 1) {
                if (self.buffer[i] == '\n') {
                    self.cursor_idx = i + 1;
                    if (self.cursor_idx > self.len) self.cursor_idx = self.len;
                    return;
                }
                jumps += 1;
                if (jumps > 120) {
                    self.cursor_idx = @min(self.cursor_idx + 120, self.len);
                    return;
                }
            }
            self.cursor_idx = self.len;
        }
    }

    pub fn render(self: *Composer, buffer: []u32, width: usize, height: usize) void {
        // [!] ISSUE #8 FIX: Explicitly typed to usize to prevent comptime_int cascade
        const start_x: usize = 56; 
        const start_y: usize = 40;
        const char_w: usize = 8;
        const line_h: usize = 10;
        
        for (buffer) |*p| p.* = 0x00000000;
        
        drawRect(buffer, width, height, 0, 0, width, 20, 0x00FFBF00); 
        var title_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&title_buf, "[ THE COMPOSER ] // {s} {s}", .{
            self.filepath[0..self.filepath_len], 
            if (self.dirty) "*" else ""
        }) catch "COMPOSER";
        
        var cx: usize = 10;
        for (header) |c| { drawCharToBuf(buffer, width, height, cx, 6, c, 0x00000000); cx += char_w; }
        
        var pre_cx: usize = start_x;
        var pre_cy: usize = start_y;
        var pre_i: usize = 0;
        while (pre_i < self.cursor_idx) : (pre_i += 1) {
            if (self.buffer[pre_i] == '\n') { pre_cx = start_x; pre_cy += line_h; continue; }
            pre_cx += char_w;
            if (pre_cx >= width - 20) { pre_cx = start_x; pre_cy += line_h; }
        }
        
        if (pre_cy < start_y + (self.scroll_y * line_h)) {
            self.scroll_y = (pre_cy - start_y) / line_h;
        } else if (pre_cy > start_y + (self.scroll_y * line_h) + (height - 80)) {
            self.scroll_y = ((pre_cy - start_y) - (height - 80)) / line_h;
        }
        
        const pixel_scroll_y = self.scroll_y * line_h;

        cx = start_x;
        var cy: usize = start_y;
        var cursor_px: usize = start_x;
        var cursor_py: usize = start_y;
        
        var line_no: usize = 1;
        var cursor_line: usize = 1;
        var is_start_of_line = true;

        var i: usize = 0;
        while (i <= self.len) : (i += 1) {
            if (i == self.cursor_idx) {
                cursor_px = cx;
                cursor_py = cy;
                cursor_line = line_no;
            }
            
            if (cy >= start_y + pixel_scroll_y and cy < start_y + pixel_scroll_y + (height - 60)) {
                if (is_start_of_line) {
                    var num_buf: [8]u8 = undefined;
                    const num_str = std.fmt.bufPrint(&num_buf, "{d: >4}", .{line_no}) catch "   0";
                    var nx: usize = 8;
                    for (num_str) |nc| {
                        drawCharToBuf(buffer, width, height, nx, cy - pixel_scroll_y, nc, 0x00555555);
                        nx += char_w;
                    }
                    drawCharToBuf(buffer, width, height, nx + 4, cy - pixel_scroll_y, 0xB3, 0x00444444); 
                    is_start_of_line = false;
                }
            }

            if (i == self.len) break;
            
            const c = self.buffer[i];
            if (c == '\n') {
                cx = start_x;
                cy += line_h;
                line_no += 1;
                is_start_of_line = true;
            } else if (c == '\t') {
                cx += char_w * 4;
                if (cx >= width - 20) { cx = start_x; cy += line_h; }
            } else {
                if (cy >= start_y + pixel_scroll_y and cy < start_y + pixel_scroll_y + (height - 60)) {
                    drawCharToBuf(buffer, width, height, cx, cy - pixel_scroll_y, c, 0x00AAAAAA);
                }
                cx += char_w;
                if (cx >= width - 20) { cx = start_x; cy += line_h; }
            }
        }
        
        if (cursor_py >= start_y + pixel_scroll_y and cursor_py < start_y + pixel_scroll_y + (height - 60)) {
            const draw_cy = cursor_py - pixel_scroll_y;
            drawCharToBuf(buffer, width, height, cursor_px, draw_cy, 0xDB, 0x00FFBF00); 
            if (self.cursor_idx < self.len and self.buffer[self.cursor_idx] != '\n' and self.buffer[self.cursor_idx] != '\t') {
                 drawCharToBuf(buffer, width, height, cursor_px, draw_cy, self.buffer[self.cursor_idx], 0x00000000);
            }
        }
        
        drawRect(buffer, width, height, 0, height - 20, width, 20, 0x00222222);
        var b_cx: usize = 10;
        for (self.status[0..self.status_len]) |c| {
            drawCharToBuf(buffer, width, height, b_cx, height - 14, c, 0x00FFFFFF);
            b_cx += 8;
        }
        
        b_cx += 24;
        var byte_buf: [64]u8 = undefined;
        const byte_str = std.fmt.bufPrint(&byte_buf, "L:{d} | B:{d}/{d}", .{cursor_line, self.cursor_idx, self.len}) catch "";
        for (byte_str) |c| {
            drawCharToBuf(buffer, width, height, b_cx, height - 14, c, 0x00FFBF00);
            b_cx += 8;
        }
        
        const help_str = "[ESC] Discard   .!SV-. Save to Disk";
        b_cx = width - (help_str.len * 8) - 10;
        for (help_str) |c| {
            drawCharToBuf(buffer, width, height, b_cx, height - 14, c, 0x00555555);
            b_cx += 8;
        }
    }
};

fn drawCharToBuf(buf: []u32, w: usize, h: usize, px: usize, py: usize, char: u8, color: u32) void {
    const bitmap = font.getBitmap(char);
    var y: usize = 0;
    while (y < 8) : (y += 1) {
        var x: usize = 0;
        while (x < 8) : (x += 1) {
            if ((bitmap[y] & (@as(u8, 1) << @intCast(7 - x))) != 0) {
                const screen_x = px + x;
                const screen_y = py + y;
                if (screen_x < w and screen_y < h) buf[screen_y * w + screen_x] = color;
            }
        }
    }
}

fn drawRect(buf: []u32, bw: usize, bh: usize, x: usize, y: usize, w: usize, h: usize, color: u32) void {
    var dy: usize = 0;
    while (dy < h) : (dy += 1) {
        var dx: usize = 0;
        while (dx < w) : (dx += 1) {
            const sx = x + dx;
            const sy = y + dy;
            if (sx < bw and sy < bh) buf[sy * bw + sx] = color;
        }
    }
}
// }-.]
