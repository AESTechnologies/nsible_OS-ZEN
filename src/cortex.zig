const std = @import("std");

// .-*-. MODULE: CORTEX (Command Processor) .-*-.
// [^] THE LOGIC CORE

pub const ActionType = enum {
    NONE,
    CLEAR,
    EXIT,
    PRINT,
};

pub const Response = struct {
    action: ActionType,
    text: []const u8,
};

// BUFFER FOR RESPONSES
var response_buf: [256]u8 = undefined;

pub fn dispatch(cmd_raw: []const u8) Response {
    // 1. Trim whitespace (newlines/spaces)
    const cmd = std.mem.trim(u8, cmd_raw, " \n\r\t");

    // 2. ROUTING
    if (std.mem.eql(u8, cmd, "clear") or std.mem.eql(u8, cmd, "cls")) {
        return Response{ .action = .CLEAR, .text = "" };
    }
    
    if (std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "quit")) {
        return Response{ .action = .EXIT, .text = "" };
    }

    if (std.mem.eql(u8, cmd, "cycle") or std.mem.eql(u8, cmd, "time")) {
        return getCycleTime();
    }
    
    if (std.mem.eql(u8, cmd, "help")) {
        return Response{ .action = .PRINT, .text = "CMDS: CYCLE, CLEAR, EXIT, HELP" };
    }

    // Default: Echo or Silence?
    // Let's return NONE to just let it pass, or PRINT "UNKNOWN"
    return Response{ .action = .NONE, .text = "" };
}

// [?] CYCLE TIME LOGIC
// 1 Cycle = 42.13 Minutes = 2527.8 Seconds
fn getCycleTime() Response {
    const cycle_sec: f64 = 2527.8;
    
    // Get Unix Timestamp (Host Mode)
    const now = std.time.timestamp();
    const now_f: f64 = @floatFromInt(now);
    
    // Calculate Total Cycles since Epoch
    const total_cycles = now_f / cycle_sec;
    
    // Format: "CYCLE: 12345.67"
    // We use std.fmt.bufPrint to write into our static buffer
    const text = std.fmt.bufPrint(&response_buf, "CYCLE: {d:.2}", .{total_cycles}) catch "ERR: TIME";
    
    return Response{ .action = .PRINT, .text = text };
}


