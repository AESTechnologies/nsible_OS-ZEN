const std = @import("std");
const linux = std.os.linux;

const TimeVal = extern struct {
    sec: isize,
    usec: isize,
};

// 1 Cycle = 42.13 Minutes = 2527.8 Seconds
const CYCLE_SECONDS: f64 = 2527.8;

pub fn getCycleString(buf: []u8) []const u8 {
    var tv = TimeVal{ .sec = 0, .usec = 0 };
    _ = linux.syscall2(.gettimeofday, @intFromPtr(&tv), 0);

    const epoch_sec = tv.sec;
    
    // [1] Equinox/Solstice Day (Approx 91 days per season)
    const days_since_epoch = @divFloor(epoch_sec, 86400);
    const eq_day = @mod(days_since_epoch, 91); 
    
    // [2] Daily Cycle Count
    const sec_today = @mod(epoch_sec, 86400);
    const cycle_count = @as(usize, @intFromFloat(@as(f64, @floatFromInt(sec_today)) / CYCLE_SECONDS));
    
    // [3] Cycle Float (00.0 to 42.1)
    const remainder_sec = @as(f64, @floatFromInt(sec_today)) - (@as(f64, @floatFromInt(cycle_count)) * CYCLE_SECONDS);
    const cycle_float = remainder_sec / 60.0;

    // Output formatted to strict 0.0 decimal precision
    return std.fmt.bufPrint(buf, "(CYCLE: {d}.{d}.{d:.1})", .{ eq_day, cycle_count, cycle_float }) catch "(CYCLE: ERR)";
}
