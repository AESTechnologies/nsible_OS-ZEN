const std = @import("std");
const font = @import("glyphs.zig");
const banyan = @import("banyan.zig");

const StringList = std.ArrayListUnmanaged([]u8);
const PhiloteMap = std.StringHashMapUnmanaged(u32);
const ExternalAgent = std.process.Child;

const FlightVector = struct {
    allocator: std.mem.Allocator,
    url: []u8,
    result_payload: ?[]u8, 
    is_complete: bool,    
    success: bool,
};

pub const Hunter = struct {
    allocator: std.mem.Allocator,
    history: StringList,
    history_index: usize, 
    lens: banyan.Banyan, 
    url: []u8,
    status: []const u8,
    scroll_y: usize,
    active: bool,
    philote_map: PhiloteMap,
    current_vector: ?*FlightVector, 
    thread_handle: ?std.Thread,

    pub fn init(allocator: std.mem.Allocator) Hunter {
        var self = Hunter{
            .allocator = allocator,
            .history = .{},
            .history_index = 0,
            .lens = banyan.Banyan.init(allocator),
            .url = allocator.dupe(u8, "WAITING") catch @panic("OOM"),
            .status = "IDLE",
            .scroll_y = 0,
            .active = false,
            .philote_map = .{},
            .current_vector = null,
            .thread_handle = null,
        };
        self.loadHistory() catch {}; 
        return self;
    }

    pub fn deinit(self: *Hunter) void {
        if (self.thread_handle) |t| t.detach(); 
        self.saveHistory() catch {}; 
        self.history.deinit(self.allocator);
        self.lens.deinit(); 
        self.philote_map.deinit(self.allocator);
        self.allocator.free(self.url);
    }

    pub fn tick(self: *Hunter) !void {
        if (self.current_vector) |vector| {
            if (vector.is_complete) {
                if (vector.success and vector.result_payload != null) {
                    const body = vector.result_payload.?;
                    defer self.allocator.free(body); 
                    try self.parseContent(body);
                    self.status = "LOCKED";
                } else {
                    self.status = "NO_SIGNAL";
                }
                if (self.thread_handle) |t| t.detach();
                self.thread_handle = null;
                self.allocator.free(vector.url);
                self.allocator.destroy(vector);
                self.current_vector = null;
            } 
        }
    }

    pub fn createMemo(self: *Hunter, content: []const u8) !void {
        var buf: [64]u8 = undefined;
        const title = try std.fmt.bufPrint(&buf, "memo://{d}", .{std.time.timestamp()});
        const title_dupe = try self.allocator.dupe(u8, title);

        try self.history.append(self.allocator, title_dupe);
        self.history_index = self.history.items.len - 1;
        
        try self.lens.absorb(content);
        self.status = "MEMO_SAVED";
        self.active = true;
        
        self.allocator.free(self.url);
        self.url = try self.allocator.dupe(u8, title);
        
        self.saveHistory() catch {};
    }

    pub fn shed(self: *Hunter) void {
        if (self.history.items.len == 0) return;
        self.allocator.free(self.history.items[self.history_index]);
        _ = self.history.orderedRemove(self.history_index);
        
        if (self.history.items.len == 0) {
            self.history_index = 0;
            self.status = "IDLE";
            for (self.lens.leaves.items) |*leaf| self.allocator.free(leaf.text);
            self.lens.leaves.clearRetainingCapacity();
            self.allocator.free(self.url);
            self.url = self.allocator.dupe(u8, "WAITING") catch return;
            self.active = false;
        } else {
            if (self.history_index >= self.history.items.len) {
                self.history_index = self.history.items.len - 1;
            }
            self.navigateHistory(0) catch {};
        }
        self.saveHistory() catch {};
    }

    fn executeFetch(self: *Hunter, target: []const u8) !void {
        self.active = true;
        self.status = "FETCHING..."; 
        self.scroll_y = 0;
        
        if (std.mem.startsWith(u8, target, "memo://")) {
            self.status = "LOCAL_MEMO";
            return; 
        }

        const gop = try self.philote_map.getOrPut(self.allocator, target);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;

        for (self.lens.leaves.items) |*leaf| self.allocator.free(leaf.text);
        self.lens.leaves.clearRetainingCapacity();

        if (self.current_vector) |_| {
             if (self.thread_handle) |t| t.detach();
             self.current_vector = null; 
        }

        const vector = try self.allocator.create(FlightVector);
        vector.* = .{
            .allocator = self.allocator,
            .url = try self.allocator.dupe(u8, target),
            .result_payload = null,
            .is_complete = false,
            .success = false,
        };
        self.current_vector = vector;

        self.thread_handle = try std.Thread.spawn(.{}, shadowFlight, .{vector});
        
        self.allocator.free(self.url);
        self.url = try self.allocator.dupe(u8, target);
    }

    fn shadowFlight(vector: *FlightVector) void {
        const argv = [_][]const u8{ "curl", "-L", "-s", "-k", vector.url };
        var agent = ExternalAgent.init(&argv, vector.allocator);
        agent.stdout_behavior = .Pipe;
        agent.stderr_behavior = .Ignore;
        
        if (agent.spawn()) |_| {
            if (agent.stdout) |stdout| {
                if (stdout.readToEndAlloc(vector.allocator, 1024 * 1024 * 2)) |body| {
                    _ = agent.wait() catch {};
                    vector.result_payload = body;
                    vector.success = true;
                } else |_| { vector.success = false; }
            }
        } else |_| { vector.success = false; }
        vector.is_complete = true; 
    }

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

    fn parseContent(self: *Hunter, raw: []const u8) !void {
        try self.lens.absorb(raw);
    }

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

    pub fn render(self: *Hunter, buffer: []u32, width: usize, height: usize) void {
        const start_y = 20; 
        const end_y = height - 20;

        self.lens.render(buffer, width, height, self.scroll_y);

        const timeline_x = width - 20;
        var t_y: usize = start_y;
        for (self.history.items, 0..) |h_url, idx| {
            if (t_y >= end_y) break;
            var weight_px: usize = 3; 
            if (self.philote_map.get(h_url)) |w| { weight_px += (w * 2); }
            
            var color: u32 = 0x00DC143C; 
            if (idx == self.history_index) {
                weight_px += 8; 
                // [!] SYNTAX FIX: Braces enforced
                if (std.mem.eql(u8, self.status, "FETCHING...")) {
                    color = 0x00FFBF00;
                } else {
                    color = 0x00FFFFFF;
                }
            }
            if (weight_px > 40) weight_px = 40;

            var dy: usize = 0;
            while (dy < 8) : (dy += 1) { 
                var dx: usize = 0;
                while (dx < weight_px) : (dx += 1) {
                    const sx = timeline_x + (18 - dx); 
                    const sy = t_y + dy;
                    if (sx < width and sy < height) buffer[sy * width + sx] = color;
                }
            }
            t_y += 10;
        }

        var sx: usize = width - 180;
        const sy: usize = height - 15;
        var status_buf: [64]u8 = undefined;
        const scope_str = switch (self.lens.focus_depth) {
            0 => "[RAW]",
            1 => "[ZEN]",
            2 => "[MATRIX]",
            3 => "[ROOT]",
            else => "[?]",
        };
        const final_status = std.fmt.bufPrint(&status_buf, "{s} {s}", .{self.status, scope_str}) catch self.status;

        for (final_status) |c| {
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
                if (screen_x < w and screen_y < h) buffer[screen_y * w + screen_x] = color;
            }
        }
    }
}
