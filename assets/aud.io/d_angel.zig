// [@://nsible_os/src/d_angel.zig/.-={
// module: "aud.io"
// version: "1.0.5"
// description: "Audio Player and Multi-Band Visualizer"
// changes: "Extracted visualizer UI elements into a VisConfig struct for rapid iteration."
// philotic_inferences: "Centralizing UI constants reduces friction during aesthetic evaluation."

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

// === [ UI CONFIGURATION ] ===
const VisConfig = struct {
    // Primary Operative Colors & Characters (@NSIBLE-RED focused)
    wave_high: []const u8 = "\x1b[91m█\x1b[0m", 
    wave_mid:  []const u8 = "\x1b[33m▆\x1b[0m",
    wave_low:  []const u8 = "\x1b[37m▃\x1b[0m",
    
    // Depth of Silence (Noise Floor)
    floor_shallow_char:  []const u8 = "\x1b[37m░\x1b[0m",
    floor_shallow_depth: f32 = 0.1,
    floor_deep_char:     []const u8 = "\x1b[90m·\x1b[0m",
    floor_deep_depth:    f32 = 0.3,
    
    // Wave rendering height thresholds
    thresh_high: f32 = 0.7,
    thresh_mid:  f32 = 0.4,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const cfg = VisConfig{};

    var engine: c.ma_engine = undefined;
    if (c.ma_engine_init(null, &engine) != c.MA_SUCCESS) return;
    defer c.ma_engine_uninit(&engine);

    var playlist: std.ArrayList([]const u8) = .empty;
    defer {
        for (playlist.items) |path| allocator.free(path);
        playlist.deinit(allocator);
    }

    const music_dir_path = "/home/static/Music";
    var dir = try std.fs.openDirAbsolute(music_dir_path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.basename, ".mp3")) {
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ music_dir_path, entry.path });
            try playlist.append(allocator, full_path);
        }
    }

    if (playlist.items.len == 0) return;

    std.crypto.random.shuffle([]const u8, playlist.items);

    var global_vol: f32 = 0.6;
    var running = true;
    
    var vis_mode: usize = 0;
    const num_vis_modes = 4;
    const vis_names = [_][]const u8{ "SINE WAVE", "PULSE CENTER", "CHAOS BANDS", "HORIZON" };

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

    for (playlist.items) |track| {
        if (!running) break;

        var sound: c.ma_sound = undefined;
        const track_c = try allocator.dupeZ(u8, track);
        defer allocator.free(track_c);

        if (c.ma_sound_init_from_file(&engine, track_c.ptr, 0, null, null, &sound) != c.MA_SUCCESS) continue;
        defer c.ma_sound_uninit(&sound);

        var v_decoder: c.ma_decoder = undefined;
        var v_config = c.ma_decoder_config_init(c.ma_format_f32, 1, 0); 
        const has_vis = (c.ma_decoder_init_file(track_c.ptr, &v_config, &v_decoder) == c.MA_SUCCESS);
        
        defer {
            if (has_vis) {
                _ = c.ma_decoder_uninit(&v_decoder);
            }
        }

        _ = c.ma_sound_set_volume(&sound, global_vol);
        _ = c.ma_sound_start(&sound);

        const filename = std.fs.path.basename(track);
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
            if (!running) break;

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
            
            const header_txt = " 高爪 @://aud.nsible.io  高高";
            const pad_len = if (term_w > header_txt.len + 6) (term_w - header_txt.len - 6) / 2 else 2;
            try stdout.print("\x1b[91m[ ", .{});
            for (0..pad_len) |_| try stdout.writeAll("=");
            try stdout.print("{s}", .{header_txt});
            for (0..pad_len) |_| try stdout.writeAll("=");
            try stdout.print(" ]\x1b[K\n\n\x1b[0m", .{});

            try stdout.print("\x1b[37m  [ FILE ]\x1b[0m :: \x1b[33m{s}\x1b[0m\x1b[K\n", .{filename});
            
            const vol_width = @min(20, term_w - 20);
            const vol_filled = @min(@as(usize, @intFromFloat((global_vol / 1.8) * @as(f32, @floatFromInt(vol_width)))), vol_width);
            try stdout.print("\x1b[37m  [ VOL  ]\x1b[0m :: \x1b[33m[\x1b[0m", .{});
            for (0..vol_width) |i| {
                if (i < vol_filled) try stdout.print("\x1b[91m#\x1b[0m", .{}) else try stdout.print("\x1b[90m-\x1b[0m", .{});
            }
            try stdout.print("\x1b[33m]\x1b[0m \x1b[37m{d:.1}\x1b[0m\x1b[K\n", .{global_vol});
            
            try stdout.print("\x1b[37m  [ VIS  ]\x1b[0m :: \x1b[33m{s}\x1b[0m\x1b[K\n\n", .{vis_names[vis_mode]});

            const vis_height = if (term_h > 15) term_h - 15 else 2;
            const vis_width = term_w - 4;
            const vol_scale = (global_vol / 1.5);
            
            for (0..vis_height) |row| {
                try stdout.writeAll("  ");
                for (0..vis_width) |col| {
                    const time_t = @as(f32, @floatFromInt(cursor_pcm)) / 44100.0;
                    const col_f = @as(f32, @floatFromInt(col));
                    const width_f = @as(f32, @floatFromInt(vis_width));
                    
                    const center_dist = @abs((col_f / width_f) - 0.5) * 2.0;
                    const freq_react = 1.0 - (center_dist * 0.5); 
                    const noise = std.crypto.random.float(f32) * 0.05; 
                    
                    var wave_val: f32 = 0.0;

                    switch (vis_mode) {
                        0 => {
                            const eq_val = (@sin(time_t * 18.0 + col_f * 0.15) + 1.0) * 0.5;
                            const level = @min((smooth_peak * 0.5) + (smooth_bass * 1.5), 1.0) * vol_scale * 2.0;
                            wave_val = ((eq_val * 0.2) + (freq_react * 0.8) + noise) * level * level;
                        },
                        1 => {
                            const block_width = smooth_bass * smooth_bass * 2.0;
                            const in_block = if (center_dist < block_width) @as(f32, 1.0) else @as(f32, 0.0);
                            const scatter = if (center_dist > block_width) smooth_treb * 2.5 else 0.0;
                            wave_val = ((in_block * 0.8) + (scatter * noise * 4.0)) * vol_scale * 2.0;
                        },
                        2 => {
                            const eq_val = (@sin(col_f * 0.8 + time_t * 25.0) + @cos(col_f * 0.4 - time_t * 10.0) + 2.0) * 0.25;
                            const level = @min(smooth_mid * 1.8, 1.0) * vol_scale * 2.0;
                            const spike = smooth_treb * noise * 5.0;
                            wave_val = ((eq_val * 0.6) + (freq_react * 0.4) + spike) * level * level;
                        },
                        3 => {
                            const eq_val = (@sin(time_t * 8.0 + col_f * 0.02) + 1.0) * 0.5;
                            const level = @min(smooth_bass * 2.2, 1.0) * vol_scale * 2.5;
                            wave_val = ((eq_val * 0.1) + 0.9 + noise) * level * level;
                        },
                        else => {}
                    }
                    
                    const threshold = @as(f32, @floatFromInt(vis_height - row)) / @as(f32, @floatFromInt(vis_height));
                    
                    if (wave_val > threshold) {
                        if (threshold > cfg.thresh_high) {
                            try stdout.writeAll(cfg.wave_high); 
                        } else if (threshold > cfg.thresh_mid) {
                            try stdout.writeAll(cfg.wave_mid); 
                        } else {
                            try stdout.writeAll(cfg.wave_low); 
                        }
                    } else {
                        const depth = threshold - wave_val;
                        if (depth < cfg.floor_shallow_depth) {
                            try stdout.writeAll(cfg.floor_shallow_char); 
                        } else if (depth < cfg.floor_deep_depth) {
                            try stdout.writeAll(cfg.floor_deep_char); 
                        } else {
                            try stdout.writeAll(" ");
                        }
                    }
                }
                try stdout.writeAll("\x1b[K\n");
            }
            try stdout.writeAll("\n");

            const bar_width = term_w - 12;
            const filled = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(bar_width))));
            
            if (is_paused) {
                 try stdout.print("  \x1b[91m[\x1b[0m \x1b[33m| PAUSED |\x1b[0m ", .{});
                 for (0..bar_width - 11) |_| try stdout.print("\x1b[90m▓\x1b[0m", .{});
            } else {
                try stdout.print("  \x1b[91m[\x1b[0m ", .{});
                for (0..bar_width) |i| {
                    if (i < filled) try stdout.print("\x1b[91m█\x1b[0m", .{}) else try stdout.print("\x1b[90m▓\x1b[0m", .{});
                }
            }
            try stdout.print(" \x1b[91m]\x1b[0m \x1b[37m{d:0>2}%\x1b[0m\x1b[K\n\n", .{@as(usize, @intFromFloat(progress * 100.0))});

            try stdout.print("\x1b[37m  [ CMD  ]\x1b[0m :: \x1b[91m[r]\x1b[0m Rstrt | \x1b[91m[z]\x1b[0m Vis | \x1b[91m[+|-]\x1b[0m Vol | \x1b[91m[Spc]\x1b[0m Play | \x1b[91m[Ent]\x1b[0m Skip | \x1b[91m[q]\x1b[0m Quit\x1b[K\n", .{});
            try stdout.print("\x1b[J", .{}); 
            
            try stdout.flush();

            const ready = std.posix.poll(&pfd, 0) catch 0;
            if (ready > 0 and (pfd[0].revents & std.posix.POLL.IN) != 0) {
                var buf: [16]u8 = undefined;
                const amt = std.posix.read(std.posix.STDIN_FILENO, &buf) catch 0;
                if (amt > 0) {
                    const cmd = buf[0];
                    if (cmd == '+') {
                        global_vol = @min(global_vol + 0.1, 1.5);
                        _ = c.ma_sound_set_volume(&sound, global_vol);
                    } else if (cmd == '-') {
                        global_vol = @max(global_vol - 0.1, 0.0);
                        _ = c.ma_sound_set_volume(&sound, global_vol);
                    } else if (cmd == ' ') { 
                        is_paused = !is_paused;
                        if (is_paused) {
                            _ = c.ma_sound_stop(&sound);
                        } else {
                            _ = c.ma_sound_start(&sound);
                        }
                    } else if (cmd == 'z') {
                        vis_mode = (vis_mode + 1) % num_vis_modes;
                    } else if (cmd == 'r') {
                        _ = c.ma_sound_seek_to_pcm_frame(&sound, 0);
                    } else if (cmd == '\n' or cmd == '\r') {
                        _ = c.ma_sound_stop(&sound);
                        break;
                    } else if (cmd == 'q') {
                        running = false;
                        _ = c.ma_sound_stop(&sound);
                        break;
                    }
                }
            }
            std.Thread.sleep(60 * std.time.ns_per_ms);
        }
    }
}
// }-.]
