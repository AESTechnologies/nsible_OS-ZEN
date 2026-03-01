const std = @import("std");
const font = @import("glyphs.zig");

// [!] RAZOR COMPLIANCE
const StringList = std.ArrayListUnmanaged([]u8);
const PhiloteMap = std.StringHashMapUnmanaged(u32);

pub const Hunter = struct {
    allocator: std.mem.Allocator,
    history: StringList,
    history_index: usize, // Tracks "Time"
    display_lines: StringList,
    url: []u8,
    status: []const u8,
    scroll_y: usize,
    active: bool,
    philote_map: PhiloteMap,

    pub fn init(allocator: std.mem.Allocator) Hunter {
        var self = Hunter{
            .allocator = allocator,
            .history = .{},
            .history_index = 0,
            .display_lines = .{},
            .url = allocator.dupe(u8, "WAITING") catch @panic("HUNTER_INIT_OOM"),
            .status = "IDLE",
            .scroll_y = 0,
            .active = false,
            .philote_map = .{},
        };
        // [!] PERSISTENCE: Load memory on boot
        self.loadHistory() catch {}; 
        return self;
    }

    pub fn deinit(self: *Hunter) void {
        self.saveHistory() catch {}; // Save on exit
        
        self.history.deinit(self.allocator);
        for (self.display_lines.items) |line| self.allocator.free(line);
        self.display_lines.deinit(self.allocator);
        self.philote_map.deinit(self.allocator);
        if (self.url.len > 0) self.allocator.free(self.url);
    }

    // --- HISTORY I/O (MEMORY INGEST METHOD) ---
    
    fn saveHistory(self: *Hunter) !void {
        // Direct write to file (Bypasses Writer API flux)
        const file = try std.fs.cwd().createFile("nsible_history.gzl", .{});
        defer file.close();
        
        for (self.history.items) |entry| {
            try file.writeAll(entry);
            try file.writeAll("\n");
        }
    }

    fn loadHistory(self: *Hunter) !void {
        const file = std.fs.cwd().openFile("nsible_history.gzl", .{}) catch return;
        defer file.close();
        
        // [!] FIX: Ingest entire file to RAM, then process. 
        // This avoids the 'Reader' interface version mismatch entirely.
        const max_size = 1024 * 1024; // 1MB History Limit
        const content = file.readToEndAlloc(self.allocator, max_size) catch return;
        defer self.allocator.free(content);
        
        // Split by newlines in memory
        var iter = std.mem.splitScalar(u8, content, '\n');
        while (iter.next()) |line| {
            const clean = std.mem.trim(u8, line, "\r");
            if (clean.len > 0) {
                try self.history.append(self.allocator, try self.allocator.dupe(u8, clean));
            }
        }
        
        if (self.history.items.len > 0) {
            self.history_index = self.history.items.len - 1;
        }
    }

    pub fn navigateHistory(self: *Hunter, direction: i32) !void {
        if (self.history.items.len == 0) return;

        if (direction < 0) { // Back
            if (self.history_index > 0) self.history_index -= 1;
        } else { // Forward
            if (self.history_index < self.history.items.len - 1) self.history_index += 1;
        }

        const target = self.history.items[self.history_index];
        try self.executeFetch(target);
    }

    // --- EXECUTION ---
    pub fn hunt(self: *Hunter, target: []const u8) !void {
        try self.history.append(self.allocator, try self.allocator.dupe(u8, target));
        self.history_index = self.history.items.len - 1;
        try self.executeFetch(target);
    }

    fn executeFetch(self: *Hunter, target: []const u8) !void {
        self.active = true;
        self.status = "FETCHING..."; // Triggers Amber state
        self.scroll_y = 0;

        const gop = try self.philote_map.getOrPut(self.allocator, target);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;

        for (self.display_lines.items) |line| self.allocator.free(line);
        self.display_lines.clearRetainingCapacity();

        const argv = [_][]const u8{ "curl", "-L", "-s", "-k", target };
        var child = std.process.Child.init(&argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;
        
        try child.spawn();
        
        const limit = 1024 * 1024;
        if (child.stdout) |stdout| {
            // readToEndAlloc is safe and stable
            const body = try stdout.readToEndAlloc(self.allocator, limit);
            defer self.allocator.free(body);
            _ = try child.wait();
            try self.parseContent(body);
            self.status = "LOCKED";
        } else {
            self.status = "NO_STREAM";
        }
        
        if (self.url.len > 0) self.allocator.free(self.url);
        self.url = try self.allocator.dupe(u8, target);
    }

    fn parseContent(self: *Hunter, raw: []const u8) !void {
        var start: usize = 0;
        var i: usize = 0;
        const width_limit = 110;

        while (i < raw.len) {
            if (raw[i] == '\n' or (i - start) >= width_limit) {
                const line = raw[start..i];
                const clean = std.mem.trim(u8, line, "\r");
                try self.display_lines.append(self.allocator, try self.allocator.dupe(u8, clean));
                start = i + 1;
            }
            i += 1;
        }
        if (start < raw.len) {
             try self.display_lines.append(self.allocator, try self.allocator.dupe(u8, raw[start..]));
        }
    }

    // --- RENDER (VISUAL FLEX) ---
    pub fn render(self: *Hunter, buffer: []u32, width: usize, height: usize) void {
        const start_y = 20; 
        const end_y = height - 20;
        const line_h = 10;
        const max_lines = (end_y - start_y) / line_h;

        // A. CONTENT
        var row: usize = 0;
        const view_slice = if (self.display_lines.items.len > self.scroll_y) 
                           self.display_lines.items[self.scroll_y..] 
                           else self.display_lines.items[0..0];

        for (view_slice) |text| {
            if (row >= max_lines) break;
            const py = start_y + (row * line_h);
            var px: usize = 10;
            for (text) |c| {
                if (px >= width - 60) break; // [!] More room for Flex
                if (c == 27) continue; 
                const color: u32 = if (c == '<' or c == '>') 0x00DC143C else 0x00AAAAAA; 
                drawCharToBuf(buffer, width, height, px, py, c, color);
                px += 8;
            }
            row += 1;
        }

        // B. TIMELINE (FLEX & WARP)
        const timeline_x = width - 20;
        var t_y: usize = start_y;
        
        for (self.history.items, 0..) |h_url, idx| {
            if (t_y >= end_y) break;
            
            // 1. Base Weight (Philotic)
            var weight_px: usize = 3; // Start thin (Warped)
            if (self.philote_map.get(h_url)) |w| { weight_px += (w * 2); }
            
            // 2. State Logic
            var color: u32 = 0x00DC143C; // Default Red
            
            if (idx == self.history_index) {
                // [!] SELECTED STATE: FLEX
                weight_px += 8; // Expand
                
                if (std.mem.eql(u8, self.status, "FETCHING...")) {
                    color = 0x00FFBF00; // Amber (Busy)
                } else {
                    color = 0x00FFFFFF; // White (Focus)
                }
            }
            
            // Cap visual width
            if (weight_px > 40) weight_px = 40;

            // 3. Draw Tab
            var dy: usize = 0;
            while (dy < 8) : (dy += 1) { 
                var dx: usize = 0;
                while (dx < weight_px) : (dx += 1) {
                    const screen_x = timeline_x + (18 - dx); // Anchored Right
                    const screen_y = t_y + dy;
                    if (screen_x < width and screen_y < height) {
                        buffer[screen_y * width + screen_x] = color;
                    }
                }
            }
            t_y += 10;
        }

        // C. STATUS
        const status_txt = self.status;
        var sx: usize = width - 120;
        const sy: usize = height - 15;
        for (status_txt) |c| {
             drawCharToBuf(buffer, width, height, sx, sy, c, 0x00DC143C);
             sx += 8;
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
                if (screen_x < w and screen_y < h) {
                    buf[screen_y * w + screen_x] = color;
                }
            }
        }
    }
}
