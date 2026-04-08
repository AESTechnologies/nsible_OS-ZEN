// [@://nsible_os/src/hunter.zig/.-={
//   module: "Hunter Traversal Module",
//   version: "0.11.5-apex // Banysang",
//   description: "Manages state history, concurrent data retrieval vectors, and local filesystem traversal.",
//   changes: "Restored philotic weighting to Timeline Rail tabs. Restored active status text readout in renderTimeline.",
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
            .color_id = 0,
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

    pub fn mountDrives(self: *Hunter) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const argv_lsblk = [_][]const u8{ "lsblk", "-nr", "-o", "KNAME,LABEL" };
        var agent = ExternalAgent.init(&argv_lsblk, self.allocator);
        agent.stdout_behavior = .Pipe;
        agent.stderr_behavior = .Ignore;
        if (agent.spawn()) |_| {
            if (agent.stdout) |stdout| {
                if (stdout.readToEndAlloc(self.allocator, 1024 * 64)) |output| {
                    var iter = std.mem.splitScalar(u8, output, '\n');
                    while (iter.next()) |line| {
                        const t_line = std.mem.trim(u8, line, " \r");
                        if (t_line.len == 0) continue;
                        if (std.mem.indexOfScalar(u8, t_line, ' ')) |space_idx| {
                            const kname = t_line[0..space_idx];
                            const label = t_line[space_idx + 1 ..];
                            if (std.mem.startsWith(u8, kname, "sda")) continue;
                            var dev_buf: [64]u8 = undefined;
                            const dev_path = std.fmt.bufPrint(&dev_buf, "/dev/{s}", .{kname}) catch continue;
                            var mnt_buf: [256]u8 = undefined;
                            const mnt_path = std.fmt.bufPrint(&mnt_buf, "/media/static/{s}", .{label}) catch continue;
                            const argv_mkdir = [_][]const u8{ "mkdir", "-p", mnt_path };
                            var agent_mkdir = ExternalAgent.init(&argv_mkdir, self.allocator);
                            if (agent_mkdir.spawn()) |_| { _ = agent_mkdir.wait() catch {}; } else |_| {}
                            const argv_m = [_][]const u8{ "mount", dev_path, mnt_path };
                            var agent_m = ExternalAgent.init(&argv_m, self.allocator);
                            if (agent_m.spawn()) |_| { _ = agent_m.wait() catch {}; } else |_| {}
                        }
                    }
                    self.allocator.free(output);
                } else |_| {}
            }
            _ = agent.wait() catch {};
        } else |_| {}
        self.status = "DRIVES MOUNTED";
    }

    pub fn unmountDrives(self: *Hunter) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const argv_lsblk = [_][]const u8{ "lsblk", "-nr", "-o", "KNAME,LABEL" };
        var agent = ExternalAgent.init(&argv_lsblk, self.allocator);
        agent.stdout_behavior = .Pipe;
        agent.stderr_behavior = .Ignore;
        if (agent.spawn()) |_| {
            if (agent.stdout) |stdout| {
                if (stdout.readToEndAlloc(self.allocator, 1024 * 64)) |output| {
                    var iter = std.mem.splitScalar(u8, output, '\n');
                    while (iter.next()) |line| {
                        const t_line = std.mem.trim(u8, line, " \r");
                        if (t_line.len == 0) continue;
                        if (std.mem.indexOfScalar(u8, t_line, ' ')) |space_idx| {
                            const kname = t_line[0..space_idx];
                            const label = t_line[space_idx + 1 ..];
                            if (std.mem.startsWith(u8, kname, "sda")) continue;
                            var mnt_buf: [256]u8 = undefined;
                            const mnt_path = std.fmt.bufPrint(&mnt_buf, "/media/static/{s}", .{label}) catch continue;
                            const argv_u = [_][]const u8{ "umount", mnt_path };
                            var agent_u = ExternalAgent.init(&argv_u, self.allocator);
                            if (agent_u.spawn()) |_| { _ = agent_u.wait() catch {}; } else |_| {}
                        }
                    }
                    self.allocator.free(output);
                } else |_| {}
            }
            _ = agent.wait() catch {};
        } else |_| {}
        self.status = "DRIVES EJECTED";
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
            if (self.scroll_y > abs_dir) { self.scroll_y -= abs_dir; } else { self.scroll_y = 0; }
        } else {
            self.scroll_y += @as(usize, @intCast(direction));
        }
    }

    pub fn toggleSort(self: *Hunter) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.sort_mode = (self.sort_mode + 1) % 4;
        self.status = switch(self.sort_mode) {
            0 => "SORT: NAME [ASC]",
            1 => "SORT: NAME [DESC]",
            2 => "SORT: DATE [ASC]",
            3 => "SORT: DATE [DESC]",
            else => "SORT",
        };
        
        if (self.history.items.len > 0) {
            const current_target = self.history.items[self.history_index].uri;
            self.executeFetch(current_target, true) catch {};
        }
    }

    pub fn tick(self: *Hunter) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.current_vector) |vector| {
            if (vector.is_complete) {
                if (vector.success and vector.result_payload != null) {
                    const body = vector.result_payload.?;
                    if (vector.is_pipe) {
                        const ts = std.time.timestamp();
                        var parsed_ext: []const u8 = "";
                        var physical_path: []const u8 = "";
                        var path_buf: [512]u8 = undefined;

                        if (vector.pipe_target_file) |custom_file| {
                            var explicit_dir: []const u8 = "";
                            var explicit_base: []const u8 = custom_file;
                            
                            if (std.mem.lastIndexOfScalar(u8, custom_file, '/')) |slash_idx| {
                                explicit_dir = custom_file[0..slash_idx];
                                explicit_base = custom_file[slash_idx + 1 ..];
                            }

                            if (std.mem.lastIndexOfScalar(u8, explicit_base, '.')) |dot_idx| {
                                parsed_ext = explicit_base[dot_idx..];
                                explicit_base = explicit_base[0..dot_idx];
                            } else {
                                parsed_ext = ".memo";
                            }
                            
                            var filename_buf: [256]u8 = undefined;
                            const final_name = std.fmt.bufPrint(&filename_buf, "{s}.{d}{s}", .{explicit_base, ts, parsed_ext}) catch "anomaly.memo";
                            
                            if (explicit_dir.len > 0) {
                                physical_path = std.fmt.bufPrint(&path_buf, "timeline/{s}/{s}", .{explicit_dir, final_name}) catch "timeline/mems/anomaly.memo";
                            } else {
                                physical_path = std.fmt.bufPrint(&path_buf, "timeline/mems/{s}", .{final_name}) catch "timeline/mems/anomaly.memo";
                            }
                        } else {
                            var hostname: []const u8 = "unknown_host";
                            if (std.mem.indexOf(u8, vector.url, "://")) |scheme_idx| {
                                const host_start = scheme_idx + 3;
                                var host_end = host_start;
                                while (host_end < vector.url.len and vector.url[host_end] != '/' and vector.url[host_end] != ':' and vector.url[host_end] != '?') : (host_end += 1) {}
                                if (host_end > host_start) hostname = vector.url[host_start..host_end];
                            } else {
                                var host_end: usize = 0;
                                while (host_end < vector.url.len and vector.url[host_end] != '/' and vector.url[host_end] != ':' and vector.url[host_end] != '?') : (host_end += 1) {}
                                if (host_end > 0) hostname = vector.url[0..host_end];
                            }
                            
                            if (std.mem.startsWith(u8, hostname, "www.")) hostname = hostname[4..];
                            if (std.mem.lastIndexOfScalar(u8, hostname, '.')) |dot_idx| {
                                hostname = hostname[0..dot_idx];
                            }

                            var parsed_filename: []const u8 = "artifact";
                            if (std.mem.lastIndexOfScalar(u8, vector.url, '/')) |slash_idx| {
                                if (slash_idx + 1 < vector.url.len) {
                                    var possible_file = vector.url[slash_idx + 1 ..];
                                    if (std.mem.indexOfScalar(u8, possible_file, '?')) |q_idx| possible_file = possible_file[0..q_idx];
                                    if (std.mem.indexOfScalar(u8, possible_file, '#')) |h_idx| possible_file = possible_file[0..h_idx];
                                    if (possible_file.len > 0) {
                                        parsed_filename = possible_file;
                                    }
                                }
                            }

                            if (std.mem.lastIndexOfScalar(u8, parsed_filename, '.')) |dot_idx| {
                                parsed_ext = parsed_filename[dot_idx..];
                                parsed_filename = parsed_filename[0..dot_idx];
                            } else {
                                parsed_ext = ".memo";
                            }

                            var filename_buf: [256]u8 = undefined;
                            const final_name = std.fmt.bufPrint(&filename_buf, "{s}.{d}.{s}{s}", .{hostname, ts, parsed_filename, parsed_ext}) catch "pipe_anomaly.memo";
                            physical_path = std.fmt.bufPrint(&path_buf, "timeline/mems/{s}", .{final_name}) catch "timeline/mems/anomaly.memo";
                        }
                        
                        var uri_buf: [512]u8 = undefined;
                        if (std.fmt.bufPrint(&uri_buf, "@://mchn/{s}", .{physical_path})) |full_uri| {
                            self.appendNode(full_uri) catch {};
                            
                            if (std.mem.lastIndexOfScalar(u8, physical_path, '/')) |last_slash| {
                                const dir_path = physical_path[0..last_slash];
                                std.fs.cwd().makePath(dir_path) catch {};
                            }

                            if (std.fs.cwd().createFile(physical_path, .{})) |file| {
                                const syn = sys_root.resolveGzlSyntax(parsed_ext);
                                const safe_url: []const u8 = if (vector.url.len > 256) vector.url[0..256] else vector.url;
                                
                                var header_buf: [1024]u8 = undefined;
                                const header = sys_root.buildHeader(header_buf[0..], syn, physical_path, "Operator Artifact (Pipe)", safe_url, "Automatically extracted via True Pipe routing.");
                                
                                file.writeAll(header) catch {};
                                file.writeAll(body) catch {};
                                
                                var footer_buf: [128]u8 = undefined;
                                const footer = sys_root.buildFooter(footer_buf[0..], syn);
                                file.writeAll(footer) catch {};
                                
                                file.close();
                            } else |_| {} 
                            
                            self.saveHistory() catch {};
                            self.status = "PIPE_SEALED";
                        } else |_| { self.status = "PIPE_FAIL_MEM"; }
                        self.allocator.free(body);
                    } else {
                        if (self.page_cache.fetchRemove(vector.url)) |kv| {
                            self.allocator.free(kv.key);
                            self.allocator.free(kv.value);
                        }
                        if (self.allocator.dupe(u8, vector.url)) |key_dupe| {
                            self.page_cache.put(self.allocator, key_dupe, body) catch { 
                                self.allocator.free(key_dupe);
                                self.allocator.free(body); 
                            };
                        } else |_| { self.allocator.free(body); }
                        try self.parseContent(body);
                        self.status = "LOCKED";
                    }
                } else {
                    if (vector.is_pipe) self.status = "PIPE_FAILED" else self.status = "NO_SIGNAL";
                }
                if (self.thread_handle) |t| t.detach();
                self.thread_handle = null;
                self.allocator.free(vector.url);
                if (vector.pipe_target_file) |pf| self.allocator.free(pf);
                self.allocator.destroy(vector);
                self.current_vector = null;
            } 
        }
    }

    pub fn refresh(self: *Hunter) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.executeFetch(self.url, true);
    }

    pub fn createMemo(self: *Hunter, title: []const u8, content: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var title_format_buf: [256]u8 = undefined;
        const fallback_title = if (title.len == 0) "manual.undesignated" else title;
        var final_title: []const u8 = fallback_title;
        var parsed_ext: []const u8 = "";

        if (std.mem.lastIndexOfScalar(u8, fallback_title, '.')) |dot_idx| {
            parsed_ext = fallback_title[dot_idx..];
        } else {
            final_title = std.fmt.bufPrint(&title_format_buf, "manual.{s}.memo", .{fallback_title}) catch "manual.undesignated.memo";
            parsed_ext = ".memo";
        }
        
        const syn = sys_root.resolveGzlSyntax(parsed_ext);

        var uri_buf: [256]u8 = undefined;
        const full_uri = try std.fmt.bufPrint(&uri_buf, "memo://{s}", .{final_title});
        try self.appendNode(full_uri);
        
        var final_content: []const u8 = content;
        var auto_wrapped: ?[]u8 = null;
        if (std.mem.indexOf(u8, content, "<") == null) {
            auto_wrapped = try std.fmt.allocPrint(self.allocator, "<p>{s}</p>", .{content});
            final_content = auto_wrapped.?;
        }
        
        var filename_buf: [128]u8 = undefined;
        const filename = try std.fmt.bufPrint(&filename_buf, "timeline/mems/{s}", .{final_title});
        
        if (std.fs.cwd().createFile(filename, .{})) |file| {
            var header_buf: [1024]u8 = undefined;
            const header = sys_root.buildHeader(header_buf[0..], syn, filename, "Operator Artifact", null, "Manually designated matrix extraction.");
            
            try file.writeAll(header);
            try file.writeAll(final_content);
            
            var footer_buf: [128]u8 = undefined;
            const footer = sys_root.buildFooter(footer_buf[0..], syn);
            try file.writeAll(footer);
            
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

    pub fn banishToVoid(self: *Hunter, target_path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const src_file = std.fs.cwd().openFile(target_path, .{}) catch {
            self.status = "VOID_ERR_404";
            return;
        };
        const file_stat = src_file.stat() catch {
            src_file.close();
            self.status = "VOID_ERR_STAT";
            return;
        };
        const f_size = file_stat.size;
        const content = src_file.readToEndAlloc(self.allocator, 1024 * 1024 * 50) catch {
            src_file.close();
            self.status = "VOID_ERR_MEM";
            return;
        };
        src_file.close();
        defer self.allocator.free(content);

        const void_file = std.fs.cwd().openFile("assets/.void/.00", .{ .mode = .read_write }) catch {
            self.status = "VOID_ERR_SYS";
            return;
        };
        defer void_file.close();
        void_file.seekFromEnd(0) catch {};

        const ts = std.time.timestamp();
        var header_buf: [512]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf,
            "\n// [@://nsible_os/assets/.void/.00/.-={{\n" ++
            "//   module: \"Banished Artifact\",\n" ++
            "//   origin: \"{s}\",\n" ++
            "//   φdate: \"{d}\",\n" ++
            "//   weight_bytes: \"{d}\",\n" ++
            "//   status: \"deprecated\"\n\n",
            .{target_path, ts, f_size}
        ) catch "\n// [VOID_HEADER_ERR]\n\n";

        void_file.writeAll(header) catch {};
        void_file.writeAll(content) catch {};
        void_file.writeAll("\n\n// }-.]\n") catch {};

        std.fs.cwd().deleteFile(target_path) catch {
            self.status = "VOID_ERR_DEL";
            return;
        };

        const size_kb = @as(f32, @floatFromInt(f_size)) / 1024.0;
        self.status = std.fmt.bufPrint(&void_status_buf, "[ VOIDED : {d:.1} KB ]", .{size_kb}) catch "[ VOIDED ]";
    }

    pub fn resolveMeltTarget(self: *Hunter, target: []const u8) ![]u8 {
        var actual_target = target;
        var ddg_dec_buf: [2048]u8 = undefined;
        if (std.mem.indexOf(u8, target, "uddg=")) |uddg_idx| {
            const start = uddg_idx + 5;
            var end = start;
            while (end < target.len and target[end] != '&') : (end += 1) {}
            const encoded_url = target[start..end];
            var dec_len: usize = 0;
            var i: usize = 0;
            while (i < encoded_url.len) {
                if (encoded_url[i] == '%' and i + 2 < encoded_url.len) {
                    const hex = encoded_url[i+1..i+3];
                    const char = std.fmt.parseInt(u8, hex, 16) catch '%';
                    if (dec_len < 2048) { ddg_dec_buf[dec_len] = char; dec_len += 1; }
                    i += 3;
                } else {
                    if (dec_len < 2048) { ddg_dec_buf[dec_len] = encoded_url[i]; dec_len += 1; }
                    i += 1;
                }
            }
            actual_target = ddg_dec_buf[0..dec_len];
        }
        var abs_buf: [2048]u8 = undefined;
        var resolved: []const u8 = actual_target;
        if (std.mem.startsWith(u8, actual_target, "http://") or std.mem.startsWith(u8, actual_target, "https://") or std.mem.startsWith(u8, actual_target, "@://") or std.mem.startsWith(u8, actual_target, "memo://")) {
            resolved = actual_target;
        } else if (std.mem.startsWith(u8, actual_target, "//")) {
            resolved = std.fmt.bufPrint(&abs_buf, "https:{s}", .{actual_target}) catch actual_target;
        } else if (std.mem.startsWith(u8, actual_target, "/")) {
            var base_end: usize = 0;
            if (std.mem.indexOf(u8, self.url, "://")) |scheme_idx| {
                if (std.mem.indexOfScalarPos(u8, self.url, scheme_idx + 3, '/')) |slash_idx| { 
                    base_end = slash_idx; 
                } else { 
                    base_end = self.url.len; 
                }
            }
            if (base_end > 0) { 
                resolved = std.fmt.bufPrint(&abs_buf, "{s}{s}", .{self.url[0..base_end], actual_target}) catch actual_target; 
            } else { 
                resolved = std.fmt.bufPrint(&abs_buf, "https://{s}", .{actual_target}) catch actual_target; 
            }
        } else {
            var base_end: usize = self.url.len;
            if (std.mem.lastIndexOfScalar(u8, self.url, '/')) |last_slash| {
                if (std.mem.indexOf(u8, self.url, "://")) |scheme_idx| { 
                    if (last_slash > scheme_idx + 2) { base_end = last_slash + 1; } 
                }
            }
            resolved = std.fmt.bufPrint(&abs_buf, "{s}{s}", .{self.url[0..base_end], actual_target}) catch actual_target;
        }
        var clean_buf: [2048]u8 = undefined;
        var clean_len: usize = 0;
        var i: usize = 0;
        while (i < resolved.len) {
            if (std.mem.startsWith(u8, resolved[i..], "&amp;")) {
                if (clean_len < 2048) { clean_buf[clean_len] = '&'; clean_len += 1; }
                i += 5;
            } else {
                if (clean_len < 2048) { clean_buf[clean_len] = resolved[i]; clean_len += 1; }
                i += 1;
            }
        }
        const final_resolved = if (clean_len > 0) clean_buf[0..clean_len] else resolved;
        return self.allocator.dupe(u8, final_resolved);
    }

    pub fn pipeMemo(self: *Hunter, target: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        var actual_url_part: []const u8 = target;
        var explicit_file: ?[]u8 = null;
        
        if (std.mem.indexOfScalar(u8, target, '|')) |pipe_idx| {
            actual_url_part = std.mem.trim(u8, target[0..pipe_idx], " \t");
            const right = std.mem.trim(u8, target[pipe_idx+1..], " \t");
            if (right.len > 0 and !std.mem.eql(u8, right, "memo")) {
                explicit_file = try self.allocator.dupe(u8, right);
            }
        }
        
        if (std.mem.startsWith(u8, actual_url_part, "@://")) {
            const possible_idx = actual_url_part[4..];
            var check_melt = possible_idx.len > 0;
            for (possible_idx) |c| { if (c < '0' or c > '9') check_melt = false; }
            if (check_melt) {
                actual_url_part = possible_idx;
            }
        }

        var free_target = false;
        var is_melt = actual_url_part.len > 0;
        for (actual_url_part) |c| { if (c < '0' or c > '9') is_melt = false; }
        var actual_target: []const u8 = actual_url_part;
        
        if (is_melt) {
            const idx = std.fmt.parseInt(usize, actual_url_part, 10) catch {
                if (explicit_file) |ef| self.allocator.free(ef);
                return;
            };
            if (idx < self.lens.links.items.len) {
                actual_target = try self.resolveMeltTarget(self.lens.links.items[idx]);
                free_target = true;
            } else { 
                self.status = "PIPE_ERR_VOID"; 
                if (explicit_file) |ef| self.allocator.free(ef);
                return; 
            }
        } else {
            actual_target = try self.resolveMeltTarget(actual_url_part);
            free_target = true;
        }
        
        if (self.current_vector) |_| { if (self.thread_handle) |t| t.detach(); self.current_vector = null; }
        const vector = try self.allocator.create(FlightVector);
        vector.* = .{ 
            .allocator = self.allocator, 
            .url = try self.allocator.dupe(u8, actual_target), 
            .result_payload = null, 
            .is_complete = false, 
            .success = false, 
            .is_pipe = true,
            .pipe_target_file = explicit_file
        };
        if (free_target) self.allocator.free(actual_target);
        self.current_vector = vector;
        self.thread_handle = try std.Thread.spawn(.{}, shadowFlight, .{vector});
        self.status = "PIPING...";
    }

    pub fn globalSearch(self: *Hunter, query: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        var encoded: std.ArrayListUnmanaged(u8) = .{};
        defer encoded.deinit(self.allocator);
        for (query) |c| {
            if (c == ' ') { 
                try encoded.append(self.allocator, '+'); 
            } else if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_' or c == '.') { 
                try encoded.append(self.allocator, c); 
            } else {
                var hex_buf: [3]u8 = undefined;
                if (std.fmt.bufPrint(&hex_buf, "%{X:0>2}", .{c})) |hex| { try encoded.appendSlice(self.allocator, hex); } else |_| {}
            }
        }
        var url_buf: [1024]u8 = undefined;
        const final_url = std.fmt.bufPrint(&url_buf, "https://lite.duckduckgo.com/lite/?q={s}", .{encoded.items}) catch "https://lite.duckduckgo.com/lite/";
        try self.appendNode(final_url);
        self.saveHistory() catch {};
        try self.executeFetch(final_url, false);
    }

    pub fn stargaze(self: *Hunter) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const ts = std.time.milliTimestamp();
        const is_bright = @rem(ts, 2) == 0;
        const target = if (is_bright) "https://en.wikipedia.org/wiki/Special:Random" else "https://old-search.marginalia.nu/explore/random";
        try self.appendNode(target);
        self.saveHistory() catch {};
        try self.executeFetch(target, false);
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
            
            const DirEntry = struct {
                name: []const u8,
                kind: std.fs.File.Kind,
                mtime: i128,
            };
            
            var entries: std.ArrayListUnmanaged(DirEntry) = .{};
            defer {
                for (entries.items) |e| self.allocator.free(e.name);
                entries.deinit(self.allocator);
            }

            while (try iter.next()) |entry| {
                const name_dupe = try self.allocator.dupe(u8, entry.name);
                var mtime: i128 = 0;
                
                if (self.sort_mode >= 2) {
                    if (entry.kind == .directory) {
                        if (dir.openDir(entry.name, .{})) |sub_dir| {
                            var sd = sub_dir;
                            if (sd.stat()) |stat| mtime = stat.mtime else |_| {}
                            sd.close();
                        } else |_| {}
                    } else {
                        if (dir.statFile(entry.name)) |stat| mtime = stat.mtime else |_| {}
                    }
                }
                
                try entries.append(self.allocator, .{ .name = name_dupe, .kind = entry.kind, .mtime = mtime });
            }

            var idx_i: usize = 1;
            while (idx_i < entries.items.len) : (idx_i += 1) {
                var idx_j: usize = idx_i;
                while (idx_j > 0) : (idx_j -= 1) {
                    const a = entries.items[idx_j - 1];
                    const b = entries.items[idx_j];
                    var swap = false;
                    switch (self.sort_mode) {
                        0 => if (std.mem.lessThan(u8, b.name, a.name)) { swap = true; },
                        1 => if (std.mem.lessThan(u8, a.name, b.name)) { swap = true; },
                        2 => if (b.mtime < a.mtime) { swap = true; },
                        3 => if (b.mtime > a.mtime) { swap = true; },
                        else => {},
                    }
                    if (swap) {
                        entries.items[idx_j - 1] = b;
                        entries.items[idx_j] = a;
                    } else {
                        break;
                    }
                }
            }

            try html_buf.appendSlice(self.allocator, "<b>[ DYNAMIC DISK: "); try html_buf.appendSlice(self.allocator, path); try html_buf.appendSlice(self.allocator, " ]</b><br><br>");
            for (entries.items) |entry| {
                const icon = if (entry.kind == .directory) "[DIR ]" else "[FILE]";
                const clean_path = if (std.mem.eql(u8, path, ".")) "" else path;
                const final_sep = if (clean_path.len > 0 and !std.mem.endsWith(u8, clean_path, "/")) "/" else "";
                try html_buf.appendSlice(self.allocator, "  ");
                try html_buf.appendSlice(self.allocator, icon); try html_buf.appendSlice(self.allocator, " <a href=\""); try html_buf.appendSlice(self.allocator, prefix); try html_buf.appendSlice(self.allocator, clean_path); try html_buf.appendSlice(self.allocator, final_sep); try html_buf.appendSlice(self.allocator, entry.name); try html_buf.appendSlice(self.allocator, "\">");
                try html_buf.appendSlice(self.allocator, entry.name); try html_buf.appendSlice(self.allocator, "</a><br>");
            }
        } else {
            const file = if (is_absolute) try std.fs.openFileAbsolute(path, .{}) else try std.fs.cwd().openFile(path, .{});
            defer file.close();
            const content = try file.readToEndAlloc(self.allocator, 1024 * 1024 * 2); defer self.allocator.free(content);
            try html_buf.appendSlice(self.allocator, "<b>[ LOCAL ARTIFACT: ");
            try html_buf.appendSlice(self.allocator, path); try html_buf.appendSlice(self.allocator, " ]</b><br><br><pre>\n");
            var line_iter = std.mem.splitScalar(u8, content, '\n'); var line_no: usize = 1;
            while (line_iter.next()) |line| {
                var num_buf: [32]u8 = undefined;
                const num_str = try std.fmt.bufPrint(&num_buf, "{d:0>4} | ", .{line_no});
                try html_buf.appendSlice(self.allocator, num_str); try html_buf.appendSlice(self.allocator, line); try html_buf.appendSlice(self.allocator, "\n");
                line_no += 1;
            }
            try html_buf.appendSlice(self.allocator, "</pre>");
        }
        try self.parseContent(html_buf.items);
    }

    fn executeFetch(self: *Hunter, target: []const u8, force_refresh: bool) !void {
        self.active = true;
        self.status = "FETCHING..."; self.scroll_y = 0;
        if (std.mem.startsWith(u8, target, "@://")) {
            const possible_idx = target[4..];
            var is_melt = possible_idx.len > 0;
            for (possible_idx) |c| { if (c < '0' or c > '9') is_melt = false; }
            if (is_melt) {
                const idx = std.fmt.parseInt(usize, possible_idx, 10) catch return;
                if (idx < self.lens.links.items.len) {
                    const raw_target = self.lens.links.items[idx];
                    const actual_target = self.resolveMeltTarget(raw_target) catch return;
                    self.allocator.free(self.history.items[self.history_index].uri);
                    self.history.items[self.history_index].uri = actual_target; 
                    self.saveHistory() catch {};
                    return self.executeFetch(self.history.items[self.history_index].uri, force_refresh);
                } else {
                    self.status = "MELT_VOID";
                    if (self.current_vector) |_| { if (self.thread_handle) |t| t.detach(); self.current_vector = null; }
                    self.allocator.free(self.url);
                    self.url = try self.allocator.dupe(u8, target); return;
                }
            }
        }
        if (std.mem.startsWith(u8, target, "memo://")) {
            self.status = "LOCAL_MEMO";
            const ts_str = target[7..]; var filename_buf: [128]u8 = undefined; const filename = std.fmt.bufPrint(&filename_buf, "timeline/mems/{s}", .{ts_str}) catch return;
            if (std.fs.cwd().openFile(filename, .{})) |file| { 
                if (file.readToEndAlloc(self.allocator, 1024 * 1024)) |body| { self.parseContent(body) catch {}; self.allocator.free(body); } else |_| { self.status = "MEMO_LOST"; } file.close(); 
            } else |_| { self.status = "MEMO_LOST"; }
            if (self.current_vector) |_| { if (self.thread_handle) |t| t.detach(); self.current_vector = null; }
            self.allocator.free(self.url);
            self.url = try self.allocator.dupe(u8, target); return; 
        }
        var local_prefix_buf: [256]u8 = undefined;
        const host_prefix = std.fmt.bufPrint(&local_prefix_buf, "@://{s}/", .{self.local_id}) catch "@://mchn/"; const mchn_prefix = "@://mchn/";
        var is_local = false;
        var local_path: []const u8 = ""; var active_prefix: []const u8 = "";
        if (std.mem.startsWith(u8, target, host_prefix)) { 
            is_local = true; local_path = target[host_prefix.len..]; active_prefix = host_prefix; 
        } else if (std.mem.startsWith(u8, target, mchn_prefix)) { 
            is_local = true; local_path = target[mchn_prefix.len..]; active_prefix = mchn_prefix; 
        }
        if (is_local) {
            self.status = "LOCAL_DISK";
            const actual_path = if (local_path.len == 0) "." else local_path; self.fetchLocal(actual_path, active_prefix) catch { self.status = "LOCAL_ERR"; };
            if (self.current_vector) |_| { if (self.thread_handle) |t| t.detach(); self.current_vector = null; }
            self.allocator.free(self.url); self.url = try self.allocator.dupe(u8, target); return;
        }
        if (!force_refresh) { 
            if (self.page_cache.get(target)) |cached_body| { 
                self.status = "CACHED"; try self.parseContent(cached_body);
                if (self.current_vector) |_| { if (self.thread_handle) |t| t.detach(); self.current_vector = null; } 
                self.allocator.free(self.url); self.url = try self.allocator.dupe(u8, target); return;
            } 
        }
        const gop = try self.philote_map.getOrPut(self.allocator, target); if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;
        if (self.current_vector) |_| { if (self.thread_handle) |t| t.detach(); self.current_vector = null; }
        const vector = try self.allocator.create(FlightVector);
        vector.* = .{ .allocator = self.allocator, .url = try self.allocator.dupe(u8, target), .result_payload = null, .is_complete = false, .success = false, .is_pipe = false, .pipe_target_file = null };
        self.current_vector = vector;
        self.thread_handle = try std.Thread.spawn(.{}, shadowFlight, .{vector});
        self.allocator.free(self.url); self.url = try self.allocator.dupe(u8, target);
    }

    fn shadowFlight(vector: *FlightVector) void {
        var is_local = false;
        var local_path_buf: [512]u8 = undefined;
        var fetch_path: []const u8 = "";

        if (std.mem.startsWith(u8, vector.url, "@://mchn/")) {
            const raw_path = vector.url[9..];
            fetch_path = if (raw_path.len == 0) "." else raw_path;
            is_local = true;
        } else if (std.mem.startsWith(u8, vector.url, "memo://")) {
            const ts_str = vector.url[7..];
            fetch_path = std.fmt.bufPrint(&local_path_buf, "timeline/mems/{s}", .{ts_str}) catch "";
            is_local = true;
        }

        if (is_local and fetch_path.len > 0) {
            if (std.fs.cwd().openFile(fetch_path, .{})) |file| {
                if (file.readToEndAlloc(vector.allocator, 1024 * 1024 * 50)) |body| {
                    var final_body: []u8 = body;
                    
                    if (std.mem.indexOf(u8, body, "[@://nsible_os/")) |hdr_start| {
                        if (std.mem.indexOf(u8, body[hdr_start..], "}-.]\n\n")) |hdr_end_rel| {
                            const payload_start = hdr_start + hdr_end_rel + 6;
                            var payload_end = body.len;
                            
                            if (std.mem.lastIndexOf(u8, body, "}-.]")) |ftr_end| {
                                if (std.mem.lastIndexOf(u8, body[0..ftr_end], "\n\n")) |ftr_start| {
                                    if (ftr_start > payload_start) {
                                        payload_end = ftr_start;
                                    }
                                }
                            }
                            
                            if (payload_start < payload_end) {
                                if (vector.allocator.dupe(u8, body[payload_start..payload_end])) |clean_body| {
                                    vector.allocator.free(body);
                                    final_body = clean_body;
                                } else |_| {}
                            }
                        }
                    }

                    vector.result_payload = final_body;
                    vector.success = true;
                } else |_| { vector.success = false; }
                file.close();
            } else |_| { vector.success = false; }
            vector.is_complete = true;
            return;
        }

        const argv = [_][]const u8{ "curl", "-L", "-s", "-k", "-A", "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0", vector.url };
        var agent = ExternalAgent.init(&argv, vector.allocator); agent.stdout_behavior = .Pipe; agent.stderr_behavior = .Ignore;
        if (agent.spawn()) |_| { 
            if (agent.stdout) |stdout| { 
                if (stdout.readToEndAlloc(vector.allocator, 1024 * 1024 * 2)) |body| { 
                    _ = agent.wait() catch {}; vector.result_payload = body; vector.success = true; 
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
            var node = TimelineNode{ .rail_pos = 0, .obj_id = 0, .phi_stamp = 0, .color_id = 0, .color_fx = 0, .is_open = false, .is_dirty = false, .uri = undefined };
            
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
            if (self.philote_map.get(node.uri)) |w| {
                weight_px += @as(usize, @intCast(w));
                if (weight_px > 30) weight_px = 30; // Hard cap
            }
            
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

        if (self.active) {
            var sx: usize = width - 180;
            const sy: usize = height - 15; var status_buf: [64]u8 = undefined;
            const scope_str = switch (self.lens.focus_depth) { 0 => "[RAW]", 1 => "[ZEN]", 2 => "[MATRIX]", 3 => "[ROOT]", else => "[?]" };
            const final_status = std.fmt.bufPrint(&status_buf, "{s} {s}", .{self.status, scope_str}) catch self.status;
            
            var status_col: u32 = codex.get("C.S");
            if (std.mem.indexOf(u8, self.status, "VOID") != null) {
                status_col = codex.get("K.H");
            } else if (std.mem.indexOf(u8, self.status, "FETCHING") != null or std.mem.indexOf(u8, self.status, "PIPING") != null) {
                status_col = codex.get("B.S");
            }
            
            for (final_status) |c| { 
                drawCharToBuf(buffer, width, height, sx, sy, c, status_col); sx += 8; 
            }
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
