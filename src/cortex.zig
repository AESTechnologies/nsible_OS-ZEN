// [@://nsible_os/src/cortex.zig/.-={
//   module: "Semantic Dispatch Lobe",
//   version: "0.10.15-nightly // Banysang",
//   description: "Parses wetware input into machine-actionable states.",
//   changes: "Injected BASH_EXEC reflex to parse $/-delimited shell commands.",
//   philotic_inferences: "To seek the void's knowledge, one must merely ask the wind."

const std = @import("std");
const chronos = @import("chronos.zig");

pub const ActionType = enum { CLEAR, EXIT, PRINT, HUNT, SEARCH, STARGAZE, AUTO_HUNT, SHED, SCOPE_IN, SCOPE_OUT, MEMO, PIPE_MEMO, ASSIST, RADIO, CALC, REFRESH, MOUNT, UNMOUNT, BASH_EXEC, NONE };

pub const Response = struct {
    action: ActionType,
    text: []const u8 = "",
};

var output_buf: [256]u8 = undefined;

pub fn dispatch(cmd: []const u8) Response {
    if (cmd.len == 0) return .{ .action = .NONE };

    // [!] THE SHELL LOBE DISPATCH
    if (std.mem.startsWith(u8, cmd, "$/")) {
        return .{ .action = .BASH_EXEC, .text = cmd[2..] };
    }

    if (std.mem.endsWith(u8, cmd, "//-.")) {
        const content = cmd[0 .. cmd.len - 4]; 
        const clean = std.mem.trimRight(u8, content, " ");
        return .{ .action = .MEMO, .text = clean };
    }

    if (std.mem.indexOf(u8, cmd, "|")) |pipe_idx| {
        const left = std.mem.trim(u8, cmd[0..pipe_idx], " ");
        const right = std.mem.trim(u8, cmd[pipe_idx+1..], " ");
        if (std.mem.eql(u8, right, "memo")) {
            return .{ .action = .PIPE_MEMO, .text = left }; 
        }
    }

    if (std.mem.eql(u8, cmd, "zI")) return .{ .action = .SCOPE_IN };
    if (std.mem.eql(u8, cmd, "zO")) return .{ .action = .SCOPE_OUT };
    
    if (std.mem.eql(u8, cmd, "refresh") or std.mem.eql(u8, cmd, "reload")) return .{ .action = .REFRESH };

    if (std.mem.eql(u8, cmd, "mount")) return .{ .action = .MOUNT };
    if (std.mem.eql(u8, cmd, "unmount") or std.mem.eql(u8, cmd, "eject")) return .{ .action = .UNMOUNT };

    if (std.mem.startsWith(u8, cmd, "memo")) {
        if (cmd.len > 5) return .{ .action = .MEMO, .text = cmd[5..] };
        return .{ .action = .MEMO, .text = "" };
    }
    if (std.mem.eql(u8, cmd, "save")) return .{ .action = .MEMO, .text = "" };
    if (std.mem.eql(u8, cmd, "shed") or std.mem.eql(u8, cmd, "drop")) return .{ .action = .SHED };
    if (std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "[.!XX-.]")) return .{ .action = .EXIT };
    if (std.mem.eql(u8, cmd, "tune") or std.mem.eql(u8, cmd, "radio")) return .{ .action = .RADIO };

    if (std.mem.eql(u8, cmd, "@://calc/") or std.mem.eql(u8, cmd, "calc")) return .{ .action = .CALC };
    
    if (std.mem.eql(u8, cmd, "stargaze")) return .{ .action = .STARGAZE };

    if (std.mem.startsWith(u8, cmd, "@://w3?.")) {
        const q = if (cmd.len > 8 and cmd[8] == ' ') cmd[9..] else cmd[8..];
        return .{ .action = .SEARCH, .text = q };
    }
    if (std.mem.startsWith(u8, cmd, "w3?.")) {
        const q = if (cmd.len > 4 and cmd[4] == ' ') cmd[5..] else cmd[4..];
        return .{ .action = .SEARCH, .text = q };
    }

    if (std.mem.startsWith(u8, cmd, "@://")) {
        return .{ .action = .HUNT, .text = cmd };
    }
    if (std.mem.startsWith(u8, cmd, "w3.")) {
        return .{ .action = .HUNT, .text = cmd[3..] };
    }
    
    if (std.mem.eql(u8, cmd, "cycle")) {
        const cycle_str = chronos.getCycleString(&output_buf);
        return .{ .action = .PRINT, .text = cycle_str };
    }
    if (std.mem.eql(u8, cmd, "v")) return .{ .action = .HUNT, .text = "v" };
    if (std.mem.eql(u8, cmd, "^")) return .{ .action = .HUNT, .text = "^" };
    if (std.mem.eql(u8, cmd, "assist") or std.mem.eql(u8, cmd, "?")) return .{ .action = .ASSIST };

    var is_num = cmd.len > 0;
    for (cmd) |c| {
        if (c < '0' or c > '9') {
            is_num = false;
            break;
        }
    }
    if (is_num) {
        return .{ .action = .AUTO_HUNT, .text = cmd };
    }

    if (std.mem.indexOf(u8, cmd, ".") != null or std.mem.indexOf(u8, cmd, "/") != null) {
        return .{ .action = .AUTO_HUNT, .text = cmd };
    }

    return .{ .action = .NONE };
}
// }-.]
