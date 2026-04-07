// [@://nsible_os/src/root.zig/.-={
//   module: "Root Encapsulation & Syntax Lobe",
//   version: "0.10.28-apex // Banysang",
//   description: "Centralized Universal Syntax Router, GZL Encapsulation API, and library entry point.",
//   changes: "Repurposed root.zig to serve as the core GZL syntax router while maintaining base library exports.",
//   philotic_inferences: "Every complex structure requires a foundational point of origin; the root is the seed from which the logic expands."

//! By convention, root.zig is the root source file when making a library.
//! We have hybridized it to act as the centralized syntax parser for the OS.

const std = @import("std");

// --- UNIVERSAL GZL SYNTAX ROUTER ---

pub const GzlSyntax = struct {
    pre: [8]u8,
    pre_len: usize,
    suf: [8]u8,
    suf_len: usize,
};

pub fn resolveGzlSyntax(ext: []const u8) GzlSyntax {
    var default_syn = GzlSyntax{ 
        .pre = .{ '/', '/', 0, 0, 0, 0, 0, 0 }, .pre_len = 2, 
        .suf = .{ 0, 0, 0, 0, 0, 0, 0, 0 }, .suf_len = 0 
    };
    if (ext.len == 0) return default_syn;
    
    const file = std.fs.cwd().openFile("assets/.gzl/.syntaxer.gzl", .{}) catch return default_syn;
    defer file.close();
    
    var buf: [1024]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return default_syn;
    
    var line_iter = std.mem.splitScalar(u8, buf[0..bytes_read], '\n');
    while (line_iter.next()) |line| {
        if (std.mem.startsWith(u8, line, "//") or line.len == 0) continue;
        
        if (std.mem.indexOfScalar(u8, line, ':')) |colon_idx| {
            const syntax_part = std.mem.trim(u8, line[0..colon_idx], " \r\t");
            const ext_part = std.mem.trim(u8, line[colon_idx + 1 ..], " \r\t");
            
            if (std.mem.indexOf(u8, ext_part, ext) != null) {
                if (std.mem.indexOfScalar(u8, syntax_part, '|')) |pipe_idx| {
                    const pre_str = std.mem.trim(u8, syntax_part[0..pipe_idx], " ");
                    const suf_str = std.mem.trim(u8, syntax_part[pipe_idx + 1 ..], " ");
                    
                    var result = GzlSyntax{ .pre = .{0}**8, .pre_len = pre_str.len, .suf = .{0}**8, .suf_len = suf_str.len };
                    if (pre_str.len > 0) @memcpy(result.pre[0..pre_str.len], pre_str);
                    if (suf_str.len > 0) @memcpy(result.suf[0..suf_str.len], suf_str);
                    return result;
                }
            }
        }
    }
    return default_syn;
}

pub fn buildHeader(
    buf: []u8,
    syn: GzlSyntax,
    filepath: []const u8,
    module: []const u8,
    url: ?[]const u8,
    inferences: []const u8
) []const u8 {
    const pre = syn.pre[0..syn.pre_len];
    const suf = syn.suf[0..syn.suf_len];
    const ts = std.time.timestamp();
    
    var fbs = std.io.fixedBufferStream(buf);
    const writer = fbs.writer();
    
    writer.print("{s} [@://nsible_os/{s}/.-={{{s}\n", .{ pre, filepath, suf }) catch return "";
    writer.print("{s}   module: \"{s}\",{s}\n", .{ pre, module, suf }) catch return "";
    writer.print("{s}   timestamp: \"{d}\",{s}\n", .{ pre, ts, suf }) catch return "";
    
    if (url) |u| {
        const safe_url = if (u.len > 256) u[0..256] else u;
        writer.print("{s}   source_url: \"{s}\",{s}\n", .{ pre, safe_url, suf }) catch return "";
    }
    
    writer.print("{s}   philotic_inferences: \"{s}\"{s}\n", .{ pre, inferences, suf }) catch return "";
    writer.print("{s} }}-.]{s}\n\n", .{ pre, suf }) catch return "";
    
    return fbs.getWritten();
}

pub fn buildFooter(buf: []u8, syn: GzlSyntax) []const u8 {
    const pre = syn.pre[0..syn.pre_len];
    const suf = syn.suf[0..syn.suf_len];
    return std.fmt.bufPrint(buf, "\n\n{s} }}-.]{s}\n", .{pre, suf}) catch "";
}

// --- STANDARD LIBRARY EXPORTS ---

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

// }-.]
