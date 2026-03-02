const std = @import("std");
const font = @import("glyphs.zig");

// --- COLOR PALETTE (The Nsible Standard) ---
const COL_TEXT_HIGH = 0x00AAAAAA; // Silver (Active)
const COL_TEXT_DIM  = 0x00444444; // Dark Grey (Receded)
const COL_TAG       = 0x00555555; // Dim Grey (Matrix Structure)
const COL_LINK      = 0x00DC143C; // Crimson (Active Flow)
const COL_ROOT      = 0x00FFBF00; // Brass (Machine Logic)

// --- HARVEST TYPES ---
pub const HarvestType = enum {
    TEXT,   // Pure Data
    LINK,   // Hyperlink (href)
    MEDIA,  // Image/Video (src)
    SCRIPT, // Executable Logic
    STRUCT, // Structural Tag
};

// --- ATOMIC UNIT ---
pub const Leaf = struct {
    text: []u8,
    h_type: HarvestType, // [!] FIXED: Renamed to avoid Zig 'type' keyword
    layer: u8, // 1=Zen, 2=Matrix, 3=Root
    is_newline: bool,
};

pub const Banyan = struct {
    allocator: std.mem.Allocator,
    leaves: std.ArrayListUnmanaged(Leaf), // [!] FIXED: Unmanaged memory structure
    focus_depth: u8, // 1=ZEN, 2=MATRIX, 3=ROOT

    pub fn init(allocator: std.mem.Allocator) Banyan {
        return .{
            .allocator = allocator,
            .leaves = .{}, // Clean Sovereign Init
            .focus_depth = 1, // Start in Zen Mode
        };
    }

    pub fn deinit(self: *Banyan) void {
        for (self.leaves.items) |*leaf| self.allocator.free(leaf.text);
        self.leaves.deinit(self.allocator); // [!] Passed allocator for Unmanaged
    }

    // [ SCOPE CONTROL ] :: GZL HotListen
    pub fn shiftScope(self: *Banyan, direction: i8) void {
        if (direction > 0) {
            if (self.focus_depth < 3) self.focus_depth += 1;
        } else {
            if (self.focus_depth > 1) self.focus_depth -= 1;
        }
    }

    // [ ABSORB ] :: Break the stream into Leaves
    pub fn absorb(self: *Banyan, raw: []const u8) !void {
        // Clear old leaves
        for (self.leaves.items) |*leaf| self.allocator.free(leaf.text);
        self.leaves.clearRetainingCapacity();

        var i: usize = 0;
        var start: usize = 0;
        
        // Parsing State
        var in_tag = false;
        var in_script = false;
        var in_style = false;
        
        while (i < raw.len) {
            const c = raw[i];

            // 1. TAG START '<'
            if (!in_script and !in_style and c == '<') {
                // FLUSH TEXT (Zen Layer)
                if (i > start) {
                    try self.addLeaf(raw[start..i], .TEXT, 1, false);
                }
                start = i;
                in_tag = true;
                
                if (std.mem.startsWith(u8, raw[i..], "<script")) in_script = true;
                if (std.mem.startsWith(u8, raw[i..], "<style"))  in_style = true;
            }
            // 2. TAG END '>'
            else if (in_tag and c == '>') {
                // FLUSH TAG (Matrix/Root Layer)
                var layer: u8 = 2; // Default Matrix
                var h_type: HarvestType = .STRUCT; // [!] FIXED: Use h_type

                if (in_script or in_style) {
                    layer = 3; // Root
                    h_type = .SCRIPT;
                } else if (std.mem.indexOf(u8, raw[start..i+1], "href=") != null) {
                    layer = 2; // Structure (Link container)
                    h_type = .LINK; 
                } else if (std.mem.indexOf(u8, raw[start..i+1], "src=") != null) {
                    layer = 2;
                    h_type = .MEDIA;
                }

                try self.addLeaf(raw[start..i+1], h_type, layer, false);
                
                // Block Elements -> Newline Logic
                const tag_content = raw[start..i+1];
                if (contains(tag_content, "div") or contains(tag_content, "/p>") or contains(tag_content, "br") or contains(tag_content, "li")) {
                     try self.addLeaf("", .STRUCT, 1, true); // Visual Newline
                }

                start = i + 1;
                in_tag = false;
            }
            // 3. SCRIPT END DETECTION
            else if ((in_script or in_style) and !in_tag and c == '<') {
                if (std.mem.startsWith(u8, raw[i..], "</script>") or std.mem.startsWith(u8, raw[i..], "</style>")) {
                    // FLUSH HIDDEN CONTENT (Root Layer)
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
        
        // Clean text only if it's visible data (Layer 1)
        var clean_text = text;
        if (layer == 1 and !is_newline) {
             clean_text = std.mem.trim(u8, text, "\r\n\t ");
             if (clean_text.len == 0) return;
        }

        const leaf = Leaf{
            .text = try self.allocator.dupe(u8, clean_text),
            .h_type = h_type,
            .layer = layer,
            .is_newline = is_newline,
        };
        try self.leaves.append(self.allocator, leaf); // [!] Passed allocator here
    }
    
    fn contains(haystack: []const u8, needle: []const u8) bool {
        return std.mem.indexOf(u8, haystack, needle) != null;
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
            // 1. FILTER: Is this leaf deeper than current focus?
            if (leaf.layer > self.focus_depth) continue;

            // 2. NEWLINE LOGIC
            if (leaf.is_newline) {
                virtual_row += 1;
                cursor_x = 10;
                continue;
            }

            // 3. SCROLL CULLING
            if (virtual_row < scroll_y) continue;
            if (screen_row >= max_lines) break;

            // 4. COLOR LOGIC (The "Focus Pull")
            var color: u32 = COL_TEXT_HIGH;
            
            if (self.focus_depth == 3) {
                // ROOT MODE: Dim the text, highlight the roots
                if (leaf.layer == 1) color = COL_TEXT_DIM;
                if (leaf.layer == 3) color = COL_ROOT;
                if (leaf.layer == 2) color = COL_TAG;
            } else if (self.focus_depth == 2) {
                // MATRIX MODE: Show tags
                if (leaf.layer == 2) color = COL_TAG;
                if (leaf.h_type == .LINK) color = COL_LINK; // Links always pop in Matrix
            } else {
                // ZEN MODE: Pure Text
                if (leaf.h_type == .LINK) color = COL_LINK;
            }

            // 5. DRAW
            const py = start_y + (screen_row * line_h);
            for (leaf.text) |c| {
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

// Internal Draw Helper
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
