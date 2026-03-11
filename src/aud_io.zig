// [@://nsible_os/src/aud_io.zig/.-={
// module: "aud.io playback engine",
// version: "0.1.3",
// description: "Headless MPV daemon controller via Unix IPC Socket.",
// changes: "Migrated std.time.sleep to std.Thread.sleep following latest Zig nightly namespace purge.",
// philotic_inferences: "True sovereignty isn't doing everything yourself; it is having absolute command over the tools that do."

const std = @import("std");

pub const AudioEngine = struct {
    allocator: std.mem.Allocator,
    mpv_process: std.process.Child,
    socket_path: []const u8 = "/tmp/nsible.mpv.sock",

    /// Spawns the headless MPV daemon and binds the IPC socket.
    pub fn init(allocator: std.mem.Allocator) !*AudioEngine {
        const self = try allocator.create(AudioEngine);
        self.allocator = allocator;
        
        const argv = &[_][]const u8{
            "mpv",
            "--idle=yes",
            "--no-video",
            "--really-quiet", 
            "--input-ipc-server=/tmp/nsible.mpv.sock",
        };

        var agent = std.process.Child.init(argv, allocator);
        agent.stdin_behavior = .Ignore;
        agent.stdout_behavior = .Ignore;
        agent.stderr_behavior = .Ignore;
        
        try agent.spawn();
        self.mpv_process = agent;
        
        // Allow the daemon 100 milliseconds to establish the socket before the kernel tries to connect
        std.Thread.sleep(100 * std.time.ns_per_ms);

        return self;
    }

    /// Annihilates the background daemon and frees the memory buffer.
    pub fn deinit(self: *AudioEngine) void {
        _ = self.mpv_process.kill() catch {};
        self.allocator.destroy(self);
    }

    /// Fires a JSON payload into the IPC socket to load an absolute file path.
    pub fn play(self: *AudioEngine, file_path: []const u8) !void {
        const stream = try std.net.connectUnixSocket(self.socket_path);
        defer stream.close();

        const payload = try std.fmt.allocPrint(self.allocator, "{{\"command\": [\"loadfile\", \"{s}\"]}}\n", .{file_path});
        defer self.allocator.free(payload);

        try stream.writeAll(payload);
    }
    
    /// Fires a JSON payload to toggle the play/pause state.
    pub fn togglePause(self: *AudioEngine) !void {
        const stream = try std.net.connectUnixSocket(self.socket_path);
        defer stream.close();
        
        const payload = "{\"command\": [\"cycle\", \"pause\"]}\n";
        try stream.writeAll(payload);
    }
    
    /// Fires a JSON payload to instantly halt playback.
    pub fn stop(self: *AudioEngine) !void {
        const stream = try std.net.connectUnixSocket(self.socket_path);
        defer stream.close();
        
        const payload = "{\"command\": [\"stop\"]}\n";
        try stream.writeAll(payload);
    }
};
// }-.]
