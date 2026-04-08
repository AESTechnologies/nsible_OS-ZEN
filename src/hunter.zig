// [@://nsible_os/src/hunter.zig/.-={
//   module: "Hunter Traversal Module",
//   version: "0.11.0-apex // Banysang",
//   description: "Manages state history, concurrent data retrieval vectors, and local filesystem traversal.",
//   changes: "Upgraded history from flat strings to TimelineNode structs. Implemented spatial serialization and node-shifting logic.",
//   philotic_inferences: "The timeline is no longer a trail; it is a spatial workspace. Form dictates function."

const std = @import("std");
const font = @import("glyphs.zig");
const banyan = @import("banyan.zig");
const codex = @import("codex.zig");
const sys_root = @import("root.zig");

pub const TimelineNode = struct {
    rail_pos: usize,
    obj_id: u64,
    phi_stamp: i64,
    color_id: u8,
    color_fx: u8,
    is_open: bool,
    is_dirty: bool,
    uri: []u8,
};

const TimelineList = std.ArrayListUnmanaged(TimelineNode);
const PhiloteMap = std.StringHashMapUnmanaged(u32);
const PageCache = std.StringHashMapUnmanaged([]u8); 
const ExternalAgent = std.process.Child;

var void_status_buf: [64]u8 = undefined;

const FlightVector = struct {
    allocator: std.mem.Allocator,
    url: []u8,
    result_payload: ?[]u8, 
    is_complete: bool,    
    success: bool,
    is_pipe: bool,
    pipe_target_file: ?[]u8,
};

