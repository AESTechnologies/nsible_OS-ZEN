const std = @import("std");
const linux = std.os.linux;

// .-*-. ARCH: CODEX (Sovereign I/O) .-*-.

// [CONSTANTS] : TERMINOLOGICAL MAPPING
pub const CODEX    = 0x5401; // TCGETS (Read the current laws/state)
pub const CODES    = 0x5402; // TCSETS (Write the new codes/state)
pub const VOIDSCAN = 0x0001; // POLLIN (Scan for input signal)
pub const XCODE    = 0x000A; // Mask for Removal (ECHO | ICANON)

// [STRUCTS] : ABI COMPLIANCE (32-bit x86)
// We define this locally to avoid std.os version conflicts on Musl/Atom
const KernelTime = extern struct {
    tv_sec: isize,
    tv_nsec: isize,
};

// [OPERATIONS]

/// TUNEIN: Align the frequency.
/// Captures the current CODEX, applies XCODE filters, and asserts CODES.
pub fn tuneIn() void {
    var state: linux.termios = undefined;
    
    // 1. READ CODEX (Get State)
    if (linux.syscall3(.ioctl, 0, CODEX, @intFromPtr(&state)) != 0) return;

    // 2. APPLY XCODE (Filter/Mask)
    // FIX: Cast packed struct to u32 for bitwise NOT/AND operations
    var lflag_int: u32 = @bitCast(state.lflag);
    lflag_int &= ~(@as(u32, XCODE));
    state.lflag = @bitCast(lflag_int);
    
    // 3. ASSERT CODES (Set State)
    _ = linux.syscall3(.ioctl, 0, CODES, @intFromPtr(&state));
}

/// TRANSCIEVE: The active signal loop.
/// Scans the void. If signal found, returns atomic unit (u8).
pub fn transcieve() ?u8 {
    // 1. VOIDSCAN (Poll)
    var fds = [1]linux.pollfd{
        .{ .fd = 0, .events = VOIDSCAN, .revents = 0 },
    };

    // Timeout = 0 (Immediate / Non-Blocking)
    const result = linux.syscall3(.poll, @intFromPtr(&fds), 1, 0);

    // 2. CHECK SIGNAL
    if (@as(usize, @bitCast(result)) > 0) {
        if ((fds[0].revents & VOIDSCAN) != 0) {
            var buffer: [1]u8 = undefined;
            // READ
            const read_res = linux.syscall3(.read, 0, @intFromPtr(&buffer), 1);
            if (@as(usize, @bitCast(read_res)) == 1) {
                return buffer[0];
            }
        }
    }
    return null;
}

/// ZEN: The wait state (wait++).
/// micros: Microseconds to hold the cycle.
pub fn zen(micros: u64) void {
    var req = KernelTime{
        .tv_sec = @intCast(micros / 1_000_000),
        .tv_nsec = @intCast((micros % 1_000_000) * 1000),
    };
    var rem = KernelTime{ .tv_sec = 0, .tv_nsec = 0 };
    _ = linux.syscall2(.nanosleep, @intFromPtr(&req), @intFromPtr(&rem));
}
