// [@://nsible_os/src/d_angel.zig/.-={
// module: "aud.io"
// version: "2.0.10"
// description: "高爪 Audio Visualizer & Autonomous Media Engine"
// changes: "Injected strict terminal flush on track transition to eliminate browser ghosting."
// philotic_inferences: "The matrix must be purged completely before a new state can be rendered to prevent buffer collisions."

const std = @import("std");
const c = @cImport({
    @cInclude("angel_a.h");
});

const winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};
const TIOCGWINSZ = 0x5413;

extern "c" fn ioctl(fd: i32, request: usize, ...) i32;

const VisConfig = struct {
    wave_high: []const u8 = "\x1b[91m█\x1b[0m", 
    wave_mid:  []const u8 = "\x1b[33m▆\x1b[0m",
    wave_low:  []const u8 = "\x1b[37m▃\x1b[0m",
    
    floor_shallow_char:  []const u8 = "\x1b[37m░\x1b[0m",
    floor_shallow_depth: f32 = 0.1,
    floor_deep_char:     []const u8 = "\x1b[90m·\x1b[0m",
    floor_deep_depth:    f32 = 0.3,
    
    thresh_high: f32 = 0.7,
    thresh_mid:  f32 = 0.4,
};

const AppMode = enum {
    BROWSER,
    PLAYER,
};

