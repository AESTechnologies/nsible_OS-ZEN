const std = @import("std");
const font = @import("glyphs.zig");

// --- PALETTE (STRICT: RED/SILVER/BRASS/BLACK) ---
const COL_TEXT_HIGH = 0x00AAAAAA; // Silver (Data)
const COL_TEXT_DIM  = 0x00444444; // Dark Grey (Receded)
const COL_TAG       = 0x00555555; // Dim Grey (Structure)
const COL_LINK      = 0x00DC143C; // Crimson (Flow)
const COL_ROOT      = 0x00FFBF00; // Brass (Machine Logic)
const COL_DELIM     = 0x00FFBF00; // Brass (Delimiters)

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
    focus_depth: u8, // 0=RAW, 1=ZEN, 2=MATRIX, 3=ROOT

    pub fn init(allocator: std.mem.Allocator) Banyan {
        return .{
            .allocator = allocator,
            .leaves = .{}, 
            .focus_depth = 1, // Default: ZEN
        };
    }

    pub fn deinit(self: *Banyan) void {
        for (self.leaves.items) |*leaf| self.allocator.free(leaf.text);
        self.leaves.deinit(self.allocator); 
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

        var i: usize = 0;
        var start: usize = 0;
        var in_tag = false;
        
        // [!] STATE MACHINE: Track when we are inside machine-logic blocks
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

                // [!] TOGGLE STATE MACHINE
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
                
                // [!] BANYSANG: Visual Markers for Lists and Headers in Zen mode
                if (contains(tag_slice, "<li")) {
                    try self.addLeaf(" > ", .TEXT, 1, false);
                } else if (contains(tag_slice, "<h1") or contains(tag_slice, "<h2") or contains(tag_slice, "<h3")) {
                    try self.addLeaf(" # ", .TEXT, 1, false);
                }

                // [!] HARD BREAK LOGIC (Includes <li> and <p> explicitly)
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
        
        // Final flush
        if (i > start) {
            const layer: u8 = if (in_script or in_style) 3 else 1;
            const hType: HarvestType = if (in_script or in_style) .SCRIPT else .TEXT;
            try self.addLeaf(raw[start..i], hType, layer, false);
        }
    }

    fn isDelim(c: u8) bool {
        return (c == '{' or c == '}' or c == '[' or c == ']' or c == '(' or c == ')');
    }

    fn addLeaf(self: *Banyan, text: []const u8, h_type: HarvestType, layer: u8, is_newline: bool) !void {
        if (text.len == 0 and !is_newline) return;
        
        var final: []u8 = undefined;
        if (layer == 1 and !is_newline and h_type == .TEXT) {
             final = try compressWhitespace(self.allocator, text);
             if (final.len == 0) { self.allocator.free(final); return; }
        } else {
             final = try self.allocator.dupe(u8, text);
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

    // [!] RENDER (UPDATED: Character-level wrap and perfect virtual row scrolling)
    pub fn render(self: *Banyan, buffer: []u32, width: usize, height: usize, scroll_y: usize) void {
        const start_y = 20;
        const line_h = 10;
        const max_lines = (height - 40) / line_h;
        
        var cursor_x: usize = 10;
        var virtual_row: usize = 0;

        for (self.leaves.items) |leaf| {
            // [!] SCOPE FILTER
            if (self.focus_depth > 0 and leaf.layer > self.focus_depth) continue;
            
            if (leaf.is_newline) {
                virtual_row += 1;
                cursor_x = 10; 
                continue;
            }

            var color: u32 = COL_TEXT_HIGH;
            
            // [!] STRUCTURAL COLORING
            if (self.focus_depth == 0) {
                if (leaf.layer > 1) color = COL_TAG;
                if (leaf.h_type == .DELIM) color = COL_DELIM;
            } else if (self.focus_depth == 3) {
                if (leaf.layer == 1) color = COL_TEXT_DIM;
                if (leaf.layer == 3) color = COL_ROOT;
                if (leaf.layer == 2) color = COL_TAG;
            } else if (self.focus_depth == 2) {
                if (leaf.layer == 2) color = COL_TAG;
                if (leaf.h_type == .LINK) color = COL_LINK;
                if (leaf.h_type == .DELIM) color = COL_DELIM;
            } else {
                if (leaf.h_type == .LINK) color = COL_LINK;
                if (leaf.h_type == .DELIM) color = COL_DELIM;
            }

            for (leaf.text) |c| {
                // Wrap logic: Carriage return if we hit the right margin
                if (cursor_x >= width - 20) {
                    virtual_row += 1;
                    cursor_x = 10;
                }

                // Pixel-perfect drawing: Only render if character's virtual row is visible
                if (virtual_row >= scroll_y) {
                    const screen_row = virtual_row - scroll_y;
                    if (screen_row >= max_lines) break; 
                    
                    const py = start_y + (screen_row * line_h);
                    drawCharToBuf(buffer, width, height, cursor_x, py, c, color);
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
