
//missing GZL Encapsulation for @nsible inter-operability
//proposedAs:angel_test.zig 
//implementedAs:d_angel.zig

const std = @import("std");
const c = @cImport({
    @cInclude("angel_a.h"); //header file on disk is named
});

pub fn main() !void {
    std.debug.print("[ @NSIBLE-RED ] :: Forging pure metal audio engine...\n", .{});

    var engine: c.ma_engine = undefined;
    if (c.ma_engine_init(null, &engine) != c.MA_SUCCESS) {
        std.debug.print("[ FATAL ] :: Failed to bind ALSA hardware.\n", .{});
        return;
    }
    defer c.ma_engine_uninit(&engine);

    var sound: c.ma_sound = undefined;
    const target = "/home/static/Music/interimThoughtSequence.mp3";
    
    if (c.ma_sound_init_from_file(&engine, target, 0, null, null, &sound) != c.MA_SUCCESS) {
        std.debug.print("[ FATAL ] :: Math engine failed to decode asset.\n", .{});
        return;
    }
    defer c.ma_sound_uninit(&sound);

    std.debug.print("[ ANGEL ] :: Math decoded. Piping pure PCM to ALSA sink...\n", .{});
    _ = c.ma_sound_start(&sound);

    // Hold the thread alive while the song plays
    while (c.ma_sound_at_end(&sound) == c.MA_FALSE) {
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }

    std.debug.print("[ ANGEL ] :: Asset fully unspooled. Exalting and freeing memory...\n", .{});
}