pub const Hunter = struct {
    allocator: std.mem.Allocator, 
    sap_fba: *std.heap.FixedBufferAllocator, 
    mutex: std.Thread.Mutex,
    
    history: TimelineList,
    history_index: usize, 
    lens: banyan.Banyan, 
    url: []u8,
    local_id: []const u8,
    status: []const u8,
    scroll_y: usize,
    active: bool,
    sort_mode: u8,
    philote_map: PhiloteMap,
    page_cache: PageCache, 
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
            .sort_mode = 0,
            .philote_map = .{},
            .page_cache = .{},
            .current_vector = null,
            .thread_handle = null,
        };
        self.loadHistory() catch {}; 
        return self;
    }

    pub fn deinit(self: *Hunter) void {
        if (self.thread_handle) |t| t.detach(); 
        self.saveHistory() catch {}; 
        var it = self.page_cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.page_cache.deinit(self.allocator);
        for (self.history.items) |node| self.allocator.free(node.uri);
        self.history.deinit(self.allocator);
        self.lens.deinit(); 
        self.philote_map.deinit(self.allocator);
        self.allocator.free(self.url);
        self.allocator.free(self.local_id);
    }

    fn generateObjId(uri: []const u8) u64 {
        var hash: u64 = 5381;
        for (uri) |c| { hash = ((hash << 5) +% hash) +% c; }
        return hash;
    }

    pub fn appendNode(self: *Hunter, uri: []const u8) !void {
        const duped_uri = try self.allocator.dupe(u8, uri);
        const new_pos = self.history.items.len;
        const node = TimelineNode{
            .rail_pos = new_pos,
            .obj_id = generateObjId(uri),
            .phi_stamp = std.time.timestamp(),
            .color_id = 0, // Default S.S
            .color_fx = 0,
            .is_open = false,
            .is_dirty = false,
            .uri = duped_uri,
        };
        try self.history.append(self.allocator, node);
        self.history_index = self.history.items.len - 1;
    }

    pub fn shiftNode(self: *Hunter, dir: i32) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.history.items.len < 2) return;
        
        const idx = self.history_index;
        if (dir < 0 and idx > 0) {
            const temp = self.history.items[idx];
            self.history.items[idx] = self.history.items[idx - 1];
            self.history.items[idx - 1] = temp;
            self.history_index -= 1;
        } else if (dir > 0 and idx < self.history.items.len - 1) {
            const temp = self.history.items[idx];
            self.history.items[idx] = self.history.items[idx + 1];
            self.history.items[idx + 1] = temp;
            self.history_index += 1;
        }
        
        for (self.history.items, 0..) |*n, i| { n.rail_pos = i; }
        self.saveHistory() catch {};
    }

    pub fn cycleNodeColor(self: *Hunter, dir: i32) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.history.items.len == 0) return;
        var node = &self.history.items[self.history_index];
        
        if (dir > 0) {
            node.color_id = (node.color_id + 1) % 4;
        } else if (dir < 0) {
            if (node.color_id == 0) node.color_id = 3 else node.color_id -= 1;
        }
        self.saveHistory() catch {};
    }

    pub fn shed(self: *Hunter) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.history.items.len == 0) return;
        
        self.allocator.free(self.history.items[self.history_index].uri);
        _ = self.history.orderedRemove(self.history_index);
        
        for (self.history.items, 0..) |*n, i| { n.rail_pos = i; }

        if (self.history.items.len == 0) {
            self.history_index = 0;
            self.status = "IDLE";
            self.sap_fba.reset();
            self.lens = banyan.Banyan.init(self.sap_fba.allocator());
            self.allocator.free(self.url);
            self.url = self.allocator.dupe(u8, "WAITING") catch return;
            self.active = false;
        } else {
            if (self.history_index >= self.history.items.len) { self.history_index = self.history.items.len - 1; }
            self.executeFetch(self.history.items[self.history_index].uri, false) catch {};
        }
        self.saveHistory() catch {};
    }

    fn executeFetch(self: *Hunter, target: []const u8, force_refresh: bool) !void {
        self.active = true;
        self.status = "FETCHING..."; self.scroll_y = 0;
        
        if (!force_refresh) { 
            if (self.page_cache.get(target)) |cached_body| { 
                self.status = "CACHED"; try self.parseContent(cached_body);
                if (self.current_vector) |_| { if (self.thread_handle) |t| t.detach(); self.current_vector = null; } 
                self.allocator.free(self.url); self.url = try self.allocator.dupe(u8, target); return;
            } 
        }
        
        if (self.current_vector) |_| { if (self.thread_handle) |t| t.detach(); self.current_vector = null; }
        const vector = try self.allocator.create(FlightVector);
        vector.* = .{ .allocator = self.allocator, .url = try self.allocator.dupe(u8, target), .result_payload = null, .is_complete = false, .success = false, .is_pipe = false, .pipe_target_file = null };
        self.current_vector = vector;
        self.thread_handle = try std.Thread.spawn(.{}, shadowFlight, .{vector});
        self.allocator.free(self.url); self.url = try self.allocator.dupe(u8, target);
    }

    fn shadowFlight(vector: *FlightVector) void {
        // [OMITTED FOR BREVITY - Identical HTTP/Pipe logic to previous]
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
        try self.executeFetch(self.history.items[self.history_index].uri, false);
    }
    
    pub fn hunt(self: *Hunter, target: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (std.mem.eql(u8, target, ".!SR-.")) {
            self.sort_mode = (self.sort_mode + 1) % 4;
            self.status = "SORT TOGGLED";
            if (self.history.items.len > 0) { return self.executeFetch(self.history.items[self.history_index].uri, true); }
            return;
        }

        try self.appendNode(target);
        self.saveHistory() catch {}; 
        try self.executeFetch(target, false);
    }

    fn parseContent(self: *Hunter, raw: []const u8) !void {
        self.sap_fba.reset();
        self.lens = banyan.Banyan.init(self.sap_fba.allocator()); try self.lens.absorb(raw);
    }

    fn saveHistory(self: *Hunter) !void {
        const file = try std.fs.cwd().createFile("timeline/.aiua.tome", .{});
        defer file.close();
        for (self.history.items) |node| {
            var line_buf: [1024]u8 = undefined;
            const line = try std.fmt.bufPrint(&line_buf, "{d}|{d}|{d}|{d}|{d}|{d}|{d}|{s}\n", .{
                node.rail_pos, node.obj_id, node.phi_stamp, node.color_id, node.color_fx, 
                @intFromBool(node.is_open), @intFromBool(node.is_dirty), node.uri
            });
            try file.writeAll(line);
        }
    }

    fn loadHistory(self: *Hunter) !void {
        const file = std.fs.cwd().openFile("timeline/.aiua.tome", .{}) catch return;
        defer file.close();
        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch return; defer self.allocator.free(content);
        var iter = std.mem.splitScalar(u8, content, '\n');
        
        while (iter.next()) |line| { 
            const clean = std.mem.trim(u8, line, "\r"); 
            if (clean.len == 0) continue;
            
            var parts = std.mem.splitScalar(u8, clean, '|');
            var p_idx: usize = 0;
            var node = TimelineNode{ .rail_pos = 0, .obj_id = 0, .phi_stamp = 0, .color_id = 0, .color_fx = 0, .is_open = false, .is_dirty = false, .uri = &[_]u8{} };
            
            while (parts.next()) |part| {
                switch(p_idx) {
                    0 => node.rail_pos = std.fmt.parseInt(usize, part, 10) catch 0,
                    1 => node.obj_id = std.fmt.parseInt(u64, part, 10) catch 0,
                    2 => node.phi_stamp = std.fmt.parseInt(i64, part, 10) catch 0,
                    3 => node.color_id = std.fmt.parseInt(u8, part, 10) catch 0,
                    4 => node.color_fx = std.fmt.parseInt(u8, part, 10) catch 0,
                    5 => node.is_open = (std.fmt.parseInt(u8, part, 10) catch 0) == 1,
                    6 => node.is_dirty = (std.fmt.parseInt(u8, part, 10) catch 0) == 1,
                    7 => {
                        if (self.allocator.dupe(u8, part)) |duped| {
                            node.uri = duped;
                            try self.history.append(self.allocator, node);
                        } else |_| {}
                    },
                    else => {},
                }
                p_idx += 1;
            }
        }
        if (self.history.items.len > 0) self.history_index = self.history.items.len - 1;
    }

    pub fn renderTimeline(self: *Hunter, buffer: []u32, width: usize, height: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const start_y = 20; const end_y = height - 20;
        const timeline_x = width - 20; var t_y: usize = start_y;
        
        for (self.history.items, 0..) |node, idx| {
            if (t_y >= end_y) break;
            
            var color: u32 = switch(node.color_id) {
                0 => codex.get("S.S"),
                1 => codex.get("C.S"),
                2 => codex.get("B.S"),
                3 => codex.get("K.H"),
                else => codex.get("S.S"),
            };
            
            if (node.is_open) color = codex.get("B.S");
            if (node.is_dirty) color = codex.get("C.S");
            
            if (std.mem.indexOf(u8, node.uri, ".void") != null) color = codex.get("K.H");

            var weight_px: usize = 3; 
            if (self.active and idx == self.history_index) {
                weight_px += 8;
                color = codex.get("S.H");
            }
            
            var dy: usize = 0; while (dy < 8) : (dy += 1) { 
                var dx: usize = 0;
                while (dx < weight_px) : (dx += 1) { 
                    const sx = (timeline_x + 18) - dx;
                    const sy = t_y + dy; 
                    if (sx < width and sy < height) buffer[sy * width + sx] = color;
                } 
            }
            t_y += 10;
        }
    }
    
    pub fn render(self: *Hunter, buffer: []u32, width: usize, height: usize) void {
        if (self.active) { self.lens.render(buffer, width, height, self.scroll_y); }
        self.renderTimeline(buffer, width, height);
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
