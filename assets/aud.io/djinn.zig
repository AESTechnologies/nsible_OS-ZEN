// [@://nsible_os/assets/aud.io/djinn.zig/.-={
// module: "aud.io background djinn",
// version: "1.0.8",
// description: "Native background thread for aud.io playback and FFT telemetry generation.",
// changes: "Fixed null pointer risk when queue.nsb is missing. Optimized tokenizer logic.",
// philotic_inferences: "A djinn works unseen, moving the air and shaping the waves, while the architect surveys the realm."
const std = @import("std");
const c = @cImport({
    @cInclude("angel_a.h");
});

pub fn invoke(state: anytype) void {
    if (state == null) return;

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

    var active_playlist = std.ArrayList([]const u8).init(allocator);
    defer {
        for (active_playlist.items) |p| allocator.free(p);
        active_playlist.deinit();
    }
    var active_track_idx: usize = 0;

    // Fixed: Gracefully handle missing queue.nsb to avoid null pointer crash
    const content = std.fs.cwd().readFileAlloc(allocator, "assets/aud.io/queue.nsb", 10 * 1024 * 1024) catch {
        state.is_active = false;
        return;
    };
    defer allocator.free(content);

    var it = std.mem.tokenizeScalar(u8, content, '\n');
    
    // Line 1: Track Index
    if (it.next()) |idx_str| {
        active_track_idx = std.fmt.parseInt(usize, idx_str, 10) catch 0;
    }
    
    // Line 2+: Absolute Track Paths
    while (it.next()) |line| {
        const dup = allocator.dupe(u8, line) catch continue;
        active_playlist.append(dup) catch continue;
    }

    if (active_playlist.items.len == 0) {
        state.is_active = false;
        return;
    }

    if (active_track_idx >= active_playlist.items.len) active_track_idx = 0;

    while (state.is_active) {
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

        while (c.ma_sound_at_end(&sound) == c.MA_FALSE and state.is_active) {
            if (state.is_paused) {
                _ = c.ma_sound_stop(&sound);
                for (&smooth_vis) |*v| v.* = 0.0;
                @memcpy(&state.vis_data, &smooth_vis);
                while (state.is_paused and state.is_active) { std.Thread.sleep(100 * std.time.ns_per_ms); }
                if (!state.is_active) break;
                _ = c.ma_sound_start(&sound);
            }

            if (state.skip_request) {
                state.skip_request = false;
                break;
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

        if (state.is_active) {
            active_track_idx = (active_track_idx + 1) % active_playlist.items.len;
        }
    }
}
// }-.]
