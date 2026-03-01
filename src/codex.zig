const std = @import("std");
const linux = std.os.linux;

// .-*-. ARCH: CODEX (Sovereign I/O) .-*-.

// [CONSTANTS]
pub const CODEX    = 0x5401; // TCGETS
pub const CODES    = 0x5402; // TCSETS
pub const VOIDSCAN = 0x0001; // POLLIN
pub const XCODE    = 0x000A; // Mask

// NETWORK CONSTANTS
pub const AF_INET = 2;
pub const SOCK_STREAM = 1;
pub const IPPROTO_TCP = 6;
pub const INADDR_ANY = 0;
pub const PORT: u16 = 4213;

// [!] TIME LAW (Centralized)
// 1 Cycle = 42.13 Minutes = 2527.8 Seconds
pub const CYCLE_S: f64 = 2527.8;

// [STRUCTS]
const HardwareTick = extern struct {
    base_ticks: isize,
    nano_ticks: isize,
};

const SockAddr = extern struct {
    family: u16,
    port: u16,
    addr: u32,
    zero: [8]u8,
};

// [OPERATIONS]

/// TUNEIN: Align the frequency (Terminal Mode).
pub fn tuneIn() void {
    var state: linux.termios = undefined;
    if (linux.syscall3(.ioctl, 0, CODEX, @intFromPtr(&state)) != 0) return;
    var lflag_int: u32 = @bitCast(state.lflag);
    lflag_int &= ~(@as(u32, XCODE));
    state.lflag = @bitCast(lflag_int);
    _ = linux.syscall3(.ioctl, 0, CODES, @intFromPtr(&state));
}

/// BIND UMBILICAL: Open the Network Bridge (Port 4213).
pub fn bindUmbilical() i32 {
    const fd_res = linux.syscall3(.socket, AF_INET, SOCK_STREAM, IPPROTO_TCP);
    const sockfd: i32 = @bitCast(@as(u32, @truncate(fd_res)));
    if (sockfd < 0) return -1;

    const port_be: u16 = @byteSwap(PORT);
    var addr = SockAddr{
        .family = AF_INET,
        .port = port_be,
        .addr = INADDR_ANY,
        .zero = [_]u8{0} ** 8,
    };

    if (linux.syscall3(.bind, @as(usize, @bitCast(sockfd)), @intFromPtr(&addr), @sizeOf(SockAddr)) != 0) {
        return -1;
    }
    _ = linux.syscall2(.listen, @as(usize, @bitCast(sockfd)), 1);
    return sockfd;
}

/// TRANSCIEVE: Scan Keyboard (0) AND Network (net_fd).
pub fn transcieve(net_fd: i32) ?u8 {
    var fds = [2]linux.pollfd{
        .{ .fd = 0, .events = VOIDSCAN, .revents = 0 },      // Keyboard
        .{ .fd = net_fd, .events = VOIDSCAN, .revents = 0 }, // Umbilical
    };

    const result = linux.syscall3(.poll, @intFromPtr(&fds), 2, 0);
    if (@as(usize, @bitCast(result)) > 0) {
        // CHECK KEYBOARD
        if ((fds[0].revents & VOIDSCAN) != 0) {
            var buffer: [1]u8 = undefined;
            const read_res = linux.syscall3(.read, 0, @intFromPtr(&buffer), 1);
            if (@as(usize, @bitCast(read_res)) == 1) return buffer[0];
        }
        
        // CHECK NETWORK
        if (net_fd > 0 and (fds[1].revents & VOIDSCAN) != 0) {
            const client_res = linux.syscall4(.accept4, @as(usize, @bitCast(net_fd)), 0, 0, 0);
            const client_fd: i32 = @bitCast(@as(u32, @truncate(client_res)));
            
            if (client_fd >= 0) {
                var buffer: [1]u8 = undefined;
                _ = linux.syscall3(.read, @as(usize, @bitCast(client_fd)), @intFromPtr(&buffer), 1);
                _ = linux.syscall1(.close, @as(usize, @bitCast(client_fd)));
                return buffer[0];
            }
        }
    }
    return null;
}

/// ZEN: The wait state (Cycle Delta).
pub fn zen(cycle_delta: f64) void {
    const total_sec = cycle_delta * CYCLE_S;
    const sec = @as(isize, @intFromFloat(total_sec));
    const frac = total_sec - @as(f64, @floatFromInt(sec));
    const nsec = @as(isize, @intFromFloat(frac * 1_000_000_000.0));

    var req = HardwareTick{ .base_ticks = sec, .nano_ticks = nsec };
    var rem = HardwareTick{ .base_ticks = 0, .nano_ticks = 0 };
    _ = linux.syscall2(.nanosleep, @intFromPtr(&req), @intFromPtr(&rem));
}
