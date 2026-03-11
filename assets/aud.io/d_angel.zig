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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

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

        // SHADOW SENSOR: Initialize secondary decoder to read raw PCM for the visualizer
        var v_decoder: c.ma_decoder = undefined;
        var v_config = c.ma_decoder_config_init(c.ma_format_f32, 1, 44100); 
        const has_vis = (c.ma_decoder_init_file(track_c.ptr, &v_config, &v_decoder) == c.MA_SUCCESS);
        defer if (has_vis) c.ma_decoder_uninit(&v_decoder);

        _ = c.ma_sound_set_volume(&sound, global_vol);
        _ = c.ma_sound_start(&sound);

        const filename = std.fs.path.basename(track);
        var length_pcm: c.ma_uint64 = 1;
        _ = c.ma_sound_get_length_in_pcm_frames(&sound, &length_pcm);

        var last_cursor: c.ma_uint64 = 0;
        var smooth_peak: f32 = 0.0;

        while (c.ma_sound_at_end(&sound) == c.MA_FALSE) {
            if (!running) break;

            var ws = winsize{ .ws_row = 24, .ws_col = 80, .ws_xpixel = 0, .ws_ypixel = 0 };
            _ = ioctl(std.posix.STDOUT_FILENO, TIOCGWINSZ, &ws);
            
            const term_w = if (ws.ws_col > 20) @as(usize, ws.ws_col) else 80;
            const term_h = if (ws.ws_row > 10) @as(usize, ws.ws_row) else 24;

            var cursor_pcm: c.ma_uint64 = 0;
            _ = c.ma_sound_get_cursor_in_pcm_frames(&sound, &cursor_pcm);
            const progress = if (length_pcm > 0) @as(f32, @floatFromInt(cursor_pcm)) / @as(f32, @floatFromInt(length_pcm)) else 0.0;
            
            // TRUE SIGNAL EXTRACTION
            var current_peak: f32 = 0.0;
            const delta_frames = if (cursor_pcm > last_cursor) cursor_pcm - last_cursor else 0;
            last_cursor = cursor_pcm;

            if (has_vis and delta_frames > 0) {
                const read_count = @min(delta_frames, 4096);
                var pcm_buffer: [4096]f32 = undefined;
                var frames_read: c.ma_uint64 = 0;
                
                _ = c.ma_decoder_read_pcm_frames(&v_decoder, &pcm_buffer, read_count, &frames_read);
                
                var max_amp: f32 = 0.0;
                for (0..@as(usize, @intCast(frames_read))) |i| {
                    // FIX: Replaced std.math.fabs with the @abs built-in
                    const amp = @abs(pcm_buffer[i]);
                    if (amp > max_amp) max_amp = amp;
                }
                current_peak = max_amp;
                
                if (delta_frames > 4096) {
                    _ = c.ma_decoder_seek_to_pcm_frame(&v_decoder, cursor_pcm);
                }
            }

            // ENVELOPE FOLLOWER
            if (current_peak > smooth_peak) {
                smooth_peak += (current_peak - smooth_peak) * 0.45;
            } else {
                smooth_peak += (current_peak - smooth_peak) * 0.15;
            }

            try stdout.writeAll("\x1b[H"); 
            
            const header_txt = " 高爪 @NSIBLE ENGINE ";
            const pad_len = if (term_w > header_txt.len + 6) (term_w - header_txt.len - 6) / 2 else 2;
            try stdout.print("\x1b[91m[ ", .{});
            for (0..pad_len) |_| try stdout.writeAll("=");
            try stdout.print("{s}", .{header_txt});
            for (0..pad_len) |_| try stdout.writeAll("=");
            try stdout.print(" ]\x1b[K\n\n\x1b[0m", .{});

            try stdout.print("\x1b[37m  [ FILE ]\x1b[0m :: \x1b[33m{s}\x1b[0m\x1b[K\n", .{filename});
            
            const vol_width = @min(20, term_w - 20);
            const vol_filled = @min(@as(usize, @intFromFloat((global_vol / 1.5) * @as(f32, @floatFromInt(vol_width)))), vol_width);
            try stdout.print("\x1b[37m  [ VOL  ]\x1b[0m :: \x1b[33m[\x1b[0m", .{});
            for (0..vol_width) |i| {
                if (i < vol_filled) try stdout.print("\x1b[91m#\x1b[0m", .{}) else try stdout.print("\x1b[90m-\x1b[0m", .{});
            }
            try stdout.print("\x1b[33m]\x1b[0m \x1b[37m{d:.1}\x1b[0m\x1b[K\n\n", .{global_vol});

            // ADAPTIVE MATRIX VISUALIZER
            const vis_height = if (term_h > 14) term_h - 14 else 2;
            const vis_width = term_w - 4;
            const audio_level = @min(smooth_peak * 2.0, 1.0);
            
            for (0..vis_height) |row| {
                try stdout.writeAll("  ");
                for (0..vis_width) |col| {
                    const time_t = @as(f32, @floatFromInt(cursor_pcm)) / 44100.0;
                    const col_f = @as(f32, @floatFromInt(col));
                    const width_f = @as(f32, @floatFromInt(vis_width));
                    
                    // FIX: Replaced std.math.fabs with @abs
                    const center_dist = @abs((col_f / width_f) - 0.5) * 2.0;
                    const freq_react = 1.0 - (center_dist * 0.4); 
                    
                    // FIX: Replaced std.math.sin with @sin
                    const eq_val = (@sin(time_t * 12.0 + col_f * 0.3) + 1.0) * 0.5;
                    const noise = std.crypto.random.float(f32);
                    
                    const wave_val = ((eq_val * 0.2 + noise * 0.2) + (audio_level * freq_react * 0.8)) * (global_vol / 1.5);
                    const threshold = @as(f32, @floatFromInt(vis_height - row)) / @as(f32, @floatFromInt(vis_height));
                    
                    if (wave_val > threshold) {
                        if (threshold > 0.7) {
                            try stdout.writeAll("\x1b[91m█\x1b[0m"); 
                        } else if (threshold > 0.4) {
                            try stdout.writeAll("\x1b[33m▆\x1b[0m"); 
                        } else {
                            try stdout.writeAll("\x1b[37m▃\x1b[0m"); 
                        }
                    } else {
                        try stdout.writeAll(" ");
                    }
                }
                try stdout.writeAll("\x1b[K\n");
            }
            try stdout.writeAll("\n");

            const bar_width = term_w - 12;
            const filled = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(bar_width))));
            try stdout.print("  \x1b[91m[\x1b[0m ", .{});
            for (0..bar_width) |i| {
                if (i < filled) try stdout.print("\x1b[91m█\x1b[0m", .{}) else try stdout.print("\x1b[90m▓\x1b[0m", .{});
            }
            try stdout.print(" \x1b[91m]\x1b[0m \x1b[37m{d:0>2}%\x1b[0m\x1b[K\n\n", .{@as(usize, @intFromFloat(progress * 100.0))});

            try stdout.print("\x1b[37m  [ CMD  ]\x1b[0m :: \x1b[91m[+]\x1b[0m Up | \x1b[91m[-]\x1b[0m Down | \x1b[91m[Enter]\x1b[0m Skip | \x1b[91m[q]\x1b[0m Quit\x1b[K\n", .{});
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
