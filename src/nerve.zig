// [@://nsible_os/src/nerve.zig/.-={
//   module: "Nerve Interrupt Lobe",
//   version: "0.10.2-nightly // Banysang",
//   description: "x86 32-bit Interrupt Descriptor Table (IDT) configuration and bare-metal neural wiring.",
//   changes: "Implemented EOF GZL encapsulation. Maintained Ring 0 safety bypass for host mode stability.",
//   philotic_inferences: "The system must possess a nervous system to feel the hardware; without interrupts, the machine is deaf to its own flesh."

const std = @import("std");
const builtin = @import("builtin");
 
// .-*-. HARD CONSTRAINT: ATOM N270 (32-BIT) .-*-.
 
// [.:] THE POINT (Origin)
pub const IdtPtr = packed struct {
    limit: u16,
    base: u32,
};
 
// [@] THE IDENTITY (Structure)
pub const IdtEntry = packed struct {
    offset_low: u16,
    selector: u16,      // [@] KERNEL_CS (0x08)
    zero: u8,
    type_attr: u8,      // [^] GATE_TYPE (0x8E = 32-bit Interrupt)
    offset_high: u16,
};
 
// GLOBAL STORAGE
var idt_entries: [256]IdtEntry = undefined;
var idt_ptr: IdtPtr = undefined;
 
// « EXECUTE: INIT_MOTOR
pub fn init() void {
    // 1. Set the Point [.:]
    idt_ptr.limit = (@sizeOf(IdtEntry) * 256) - 1;
    idt_ptr.base = @intFromPtr(&idt_entries);
 
    // 2. Wire the Default "Safety" Circuit
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        setGate(i, &isr_ignore);
    }
 
    // 3. Load the Motor [<<]
    // [!] SAFETY BYPASS: HOST MODE
    // Ring 0 instructions disabled for Linux Host compatibility.
    // asm volatile ("lidt (%eax)"
    //    :
    //    : [ptr] "{eax}" (&idt_ptr),
    // );
}
 
// [INTERNAL] Wiring Tool
fn setGate(n: usize, handler: *const fn () callconv(.{ .x86_interrupt = .{} }) void) void {
    const addr = @intFromPtr(handler);
    idt_entries[n].offset_low  = @as(u16, @truncate(addr));
    idt_entries[n].selector    = 0x08; // [@] Identity
    idt_entries[n].zero        = 0;
    idt_entries[n].type_attr   = 0x8E; // [^] Switch
    idt_entries[n].offset_high = @as(u16, @truncate(addr >> 16));
}
 
// [\] THE COMPRESSION (Trap)
pub fn isr_ignore() callconv(.{ .x86_interrupt = .{} }) void {
    // Compiler inserts iret/iretd automatically.
}

// }-.]
