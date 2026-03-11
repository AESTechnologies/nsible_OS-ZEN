const std = @import("std");
const c = @cImport({
    @cInclude("angel_a.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    std.debug.print("[ @NSIBLE-RED ] :: Forging Talon Alta TUI Player...\n", .{});

    var engine: c.ma_engine = undefined;
    if (c.ma_engine_init(null, &engine) != c.MA_SUCCESS) {
        std.debug.print("[ FATAL ] :: ALSA Hardware Lock Failed.\n", .{});
        return;
    }
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

    if (playlist.items.len == 0) {
        std.debug.print("[ FATAL ] :: No assets found in {s}\n", .{music_dir_path});
        return;
    }

    std.crypto.random.shuffle([]const u8, playlist.items);

    var global_vol: f32 = 0.6;

    // FIX: Using pure Linux POSIX polling instead of hallucinated std.io methods
    var pfd = [_]std.posix.pollfd{
        .{ .fd = std.posix.STDIN_FILENO, .events = std.posix.POLL.IN, .revents = 0 },
    };

    for (playlist.items) |track| {
        var sound: c.ma_sound = undefined;
        const track_c = try allocator.dupeZ(u8, track);
        defer allocator.free(track_c);

        if (c.ma_sound_init_from_file(&engine, track_c.ptr, 0, null, null, &sound) != c.MA_SUCCESS) continue;
        defer c.ma_sound_uninit(&sound);

        _ = c.ma_sound_set_volume(&sound, global_vol);
        _ = c.ma_sound_start(&sound);

        std.debug.print("\n[ PLAYING ] :: {s}\n", .{std.fs.path.basename(track)});
        std.debug.print("[ TUI ] :: [Enter] Skip | [+] Vol Up | [-] Vol Down\n", .{});

        while (c.ma_sound_at_end(&sound) == c.MA_FALSE) {
            // OS-level non-blocking read (timeout = 0)
            const ready = std.posix.poll(&pfd, 0) catch 0;
            if (ready > 0 and (pfd[0].revents & std.posix.POLL.IN) != 0) {
                var buf: [16]u8 = undefined;
                const amt = std.posix.read(std.posix.STDIN_FILENO, &buf) catch 0;
                if (amt > 0) {
                    const cmd = buf[0];
                    if (cmd == '+') {
                        global_vol = @min(global_vol + 0.1, 1.2);
                        _ = c.ma_sound_set_volume(&sound, global_vol);
                        std.debug.print("[ VOL ] :: {d:.1}\n", .{global_vol});
                    } else if (cmd == '-') {
                        global_vol = @max(global_vol - 0.1, 0.0);
                        _ = c.ma_sound_set_volume(&sound, global_vol);
                        std.debug.print("[ VOL ] :: {d:.1}\n", .{global_vol});
                    } else if (cmd == '\n' or cmd == '\r') {
                        _ = c.ma_sound_stop(&sound);
                        break;
                    }
                }
            }
            std.Thread.sleep(100 * std.time.ns_per_ms);
        }
    }
}