const FileEntry = struct {
    name: []const u8,
    is_dir: bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const cfg = VisConfig{};

    const orig_term = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
    var raw_term = orig_term;
    raw_term.lflag.ICANON = false;
    raw_term.lflag.ECHO = false;
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw_term);
    defer std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, orig_term) catch {};

    var engine: c.ma_engine = undefined;
    if (c.ma_engine_init(null, &engine) != c.MA_SUCCESS) return;
    defer c.ma_engine_uninit(&engine);
    
    const engine_sr = c.ma_engine_get_sample_rate(&engine);

    var pfd = [_]std.posix.pollfd{
        .{ .fd = std.posix.STDIN_FILENO, .events = std.posix.POLL.IN, .revents = 0 },
    };

    var stdout_buf: [65536]u8 = undefined;
    var writer_inst = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &writer_inst.interface;

    try stdout.writeAll("\x1b[?25l\x1b[2J");
    try stdout.flush();
    defer {
        stdout.writeAll("\x1b[?25h\x1b[2J\x1b[H") catch {};
        stdout.flush() catch {};
    }

    var app_mode = AppMode.BROWSER;
    var running = true;
    
    var current_path: std.ArrayList(u8) = .empty;
    defer current_path.deinit(allocator);
    try current_path.appendSlice(allocator, "/home/static/Music");

    var browser_cursor: usize = 0;
    var browser_scroll: usize = 0;
    
    var active_playlist: std.ArrayList([]const u8) = .empty;
    defer {
        for (active_playlist.items) |path| allocator.free(path);
        active_playlist.deinit(allocator);
    }
    var active_track_idx: usize = 0;

    var global_vol: f32 = 0.6;
    var vis_mode: usize = 0;
    const num_vis_modes = 4;
    const vis_names = [_][]const u8{ "SINE WAVE", "PULSE CENTER", "CHAOS BANDS", "HORIZON" };

    while (running) {
        
        if (app_mode == .BROWSER) {
            // FIX: Hard flush when re-entering the BROWSER state
            try stdout.writeAll("\x1b[2J\x1b[H"); 
            try stdout.flush();
            
            var ws = winsize{ .ws_row = 24, .ws_col = 80, .ws_xpixel = 0, .ws_ypixel = 0 };
            _ = ioctl(std.posix.STDOUT_FILENO, TIOCGWINSZ, &ws);
            const term_w = if (ws.ws_col > 20) @as(usize, ws.ws_col) else 80;
            const term_h = if (ws.ws_row > 10) @as(usize, ws.ws_row) else 24;

            var entries: std.ArrayList(FileEntry) = .empty;
            defer {
                for (entries.items) |e| allocator.free(e.name);
                entries.deinit(allocator);
            }

            var dir = std.fs.openDirAbsolute(current_path.items, .{ 
                .iterate = true,
                .no_follow = false 
            }) catch null;

            if (dir) |*d| {
                var it = d.iterate();
                while (it.next() catch null) |entry| {
                    const is_dir_like = (entry.kind == .directory or entry.kind == .sym_link);
                    const is_mp3 = std.mem.endsWith(u8, entry.name, ".mp3");

                    if (is_dir_like or is_mp3) {
                        const name_dup = allocator.dupe(u8, entry.name) catch continue;
                        try entries.append(allocator, .{ 
                            .name = name_dup, 
                            .is_dir = is_dir_like 
                        });
                    }
                }
                d.close();
            }

            std.sort.block(FileEntry, entries.items, {}, struct {
                fn lessThan(context: void, lhs: FileEntry, rhs: FileEntry) bool {
                    _ = context;
                    if (lhs.is_dir and !rhs.is_dir) return true;
                    if (!lhs.is_dir and rhs.is_dir) return false;
                    return std.mem.lessThan(u8, lhs.name, rhs.name);
                }
            }.lessThan);

            if (browser_cursor >= entries.items.len) browser_cursor = if (entries.items.len > 0) entries.items.len - 1 else 0;

            const max_display = if (term_h > 10) term_h - 10 else 2;
            if (browser_cursor < browser_scroll) browser_scroll = browser_cursor;
            if (browser_cursor >= browser_scroll + max_display) browser_scroll = browser_cursor - max_display + 1;

            try stdout.writeAll("\x1b[H");
            
            const header_txt = " 高爪 @://aud.nsible.io [ INDEXER ] ";
            const pad_len = if (term_w > header_txt.len + 6) (term_w - header_txt.len - 6) / 2 else 2;
            try stdout.print("\x1b[91m[ ", .{});
            for (0..pad_len) |_| try stdout.writeAll("=");
            try stdout.print("{s}", .{header_txt});
            for (0..pad_len) |_| try stdout.writeAll("=");
            try stdout.print(" ]\x1b[K\n\n\x1b[0m", .{});

            try stdout.print("\x1b[37m  [ PATH ]\x1b[0m :: \x1b[33m{s}\x1b[0m\x1b[K\n\n", .{current_path.items});

            if (entries.items.len == 0) {
                try stdout.print("  \x1b[90m... No media found in this sector ...\x1b[0m\x1b[K\n", .{});
                for (0..max_display - 1) |_| try stdout.writeAll("\x1b[K\n");
            } else {
                for (0..max_display) |i| {
                    const idx = browser_scroll + i;
                    if (idx < entries.items.len) {
                        const e = entries.items[idx];
                        const cursor_char = if (idx == browser_cursor) "\x1b[91m>\x1b[0m" else " ";
                        if (e.is_dir) {
                            try stdout.print("  {s} \x1b[33m[{s}]\x1b[0m\x1b[K\n", .{cursor_char, e.name});
                        } else {
                            try stdout.print("  {s} \x1b[37m{s}\x1b[0m\x1b[K\n", .{cursor_char, e.name});
                        }
                    } else {
                        try stdout.writeAll("\x1b[K\n");
                    }
                }
            }

            try stdout.print("\n\x1b[37m  [ CMD  ]\x1b[0m :: \x1b[91m[w|s]\x1b[0m Nav | \x1b[91m[Ent]\x1b[0m In/Play | \x1b[91m[p|x]\x1b[0m Play/Shfl All | \x1b[91m[m]\x1b[0m Media | \x1b[91m[b]\x1b[0m Back | \x1b[91m[q]\x1b[0m Quit\x1b[K", .{});
            try stdout.print("\x1b[J", .{}); 
            try stdout.flush();

            const ready = std.posix.poll(&pfd, 0) catch 0;
            if (ready > 0 and (pfd[0].revents & std.posix.POLL.IN) != 0) {
                var buf: [16]u8 = undefined;
                const amt = std.posix.read(std.posix.STDIN_FILENO, &buf) catch 0;
                if (amt > 0) {
                    const cmd = buf[0];
                    if (cmd == 'w' and browser_cursor > 0) {
                        browser_cursor -= 1;
                    } else if (cmd == 's' and entries.items.len > 0 and browser_cursor < entries.items.len - 1) {
                        browser_cursor += 1;
                    } else if (cmd == 'b') {
                        if (std.fs.path.dirname(current_path.items)) |parent| {
                            current_path.clearRetainingCapacity();
                            try current_path.appendSlice(allocator, parent);
                            browser_cursor = 0;
                            browser_scroll = 0;
                        }
                    } else if (cmd == 'm') {
                        const mount_cmd = "for b in $(lsblk -rno PATH,TYPE,MOUNTPOINT | awk '$2==\"part\" && $3==\"\" {print $1}'); do udisksctl mount -b $b >/dev/null 2>&1 || true; done";
                        const res = std.process.Child.run(.{
                            .allocator = allocator,
                            .argv = &[_][]const u8{ "sh", "-c", mount_cmd },
                        }) catch null;
                        if (res) |r| {
                            allocator.free(r.stdout);
                            allocator.free(r.stderr);
                        }

                        current_path.clearRetainingCapacity();
                        try current_path.appendSlice(allocator, "/media");
                        browser_cursor = 0;
                        browser_scroll = 0;
                    } else if (cmd == 'p' or cmd == 'x') {
                        for (active_playlist.items) |path| allocator.free(path);
                        active_playlist.clearRetainingCapacity();

                        for (entries.items) |e| {
                            if (!e.is_dir) {
                                const full_path = try std.fs.path.join(allocator, &[_][]const u8{ current_path.items, e.name });
                                try active_playlist.append(allocator, full_path);
                            }
                        }

                        if (active_playlist.items.len > 0) {
                            if (cmd == 'x') {
                                std.crypto.random.shuffle([]const u8, active_playlist.items);
                            }
                            active_track_idx = 0;
                            app_mode = .PLAYER;
                        }
                    } else if (cmd == '\n' or cmd == '\r') {
                        if (entries.items.len > 0) {
                            const selected = entries.items[browser_cursor];
                            if (selected.is_dir) {
                                const new_path = try std.fs.path.join(allocator, &[_][]const u8{ current_path.items, selected.name });
                                current_path.clearRetainingCapacity();
                                try current_path.appendSlice(allocator, new_path);
                                allocator.free(new_path);
                                browser_cursor = 0;
                                browser_scroll = 0;
                            } else {
                                for (active_playlist.items) |path| allocator.free(path);
                                active_playlist.clearRetainingCapacity();
                                const new_file = try std.fs.path.join(allocator, &[_][]const u8{ current_path.items, selected.name });
                                try active_playlist.append(allocator, new_file);
                                active_track_idx = 0;
                                app_mode = .PLAYER; 
                            }
                        }
                    } else if (cmd == 'q') {
                        running = false;
                    }
                }
            }
            std.Thread.sleep(20 * std.time.ns_per_ms);
        }

        // PLAYER STATE
        if (app_mode == .PLAYER) {
            // FIX: Hard flush immediately upon entering the PLAYER state for a new track
            try stdout.writeAll("\x1b[2J\x1b[H"); 
            try stdout.flush();
            
            var sound: c.ma_sound = undefined;
            const current_track = active_playlist.items[active_track_idx];
            const track_c = try allocator.dupeZ(u8, current_track);
            defer allocator.free(track_c);

            if (c.ma_sound_init_from_file(&engine, track_c.ptr, 0, null, null, &sound) != c.MA_SUCCESS) {
                active_track_idx += 1;
                if (active_track_idx >= active_playlist.items.len) app_mode = .BROWSER;
                continue;
            }
            defer c.ma_sound_uninit(&sound);

            var v_decoder: c.ma_decoder = undefined;
            var v_config = c.ma_decoder_config_init(c.ma_format_f32, 1, engine_sr); 
            const has_vis = (c.ma_decoder_init_file(track_c.ptr, &v_config, &v_decoder) == c.MA_SUCCESS);
            
            defer {
                if (has_vis) _ = c.ma_decoder_uninit(&v_decoder);
            }

            _ = c.ma_sound_set_volume(&sound, global_vol);
            _ = c.ma_sound_start(&sound);

            const filename = std.fs.path.basename(current_track);
            var length_pcm: c.ma_uint64 = 1;
            _ = c.ma_sound_get_length_in_pcm_frames(&sound, &length_pcm);

            var smooth_peak: f32 = 0.0;
            var smooth_bass: f32 = 0.0;
            var smooth_mid: f32 = 0.0;
            var smooth_treb: f32 = 0.0;
            var lf_sample_state: f32 = 0.0;
            var last_sample: f32 = 0.0;
            var is_paused = false;

            while (c.ma_sound_at_end(&sound) == c.MA_FALSE or is_paused) {
                if (app_mode != .PLAYER or !running) break;

                var ws = winsize{ .ws_row = 24, .ws_col = 80, .ws_xpixel = 0, .ws_ypixel = 0 };
                _ = ioctl(std.posix.STDOUT_FILENO, TIOCGWINSZ, &ws);
                const term_w = if (ws.ws_col > 20) @as(usize, ws.ws_col) else 80;
                const term_h = if (ws.ws_row > 10) @as(usize, ws.ws_row) else 24;

                var cursor_pcm: c.ma_uint64 = 0;
                _ = c.ma_sound_get_cursor_in_pcm_frames(&sound, &cursor_pcm);
                const progress = if (length_pcm > 0) @as(f32, @floatFromInt(cursor_pcm)) / @as(f32, @floatFromInt(length_pcm)) else 0.0;
                
                var current_peak: f32 = 0.0;
                var current_bass: f32 = 0.0;
                var current_mid: f32 = 0.0;
                var current_treb: f32 = 0.0;

                if (has_vis and !is_paused) {
                    var pcm_buffer: [4096]f32 = undefined;
                    var frames_read: c.ma_uint64 = 0;
                    _ = c.ma_decoder_seek_to_pcm_frame(&v_decoder, cursor_pcm);
                    _ = c.ma_decoder_read_pcm_frames(&v_decoder, &pcm_buffer, 4096, &frames_read);
                    for (0..@as(usize, @intCast(frames_read))) |i| {
                        const s = pcm_buffer[i];
                        const abs_s = @abs(s);
                        if (abs_s > current_peak) current_peak = abs_s;
                        lf_sample_state += (s - lf_sample_state) * 0.08;
                        if (@abs(lf_sample_state) > current_bass) current_bass = @abs(lf_sample_state);
                        const diff = s - last_sample;
                        if (@abs(diff) > current_treb) current_treb = @abs(diff);
                        const mid_val = s - lf_sample_state - (diff * 0.5);
                        if (@abs(mid_val) > current_mid) current_mid = @abs(mid_val);
                        last_sample = s;
                    }
                }

                if (is_paused) {
                    smooth_peak = 0.0; smooth_bass = 0.0; smooth_mid = 0.0; smooth_treb = 0.0;
                } else {
                    smooth_peak += (current_peak - smooth_peak) * if (current_peak > smooth_peak) @as(f32, 0.88) else @as(f32, 0.42);
                    smooth_bass += (current_bass - smooth_bass) * if (current_bass > smooth_bass) @as(f32, 0.85) else @as(f32, 0.35);
                    smooth_mid  += (current_mid  - smooth_mid)  * if (current_mid  > smooth_mid)  @as(f32, 0.88) else @as(f32, 0.40);
                    smooth_treb += (current_treb - smooth_treb) * if (current_treb > smooth_treb) @as(f32, 0.92) else @as(f32, 0.50);
                }

                try stdout.writeAll("\x1b[H"); 
                try stdout.print("\x1b[91m[ ", .{});
                const header_txt_p = " 高爪 @://aud.nsible.io  高高";
                const pad_len_p = if (term_w > header_txt_p.len + 6) (term_w - header_txt_p.len - 6) / 2 else 2;
                for (0..pad_len_p) |_| try stdout.writeAll("=");
                try stdout.print("{s}", .{header_txt_p});
                for (0..pad_len_p) |_| try stdout.writeAll("=");
                try stdout.print(" ]\x1b[K\n\n\x1b[0m", .{});
                try stdout.print("\x1b[37m  [ FILE ]\x1b[0m :: \x1b[33m{s}\x1b[0m\x1b[K\n", .{filename});
                try stdout.print("\x1b[37m  [ VOL  ]\x1b[0m :: \x1b[33m{d:.1}\x1b[0m\x1b[K\n", .{global_vol});
                try stdout.print("\x1b[37m  [ VIS  ]\x1b[0m :: \x1b[33m{s}\x1b[0m\x1b[K\n\n", .{vis_names[vis_mode]});

                const vis_height = if (term_h > 14) term_h - 14 else 2;
                const vis_width = if (term_w > 4) term_w - 4 else 2;
                
                for (0..vis_height) |row| {
                    try stdout.writeAll("  ");
                    for (0..vis_width) |col| {
                        const time_t = @as(f32, @floatFromInt(cursor_pcm)) / @as(f32, @floatFromInt(engine_sr));
                        const col_f = @as(f32, @floatFromInt(col));
                        const width_f = @as(f32, @floatFromInt(vis_width));
                        const center_dist = @abs((col_f / width_f) - 0.5) * 2.0;
                        const freq_react = 1.0 - (center_dist * 0.5); 
                        var wave_val: f32 = 0.0;
                        switch (vis_mode) {
                            0 => {
                                const eq_val = (@sin(time_t * 18.0 + col_f * 0.15) + 1.0) * 0.5;
                                wave_val = ((eq_val * 0.2) + (freq_react * 0.8)) * @min((smooth_peak * 0.5) + (smooth_bass * 1.5), 1.0);
                            },
                            1 => {
                                const block_width = smooth_bass * smooth_bass * 2.0;
                                const in_block = if (center_dist < block_width) @as(f32, 1.0) else @as(f32, 0.0);
                                wave_val = in_block * 0.8 * @min(smooth_peak * 1.5, 1.0);
                            },
                            2 => {
                                const eq_val = (@sin(col_f * 0.8 + time_t * 25.0) + @cos(col_f * 0.4 - time_t * 10.0) + 2.0) * 0.25;
                                wave_val = ((eq_val * 0.6) + (freq_react * 0.4)) * @min(smooth_mid * 1.8, 1.0);
                            },
                            3 => {
                                const eq_val = (@sin(time_t * 8.0 + col_f * 0.02) + 1.0) * 0.5;
                                wave_val = ((eq_val * 0.2) + 0.1) * @min(smooth_bass * 2.2, 1.0);
                            },
                            else => {}
                        }
                        const threshold = @as(f32, @floatFromInt(vis_height - row)) / @as(f32, @floatFromInt(vis_height));
                        if (wave_val > threshold) {
                            if (threshold > cfg.thresh_high) try stdout.writeAll(cfg.wave_high) 
                            else if (threshold > cfg.thresh_mid) try stdout.writeAll(cfg.wave_mid) 
                            else try stdout.writeAll(cfg.wave_low); 
                        } else {
                            const depth = threshold - wave_val;
                            if (depth < cfg.floor_shallow_depth) try stdout.writeAll(cfg.floor_shallow_char) 
                            else if (depth < cfg.floor_deep_depth) try stdout.writeAll(cfg.floor_deep_char) 
                            else try stdout.writeAll(" ");
                        }
                    }
                    try stdout.writeAll("\x1b[K\n");
                }

                try stdout.writeAll("\n");
                const bar_width = if (term_w > 12) term_w - 12 else 10;
                const filled = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(bar_width))));
                if (is_paused) {
                    try stdout.print("  \x1b[91m[\x1b[0m \x1b[33m| PAUSED |\x1b[0m ", .{});
                    for (0..if (bar_width > 11) bar_width - 11 else 0) |_| try stdout.writeAll("\x1b[90m▓\x1b[0m");
                } else {
                    try stdout.print("  \x1b[91m[\x1b[0m ", .{});
                    for (0..bar_width) |i| try stdout.writeAll(if (i < filled) "\x1b[91m█\x1b[0m" else "\x1b[90m▓\x1b[0m");
                }
                try stdout.print(" \x1b[91m]\x1b[0m \x1b[37m{d:0>2}%\x1b[0m\x1b[K\n\n", .{@as(usize, @intFromFloat(progress * 100.0))});
                try stdout.print("\x1b[37m  [ CMD  ]\x1b[0m :: \x1b[91m[r]\x1b[0m Rstrt | \x1b[91m[z]\x1b[0m Vis | \x1b[91m[+|-]\x1b[0m Vol | \x1b[91m[Spc]\x1b[0m Play | \x1b[91m[Ent]\x1b[0m Skip | \x1b[91m[b]\x1b[0m Browse | \x1b[91m[q]\x1b[0m Quit\x1b[K", .{});
                try stdout.print("\x1b[J", .{}); 
                try stdout.flush();

                const ready = std.posix.poll(&pfd, 0) catch 0;
                if (ready > 0 and (pfd[0].revents & std.posix.POLL.IN) != 0) {
                    var buf: [16]u8 = undefined;
                    const amt = std.posix.read(std.posix.STDIN_FILENO, &buf) catch 0;
                    if (amt > 0) {
                        const cmd = buf[0];
                        if (cmd == '+') { global_vol = @min(global_vol + 0.1, 1.5); _ = c.ma_sound_set_volume(&sound, global_vol); }
                        else if (cmd == '-') { global_vol = @max(global_vol - 0.1, 0.0); _ = c.ma_sound_set_volume(&sound, global_vol); }
                        else if (cmd == ' ') { is_paused = !is_paused; if (is_paused) _ = c.ma_sound_stop(&sound) else _ = c.ma_sound_start(&sound); }
                        else if (cmd == 'z') vis_mode = (vis_mode + 1) % num_vis_modes
                        else if (cmd == 'r') _ = c.ma_sound_seek_to_pcm_frame(&sound, 0)
                        else if (cmd == '\n' or cmd == '\r') { _ = c.ma_sound_stop(&sound); break; }
                        else if (cmd == 'b') { _ = c.ma_sound_stop(&sound); app_mode = .BROWSER; break; }
                        else if (cmd == 'q') { _ = c.ma_sound_stop(&sound); running = false; break; }
                    }
                }
                std.Thread.sleep(60 * std.time.ns_per_ms);
            }
            if (app_mode == .PLAYER) {
                active_track_idx += 1;
                if (active_track_idx >= active_playlist.items.len) app_mode = .BROWSER;
            }
        }
    }
}
// }-.]
