// [@://nsible_os/src/hunter.zig/.-={
//   module: "Hunter Traversal Lobe",
//   version: "0.10.6-nightly // Banysang",
//   description: "Manages state history, concurrent data retrieval vectors, and local filesystem traversal.",
//   changes: "Omni-render for timeline rail. Fixed directory pointer mutability and ArrayList API drift. Added dynamic hostname enumeration.",
//   philotic_inferences: "To navigate the self, the system must first know its own name, and its history must always cast a shadow."

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
    sap_fba: *std.heap.FixedBufferAllocator, 
    mutex: std.Thread.Mutex,
    
    history: StringList,
    history_index: usize, 
    lens: banyan.Banyan, 
    url: []u8,
    local_id: []const u8,
    status: []const u8,
    scroll_y: usize,
    active: bool,
    philote_map: PhiloteMap,
    current_vector: ?*FlightVector, 
    thread_handle: ?std.Thread,

    pub fn init(perm_allocator: std.mem.Allocator, sap_fba: *std.heap.FixedBufferAllocator) Hunter {
        var id_to_dupe: []const u8 = "mchn";
        var host_buf: [256]u8 = undefined;
        if (std.fs.cwd().openFile("/etc/hostname", .{})) |file| {
            if (file.readAll(&host_buf)) |bytes_read| {
                const trimmed = std.mem.trim(u8, host_buf[0..bytes_read], " \n\r\t");
                if (trimmed.len > 0) id_to_dupe = trimmed;
            } else |_| {}
            file.close();
        } else |_| {}

        var self = Hunter{
            .allocator = perm_allocator,
            .sap_fba = sap_fba,
            .mutex = .{},
            .history = .{},
            .history_index = 0,
            .lens = banyan.Banyan.init(sap_fba.allocator()),
            .url = perm_allocator.dupe(u8, "WAITING") catch @panic("OOM_INIT"),
            .local_id = perm_allocator.dupe(u8, id_to_dupe) catch @panic("OOM_INIT"),
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
        self.allocator.free(self.local_id);
    }

    pub fn isActive(self: *Hunter) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.active;
    }

    pub fn shiftScope(self: *Hunter, direction: i8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.lens.shiftScope(direction);
    }

    pub fn scrollBy(self: *Hunter, direction: i32) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (direction < 0) {
            const abs_dir = @as(usize, @intCast(-direction));
            if (self.scroll_y > abs_dir) {
                self.scroll_y -= abs_dir;
            } else {
                self.scroll_y = 0;
            }
        } else {
            self.scroll_y += @as(usize, @intCast(direction));
        }
    }

    pub fn tick(self: *Hunter) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
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

    pub fn createMemo(self: *Hunter, title: []const u8, content: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const clean_title = if (title.len == 0) "untitled_anomaly" else title;
        var uri_buf: [256]u8 = undefined;
        const full_uri = try std.fmt.bufPrint(&uri_buf, "memo://{s}", .{clean_title});
        const title_dupe = try self.allocator.dupe(u8, full_uri);

        try self.history.append(self.allocator, title_dupe);
        self.history_index = self.history.items.len - 1;
        
        var final_content: []const u8 = content;
        var auto_wrapped: ?[]u8 = null;
        
        if (std.mem.indexOf(u8, content, "<") == null) {
            auto_wrapped = try std.fmt.allocPrint(self.allocator, "<p>{s}</p>", .{content});
            final_content = auto_wrapped.?;
        }

        var filename_buf: [128]u8 = undefined;
        const filename = try std.fmt.bufPrint(&filename_buf, "timeline/mems/{s}.memo", .{clean_title});
        if (std.fs.cwd().createFile(filename, .{})) |file| {
            const ts = std.time.timestamp();
            var header_buf: [512]u8 = undefined;
            const header = std.fmt.bufPrint(&header_buf,
                "// [@://nsible_os/{s}/.-={{\n" ++
                "//   module: \"Operator Artifact\",\n" ++
                "//   timestamp: \"{d}\",\n" ++
                "//   philotic_inferences: \"Manually designated matrix extraction.\"\n" ++
                "// }}-.]\n\n",
                .{filename, ts}
            ) catch "";

            try file.writeAll(header);
            try file.writeAll(final_content);
            try file.writeAll("\n\n// }-.]\n");
            file.close();
        } else |_| {}

        try self.parseContent(final_content);
        if (auto_wrapped) |w| self.allocator.free(w);
        
        self.status = "MEMO_SAVED";
        self.active = true;
        self.allocator.free(self.url);
        self.url = try self.allocator.dupe(u8, full_uri);
        self.saveHistory() catch {};
    }

    pub fn shed(self: *Hunter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.history.items.len == 0) return;
        self.allocator.free(self.history.items[self.history_index]);
        _ = self.history.orderedRemove(self.history_index);
        if (self.history.items.len == 0) {
            self.history_index = 0;
            self.status = "IDLE";
            self.sap_fba.reset();
            self.lens = banyan.Banyan.init(self.sap_fba.allocator());
            self.allocator.free(self.url);
            self.url = self.allocator.dupe(u8, "WAITING") catch return;
            self.active = false;
        } else {
            if (self.history_index >= self.history.items.len) {
                self.history_index = self.history.items.len - 1;
            }
            self.executeFetch(self.history.items[self.history_index]) catch {};
        }
        self.saveHistory() catch {};
    }

    fn fetchLocal(self: *Hunter, path: []const u8, prefix: []const u8) !void {
        var html_buf: std.ArrayListUnmanaged(u8) = .{};
        defer html_buf.deinit(self.allocator);

        const is_absolute = std.mem.startsWith(u8, path, "/");
        
        var is_dir = false;
        if (is_absolute) {
            if (std.fs.openDirAbsolute(path, .{})) |dir| { var d = dir; is_dir = true; d.close(); } else |_| {}
        } else {
            if (std.fs.cwd().openDir(path, .{})) |dir| { var d = dir; is_dir = true; d.close(); } else |_| {}
        }

        if (is_dir) {
            var dir = if (is_absolute) try std.fs.openDirAbsolute(path, .{ .iterate = true }) else try std.fs.cwd().openDir(path, .{ .iterate = true });
            defer dir.close();
            var iter = dir.iterate();

            try html_buf.appendSlice(self.allocator, "<b>[ DYNAMIC DISK: ");
            try html_buf.appendSlice(self.allocator, path);
            try html_buf.appendSlice(self.allocator, " ]</b><br><br>");

            while (try iter.next()) |entry| {
                const icon = if (entry.kind == .directory) "[DIR ]" else "[FILE]";
                const clean_path = if (std.mem.eql(u8, path, ".")) "" else path;
                const final_sep = if (clean_path.len > 0 and !std.mem.endsWith(u8, clean_path, "/")) "/" else "";
                
                try html_buf.appendSlice(self.allocator, "  ");
                try html_buf.appendSlice(self.allocator, icon);
                try html_buf.appendSlice(self.allocator, " <a href=\"");
                try html_buf.appendSlice(self.allocator, prefix);
                try html_buf.appendSlice(self.allocator, clean_path);
                try html_buf.appendSlice(self.allocator, final_sep);
                try html_buf.appendSlice(self.allocator, entry.name);
                try html_buf.appendSlice(self.allocator, "\">");
                try html_buf.appendSlice(self.allocator, entry.name);
                try html_buf.appendSlice(self.allocator, "</a><br>");
            }
        } else {
            const file = if (is_absolute) try std.fs.openFileAbsolute(path, .{}) else try std.fs.cwd().openFile(path, .{});
            defer file.close();
            const content = try file.readToEndAlloc(self.allocator, 1024 * 1024 * 2); 
            defer self.allocator.free(content);
            
            try html_buf.appendSlice(self.allocator, "<b>[ LOCAL ARTIFACT: ");
            try html_buf.appendSlice(self.allocator, path);
            try html_buf.appendSlice(self.allocator, " ]</b><br><br><pre>\n");
            
            var line_iter = std.mem.splitScalar(u8, content, '\n');
            var line_no: usize = 1;
            while (line_iter.next()) |line| {
                var num_buf: [32]u8 = undefined;
                const num_str = try std.fmt.bufPrint(&num_buf, "{d:0>4} | ", .{line_no});
                try html_buf.appendSlice(self.allocator, num_str);
                try html_buf.appendSlice(self.allocator, line);
                try html_buf.appendSlice(self.allocator, "\n");
                line_no += 1;
            }
            try html_buf.appendSlice(self.allocator, "</pre>");
        }

        try self.parseContent(html_buf.items);
    }

    fn executeFetch(self: *Hunter, target: []const u8) !void {
        self.active = true;
        self.status = "FETCHING..."; 
        self.scroll_y = 0;
        
        if (std.mem.startsWith(u8, target, "memo://")) {
            self.status = "LOCAL_MEMO";
            const ts_str = target[7..];
            var filename_buf: [128]u8 = undefined;
            const filename = std.fmt.bufPrint(&filename_buf, "timeline/mems/{s}.memo", .{ts_str}) catch return;
            if (std.fs.cwd().openFile(filename, .{})) |file| {
                if (file.readToEndAlloc(self.allocator, 1024 * 1024)) |body| {
                    self.parseContent(body) catch {};
                    self.allocator.free(body); 
                } else |_| { self.status = "MEMO_LOST"; }
                file.close();
            } else |_| { self.status = "MEMO_LOST"; }

            if (self.current_vector) |_| {
                 if (self.thread_handle) |t| t.detach();
                 self.current_vector = null;
            }
            self.allocator.free(self.url);
            self.url = try self.allocator.dupe(u8, target);
            return; 
        }

        var local_prefix_buf: [256]u8 = undefined;
        const host_prefix = std.fmt.bufPrint(&local_prefix_buf, "@://{s}/", .{self.local_id}) catch "@://mchn/";
        const mchn_prefix = "@://mchn/";

        var is_local = false;
        var local_path: []const u8 = "";
        var active_prefix: []const u8 = "";

        if (std.mem.startsWith(u8, target, host_prefix)) {
            is_local = true;
            local_path = target[host_prefix.len..];
            active_prefix = host_prefix;
        } else if (std.mem.startsWith(u8, target, mchn_prefix)) {
            is_local = true;
            local_path = target[mchn_prefix.len..];
            active_prefix = mchn_prefix;
        }

        if (is_local) {
            self.status = "LOCAL_DISK";
            const actual_path = if (local_path.len == 0) "." else local_path;
            self.fetchLocal(actual_path, active_prefix) catch { self.status = "LOCAL_ERR"; };
            if (self.current_vector) |_| {
                 if (self.thread_handle) |t| t.detach();
                 self.current_vector = null;
            }
            self.allocator.free(self.url);
            self.url = try self.allocator.dupe(u8, target);
            return; 
        }

        const gop = try self.philote_map.getOrPut(self.allocator, target);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;

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
        self.mutex.lock();
        defer self.mutex.unlock();
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
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.history.append(self.allocator, try self.allocator.dupe(u8, target));
        self.history_index = self.history.items.len - 1;
        self.saveHistory() catch {};
        try self.executeFetch(target);
    }

    fn parseContent(self: *Hunter, raw: []const u8) !void {
        self.sap_fba.reset();
        self.lens = banyan.Banyan.init(self.sap_fba.allocator());
        try self.lens.absorb(raw);
    }

    fn saveHistory(self: *Hunter) !void {
        const file = try std.fs.cwd().createFile("aiua.tome", .{});
        defer file.close();
        for (self.history.items) |entry| {
            try file.writeAll(entry);
            try file.writeAll("\n");
        }
    }

    fn loadHistory(self: *Hunter) !void {
        const file = std.fs.cwd().openFile("aiua.tome", .{}) catch return;
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
        self.mutex.lock();
        defer self.mutex.unlock();

        const start_y = 20;
        const end_y = height - 20;

        if (self.active) {
            self.lens.render(buffer, width, height, self.scroll_y);
        }

        const timeline_x = width - 20;
        var t_y: usize = start_y;
        for (self.history.items, 0..) |h_url, idx| {
            if (t_y >= end_y) break;
            var weight_px: usize = 3; 
            if (self.philote_map.get(h_url)) |w| { weight_px += (w * 2); }
            
            var color: u32 = 0x00DC143C;
            if (self.active and idx == self.history_index) {
                weight_px += 8;
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
                    const sx = (timeline_x + 18) - dx;
                    const sy = t_y + dy;
                    if (sx < width and sy < height) buffer[sy * width + sx] = color;
                }
            }
            t_y += 10;
        }

        if (self.active) {
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

// }-.]
