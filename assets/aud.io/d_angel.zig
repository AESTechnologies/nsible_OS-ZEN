const std = @import("std");
const c = @cImport({
    @cInclude("angel_a.h");
});

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

    const stdout = std.io.getStdOut().writer();

    // TUI Init: Hide cursor and clear screen
    _ = stdout.write("\x1b[?25l\x1b[2J") catch {};
    defer _ = stdout.write("\x1b[?25h\x1b[2J\x1b[H") catch {}; // Restore on exit

    for (playlist.items) |track| {
        if (!running) break;

        var sound: c.ma_sound = undefined;
        const track_c = try allocator.dupeZ(u8, track);
        defer allocator.free(track_c);

        if (c.ma_sound_init_from_file(&engine, track_c.ptr, 0, null, null, &sound) != c.MA_SUCCESS) continue;
        defer c.ma_sound_uninit(&sound);

        _ = c.ma_sound_set_volume(&sound, global_vol);
        _ = c.ma_sound_start(&sound);

        const filename = std.fs.path.basename(track);
        var length_pcm: c.ma_uint64 = 1; 
        _ = c.ma_sound_get_length_in_pcm_frames(&sound, &length_pcm);

        while (c.ma_sound_at_end(&sound) == c.MA_FALSE) {
            if (!running) break;

            // Math: Playback Progress
            var cursor_pcm: c.ma_uint64 = 0;
            _ = c.ma_sound_get_cursor_in_pcm_frames(&sound, &cursor_pcm);
            const progress = if (length_pcm > 0) @as(f32, @floatFromInt(cursor_pcm)) / @as(f32, @floatFromInt(length_pcm)) else 0.0;
            
            // Frame Render: Home Cursor (\x1b[H) to prevent flicker
            try stdout.print("\x1b[H\x1b[91m[ ==================== 高爪 AUDIO ENGINE ==================== ]\x1b[K\n\n\x1b[0m", .{});
            
            // Track Info (Silver/Brass)
            try stdout.print("\x1b[37m  [ FILE ]\x1b[0m :: \x1b[33m{s}\x1b[0m\x1b[K\n", .{filename});
            
            // Volume Bar (Crimson/Brass/Black)
            const vol_width = 15;
            const vol_filled = @min(@as(usize, @intFromFloat((global_vol / 1.5) * @as(f32, @floatFromInt(vol_width)))), vol_width);
            try stdout.print("\x1b[37m  [ VOL  ]\x1b[0m :: \x1b[33m[\x1b[0m", .{});
            for (0..vol_width) |i| {
                if (i < vol_filled) try stdout.print("\x1b[91m#\x1b[0m", .{}) else try stdout.print("\x1b[90m-\x1b[0m", .{});
            }
            try stdout.print("\x1b[33m]\x1b[0m \x1b[37m{d:.1}\x1b[0m\x1b[K\n\n", .{global_vol});

            // Progress Bar (Crimson/Black)
            const bar_width = 42;
            const filled = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(bar_width))));
            try stdout.print("  \x1b[91m[\x1b[0m ", .{});
            for (0..bar_width) |i| {
                if (i < filled) try stdout.print("\x1b[91m█\x1b[0m", .{}) else try stdout.print("\x1b[90m▓\x1b[0m", .{});
            }
            try stdout.print(" \x1b[91m]\x1b[0m \x1b[37m{d:0>2}%\x1b[0m\x1b[K\n\n", .{@as(usize, @intFromFloat(progress * 100.0))});

            // Input Map
            try stdout.print("\x1b[37m  [ CMD  ]\x1b[0m :: \x1b[91m[+]\x1b[0m Up | \x1b[91m[-]\x1b[0m Down | \x1b[91m[Enter]\x1b[0m Skip | \x1b[91m[q]\x1b[0m Quit\x1b[K\n", .{});
            try stdout.print("\x1b[J", .{}); // Clear any artifacting below the UI

            // POSIX Polling (Unchanged)
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
            std.Thread.sleep(50 * std.time.ns_per_ms);
        }
    }
}
