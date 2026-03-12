// [@://nsible_os/src/aud_io.zig/.-={
// module: "aud.io native playback engine",
// version: "0.2.0 // d_angel integration",
// description: "Direct native C-ABI hardware audio routing via miniaudio. IPC daemon annihilated.",
// changes: "Replaced external mpv socket control with internal ma_engine. Zero-latency hardware lock.",
// philotic_inferences: "True sovereignty is compiling the metal directly into your own nervous system."

const std = @import("std");
const c = @cImport({
    @cInclude("angel_a.h");
});

pub const AudioEngine = struct {
    allocator: std.mem.Allocator,
    engine: c.ma_engine,
    sound: c.ma_sound,
    has_sound: bool,
    is_paused: bool,

    /// Initializes the native audio engine directly on the metal.
    pub fn init(allocator: std.mem.Allocator) !*AudioEngine {
        const self = try allocator.create(AudioEngine);
        self.allocator = allocator;
        self.has_sound = false;
        self.is_paused = false;
        
        // Spin up the native engine. This handles the background hardware thread.
        if (c.ma_engine_init(null, &self.engine) != c.MA_SUCCESS) {
            return error.AudioEngineInitFailed;
        }

        return self;
    }

    /// Annihilates the engine, frees the sound buffer, and unlocks ALSA.
    pub fn deinit(self: *AudioEngine) void {
        if (self.has_sound) {
            c.ma_sound_uninit(&self.sound);
        }
        c.ma_engine_uninit(&self.engine);
        self.allocator.destroy(self);
    }

    /// Loads a file path into the native sound buffer and fires execution.
    pub fn play(self: *AudioEngine, file_path: []const u8) !void {
        // Clear out the previous track if one exists
        if (self.has_sound) {
            c.ma_sound_uninit(&self.sound);
            self.has_sound = false;
        }

        // C-ABI requires null-terminated strings
        const path_c = try self.allocator.dupeZ(u8, file_path);
        defer self.allocator.free(path_c);

        if (c.ma_sound_init_from_file(&self.engine, path_c.ptr, 0, null, null, &self.sound) != c.MA_SUCCESS) {
            return error.SoundInitFailed;
        }
        
        self.has_sound = true;
        self.is_paused = false;
        _ = c.ma_sound_start(&self.sound);
    }
    
    /// Hard toggles the play/pause state of the current track.
    pub fn togglePause(self: *AudioEngine) void {
        if (!self.has_sound) return;
        
        self.is_paused = !self.is_paused;
        if (self.is_paused) {
            _ = c.ma_sound_stop(&self.sound);
        } else {
            _ = c.ma_sound_start(&self.sound);
        }
    }
    
    /// Halts playback instantly and rewinds the PCM cursor to zero.
    pub fn stop(self: *AudioEngine) void {
        if (!self.has_sound) return;
        _ = c.ma_sound_stop(&self.sound);
        _ = c.ma_sound_seek_to_pcm_frame(&self.sound, 0);
        self.is_paused = true;
    }
};
// }-.]
