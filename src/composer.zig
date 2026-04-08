// [@://nsible_os/src/composer.zig/.-={
//   module: "The Composer IDE",
//   version: "0.11.0-apex // Banysang",
//   description: "Native, full-screen IDE operating in a dedicated 50MB BSS matrix.",
//   changes: "Restricted render width by 200px to permanently accommodate the persistent Timeline rail interface.",
//   philotic_inferences: "The matrix must protect the operator's unsealed thoughts from the void."

const std = @import("std");
const font = @import("glyphs.zig");
const codex = @import("codex.zig");
const sys_root = @import("root.zig");

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
    
    comment_pre: [8]u8,
    comment_pre_len: usize,
    comment_suf: [8]u8,
    comment_suf_len: usize,
    
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
            .comment_pre = .{0} ** 8,
            .comment_pre_len = 0,
            .comment_suf = .{0} ** 8,
            .comment_suf_len = 0,
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

    // [OMITTED FOR BREVITY - Standard structural logic intact]
    
    pub fn render(self: *Composer, buffer: []u32, width: usize, height: usize) void {
        const start_x: usize = 56;
        const start_y: usize = 46; 
        const char_w: usize = 8;
        const line_h: usize = 10;
        
        // [!] The absolute workspace limit. Protects the Timeline Rail on the right.
        const effective_width = width - 200;

        drawRect(buffer, width, height, 0, 20, effective_width, height - 20, codex.get("K.S"));
        drawRect(buffer, width, height, 0, 20, effective_width, 20, codex.get("C.S")); 
        
        var title_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&title_buf, "[ THE COMPOSER ] // {s} {s}", .{
            self.filepath[0..self.filepath_len], 
            if (self.dirty) "*" else ""
        }) catch "COMPOSER";
        var head_cx: usize = 10;
        for (header) |c| { 
            drawCharToBuf(buffer, width, height, head_cx, 26, c, codex.get("K.S"));
            head_cx += char_w; 
        }

        var cx: usize = start_x;
        var cy: usize = start_y;
        var line_no: usize = 1;
        var cursor_px: usize = start_x;
        var cursor_py: usize = start_y;
        var cursor_line: usize = 1;

        var i: usize = 0;
        while (i < self.cursor_idx) : (i += 1) {
            const c = self.buffer[i];
            if (c == '\n') {
                cx = start_x;
                cy += line_h; line_no += 1;
            } else if (c == '\t') {
                cx += char_w * 4;
                if (cx >= effective_width - 20) { cx = start_x; cy += line_h; }
            } else {
                cx += char_w;
                if (cx >= effective_width - 20) { cx = start_x; cy += line_h; }
            }
        }
        cursor_px = cx;
        cursor_py = cy;
        cursor_line = line_no;

        if (cursor_py < start_y + (self.scroll_y * line_h)) {
            self.scroll_y = (cursor_py - start_y) / line_h;
        } else if (cursor_py > start_y + (self.scroll_y * line_h) + (height - 80)) {
            self.scroll_y = ((cursor_py - start_y) - (height - 80)) / line_h;
        }
        const pixel_scroll_y = self.scroll_y * line_h;
        const visible_top = start_y + pixel_scroll_y;
        const visible_bottom = visible_top + height;

        cx = start_x;
        cy = start_y;
        line_no = 1;
        var draw_start_idx: usize = 0;
        
        i = 0;
        while (i < self.len) : (i += 1) {
            if (cy + line_h >= visible_top) {
                draw_start_idx = i;
                break;
            }
            const c = self.buffer[i];
            if (c == '\n') {
                cx = start_x;
                cy += line_h; line_no += 1;
            } else if (c == '\t') {
                cx += char_w * 4;
                if (cx >= effective_width - 20) { cx = start_x; cy += line_h; }
            } else {
                cx += char_w;
                if (cx >= effective_width - 20) { cx = start_x; cy += line_h; }
            }
        }

        var keyword_countdown: usize = 0;
        var current_color: u32 = codex.get("S.S");
        var is_start_of_line = (cx == start_x);

        i = draw_start_idx;
        while (i <= self.len) : (i += 1) {
            if (cy > visible_bottom) { break; } 
            
            if (is_start_of_line) {
                var num_buf: [8]u8 = undefined;
                const num_str = std.fmt.bufPrint(&num_buf, "{d: >4}", .{line_no}) catch "   0";
                var nx: usize = 8;
                for (num_str) |nc| { 
                    drawCharToBuf(buffer, width, height, nx, cy - pixel_scroll_y, nc, codex.get("K.H"));
                    nx += char_w; 
                }
                drawCharToBuf(buffer, width, height, nx + 4, cy - pixel_scroll_y, 0xB3, codex.get("K.H"));
            }

            if (i == self.len) { break; }
            const c = self.buffer[i];
            
            current_color = codex.get("S.H"); // Syntax Highlighting Omitted for spatial demonstration.
            is_start_of_line = false;
            if (c == '\n') {
                cx = start_x;
                cy += line_h; line_no += 1; is_start_of_line = true;
            } else if (c == '\t') {
                cx += char_w * 4;
                if (cx >= effective_width - 20) { cx = start_x; cy += line_h; }
            } else {
                drawCharToBuf(buffer, width, height, cx, cy - pixel_scroll_y, c, current_color);
                cx += char_w;
                if (cx >= effective_width - 20) { cx = start_x; cy += line_h; }
            }
        }
        
        if (cursor_py >= visible_top and cursor_py < visible_bottom - 40) {
            const draw_cy = cursor_py - pixel_scroll_y;
            drawCharToBuf(buffer, width, height, cursor_px, draw_cy, 0xDB, codex.get("B.S")); 
        }

        drawRect(buffer, width, height, 0, height - 20, effective_width, 20, codex.get("K.H"));
        var b_cx: usize = 10;
        
        const now = std.time.milliTimestamp();
        const status_color: u32 = if (now - self.last_xx_ms < 3000) codex.get("C.S") else codex.get("S.H");
        for (self.status[0..self.status_len]) |c| {
            drawCharToBuf(buffer, width, height, b_cx, height - 14, c, status_color);
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
                if (screen_x < w and screen_y < h) { buf[screen_y * w + screen_x] = color; }
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
            if (sx < bw and sy < bh) { buf[sy * bw + sx] = color; }
        }
    }
}
// }-.]
