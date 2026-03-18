// [@://nsible_os/assets/indexer.zig/.-={
// module: "aud.io indexer angel",
// version: "0.1.4",
// description: "Standalone angel to recursively seek and map audio assets into a flat, |-delimited GZL-compliant aud.io.tome.",
// changes: "Angels over daemons. Purged hardcoded personal paths. Routed index output directly to assets/aud.io/aud.io.tome.",
// philotic_inferences: "A zero-trust, bare-metal indexer bypassing relational databases to forge a raw text mapping."
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("[ @NSIBLE-RED ] :: Initiating aud.io indexing angel...\n", .{});
    // Open or create the index tome in the sovereign assets/aud.io/ directory
    const tome_file = std.fs.cwd().createFile("assets/aud.io/aud.io.tome", .{}) catch |err|
    {
        std.debug.print("[ FATAL ] :: Could not forge assets/aud.io/aud.io.tome: {}\n", .{err});
        return;
    };
    defer tome_file.close();

    // Acquire target directory from arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // Skip executable name
    const target_dir_path = args.next() orelse {
        std.debug.print("[ @NSIBLE-RED ] :: Usage: ./indexer <target_directory>\n", .{});
        return;
    };
    std.debug.print("[ @NSIBLE-RED ] :: Target directory locked: {s}\n", .{target_dir_path});

    // Utilize openDir with the iterate flag for modern Zig nightly compatibility
    var dir = std.fs.cwd().openDir(target_dir_path, .{ .iterate = true }) catch |err|
    {
        std.debug.print("[ FATAL ] :: Failed to access directory. Ensure path exists: {}\n", .{err});
        return;
    };
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var count: usize = 0;
    // Crawl the directory and filter for audio assets
    while (try walker.next()) |entry|
    {
        if (entry.kind == .file) {
            const ext = std.fs.path.extension(entry.basename);
            if (std.mem.eql(u8, ext, ".mp3") or
                std.mem.eql(u8, ext, ".flac") or
                std.mem.eql(u8, ext, ".wav") or
                std.mem.eql(u8, ext, ".m4a"))
            {
                // Format the absolute mapping into memory, then write raw bytes to the matrix
                const line = try std.fmt.allocPrint(allocator, "{s}|{s}/{s}\n", .{entry.basename, target_dir_path, entry.path});
                defer allocator.free(line);
                try tome_file.writeAll(line);
                
                count += 1;
                
                if (count % 500 == 0) {
                    std.debug.print("[ @NSIBLE-RED ] :: Indexed {} audio assets...\n", .{count});
                }
            }
        }
    }

    std.debug.print("[ @NSIBLE-RED ] :: Indexing complete. Total valid assets mapped: {}\n", .{count});
}
// }-.]
