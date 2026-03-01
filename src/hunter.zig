const std = @import("std");
const font = @import("glyphs.zig");

// [!] SOVEREIGN TYPES
const StringList = std.ArrayListUnmanaged([]u8);
const PhiloteMap = std.StringHashMapUnmanaged(u32);

// [!] THREAD CONTEXT
// A secure capsule to pass data between the Main Thread and the Shadow Thread.
const FetchJob = struct {
    allocator: std.mem.Allocator,
    url: []u8,
    result_payload: ?[]u8, // The data comes back here
    is_complete: bool,     // Flag for the main thread
    success: bool,
};

pub const Hunter = struct {
    allocator: std.mem.Allocator,
    history: StringList,
    history_index: usize, 
    display_lines: StringList,
    url: []u8,
    status: []const u8,
    scroll_y: usize,
    active: bool,
    philote_map: PhiloteMap,
    
    // ASYNC STATE
    current_job: ?*FetchJob, // Pointer to active job
    thread_handle: ?std.Thread,

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
            .current_job = null,
            .thread_handle = null,
        };
        self.loadHistory() catch {}; 
        
        // Waking State: Auto-fetch last known if exists
        if (self.history.items.len > 0) {
            self.navigateHistory(0) catch {};
        }
        return self;
    }

    pub fn deinit(self: *Hunter) void {
        if (self.thread_handle) |t| t.detach(); // Cut the cord
        
        self.saveHistory() catch {}; 
        self.history.deinit(self.allocator);
        for (self.display_lines.items) |line| self.allocator.free(line);
        self.display_lines.deinit(self.allocator);
        self.philote_map.deinit(self.allocator);
        if (self.url.len > 0) self.allocator.free(self.url);
    }

    // --- HEARTBEAT (Call this every frame) ---
    pub fn tick(self: *Hunter) !void {
        if (self.current_job) |job| {
            if (job.is_complete) {
                // JOB FINISHED: Integrate the data
                if (job.success and job.result_payload != null) {
                    const body = job.result_payload.?;
                    defer self.allocator.free(body); 
                    try self.parseContent(body);
                    self.status = "LOCKED";
                } else {
                    self.status = "NO_SIGNAL";
                }
                
                // Cleanup
                if (self.thread_handle) |t| t.detach();
                self.thread_handle = null;
                self.allocator.free(job.url);
                self.allocator.destroy(job);
                self.current_job = null;
            } 
        }
    }

    // --- EXECUTION (Async) ---
    fn executeFetch(self: *Hunter, target: []const u8) !void {
        self.active = true;
        self.status = "FETCHING..."; // Amber Alert
        self.scroll_y = 0;

        // 1. Update Weights
        const gop = try self.philote_map.getOrPut(self.allocator, target);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;

        // 2. Clear UI Immediately
        for (self.display_lines.items) |line| self.allocator.free(line);
        self.display_lines.clearRetainingCapacity();

        // 3. Debounce: Kill previous job if still running
        if (self.current_job) |old_job| {
             if (self.thread_handle) |t| t.detach();
             self.current_job = null; 
        }

        // 4. Spawn Shadow Thread
        const job = try self.allocator.create(FetchJob);
        job.* = .{
            .allocator = self.allocator,
            .url = try self.allocator.dupe(u8, target),
            .result_payload = null,
            .is_complete = false,
            .success = false,
        };
        self.current_job = job;

        self.thread_handle = try std.Thread.spawn(.{}, backgroundHunt, .{job});
        
        if (self.url.len > 0) self.allocator.free(self.url);
        self.url = try self.allocator.dupe(u8, target);
    }

    // --- SHADOW FUNCTION (Runs in Background) ---
    fn backgroundHunt(job: *FetchJob) void {
        const argv = [_][]const u8{ "curl", "-L", "-s", "-k", job.url };
        
        var child = std.process.Child.init(&argv, job.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;
        
        if (child.spawn()) |_| {
            // Limit buffer to 2MB to prevent memory bombs
            if (child.stdout) |stdout| {
                if (stdout.readToEndAlloc(job.allocator, 1024 * 1024 * 2)) |body| {
                    _ = child.wait() catch {};
                    job.result_payload = body;
                    job.success = true;
                } else |_| { job.success = false; }
            }
        } else |_| { job.success = false; }
        
        job.is_complete = true; // Signal Main Thread
    }

    // --- NAVIGATION ---
    pub fn navigateHistory(self: *Hunter, direction: i32) !void {
        if (self.history.items.len == 0) return;

        if (direction < 0) { 
            if (self.history_index > 0) self.history_index -= 1;
        } else if (direction > 0) { 
            if (self.history_index < self.history.items.len - 1) self.history_index += 1;
        }
        
        self.saveHistory() catch {};
        try self.executeFetch(self.history.items[self.history_index]);
    }
    
    pub fn hunt(self: *Hunter, target: []const u8) !void {
        try self.history.append(self.allocator, try self.allocator.dupe(u8, target));
        self.history_index = self.history.items.len - 1;
        self.saveHistory() catch {};
        try self.executeFetch(target);
    }

    // --- PARSING ---
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

    // --- PERSISTENCE ---
    fn saveHistory(self: *Hunter) !void {
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
        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch return;
        defer self.allocator.free(content);
        var iter = std.mem.splitScalar(u8, content, '\n');
        while (iter.next()) |line| {
            const clean = std.mem.trim(u8, line, "\r");
            if (clean.len > 0) {
                try self.history.append(self.allocator, try self.allocator.dupe(u8, clean));
            }
        }
        if (self.history.items.len > 0) self.history_index = self.history.items.len - 1;
    }

    // --- RENDER ---
    pub fn render(self: *Hunter, buffer: []u32, width: usize, height: usize) void {
        const start_y = 20; 
        const end_y = height - 20;
        const line_h = 10;
        const max_lines = (end_y - start_y) / line_h;

        // A. Content
        var row: usize = 0;
        const view_slice = if (self.display_lines.items.len > self.scroll_y) 
                           self.display_lines.items[self.scroll_y..] 
                           else self.display_lines.items[0..0];

        for (view_slice) |text| {
            if (row >= max_lines) break;
            const py = start_y + (row * line_h);
            var px: usize = 10;
            for (text) |c| {
                if (px >= width - 60) break; 
                if (c == 27) continue; 
                const color: u32 = if (c == '<' or c == '>') 0x00DC143C else 0x00AAAAAA; 
                drawCharToBuf(buffer, width, height, px, py, c, color);
                px += 8;
            }
            row += 1;
        }

        // B. Timeline (Flex/Warp)
        const timeline_x = width - 20;
        var t_y: usize = start_y;
        
        for (self.history.items, 0..) |h_url, idx| {
            if (t_y >= end_y) break;
            
            var weight_px: usize = 3; 
            if (self.philote_map.get(h_url)) |w| { weight_px += (w * 2); }
            
            var color: u32 = 0x00DC143C; 
            if (idx == self.history_index) {
                weight_px += 8; // Flex
                if (std.mem.eql(u8, self.status, "FETCHING...")) {
                    color = 0x00FFBF00; // Amber Pulse
                } else {
                    color = 0x00FFFFFF; // White Lock
                }
            }
            if (weight_px > 40) weight_px = 40;

            var dy: usize = 0;
            while (dy < 8) : (dy += 1) { 
                var dx: usize = 0;
                while (dx < weight_px) : (dx += 1) {
                    const screen_x = timeline_x + (18 - dx); 
                    const screen_y = t_y + dy;
                    if (screen_x < width and screen_y < height) {
                        buffer[screen_y * width + screen_x] = color;
                    }
                }
            }
            t_y += 10;
        }

        // C. Status
        var sx: usize = width - 120;
        const sy: usize = height - 15;
        for (self.status) |c| {
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
