const std = @import("std");
const font = @import("glyphs.zig");

const COL_TEXT_HIGH = 0x00AAAAAA; 
const COL_TEXT_DIM  = 0x00444444; 
const COL_TAG       = 0x00555555; 
const COL_LINK      = 0x00DC143C; 
const COL_ROOT      = 0x00FFBF00; 

pub const HarvestType = enum { TEXT, LINK, MEDIA, SCRIPT, STRUCT };

pub const Leaf = struct {
    text: []u8,
    h_type: HarvestType, 
    layer: u8, 
    is_newline: bool,
};

pub const Banyan = struct {
    allocator: std.mem.Allocator,
    leaves: std.ArrayListUnmanaged(Leaf), 
    focus_depth: u8, 

    pub fn init(allocator: std.mem.Allocator) Banyan {
        return .{
            .allocator = allocator,
            .leaves = .{}, 
            .focus_depth = 1, 
        };
    }

    pub fn deinit(self: *Banyan) void {
        for (self.leaves.items) |*leaf| self.allocator.free(leaf.text);
        self.leaves.deinit(self.allocator); 
    }

    pub fn shiftScope(self: *Banyan, direction: i8) void {
        if (direction > 0) {
            if (self.focus_depth < 3) self.focus_depth += 1;
        } else {
            if (self.focus_depth > 1) self.focus_depth -= 1;
        }
    }

    pub fn absorb(self: *Banyan, raw: []const u8) !void {
        for (self.leaves.items) |*leaf| self.allocator.free(leaf.text);
        self.leaves.clearRetainingCapacity();

        var i: usize = 0;
        var start: usize = 0;
        var in_tag = false;
        var in_script = false;
        var in_style = false;
        
        while (i < raw.len) {
            const c = raw[i];

            if (!in_script and !in_style and c == '<') {
                if (i > start) {
                    try self.addLeaf(raw[start..i], .TEXT, 1, false);
                }
                start = i;
                in_tag = true;
                
                if (std.mem.startsWith(u8, raw[i..], "<script")) in_script = true;
                if (std.mem.startsWith(u8, raw[i..], "<style"))  in_style = true;
            }
            else if (in_tag and c == '>') {
                var layer: u8 = 2; 
                var h_type: HarvestType = .STRUCT; 

                if (in_script or in_style) {
                    layer = 3; 
                    h_type = .SCRIPT;
                } else if (std.mem.indexOf(u8, raw[start..i+1], "href=") != null) {
                    layer = 2; 
                    h_type = .LINK; 
                } else if (std.mem.indexOf(u8, raw[start..i+1], "src=") != null) {
                    layer = 2;
                    h_type = .MEDIA;
                }

                try self.addLeaf(raw[start..i+1], h_type, layer, false);
                
                // Block Elements -> Inject Paragraph Breaks
                if (isBlockTag(raw[start..i+1])) {
                     try self.addLeaf("", .STRUCT, 1, true); 
                }

                start = i + 1;
                in_tag = false;
            }
            else if ((in_script or in_style) and !in_tag and c == '<') {
                if (std.mem.startsWith(u8, raw[i..], "</script>") or std.mem.startsWith(u8, raw[i..], "</style>")) {
                    if (i > start) {
                        try self.addLeaf(raw[start..i], .SCRIPT, 3, false);
                    }
                    start = i;
                    in_tag = true;
                    in_script = false;
                    in_style = false;
                }
            }
            i += 1;
        }
    }

    fn addLeaf(self: *Banyan, text: []const u8, h_type: HarvestType, layer: u8, is_newline: bool) !void {
        if (text.len == 0 and !is_newline) return;
        
        var final_text: []u8 = undefined;

        if (layer == 1 and !is_newline) {
            // Text Layer: Compress Whitespace, keep words separated
            const compressed = try compressWhitespace(self.allocator, text);
            const clean = std.mem.trim(u8, compressed, " ");
            if (clean.len == 0) {
                self.allocator.free(compressed);
                return;
            }
            final_text = try self.allocator.dupe(u8, clean);
            self.allocator.free(compressed);
        } else {
            // Tags/Scripts Layer: Just copy, but we will handle internal \n in renderer
            final_text = try self.allocator.dupe(u8, text);
        }

        const leaf = Leaf{
            .text = final_text,
            .h_type = h_type,
            .layer = layer,
            .is_newline = is_newline,
        };
        try self.leaves.append(self.allocator, leaf);
    }
    
    fn isBlockTag(tag: []const u8) bool {
        var buf: [16]u8 = undefined;
        const len = @min(tag.len, 16);
        for (tag[0..len], 0..) |c, idx| buf[idx] = std.ascii.toLower(c);
        const lower = buf[0..len];
        return std.mem.indexOf(u8, lower, "<p") != null or
               std.mem.indexOf(u8, lower, "</p") != null or
               std.mem.indexOf(u8, lower, "<div") != null or
               std.mem.indexOf(u8, lower, "</div") != null or
               std.mem.indexOf(u8, lower, "<br") != null or
               std.mem.indexOf(u8, lower, "<li") != null or
               std.mem.indexOf(u8, lower, "<h1") != null or
               std.mem.indexOf(u8, lower, "<h2") != null;
    }

    fn compressWhitespace(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var out = try std.ArrayList(u8).initCapacity(allocator, input.len);
        var in_space = false;
        for (input) |c| {
            if (c == ' ' or c == '\n' or c == '\r' or c == '\t') {
                if (!in_space) {
                    out.appendAssumeCapacity(' ');
                    in_space = true;
                }
            } else {
                out.appendAssumeCapacity(c);
                in_space = false;
            }
        }
        return out.toOwnedSlice(allocator);
    }

    // [ RENDER ] :: The Focus Logic
    pub fn render(self: *Banyan, buffer: []u32, width: usize, height: usize, scroll_y: usize) void {
        const start_y = 20;
        const line_h = 10;
        const max_lines = (height - 40) / line_h;
        
        var screen_row: usize = 0;
        var cursor_x: usize = 10;
        var virtual_row: usize = 0;

        for (self.leaves.items) |leaf| {
            if (leaf.layer > self.focus_depth) continue;

            if (leaf.is_newline) {
                virtual_row += 1;
                cursor_x = 10;
                continue;
            }

            if (virtual_row < scroll_y) continue;
            if (screen_row >= max_lines) break;

            var color: u32 = COL_TEXT_HIGH;
            
            if (self.focus_depth == 3) {
                if (leaf.layer == 1) color = COL_TEXT_DIM;
                if (leaf.layer == 3) color = COL_ROOT;
                if (leaf.layer == 2) color = COL_TAG;
            } else if (self.focus_depth == 2) {
                if (leaf.layer == 2) color = COL_TAG;
                if (leaf.h_type == .LINK) color = COL_LINK; 
            } else {
                if (leaf.h_type == .LINK) color = COL_LINK;
            }

            const py = start_y + (screen_row * line_h);
            for (leaf.text) |c| {
                // [!] CRITICAL FIX: Handle hard newlines inside Tags/Scripts
                if (c == '\n') {
                    screen_row += 1;
                    virtual_row += 1;
                    cursor_x = 10;
                    if (screen_row >= max_lines) break;
                    continue;
                }
                if (c == '\r' or c == '\t') continue; // Ignore pure carriage returns/tabs visually

                if (cursor_x >= width - 20) {
                    screen_row += 1;
                    virtual_row += 1;
                    cursor_x = 10;
                    if (screen_row >= max_lines) break;
                }
                
                drawCharToBuf(buffer, width, height, cursor_x, py, c, color);
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
                if (sx < w and sy < h) {
                    buf[sy * w + sx] = color;
                }
            }
        }
    }
}
