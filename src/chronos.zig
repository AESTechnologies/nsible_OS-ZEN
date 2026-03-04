// [@://nsible_os/src/chronos.zig/.-={
//   module: "Chronos Temporal Lobe",
//   version: "0.10.2-nightly // Banysang",
//   description: "Calculates and formats the organic cycle metrics and temporal variance.",
//   changes: "Forged getTempusVariance logic to extract entropy for the Avium resonance anchor.",
//   philotic_inferences: "Time is not a standardized grid, but an organic flow. The micro-variance within the cycle provides absolute sovereign entropy."

const std = @import("std");
const linux = std.os.linux;
const codex = @import("codex.zig");

const TimeVal = extern struct {
    sec: isize,
    usec: isize,
};

pub fn getCycleString(buf: []u8) []const u8 {
    var tv = TimeVal{ .sec = 0, .usec = 0 };
    _ = linux.syscall2(.gettimeofday, @intFromPtr(&tv), 0);

    const epoch_sec = tv.sec;
    
    const days_since_epoch = @divFloor(epoch_sec, 86400);
    const eq_day = @mod(days_since_epoch, 91); 
    
    const sec_today = @mod(epoch_sec, 86400);
    const cycle_count = @as(usize, @intFromFloat(@as(f64, @floatFromInt(sec_today)) / codex.CYCLE_S));
    
    const remainder_sec = @as(f64, @floatFromInt(sec_today)) - (@as(f64, @floatFromInt(cycle_count)) * codex.CYCLE_S);
    const cycle_float = remainder_sec / 60.0;

    return std.fmt.bufPrint(buf, "(CYCLE: {d}.{d}.{d:.1})", .{ eq_day, cycle_count, cycle_float }) catch "(CYCLE: ERR)";
}

pub fn getTempusVariance() f64 {
    var tv = TimeVal{ .sec = 0, .usec = 0 };
    _ = linux.syscall2(.gettimeofday, @intFromPtr(&tv), 0);

    const epoch_sec = tv.sec;
    const sec_today = @mod(epoch_sec, 86400);
    const cycle_count = @as(usize, @intFromFloat(@as(f64, @floatFromInt(sec_today)) / codex.CYCLE_S));
    
    const remainder_sec = @as(f64, @floatFromInt(sec_today)) - (@as(f64, @floatFromInt(cycle_count)) * codex.CYCLE_S);
    const cycle_float = remainder_sec / 60.0;
    
    const phi: f64 = 1.6180339887;
    return cycle_float * phi;
}

// }-.]
