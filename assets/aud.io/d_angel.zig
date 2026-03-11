const std = @import("std");
const c = @cImport({
    @cInclude("angel_a.h");
});

pub fn main() !void {
    // 1. Memory Setup
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    std.debug.print("[ @NSIBLE-RED ] :: Forging Talon Alta TUI Player...\n", .{});

    // 2. Hardware Bind
    // FIXED: Correct type declaration for Zig 0.15.2 namespace
    var engine: c.ma_engine = undefined;
    if (c.ma_engine_init(null, &engine) != c.MA_SUCCESS) {
        std.debug.print("[ FATAL ] :: ALSA Hardware Lock Failed.\n", .{});
        return;
    }
    defer c.ma_engine_uninit(&engine);

    // 3. Dynamic Playlist Generation
    var playlist = std.ArrayList([]const u8).init(allocator);
    defer {
        for (playlist.items) |path| allocator.free(path);
        playlist.deinit();
    }

    const music_dir_path = "/home/static/Music";
    var dir = try std.fs.openDirAbsolute(music_dir_path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.basename, ".mp3")) {
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ music_dir_path, entry.path });
            try playlist.append(full_path);
        }
    }

    if (playlist.items.len == 0) {
        std.debug.print("[ FATAL ] :: No assets found in {s}\n", .{music_dir_path});
        return;
    }

    // 4. Shuffle logic
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    random.shuffle([]const u8, playlist.items);

    const stdin = std.io.getStdIn().reader();
    var global_vol: f32 = 0.6;

    // 5. Playback Loop
    for (playlist.items) |track| {
        var sound: c.ma_sound = undefined;
        // dupeZ ensures the C-engine gets a null-terminated sentinel
        const track_c = try allocator.dupeZ(u8, track);
        defer allocator.free(track_c);

        if (c.ma_sound_init_from_file(&engine, track_c.ptr, 0, null, null, &sound) != c.MA_SUCCESS) {
            std.debug.print("[ ERROR ] :: Failed to decode: {s}\n", .{track});
            continue;
        }
        defer c.ma_sound_uninit(&sound);

        _ = c.ma_sound_set_volume(&sound, global_vol);
        _ = c.ma_sound_start(&sound);

        std.debug.print("\n[ PLAYING ] :: {s}\n", .{std.fs.path.basename(track)});
        std.debug.print("[ TUI ] :: [Enter] Skip | [+] Vol Up | [-] Vol Down\n", .{});

        while (c.ma_sound_at_end(&sound) == c.MA_FALSE) {
            // Non-blocking input poll
            if (std.io.getStdIn().poll(.{ .read = true }, 0)) |has_input| {
                if (has_input.read) {
                    var buf: [16]u8 = undefined;
                    const amt = try stdin.read(&buf) catch 0;
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
                        } else {
                            std.debug.print("[ SIGNAL ] :: Skipping Track...\n", .{});
                            _ = c.ma_sound_stop(&sound);
                            break;
                        }
                    }
                }
            }
            // Sleep moved to std.Thread for newer nightlies
            std.Thread.sleep(100 * std.time.ns_per_ms);
        }
    }

    std.debug.print("[ @NSIBLE-RED ] :: Setlist Exhausted. Matrix Idle.\n", .{});
}
