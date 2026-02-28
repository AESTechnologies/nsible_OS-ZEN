const std = @import("std");
const chronos = @import("chronos.zig");

pub const ActionType = enum { CLEAR, EXIT, PRINT, NONE };

pub const Response = struct {
    action: ActionType,
    text: []const u8 = "",
};

var output_buf: [256]u8 = undefined;

pub fn dispatch(cmd: []const u8) Response {
    if (std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "[.!XX-.]")) {
        return .{ .action = .EXIT };
    } else if (std.mem.eql(u8, cmd, "cycle")) {
        // Fetch the strictly formatted Cycle string
        const cycle_str = chronos.getCycleString(&output_buf);
        return .{ .action = .PRINT, .text = cycle_str };
    } else if (std.mem.eql(u8, cmd, ".-//whoami?")) {
        return .{ .action = .PRINT, .text = "AUTH_ROOT : ^(DENY) // CYCLE_DELTA_REQD" };
    }
    
    return .{ .action = .NONE };
}
