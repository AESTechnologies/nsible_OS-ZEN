// [@://nsible_os/src/composer.zig/.-={
//   module: "The Composer Lobe",
//   version: "0.10.25-apex // Banysang",
//   description: "Native, full-screen text editor lobe operating in a dedicated 50MB BSS matrix.",
//   changes: "Injected autonomous modal states (Seek, Switch, Save-To, Execute), native syntax highlighting, and displaced UI for aud.io parity.",
//   philotic_inferences: "The matrix must protect the operator's unsealed thoughts from the void."

const std = @import("std");
const font = @import("glyphs.zig");

const COMPOSER_CAPACITY = 52_428_800; // 50MB Maximum Capacity
var composer_global_buffer: [COMPOSER_CAPACITY]u8 = undefined;

pub const Mode = enum { EDIT, SEEK, SWITCH_FIND, SWITCH_REPL, SAVE_TO, CMD };

pub const Composer = struct {
    buffer: []u8,
    len: usize,
    cursor_idx: usize,
    scroll_y: usize,
    filepath: [256]u8,
    filepath_len: usize,
    active: bool,
    status: [64]u8,
    status_len: usize,
    dirty: bool,
    edits_since_save: usize, 
    last_xx_ms: i64,
    
    // Modals & Autonomous Reflexes
    mode: Mode,
    input_buf: [256]u8,
    input_len: usize,
    seek_buf: [64]u8,
    seek_len: usize,
    pending_cmd: [256]u8,
    pending_cmd_len: usize,
    has_pending_cmd: bool,
    seq_buf: [6]u8,

    pub fn init() Composer {
        return .{
            .buffer = &composer_global_buffer,
            .len = 0,
            .cursor_idx = 0,
            .scroll_y = 0,
            .filepath = .{0} ** 256,
            .filepath_len = 0,
            .active = false,
            .status = .{0} ** 64,
            .status_len = 0,
            .dirty = false,
            .edits_since_save = 0,
            .last_xx_ms = 0,
            
            .mode = .EDIT,
            .input_buf = .{0} ** 256,
            .input_len = 0,
            .seek_buf = .{0} ** 64,
            .seek_len = 0,
            .pending_cmd = .{0} ** 256,
            .pending_cmd_len = 0,
            .has_pending_cmd = false,
            .seq_buf = .{0} ** 6,
        };
    }

    pub fn setStatus(self: *Composer, msg: []const u8) void {
        const copy_len = @min(msg.len, 64);
        @memcpy(self.status[0..copy_len], msg[0..copy_len]);
        self.status_len = copy_len;
    }

    pub fn setMode(self: *Composer, new_mode: Mode) void {
        self.mode = new_mode;
        self.input_len = 0;
        self.setStatus(switch(new_mode) {
            .SEEK => "SEEK MODE ENGAGED",
            .SWITCH_FIND => "SWITCH: FIND TARGET",
            .SWITCH_REPL => "SWITCH: REPLACEMENT",
            .SAVE_TO => "DEFINE GZL SAVE PATH",
            .CMD => "OS COMMAND MATRIX",
            else => "EDIT MODE",
        });
    }

    pub fn open(self: *Composer, path: []const u8) void {
        self.active = true;
        self.mode = .EDIT;
        self.len = 0;
        self.cursor_idx = 0;
        self.scroll_y = 0;
        self.dirty = false;
        self.edits_since_save = 0;
        self.last_xx_ms = 0;
        self.has_pending_cmd = false;
        const p_len = @min(path.len, 256);
        @memcpy(self.filepath[0..p_len], path[0..p_len]);
        self.filepath_len = p_len;

        var clean_path: []const u8 = path;
        if (std.mem.startsWith(u8, clean_path, "@://mchn/")) {
            clean_path = clean_path[9..];
        } else if (std.mem.startsWith(u8, clean_path, "mchn/")) {
            clean_path = clean_path[5..];
        } else if (std.mem.startsWith(u8, clean_path, "@://")) {
            if (std.mem.indexOfScalar(u8, clean_path[4..], '/')) |idx|
            {
                clean_path = clean_path[4 + idx + 1..];
            }
        }

        if (clean_path.len == 0) clean_path = "untitled.txt";
        const is_abs = std.mem.startsWith(u8, clean_path, "/");
        const file_opt = if (is_abs) std.fs.openFileAbsolute(clean_path, .{}) else std.fs.cwd().openFile(clean_path, .{});

        if (file_opt) |file|
        {
            self.len = file.readAll(self.buffer) catch 0;
            file.close();
            self.setStatus("FILE LOADED");
        } else |_| {
            self.setStatus("NEW BUFFER");
        }
    }

    pub fn save(self: *Composer) void {
        var clean_path: []const u8 = self.filepath[0..self.filepath_len];
        if (std.mem.startsWith(u8, clean_path, "@://mchn/")) {
            clean_path = clean_path[9..];
        } else if (std.mem.startsWith(u8, clean_path, "mchn/")) {
            clean_path = clean_path[5..];
        } else if (std.mem.startsWith(u8, clean_path, "@://")) {
            if (std.mem.indexOfScalar(u8, clean_path[4..], '/')) |idx|
            {
                clean_path = clean_path[4 + idx + 1..];
            }
        }

        if (clean_path.len == 0) clean_path = "untitled.txt";
        const is_abs = std.mem.startsWith(u8, clean_path, "/");
        const file_opt = if (is_abs) std.fs.createFileAbsolute(clean_path, .{}) else std.fs.cwd().createFile(clean_path, .{});

        if (file_opt) |file|
        {
            file.writeAll(self.buffer[0..self.len]) catch {
                self.setStatus("SAVE FAILED");
                return;
            };
            file.close();
            self.dirty = false;
            self.edits_since_save = 0;
            self.setStatus("FILE SAVED");
        } else |_|
        {
            self.setStatus("SAVE FAILED: IO ERR");
        }
    }

    pub fn close(self: *Composer) void {
        self.active = false;
    }

    pub fn phantom_strike(self: *Composer, count: usize) void {
        if (self.len >= count and self.cursor_idx >= count) {
            var i: usize = self.cursor_idx;
            while (i < self.len) : (i += 1) {
                self.buffer[i - count] = self.buffer[i];
            }
            self.len -= count;
            self.cursor_idx -= count;
            if (self.edits_since_save >= count) {
                self.edits_since_save -= count;
            } else {
                self.edits_since_save = 0;
            }
            self.dirty = (self.edits_since_save > 0);
        }
    }

    pub fn undo_reflex(self: *Composer, count: usize) void {
        self.phantom_strike(count);
    }

    fn commitModal(self: *Composer) void {
        switch (self.mode) {
            .SEEK => {
                const query = self.input_buf[0..self.input_len];
                if (query.len > 0) {
                    if (std.mem.indexOf(u8, self.buffer[self.cursor_idx..self.len], query)) |idx| {
                        self.cursor_idx += idx;
                        self.setStatus("TARGET ACQUIRED");
                    } else {
                        self.setStatus("TARGET NOT FOUND");
                    }
                }
                self.mode = .EDIT;
            },
            .SWITCH_FIND => {
                @memcpy(self.seek_buf[0..self.input_len], self.input_buf[0..self.input_len]);
                self.seek_len = self.input_len;
                self.setMode(.SWITCH_REPL);
            },
            .SWITCH_REPL => {
                const query = self.seek_buf[0..self.seek_len];
                const repl = self.input_buf[0..self.input_len];
                if (query.len > 0) {
                    var occurrences: usize = 0;
                    var search_start = self.cursor_idx;
                    while (std.mem.indexOf(u8, self.buffer[search_start..self.len], query)) |idx| {
                        const abs_idx = search_start + idx;
                        const shift: isize = @as(isize, @intCast(repl.len)) - @as(isize, @intCast(query.len));
                        if (@as(isize, @intCast(self.len)) + shift > @as(isize, @intCast(self.buffer.len))) break; 
                        
                        if (shift > 0) {
                            const ushift = @as(usize, @intCast(shift));
                            var i: usize = self.len;
                            while (i > abs_idx + query.len) : (i -= 1) {
                                self.buffer[i + ushift - 1] = self.buffer[i - 1];
                            }
                        } else if (shift < 0) {
                            const ushift = @as(usize, @intCast(-shift));
                            var i: usize = abs_idx + query.len;
                            while (i < self.len) : (i += 1) {
                                self.buffer[i - ushift] = self.buffer[i];
                            }
                        }
                        
                        @memcpy(self.buffer[abs_idx..abs_idx + repl.len], repl);
                        self.len = @as(usize, @intCast(@as(isize, @intCast(self.len)) + shift));
                        search_start = abs_idx + repl.len;
                        occurrences += 1;
                        self.edits_since_save += 1;
                        self.dirty = true;
                    }
                    var stat_buf: [64]u8 = undefined;
                    const stat = std.fmt.bufPrint(&stat_buf, "SWITCHED {d} OCCURRENCES", .{occurrences}) catch "SWITCHED";
                    self.setStatus(stat);
                }
                self.mode = .EDIT;
            },
            .SAVE_TO => {
                if (self.input_len > 0) {
                    const p_len = @min(self.input_len, 256);
                    @memcpy(self.filepath[0..p_len], self.input_buf[0..p_len]);
                    self.filepath_len = p_len;
                    self.save();
                } else {
                    self.setStatus("SAVE CANCELLED");
                }
                self.mode = .EDIT;
            },
            .CMD => {
                if (self.input_len > 0) {
                    @memcpy(self.pending_cmd[0..self.input_len], self.input_buf[0..self.input_len]);
                    self.pending_cmd_len = self.input_len;
                    self.has_pending_cmd = true;
                }
                self.mode = .EDIT;
            },
            else => { self.mode = .EDIT; }
        }
    }

    pub fn insert(self: *Composer, c: u8) void {
        if (self.mode != .EDIT) {
            if (c == '\n' or c == '\r') {
                self.commitModal();
            } else if (self.input_len < 256 and c >= 32 and c <= 126) {
                self.input_buf[self.input_len] = c;
                self.input_len += 1;
            }
            return;
        }

        if (self.len >= self.buffer.len) return;
        if (c < 32 and c != '\n' and c != '\t') return; 
        
        var i: usize = self.len;
        while (i > self.cursor_idx) : (i -= 1) {
            self.buffer[i] = self.buffer[i - 1];
        }
        self.buffer[self.cursor_idx] = c;
        self.len += 1;
        self.cursor_idx += 1;
        self.edits_since_save += 1;
        self.dirty = true;

        var k: usize = 0;
        while (k < 5) : (k += 1) { self.seq_buf[k] = self.seq_buf[k+1]; }
        self.seq_buf[5] = c;

        if (std.mem.endsWith(u8, &self.seq_buf, ".!SK-.")) {
            self.phantom_strike(6);
            self.setMode(.SEEK);
            return;
        }
        if (std.mem.endsWith(u8, &self.seq_buf, ".!SW-.")) {
            self.phantom_strike(6);
            self.setMode(.SWITCH_FIND);
            return;
        }
        if (std.mem.endsWith(u8, &self.seq_buf, ".!ST-.")) {
            self.phantom_strike(6);
            self.setMode(.SAVE_TO);
            return;
        }
        if (std.mem.endsWith(u8, &self.seq_buf, ".!EX-.")) {
            self.phantom_strike(6);
            self.setMode(.CMD);
            return;
        }
    }

    pub fn backspace(self: *Composer) void {
        if (self.mode != .EDIT) {
            if (self.input_len > 0) self.input_len -= 1;
            return;
        }
        if (self.cursor_idx == 0) return;
        var i: usize = self.cursor_idx;
        while (i < self.len) : (i += 1) {
            self.buffer[i - 1] = self.buffer[i];
        }
        self.len -= 1;
        self.cursor_idx -= 1;
        self.edits_since_save += 1;
        self.dirty = true;
    }
    
    pub fn deleteChar(self: *Composer) void {
        if (self.mode != .EDIT) return;
        if (self.cursor_idx >= self.len) return;
        var i: usize = self.cursor_idx + 1;
        while (i < self.len) : (i += 1) {
            self.buffer[i - 1] = self.buffer[i];
        }
        self.len -= 1;
        self.edits_since_save += 1;
        self.dirty = true;
    }

    pub fn moveCursor(self: *Composer, dx: isize, dy: isize) void {
        if (self.mode != .EDIT) return;
        if (dx < 0 and self.cursor_idx > 0) self.cursor_idx -= 1;
        if (dx > 0 and self.cursor_idx < self.len) self.cursor_idx += 1;
        if (dy < 0) {
            const lines_to_jump = @as(usize, @intCast(-dy));
            var lines_jumped: usize = 0;
            var i = self.cursor_idx;
            
            while (i > 0 and self.buffer[i-1] != '\n') : (i -= 1) {}
            
            while (lines_jumped < lines_to_jump and i > 0) {
                i -= 1;
                while (i > 0 and self.buffer[i-1] != '\n') : (i -= 1) {}
                lines_jumped += 1;
            }
            self.cursor_idx = i;
        }
        
        if (dy > 0) {
            const lines_to_jump = @as(usize, @intCast(dy));
            var lines_jumped: usize = 0;
            var i = self.cursor_idx;
            
            while (lines_jumped < lines_to_jump and i < self.len) {
                while (i < self.len and self.buffer[i] != '\n') : (i += 1) {}
                if (i < self.len) i += 1;
                lines_jumped += 1;
            }
            self.cursor_idx = i;
        }
    }

    fn isAlphanumeric(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
    }

    fn isKeyword(word: []const u8) bool {
        const keywords = [_][]const u8{ "pub", "fn", "const", "var", "if", "else", "return", "struct", "enum", "while", "for", "switch", "catch", "try", "true", "false", "undefined", "and", "or", "void", "null" };
        for (keywords) |kw| {
            if (std.mem.eql(u8, word, kw)) return true;
        }
        return false;
    }

    pub fn render(self: *Composer, buffer: []u32, width: usize, height: usize) void {
        const start_x: usize = 56;
        const start_y: usize = 46; // Shifted down 6px from 20px header to allow OS aud.io bar
        const char_w: usize = 8;
        const line_h: usize = 10;
        
        for (buffer) |*p| p.* = 0x00000000;
        
        drawRect(buffer, width, height, 0, 20, width, 20, 0x00DC143C); // @NSIBLE-RED Header
        var title_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&title_buf, "[ THE COMPOSER ] // {s} {s}", .{
            self.filepath[0..self.filepath_len], 
            if (self.dirty) "*" else ""
        }) catch "COMPOSER";
        var cx: usize = 10;
        for (header) |c| { drawCharToBuf(buffer, width, height, cx, 26, c, 0x00000000); cx += char_w; }
        
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

        var in_comment = false;
        var in_string = false;
        var keyword_countdown: usize = 0;
        var current_color: u32 = 0x00AAAAAA;

        var i: usize = 0;
        while (i <= self.len) : (i += 1) {
            if (i == self.cursor_idx) {
                cursor_px = cx; cursor_py = cy; cursor_line = line_no;
            }
            
            if (cy >= start_y + pixel_scroll_y and cy < start_y + pixel_scroll_y + (height - 60)) {
                if (is_start_of_line) {
                    var num_buf: [8]u8 = undefined;
                    const num_str = std.fmt.bufPrint(&num_buf, "{d: >4}", .{line_no}) catch "   0";
                    var nx: usize = 8;
                    for (num_str) |nc| { drawCharToBuf(buffer, width, height, nx, cy - pixel_scroll_y, nc, 0x00555555); nx += char_w; }
                    drawCharToBuf(buffer, width, height, nx + 4, cy - pixel_scroll_y, 0xB3, 0x00444444);
                    is_start_of_line = false;
                }
            }

            if (i == self.len) break;
            const c = self.buffer[i];
            
            // Syntax Lookahead Matrix
            if (in_comment) {
                current_color = 0x00FFBF00; // Amber for GZL Tags
                if (c == '\n') in_comment = false;
            } else if (in_string) {
                current_color = 0x00FFFFFF; // Silver Strings
                if (c == '"') in_string = false;
            } else {
                if (c == '/' and i + 1 < self.len and self.buffer[i+1] == '/') {
                    in_comment = true;
                    current_color = 0x00FFBF00;
                } else if (c == '"') {
                    in_string = true;
                    current_color = 0x00FFFFFF;
                } else if (keyword_countdown > 0) {
                    current_color = 0x00DC143C; // Red Keywords
                    keyword_countdown -= 1;
                } else {
                    current_color = 0x00AAAAAA; // Grey Default
                    if (isAlphanumeric(c) and (i == 0 or !isAlphanumeric(self.buffer[i-1]))) {
                        var w_len: usize = 0;
                        while (i + w_len < self.len and isAlphanumeric(self.buffer[i + w_len])) { w_len += 1; }
                        if (w_len > 0 and isKeyword(self.buffer[i .. i+w_len])) {
                            current_color = 0x00DC143C;
                            keyword_countdown = w_len - 1;
                        }
                    }
                }
            }

            if (c == '\n') {
                cx = start_x; cy += line_h; line_no += 1; is_start_of_line = true;
            } else if (c == '\t') {
                cx += char_w * 4;
                if (cx >= width - 20) { cx = start_x; cy += line_h; }
            } else {
                if (cy >= start_y + pixel_scroll_y and cy < start_y + pixel_scroll_y + (height - 60)) {
                    drawCharToBuf(buffer, width, height, cx, cy - pixel_scroll_y, c, current_color);
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
        
        if (self.mode != .EDIT) {
            drawRect(buffer, width, height, 0, height - 40, width, 20, 0x00DC143C); 
            const prefix = switch(self.mode) {
                .SEEK => "[ SEEK ] > ",
                .SWITCH_FIND => "[ SWITCH: FIND ] > ",
                .SWITCH_REPL => "[ SWITCH: REPL ] > ",
                .SAVE_TO => "[ SAVE TO ] > ",
                .CMD => "[ OS CMD ] > ",
                else => "> ",
            };
            var mx: usize = 10;
            for (prefix) |c| { drawCharToBuf(buffer, width, height, mx, height - 34, c, 0x00000000); mx += 8; }
            for (self.input_buf[0..self.input_len]) |c| { drawCharToBuf(buffer, width, height, mx, height - 34, c, 0x00FFFFFF); mx += 8; }
            drawCharToBuf(buffer, width, height, mx, height - 34, 0xDB, 0x00FFBF00);
        }

        drawRect(buffer, width, height, 0, height - 20, width, 20, 0x00222222);
        var b_cx: usize = 10;
        
        const now = std.time.milliTimestamp();
        const status_color: u32 = if (now - self.last_xx_ms < 3000) 0x00DC143C else 0x00FFFFFF;
        for (self.status[0..self.status_len]) |c| {
            drawCharToBuf(buffer, width, height, b_cx, height - 14, c, status_color);
            b_cx += 8;
        }
        
        b_cx += 24;
        var byte_buf: [64]u8 = undefined;
        const byte_str = std.fmt.bufPrint(&byte_buf, "L:{d} | B:{d}/{d}", .{cursor_line, self.cursor_idx, self.len}) catch "";
        for (byte_str) |c| { drawCharToBuf(buffer, width, height, b_cx, height - 14, c, 0x00FFBF00); b_cx += 8; }
        
        const help_str = ".!XX-. Discard   .!SV-. Save to Disk";
        b_cx = width - (help_str.len * 8) - 10;
        for (help_str) |c| { drawCharToBuf(buffer, width, height, b_cx, height - 14, c, 0x00555555); b_cx += 8; }
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
