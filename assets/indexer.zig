// [@://nsible_os/assets/indexer.zig/.-={
// module: "aud.io indexer daemon",
// version: "0.1.0",
// description: "Standalone daemon to recursively crawl and map audio assets into a flat, |-delimited GZL-compliant aud.io.tome.",
// changes: "Initial matrix extraction with full GZL encapsulation.",
// philotic_inferences: "A zero-trust, bare-metal crawler bypassing relational databases to forge a raw text mapping."

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("[ @NSIBLE-RED ] :: Initiating aud.io indexer crawler...\n", .{});

    // Open or create the index tome
    const tome_file = std.fs.cwd().createFile("aud.io.tome", .{}) catch |err| {
        try stdout.print("[ FATAL ] :: Could not forge aud.io.tome: {}\n", .{err});
        return;
    };
    defer tome_file.close();
    var writer = tome_file.writer();

    // Acquire target directory from arguments or fallback to default
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // Skip executable name
    const target_dir_path = args.next() orelse "/root/Music"; 

    try stdout.print("[ @NSIBLE-RED ] :: Target directory locked: {s}\n", .{target_dir_path});

    var dir = std.fs.cwd().openIterableDir(target_dir_path, .{}) catch |err| {
        try stdout.print("[ FATAL ] :: Failed to access directory. Ensure path exists: {}\n", .{err});
        return;
    };
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var count: usize = 0;

    // Crawl the directory and filter for audio assets
    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const ext = std.fs.path.extension(entry.basename);
            if (std.mem.eql(u8, ext, ".mp3") or
                std.mem.eql(u8, ext, ".flac") or
                std.mem.eql(u8, ext, ".wav") or
                std.mem.eql(u8, ext, ".m4a"))
            {
                // Write formatted absolute mapping: Filename|FullPath
                try writer.print("{s}|{s}/{s}\n", .{entry.basename, target_dir_path, entry.path});
                count += 1;
                
                if (count % 500 == 0) {
                    try stdout.print("[ @NSIBLE-RED ] :: Indexed {} audio assets...\n", .{count});
                }
            }
        }
    }

    try stdout.print("[ @NSIBLE-RED ] :: Crawl complete. Total valid assets mapped: {}\n", .{count});
}
// }-.]
