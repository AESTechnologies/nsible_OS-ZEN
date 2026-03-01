const std = @import("std");
const chronos = @import("chronos.zig");

// [ACTIONS]
pub const ActionType = enum { CLEAR, EXIT, PRINT, HUNT, NONE };

pub const Response = struct {
    action: ActionType,
    text: []const u8 = "",
};

var output_buf: [256]u8 = undefined;

pub fn dispatch(cmd: []const u8) Response {
    if (cmd.len == 0) return .{ .action = .NONE };

    // 1. EXIT
    if (std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "[.!XX-.]")) {
        return .{ .action = .EXIT };
    } 
    // 2. CYCLE FETCH
    else if (std.mem.eql(u8, cmd, "cycle")) {
        const cycle_str = chronos.getCycleString(&output_buf);
        return .{ .action = .PRINT, .text = cycle_str };
    } 
    // 3. SYSTEM IDENTITY
    else if (std.mem.eql(u8, cmd, ".-//whoami?")) {
        return .{ .action = .PRINT, .text = "AUTH_ROOT : ^(DENY) // CYCLE_DELTA_REQD" };
    }
    // 4. HUNTER TRIGGER (@:// or hunt)
    else if (std.mem.startsWith(u8, cmd, "@://") or std.mem.startsWith(u8, cmd, "hunt ")) {
        return .{ .action = .HUNT, .text = cmd };
    }
    // 5. SCROLL COMMANDS (Simple pass-through for main to handle)
    else if (std.mem.eql(u8, cmd, "v") or std.mem.eql(u8, cmd, "^")) {
        return .{ .action = .HUNT, .text = cmd }; // Treat scroll as a hunt update
    }

    return .{ .action = .NONE };
}
