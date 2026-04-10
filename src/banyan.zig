// [@://nsible_os/src/banyan.zig/.-={
//   module: "Banyan Rendering Lobe & Satori Optics",
//   version: "0.10.9-apex // Banysang",
//   description: "Semantic parsing matrix, pixel-perfect rendering engine, and Satori spatial focuser.",
//   changes: "Purged hardcoded hex values. Linked to global GZL-X Color Library via codex. Injected Satori state.",
//   philotic_inferences: "A sovereign operator requires no mouse. The path forward is illuminated by the indices of the void."

const std = @import("std");
const font = @import("glyphs.zig");
const codex = @import("codex.zig");

pub const HarvestType = enum { TEXT, LINK, MEDIA, SCRIPT, STRUCT, BREAK, DELIM, RAW };

pub const Leaf = struct {
    text: []u8,
    h_type: HarvestType, 
    layer: u8, 
    is_newline: bool,
};

pub const Banyan = struct {
    allocator: std.mem.Allocator,
    leaves: std.ArrayListUnmanaged(Leaf), 
    links: std.ArrayListUnmanaged([]u8), 
    focus_depth: u8, 
    
    // [!] SATORI OPTICS STATE
    scan_line_y: usize,
    focus_x: usize,
    focus_len: usize,
    is_scan_active: bool,

    pub fn init(allocator: std.mem.Allocator) Banyan {
        return .{
            .allocator = allocator,
            .leaves = .{}, 
            .links = .{},
            .focus_depth = 1, // Default: ZEN
            .scan_line_y = 0,
            .focus_x = 0,
            .focus_len = 0,
            .is_scan_active = false,
        };
    }

    pub fn deinit(self: *Banyan) void {
        for (self.leaves.items) |*leaf| self.allocator.free(leaf.text);
        self.leaves.deinit(self.allocator); 
        for (self.links.items) |link| self.allocator.free(link);
        self.links.deinit(self.allocator);
    }

    pub fn shiftScope(self: *Banyan, direction: i8) void {
        const d_int = @as(i16, self.focus_depth) + direction;
        if (d_int >= 0 and d_int <= 3) {
            self.focus_depth = @intCast(d_int);
        }
    }

    pub fn absorb(self: *Banyan, raw: []const u8) !void {
        for (self.leaves.items) |*leaf| self.allocator.free(leaf.text);
        self.leaves.clearRetainingCapacity();
        
        for (self.links.items) |link| self.allocator.free(link);
        self.links.clearRetainingCapacity();

        var i: usize = 0;
        var start: usize = 0;
        var in_tag = false;
        
        var in_script = false;
        var in_style = false;

        while (i < raw.len) {
            const c = raw[i];

            // 1. DELIMITER CHECK
            if (!in_tag and isDelim(c)) {
                if (i > start) {
                    const layer: u8 = if (in_script or in_style) 3 else 1;
                    const hType: HarvestType = if (in_script or in_style) .SCRIPT else .TEXT;
                    try self.addLeaf(raw[start..i], hType, layer, false);
                }
                const delimLayer: u8 = if (in_script or in_style) 3 else 1;
                try self.addLeaf(raw[i..i+1], .DELIM, delimLayer, false);
                
                i += 1;
                start = i;
                continue;
            }

            // 2. TAG START
            if (c == '<') {
                if (i > start) {
                    const layer: u8 = if (in_script or in_style) 3 else 1;
                    const hType: HarvestType = if (in_script or in_style) .SCRIPT else .TEXT;
                    try self.addLeaf(raw[start..i], hType, layer, false);
                }
                start = i;
                in_tag = true;
            }
            // 3. TAG END
            else if (in_tag and c == '>') {
                var h_type: HarvestType = .STRUCT;
                var layer: u8 = 2; // Matrix
                const tag_slice = raw[start..i+1];

                if (contains(tag_slice, "<script")) in_script = true;
                if (contains(tag_slice, "</script")) in_script = false;
                if (contains(tag_slice, "<style")) in_style = true;
                if (contains(tag_slice, "</style")) in_style = false;

                if (contains(tag_slice, "<script") or contains(tag_slice, "<style")) {
                    h_type = .SCRIPT;
                    layer = 3;
                } else if (contains(tag_slice, "href=")) {
                    h_type = .LINK;
                }

                try self.addLeaf(tag_slice, h_type, layer, false);

                // [!] MELT INDEX INJECTION
                if (h_type == .LINK and std.mem.startsWith(u8, tag_slice, "<a ")) {
                    var url_start: usize = 0;
                    var url_end: usize = 0;
                    
                    if (std.mem.indexOf(u8, tag_slice, "href=\"")) |idx| {
                        url_start = idx + 6;
                        if (std.mem.indexOfScalarPos(u8, tag_slice, url_start, '"')) |e_idx| { url_end = e_idx; }
                    } else if (std.mem.indexOf(u8, tag_slice, "href='")) |idx| {
                        url_start = idx + 6;
                        if (std.mem.indexOfScalarPos(u8, tag_slice, url_start, '\'')) |e_idx| { url_end = e_idx; }
                    }

                    if (url_end > url_start) {
                        const extracted_url = tag_slice[url_start..url_end];
                        const link_idx = self.links.items.len;
                        if (self.allocator.dupe(u8, extracted_url)) |duped| {
                            self.links.append(self.allocator, duped) catch {};
                            var marker_buf: [32]u8 = undefined;
                            const marker_str = std.fmt.bufPrint(&marker_buf, "[{d}]", .{link_idx}) catch "[?]";
                            try self.addLeaf(marker_str, .LINK, 1, false); // Injected at Layer 1
                        } else |_| {}
                    }
                }

                if (contains(tag_slice, "<li")) {
                    try self.addLeaf(" > ", .TEXT, 1, false);
                } else if (contains(tag_slice, "<h1") or contains(tag_slice, "<h2") or contains(tag_slice, "<h3")) {
                    try self.addLeaf(" # ", .TEXT, 1, false);
                }

                if (isBlockTag(tag_slice) and !in_script and !in_style) {
                    try self.addLeaf("", .BREAK, 1, true);
                    if (contains(tag_slice, "<p") or contains(tag_slice, "</p") or contains(tag_slice, "<li") or contains(tag_slice, "</li")) {
                         try self.addLeaf("", .BREAK, 1, true);
                    }
                }
                
                start = i + 1;
                in_tag = false;
            }
            
            i += 1;
        }
        
        if (i > start) {
            const layer: u8 = if (in_script or in_style) 3 else 1;
            const hType: HarvestType = if (in_script or in_style) .SCRIPT else .TEXT;
            try self.addLeaf(raw[start..i], hType, layer, false);
        }
    }

    fn isDelim(c: u8) bool {
        return (c == '{' or c == '}' or c == '[' or c == ']' or c == '(' or c == ')');
    }

    // [!] IN-PLACE HTML ENTITY DECODER
    fn decodeEntitiesInPlace(text: []u8) []u8 {
        var read_ptr: usize = 0;
        var write_ptr: usize = 0;
        while (read_ptr < text.len) {
            if (text[read_ptr] == '&' and read_ptr + 3 < text.len) {
                if (std.mem.startsWith(u8, text[read_ptr..], "&#160;")) {
                    text[write_ptr] = ' ';
                    write_ptr += 1; read_ptr += 6; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&#8217;")) {
                    text[write_ptr] = '\'';
                    write_ptr += 1; read_ptr += 7; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&amp;")) {
                    text[write_ptr] = '&';
                    write_ptr += 1; read_ptr += 5; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&quot;")) {
                    text[write_ptr] = '"'; write_ptr += 1; read_ptr += 6; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&#39;")) {
                    text[write_ptr] = '\''; write_ptr += 1; read_ptr += 5; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&lt;")) {
                    text[write_ptr] = '<'; write_ptr += 1; read_ptr += 4; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&gt;")) {
                    text[write_ptr] = '>'; write_ptr += 1; read_ptr += 4; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&#8211;")) {
                    text[write_ptr] = '-'; write_ptr += 1; read_ptr += 7; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&#8212;")) {
                    text[write_ptr] = '-'; write_ptr += 1; read_ptr += 7; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&#8220;")) {
                    text[write_ptr] = '"';
                    write_ptr += 1; read_ptr += 7; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&#8221;")) {
                    text[write_ptr] = '"'; write_ptr += 1; read_ptr += 7; continue;
                } else if (std.mem.startsWith(u8, text[read_ptr..], "&#8230;")) {
                    text[write_ptr] = '.'; write_ptr += 1;
                    if (write_ptr < text.len) { text[write_ptr] = '.'; write_ptr += 1; }
                    if (write_ptr < text.len) { text[write_ptr] = '.'; write_ptr += 1; }
                    read_ptr += 7; continue;
                }
            }
            text[write_ptr] = text[read_ptr];
            write_ptr += 1;
            read_ptr += 1;
        }
        return text[0..write_ptr];
    }

    fn addLeaf(self: *Banyan, text: []const u8, h_type: HarvestType, layer: u8, is_newline: bool) !void {
        if (text.len == 0 and !is_newline) return;
        
        var final: []u8 = undefined;
        if (layer == 1 and !is_newline and h_type == .TEXT) {
             final = try compressWhitespace(self.allocator, text);
             if (final.len == 0) { self.allocator.free(final); return; }
             final = decodeEntitiesInPlace(final);
        } else {
             final = try self.allocator.dupe(u8, text);
             if (h_type == .TEXT) { final = decodeEntitiesInPlace(final); }
        }

        const leaf = Leaf{ .text = final, .h_type = h_type, .layer = layer, .is_newline = is_newline };
        try self.leaves.append(self.allocator, leaf);
    }

    fn contains(haystack: []const u8, needle: []const u8) bool {
        return std.mem.indexOf(u8, haystack, needle) != null;
    }

    fn isBlockTag(tag: []const u8) bool {
        if (contains(tag, "<br")) return true;
        if (contains(tag, "<p")) return true;
        if (contains(tag, "</p")) return true;
        if (contains(tag, "<div")) return true;
        if (contains(tag, "</div")) return true;
        if (contains(tag, "<li")) return true;
        if (contains(tag, "</li")) return true;
        if (contains(tag, "<h")) return true;
        if (contains(tag, "</h")) return true;
        return false;
    }

    fn compressWhitespace(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var out = try std.ArrayList(u8).initCapacity(allocator, input.len);
        var last_space = false;
        for (input) |c| {
            if (c == ' ' or c == '\n' or c == '\r' or c == '\t') {
                if (!last_space) { out.appendAssumeCapacity(' ');
                last_space = true; }
            } else {
                out.appendAssumeCapacity(c);
                last_space = false;
            }
        }
        return out.toOwnedSlice(allocator);
    }

    pub fn render(self: *Banyan, buffer: []u32, width: usize, height: usize, scroll_y: usize) void {
        const start_y = 20;
        const line_h = 10;
        const max_lines = (height - 40) / line_h;
        
        var cursor_x: usize = 10;
        var virtual_row: usize = 0;

        for (self.leaves.items) |leaf| {
            if (self.focus_depth > 0 and leaf.layer > self.focus_depth) continue;
            if (leaf.is_newline) {
                virtual_row += 1;
                cursor_x = 10; 
                continue;
            }

            var color: u32 = codex.get("S.S");
            if (self.focus_depth == 0) {
                if (leaf.layer > 1) color = codex.get("K.H");
                if (leaf.h_type == .DELIM) color = codex.get("B.H");
            } else if (self.focus_depth == 3) {
                if (leaf.layer == 1) color = codex.get("K.H");
                if (leaf.layer == 3) color = codex.get("B.S");
                if (leaf.layer == 2) color = codex.get("K.H");
            } else if (self.focus_depth == 2) {
                if (leaf.layer == 2) color = codex.get("K.H");
                if (leaf.h_type == .LINK) color = codex.get("C.S");
                if (leaf.h_type == .DELIM) color = codex.get("B.H");
            } else {
                if (leaf.h_type == .LINK) color = codex.get("C.S");
                if (leaf.h_type == .DELIM) color = codex.get("B.H");
            }

            for (leaf.text) |c| {
                if (cursor_x >= width - 20) {
                    virtual_row += 1;
                    cursor_x = 10;
                }

                if (virtual_row >= scroll_y) {
                    const screen_row = virtual_row - scroll_y;
                    if (screen_row >= max_lines) break; 
                    
                    const py = start_y + (screen_row * line_h);
                    var draw_col = color;

                    // [!] SATORI RENDERING: Paint the crimson beam and brass lock
                    if (self.is_scan_active and virtual_row == self.scan_line_y) {
                        const is_focused = (cursor_x >= self.focus_x) and (cursor_x < self.focus_x + (self.focus_len * 8));
                        const bg_col: u32 = if (is_focused) codex.get("B.S") else codex.get("C.H");
                        draw_col = if (is_focused) codex.get("K.S") else codex.get("S.H");

                        // Fill the 10px high structural block behind the character
                        var bg_y: usize = 0;
                        while (bg_y < line_h) : (bg_y += 1) {
                            var bg_x: usize = 0;
                            while (bg_x < 8) : (bg_x += 1) {
                                const px_x = cursor_x + bg_x;
                                const px_y = py + bg_y;
                                if (px_x < width and px_y < height) {
                                    buffer[px_y * width + px_x] = bg_col;
                                }
                            }
                        }
                    }

                    drawCharToBuf(buffer, width, height, cursor_x, py, c, draw_col);
                }
                cursor_x += 8;
            }
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
                const sx = px + x;
                const sy = py + y;
                if (sx < w and sy < h) { buf[sy * w + sx] = color; }
            }
        }
    }
}
// }-.]
