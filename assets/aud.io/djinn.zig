// [@://nsible_os/assets/aud.io/djinn.zig/.-={
// module: "aud.io background djinn",
// version: "1.0.7",
// description: "Native background thread for aud.io playback and FFT telemetry generation.",
// changes: "Decoupled queue.nsb from queue_idx.nsb to prevent memory overwrite bugs. Enabled live hot-reloading.",
// philotic_inferences: "A djinn works unseen, moving the air and shaping the waves, while the architect surveys the realm."
const std = @import("std");
const c = @cImport({
    @cInclude("angel_a.h");
});

pub fn invoke(state: anytype) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var engine: c.ma_engine = undefined;
    if (c.ma_engine_init(null, &engine) != c.MA_SUCCESS) {
        state.is_active = false;
        return;
    }
    defer c.ma_engine_uninit(&engine);

    const engine_sr = c.ma_engine_get_sample_rate(&engine);

    var active_playlist: std.ArrayList([]const u8) = .empty;
    defer {
        for (active_playlist.items) |p| allocator.free(p);
        active_playlist.deinit(allocator);
    }
    var active_track_idx: usize = 0;

    // Load active index
    if (std.fs.cwd().readFileAlloc(allocator, "assets/aud.io/.queue_idx.nsb", 1024)) |idx_content| {
        active_track_idx = std.fmt.parseInt(usize, std.mem.trim(u8, idx_content, " \n\r"), 10) catch 0;
        allocator.free(idx_content);
    } else |_| {}

    // Load playlist
    if (std.fs.cwd().readFileAlloc(allocator, "assets/aud.io/.queue.nsb", 10 * 1024 * 1024)) |content| {
        defer allocator.free(content);
        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |line| {
            if (line.len > 0) {
                const dup = allocator.dupe(u8, line) catch continue;
                active_playlist.append(allocator, dup) catch continue;
            }
        }
    } else |_| {
        state.is_active = false;
        return;
    }

    if (active_playlist.items.len == 0) {
        state.is_active = false;
        return;
    }

    if (active_track_idx >= active_playlist.items.len) active_track_idx = 0;

    while (state.is_active) {
        if (active_playlist.items.len == 0) {
            state.is_active = false;
            break;
        }

        // Save active index at start of new track
        if (std.fs.cwd().createFile("assets/aud.io/.queue_idx.nsb", .{ .truncate = true })) |file| {
            var buf: [32]u8 = undefined;
            const idx_str = std.fmt.bufPrint(&buf, "{d}\n", .{active_track_idx}) catch "0\n";
            file.writeAll(idx_str) catch {};
            file.close();
        } else |_| {}

        const current_track = active_playlist.items[active_track_idx];
        const track_c = allocator.dupeZ(u8, current_track) catch break;
        defer allocator.free(track_c);

        var sound: c.ma_sound = undefined;
        if (c.ma_sound_init_from_file(&engine, track_c.ptr, 0, null, null, &sound) != c.MA_SUCCESS) {
            active_track_idx = (active_track_idx + 1) % active_playlist.items.len;
            if (active_track_idx == 0) break;
            continue;
        }
        defer c.ma_sound_uninit(&sound);

        var v_decoder: c.ma_decoder = undefined;
        var v_config = c.ma_decoder_config_init(c.ma_format_f32, 1, engine_sr);
        const has_vis = (c.ma_decoder_init_file(track_c.ptr, &v_config, &v_decoder) == c.MA_SUCCESS);
        
        defer {
            if (has_vis) _ = c.ma_decoder_uninit(&v_decoder);
        }

        _ = c.ma_sound_set_volume(&sound, state.vol_level); 
        _ = c.ma_sound_start(&sound);

        const filename = std.fs.path.basename(current_track);
        const name_len = @min(filename.len, 64);
        @memcpy(state.track_name[0..name_len], filename[0..name_len]);
        state.track_name_len = name_len;

        var smooth_vis: [32]f32 = .{0.0} ** 32;
        var track_completed_naturally = true;

        while (c.ma_sound_at_end(&sound) == c.MA_FALSE and state.is_active) {
            // Check Live Flags
            if (state.reload_request) {
                state.reload_request = false;
                if (std.fs.cwd().readFileAlloc(allocator, "assets/aud.io/.queue.nsb", 10 * 1024 * 1024)) |content| {
                    for (active_playlist.items) |p| allocator.free(p);
                    active_playlist.clearRetainingCapacity();
                    var it = std.mem.splitScalar(u8, content, '\n');
                    while (it.next()) |line| {
                        if (line.len > 0) {
                            if (allocator.dupe(u8, line)) |dup| {
                                active_playlist.append(allocator, dup) catch {};
                            } else |_| {}
                        }
                    }
                    allocator.free(content);
                } else |_| {}
            }

            if (state.clr_request) {
                state.clr_request = false;
                state.is_active = false;
                if (std.fs.cwd().createFile("assets/aud.io/.queue.nsb", .{ .truncate = true })) |f| { f.close(); } else |_| {}
                if (std.fs.cwd().createFile("assets/aud.io/.queue_idx.nsb", .{ .truncate = true })) |f| { f.close(); } else |_| {}
                track_completed_naturally = false;
                break;
            }

            if (state.rmv_request) {
                state.rmv_request = false;
                if (active_playlist.items.len > 0) {
                    const removed = active_playlist.orderedRemove(active_track_idx);
                    allocator.free(removed);
                    if (std.fs.cwd().createFile("assets/aud.io/.queue.nsb", .{ .truncate = true })) |file| {
                        for (active_playlist.items) |p| {
                            file.writeAll(p) catch {};
                            file.writeAll("\n") catch {};
                        }
                        file.close();
                    } else |_| {}
                }
                
                if (active_playlist.items.len == 0) {
                    state.is_active = false;
                } else if (active_track_idx >= active_playlist.items.len) {
                    active_track_idx = 0;
                }
                track_completed_naturally = false;
                break;
            }

            if (state.back_request) {
                state.back_request = false;
                if (active_track_idx > 0) {
                    active_track_idx -= 1;
                } else if (active_playlist.items.len > 0) {
                    active_track_idx = active_playlist.items.len - 1;
                }
                track_completed_naturally = false;
                break;
            }

            if (state.skip_request) {
                state.skip_request = false;
                active_track_idx = (active_track_idx + 1) % active_playlist.items.len;
                track_completed_naturally = false;
                break;
            }

            if (state.is_paused) {
                _ = c.ma_sound_stop(&sound);
                for (&smooth_vis) |*v| v.* = 0.0;
                @memcpy(&state.vis_data, &smooth_vis);
                while (state.is_paused and state.is_active and !state.skip_request and !state.rmv_request and !state.back_request and !state.clr_request) { 
                    std.Thread.sleep(100 * std.time.ns_per_ms); 
                }
                if (!state.is_active or state.skip_request or state.rmv_request or state.back_request or state.clr_request) continue;
                _ = c.ma_sound_start(&sound);
            }

            _ = c.ma_sound_set_volume(&sound, state.vol_level);

            if (has_vis) {
                var cursor_pcm: c.ma_uint64 = 0;
                _ = c.ma_sound_get_cursor_in_pcm_frames(&sound, &cursor_pcm);
                var pcm_buffer: [1024]f32 = undefined;
                var frames_read: c.ma_uint64 = 0;
                _ = c.ma_decoder_seek_to_pcm_frame(&v_decoder, cursor_pcm);
                _ = c.ma_decoder_read_pcm_frames(&v_decoder, &pcm_buffer, 1024, &frames_read);
                
                var current_vis: [32]f32 = .{0.0} ** 32;
                
                const frames_usize = @as(usize, @intCast(frames_read));
                const chunk = if (frames_usize > 32) frames_usize / 32 else 1;
                
                if (frames_usize > 0) {
                    for (0..32) |b| {
                        var peak: f32 = 0.0;
                        const limit = @min(chunk, frames_usize - (b * chunk));
                        for (0..limit) |i| {
                            const s = @abs(pcm_buffer[b * chunk + i]);
                            if (s > peak) peak = s;
                        }
                        current_vis[b] = peak;
                    }
                }

                for (0..32) |b| {
                    smooth_vis[b] += (current_vis[b] - smooth_vis[b]) * if (current_vis[b] > smooth_vis[b]) @as(f32, 0.8) else @as(f32, 0.3);
                    state.vis_data[b] = smooth_vis[b];
                }
            }
            std.Thread.sleep(30 * std.time.ns_per_ms);
        }

        if (state.is_active and track_completed_naturally) {
            active_track_idx = (active_track_idx + 1) % active_playlist.items.len;
        }
    }
}
// }-.]
