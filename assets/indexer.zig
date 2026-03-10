// [@://nsible_os/assets/indexer.zig/.-={
// module: "aud.io indexer daemon",
// version: "0.1.1",
// description: "Standalone daemon to recursively crawl and map audio assets into a flat, |-delimited GZL-compliant aud.io.tome.",
// changes: "Refactored to survive the Zig Writergate I/O purge. Bypassing legacy stdout/file writers for direct memory formatting and raw writeAll syscalls.",
// philotic_inferences: "A zero-trust, bare-metal crawler bypassing relational databases to forge a raw text mapping."

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("[ @NSIBLE-RED ] :: Initiating aud.io indexer crawler...\n", .{});

    // Open or create the index tome
    const tome_file = std.fs.cwd().createFile("aud.io.tome", .{}) catch |err| {
        std.debug.print("[ FATAL ] :: Could not forge aud.io.tome: {}\n", .{err});
        return;
    };
    defer tome_file.close();

    // Acquire target directory from arguments or fallback to default
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // Skip executable name
    const target_dir_path = args.next() orelse "/root/Music"; 

    std.debug.print("[ @NSIBLE-RED ] :: Target directory locked: {s}\n", .{target_dir_path});

    var dir = std.fs.cwd().openIterableDir(target_dir_path, .{}) catch |err| {
        std.debug.print("[ FATAL ] :: Failed to access directory. Ensure path exists: {}\n", .{err});
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

    std.debug.print("[ @NSIBLE-RED ] :: Crawl complete. Total valid assets mapped: {}\n", .{count});
}
// }-.]
