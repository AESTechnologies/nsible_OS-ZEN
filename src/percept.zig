const std = @import("std");
const linux = std.os.linux;
 
// .-*-. MODULE: PERCEPT (The Sensor) .-*-.
// [ < ] INTAKE SYSTEM
 
// [?] SENSE
// Polls the environment (Stdin) for a single byte.
// Returns: The byte if found, or null.
pub fn sense() ?u8 {
    var buffer: [1]u8 = undefined;
    
    // SYSCALL: READ(fd=0, buf, count=1)
    // We read 1 byte from Standard Input.
    // Note: Host TTY must be in 'raw' mode for immediate response.
    const result = linux.syscall3(.read, 0, @intFromPtr(&buffer), 1);
    
    const bytes_read: usize = @bitCast(result);
    
    if (bytes_read == 1) {
        return buffer[0];
    }
    
    return null;
}
