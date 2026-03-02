const std = @import("std");
const chronos = @import("chronos.zig");

// [ACTIONS]
pub const ActionType = enum { CLEAR, EXIT, PRINT, HUNT, SHED, SCOPE_IN, SCOPE_OUT, MEMO, NONE };

pub const Response = struct {
    action: ActionType,
    text: []const u8 = "",
};

var output_buf: [256]u8 = undefined;

pub fn dispatch(cmd: []const u8) Response {
    if (cmd.len == 0) return .{ .action = .NONE };

    // [!] LOG-PHILOTE TRIGGER
    // If the input ends with "//-.", treat it as a memo save.
    if (std.mem.endsWith(u8, cmd, "//-.")) {
        // Strip the trigger and whitespace
        const content = cmd[0 .. cmd.len - 4]; // Remove //-.
        const clean = std.mem.trimRight(u8, content, " ");
        return .{ .action = .MEMO, .text = clean };
    }

    // 1. SCOPE (Zoom)
    if (std.mem.eql(u8, cmd, "zI")) return .{ .action = .SCOPE_IN };
    if (std.mem.eql(u8, cmd, "zO")) return .{ .action = .SCOPE_OUT };
    
    // 2. JOURNAL MEMO (Legacy Command)
    if (std.mem.startsWith(u8, cmd, "memo")) {
        if (cmd.len > 5) return .{ .action = .MEMO, .text = cmd[5..] };
        return .{ .action = .MEMO, .text = "" };
    }
    if (std.mem.eql(u8, cmd, "save")) return .{ .action = .MEMO, .text = "" };

    // 3. TAB MANAGEMENT
    if (std.mem.eql(u8, cmd, "shed") or std.mem.eql(u8, cmd, "drop")) return .{ .action = .SHED };

    // 4. EXIT
    if (std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "[.!XX-.]")) return .{ .action = .EXIT };
    
    // 5. FETCH
    if (std.mem.startsWith(u8, cmd, "@://") or std.mem.startsWith(u8, cmd, "hunt ")) {
        return .{ .action = .HUNT, .text = cmd };
    }
    
    // 6. UTILS
    if (std.mem.eql(u8, cmd, "cycle")) {
        const cycle_str = chronos.getCycleString(&output_buf);
        return .{ .action = .PRINT, .text = cycle_str };
    }
    if (std.mem.eql(u8, cmd, "v")) return .{ .action = .HUNT, .text = "v" }; 
    if (std.mem.eql(u8, cmd, "^")) return .{ .action = .HUNT, .text = "^" };

    return .{ .action = .NONE };
}
