// [@://nsible_os/src/main.zig/.-={
//   module: "Kernel Root",
//   version: "0.10.7-nightly // Banysang",
//   description: "Primary initialization, rendering loop, and sovereign identity trap.",
//   changes: "Unified Dynamic Header mapping. Deployed full Command Bible and Calculator staging in Assist Modal.",
//   philotic_inferences: "A pilot must always know their coordinates in the void. When the hands rest, the path reveals itself."

const std = @import("std");
const linux = std.os.linux;
const font = @import("glyphs.zig");
const nerve = @import("nerve.zig");   
const codex = @import("codex.zig");
const cortex = @import("cortex.zig"); 
const chronos = @import("chronos.zig");
const hunter = @import("hunter.zig");

const SYSTEM_NAME = "@NSIBLE OS";
const VERSION     = "v0.10.7-nightly";
const URI_PREFIX  = "@://";
const WIDTH: usize = 1024;
const HEIGHT: usize = 600;

var sys_host_id: [128]u8 = undefined;
var sys_host_id_len: usize = 0;

const VOID_SIZE = 42_130_000;
var void_buffer: [VOID_SIZE]u8 = undefined;
const SAP_SIZE = 88_000_000;
var sap_buffer: [SAP_SIZE]u8 = undefined;

var fb_pixels: []u32 = undefined;
var back_buffer: [WIDTH * HEIGHT]u32 = undefined;
var panic_fd: i32 = -1;

var radio_f0: f32 = 432.0;
var radio_decay: f32 = 2.5;
var radio_diss: f32 = 0.45;
var radio_phi: f32 = 1.618;
var radio_sel: u8 = 0; 
var pulse_timer: usize = 0; 
const PULSE_MAX: usize = 120;

fn loadResonance() void {
    if (std.fs.cwd().openFile("timeline/resonance.cfg", .{})) |file| {
        var buf: [128]u8 = undefined;
        if (file.readAll(&buf)) |bytes_read| {
            var iter = std.mem.splitScalar(u8, buf[0..bytes_read], '|');
            if (iter.next()) |val| radio_f0 = std.fmt.parseFloat(f32, val) catch 432.0;
            if (iter.next()) |val| radio_decay = std.fmt.parseFloat(f32, val) catch 2.5;
            if (iter.next()) |val| radio_diss = std.fmt.parseFloat(f32, val) catch 0.45;
            if (iter.next()) |val| radio_phi = std.fmt.parseFloat(f32, val) catch 1.618;
        } else |_| {}
        file.close();
    } else |_| {}
}

fn saveResonance() void {
    if (std.fs.cwd().createFile("timeline/resonance.cfg", .{})) |file| {
        var buf: [128]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d:.2}|{d:.2}|{d:.2}|{d:.3}", .{radio_f0, radio_decay, radio_diss, radio_phi}) catch return;
        file.writeAll(str) catch {};
        file.close();
    } else |_| {}
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (panic_fd >= 0) {
        _ = linux.syscall2(.dup2, @as(usize, @bitCast(panic_fd)), 2);
        const header = "\n[ @NSIBLE FATAL EXCEPTION ]\n";
        _ = linux.syscall3(.write, 2, @intFromPtr(header), header.len);
        _ = linux.syscall3(.write, 2, @intFromPtr("Message: "), 9);
        _ = linux.syscall3(.write, 2, @intFromPtr(msg.ptr), msg.len);
        _ = linux.syscall3(.write, 2, @intFromPtr("\n"), 1);
        if (trace) |t| { std.debug.dumpStackTrace(t.*); } else { std.debug.dumpCurrentStackTrace(ret_addr); }
    }
    var blink: bool = true;
    while (true) {
        var delay: usize = 0;
        while (delay < 5_000_000) : (delay += 1) { asm volatile ("pause"); }
        blink = !blink;
    }
}

fn drawChar(px: usize, py: usize, char: u8, color: u32) void {
    const bitmap = font.getBitmap(char);
    var y: usize = 0;
    while (y < 8) : (y += 1) {
        var x: usize = 0;
        while (x < 8) : (x += 1) {
            if ((bitmap[y] & (@as(u8, 1) << @intCast(7 - x))) != 0) {
                const sx = px + x;
                const sy = py + y;
                if (sx < WIDTH and sy < HEIGHT) back_buffer[sy * WIDTH + sx] = color;
            }
        }
    }
}

fn drawRect(x: usize, y: usize, w: usize, h: usize, color: u32) void {
    var dy: usize = 0;
    while (dy < h) : (dy += 1) {
        var dx: usize = 0;
        while (dx < w) : (dx += 1) {
            const sx = x + dx;
            const sy = y + dy;
            if (sx < WIDTH and sy < HEIGHT) back_buffer[sy * WIDTH + sx] = color;
        }
    }
}

fn clear(color: u32) void {
    for (&back_buffer) |*pixel| { pixel.* = color; }
}

fn print(x: usize, y: usize, text: []const u8, color: u32) void {
    var cx = x;
    for (text) |char| { drawChar(cx, y, char, color); cx += 8; }
}

fn drawHeader(is_high: bool) void {
    drawRect(0, 0, WIDTH, 20, 0x00DC143C);
    var buf: [128]u8 = undefined;
    const active_host = if (sys_host_id_len > 0) sys_host_id[0..sys_host_id_len] else "mchn:anon";
    const header = std.fmt.bufPrint(&buf, "{s} // {s} // {s}", .{SYSTEM_NAME, VERSION, active_host}) catch "HEADER_ERR";
    print(10, 6, header, 0x00FFFFFF);
    const glyph: u8 = if (is_high) 127 else 128;
    drawChar(994, 6, glyph, 0x00FFFFFF);
}

fn getUriBarY(input_len: usize, url_len: usize) usize {
    const char_w = 8; const line_h = 10; const padding = 6;
    var cursor_x: usize = 10; var lines: usize = 1;
    const active_len = if (input_len > 0) input_len + URI_PREFIX.len else url_len;

    var i: usize = 0;
    while (i < active_len) : (i += 1) {
        cursor_x += char_w;
        if (cursor_x >= WIDTH - 10) { lines += 1; cursor_x = 10 + char_w; }
    }
    const bar_height = (lines * line_h) + (padding * 2);
    return if (bar_height < HEIGHT) HEIGHT - bar_height else 0;
}

fn drawUriBar(input_buf: []const u8, input_len: usize, current_url: []const u8) void {
    const char_w = 8; const line_h = 10; const padding = 6;
    const start_y = getUriBarY(input_len, current_url.len);
    const bar_height = HEIGHT - start_y;
    drawRect(0, start_y, WIDTH, bar_height, 0x00DC143C);
    
    var cursor_x: usize = 10; var cursor_y: usize = start_y + padding;
    
    if (input_len == 0) {
        for (current_url) |char| { 
            drawChar(cursor_x, cursor_y, char, 0x00888888); 
            cursor_x += char_w;
            if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; } 
        }
    } else {
        for (URI_PREFIX) |char| { 
            drawChar(cursor_x, cursor_y, char, 0x00000000); 
            cursor_x += char_w;
            if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; } 
        }
        var i: usize = 0;
        while (i < input_len) : (i += 1) {
            const char = input_buf[i];
            drawChar(cursor_x, cursor_y, char, 0x00000000);
            cursor_x += char_w;
            if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; }
        }
    }
    drawChar(cursor_x, cursor_y, 0xDB, 0x00000000);
}

fn strikeRadio(allocator: std.mem.Allocator) void {
    const sample_rate = 8000;
    const buffer_size = 12000; 
    var pcm = allocator.alloc(u8, buffer_size) catch return;
    defer allocator.free(pcm);

    const f1 = radio_f0 * 2.05; 
    
    var i: usize = 0;
    while (i < buffer_size) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, sample_rate);
        const base_wave = @sin(2.0 * std.math.pi * radio_f0 * t);
        const over_wave = @sin(2.0 * std.math.pi * f1 * t + radio_phi);
        
        var total_wave = base_wave + (radio_diss * over_wave);
        if (total_wave > 1.0) total_wave = 1.0;
        if (total_wave < -1.0) total_wave = -1.0;
        
        const env = @exp(-radio_decay * t);
        const out = 128.0 + (127.0 * env * total_wave);
        pcm[i] = @as(u8, @intFromFloat(out));
    }

    if (std.fs.cwd().createFile("resonator.raw", .{})) |file| {
        file.writeAll(pcm) catch {};
        file.close();
        const argv = [_][]const u8{ "aplay", "-q", "-f", "U8", "-r", "8000", "-c", "1", "resonator.raw" };
        var agent = std.process.Child.init(&argv, allocator);
        agent.stdout_behavior = .Ignore; agent.stderr_behavior = .Ignore;
        _ = agent.spawn() catch {};
    } else |_| {} 
}

fn drawPulseOverlay() void {
    if (pulse_timer == 0) return;
    
    const center_y = HEIGHT / 2;
    const zoom: f32 = 0.005; 
    
    const ratio = @as(f32, @floatFromInt(pulse_timer)) / @as(f32, PULSE_MAX);
    const r = @as(u32, @intFromFloat(220.0 * ratio));
    const g = @as(u32, @intFromFloat(20.0 * ratio));
    const b = @as(u32, @intFromFloat(60.0 * ratio));
    const fade_color = (r << 16) | (g << 8) | b;
    
    const f1 = radio_f0 * 2.05;
    var x: usize = 0;
    while (x < WIDTH) : (x += 1) {
        const t = @as(f32, @floatFromInt(x)) * zoom;
        const base_wave = @sin(2.0 * std.math.pi * radio_f0 * t);
        const over_wave = @sin(2.0 * std.math.pi * f1 * t + radio_phi);
        var total_wave = base_wave + (radio_diss * over_wave);
        if (total_wave > 1.0) total_wave = 1.0;
        if (total_wave < -1.0) total_wave = -1.0;
        
        const env = @exp(-radio_decay * (t * 0.5)); 
        const amplitude = total_wave * env * 150.0; 
        
        const py = @as(isize, center_y) - @as(isize, @intFromFloat(amplitude));
        if (py > 0 and py < HEIGHT) {
            back_buffer[@as(usize, @intCast(py)) * WIDTH + x] = fade_color;
        }
    }
}

fn exitSequence() noreturn {
    clear(0x00000000);
    const stamp_x = WIDTH - 24; const stamp_y = HEIGHT - 16;
    drawChar(stamp_x, stamp_y, 127, 0x00DC143C); drawChar(stamp_x + 8, stamp_y, 128, 0x00DC143C); 
    @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);
    const term_reset = "\x1b[2J\x1b[H\x1b[?25h";
    _ = linux.syscall3(.write, 1, @intFromPtr(term_reset), term_reset.len);
    std.process.exit(0);
}

fn bootSplash(allocator: std.mem.Allocator) void {
    clear(0x00000000);
    const center_y = HEIGHT / 2;
    drawRect(0, center_y, WIDTH, 1, 0x00444444);
    
    loadResonance();

    var aiua_mass: usize = 0;
    var inference_count: usize = 0;

    if (std.fs.cwd().openFile("aiua.tome", .{})) |file| {
        if (file.stat()) |stat| {
            aiua_mass = @as(usize, @intCast(stat.size));
        } else |_| {}
        
        var buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = file.read(&buf) catch 0;
            if (bytes_read == 0) break;
            for (buf[0..bytes_read]) |b| {
                if (b == '\n') inference_count += 1;
            }
        }
        file.close();
    } else |_| {}

    const mass_units = @min(@as(f32, @floatFromInt(aiua_mass)) / 1024.0, 500.0);
    const philotic_weight = @min(@as(f32, @floatFromInt(inference_count)), 1000.0);
    
    const current_ts = @as(u64, @intCast(std.time.timestamp()));
    const cycle_progression = @as(f32, @floatFromInt(current_ts % 86400)) / 86400.0;

    const dynamic_f0 = @max(100.0, radio_f0 - (mass_units * 0.2));
    const dynamic_decay = @max(0.1, radio_decay - (cycle_progression * radio_decay * 0.75));
    const dynamic_diss = @min(1.0, radio_diss + (philotic_weight * 0.002));

    const sample_rate = 8000;
    const buffer_size = 32000; 
    var pcm = allocator.alloc(u8, buffer_size) catch return;
    defer allocator.free(pcm);

    const f1 = dynamic_f0 * 2.05;

    var sample_idx: usize = 0;
    while (sample_idx < buffer_size) : (sample_idx += 1) {
        const t = @as(f32, @floatFromInt(sample_idx)) / @as(f32, sample_rate);
        const base_wave = @sin(2.0 * std.math.pi * dynamic_f0 * t);
        const over_wave = @sin(2.0 * std.math.pi * f1 * t + radio_phi);

        var total_wave = base_wave + (dynamic_diss * over_wave);
        if (total_wave > 1.0) total_wave = 1.0;
        if (total_wave < -1.0) total_wave = -1.0;

        const env = @exp(-dynamic_decay * t);
        const out = 128.0 + (127.0 * env * total_wave);
        pcm[sample_idx] = @as(u8, @intFromFloat(out));
    }

    const zoom: f32 = 0.005;
    var x: usize = 100;
    while (x < WIDTH - 100) : (x += 1) {
        const t = @as(f32, @floatFromInt(x - 100)) * zoom;
        const base_wave = @sin(2.0 * std.math.pi * dynamic_f0 * t);
        const over_wave = @sin(2.0 * std.math.pi * f1 * t + radio_phi);
        var total_wave = base_wave + (dynamic_diss * over_wave);
        if (total_wave > 1.0) total_wave = 1.0;
        if (total_wave < -1.0) total_wave = -1.0;

        const env = @exp(-dynamic_decay * t);
        const amplitude = total_wave * env * 40.0;

        const py = @as(isize, center_y) - @as(isize, @intFromFloat(amplitude));
        if (py > 0 and py < HEIGHT) {
            back_buffer[@as(usize, @intCast(py)) * WIDTH + x] = 0x00DC143C;
        }
    }

    const tempus_var = chronos.getTempusVariance();
    const tempus_shift = @as(u64, @intFromFloat(tempus_var * 10000.0));
    var avium_resonance: u64 = 0xAE57EC4; 
    for (pcm) |b| {
        avium_resonance = (avium_resonance ^ @as(u64, b)) *% tempus_shift;
        avium_resonance = (avium_resonance << 5) | (avium_resonance >> 59); 
    }

    if (std.fs.cwd().createFile(".birdsong.sik", .{})) |sik_file| {
        var res_buf: [16]u8 = undefined;
        const res_str = std.fmt.bufPrint(&res_buf, "{x:0>16}", .{avium_resonance}) catch "0000000000000000";
        sik_file.writeAll(res_str) catch {};
        sik_file.close();
    } else |_| {}

    print(WIDTH / 2 - 80, center_y - 60, "A E S   T E C H N O L O G I E S", 0x00FFFFFF);
    print(WIDTH / 2 - 40, center_y + 30, "SYSTEM WAKING...", 0x00AAAAAA);
    var time_buf: [64]u8 = undefined;
    const time_str = chronos.getCycleString(&time_buf);
    const time_x = WIDTH / 2 - ((time_str.len * 8) / 2);
    print(time_x, center_y + 45, time_str, 0x00FFBF00);
    @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);

    if (std.fs.cwd().createFile("resonator.raw", .{})) |file| {
        file.writeAll(pcm) catch {};
        file.close();
        const argv = [_][]const u8{ "aplay", "-q", "-f", "U8", "-r", "8000", "-c", "1", "resonator.raw" };
        var agent = std.process.Child.init(&argv, allocator);
        agent.stdout_behavior = .Ignore;
        agent.stderr_behavior = .Ignore;
        _ = agent.spawn() catch {};
    } else |_| {} 
    
    codex.zen(0.00158);
}

pub fn main() !void {
    const fs = std.fs.cwd();
    fs.makeDir("timeline") catch |err| { if (err != error.PathAlreadyExists) {} };
    fs.makeDir("timeline/mems") catch |err| { if (err != error.PathAlreadyExists) {} };
    if (fs.access("aiua.tome", .{})) |_| {} else |_| { if (fs.createFile("aiua.tome", .{})) |f| { f.close(); } else |_| {} }
    if (fs.createFile("trail.tome", .{})) |f| { panic_fd = f.handle; } else |_| {}

    _ = linux.syscall5(.mount, @intFromPtr("proc"), @intFromPtr("/proc"), @intFromPtr("proc"), 0, 0);
    _ = linux.syscall5(.mount, @intFromPtr("sysfs"), @intFromPtr("/sys"), @intFromPtr("sysfs"), 0, 0);
    const fd_res = linux.syscall3(.open, @intFromPtr("/dev/fb0"), 2, 0);
    const fb_fd: i32 = @bitCast(@as(u32, @truncate(fd_res)));
    const map_len = WIDTH * HEIGHT * 4;
    const map_res = linux.syscall6(.mmap2, 0, map_len, 3, 1, @as(usize, @bitCast(fb_fd)), 0);
    const fb_ptr = @as([*]u32, @ptrFromInt(map_res));
    fb_pixels = fb_ptr[0..(WIDTH * HEIGHT)];

    nerve.init();
    codex.tuneIn();
    const vinculum_fd = codex.bindVinculum(); 

    // [!] ENUMERATE MCHN:SOCIUS IDENTITY
    var mchn_buf: [64]u8 = .{0} ** 64;
    var mchn_len: usize = 0;
    if (fs.openFile("/etc/hostname", .{})) |file| {
        if (file.readAll(&mchn_buf)) |br| {
            const tr = std.mem.trim(u8, mchn_buf[0..br], " \n\r\t");
            if (tr.len > 0) { @memcpy(mchn_buf[0..tr.len], tr); mchn_len = tr.len; }
        } else |_| {}
        file.close();
    } else |_| {}
    const mchn_str = if (mchn_len > 0) mchn_buf[0..mchn_len] else "mchn";

    var soc_buf: [64]u8 = .{0} ** 64;
    var soc_len: usize = 0;
    if (fs.openFile("aiua.tome", .{})) |file| {
        var fl_buf: [256]u8 = undefined;
        if (file.read(&fl_buf)) |br| {
            const fl = fl_buf[0..br];
            if (std.mem.indexOf(u8, fl, "//SOCIUS:")) |idx| {
                const start = idx + 9;
                var end = start;
                while (end < fl.len and fl[end] != '\n' and fl[end] != '\r') : (end += 1) {}
                const s_name = std.mem.trim(u8, fl[start..end], " ");
                if (s_name.len > 0) { @memcpy(soc_buf[0..s_name.len], s_name); soc_len = s_name.len; }
            }
        } else |_| {}
        file.close();
    } else |_| {}
    const soc_str = if (soc_len > 0) soc_buf[0..soc_len] else "anon";

    const final_id = std.fmt.bufPrint(&sys_host_id, "{s}:{s}", .{mchn_str, soc_str}) catch "mchn:anon";
    sys_host_id_len = final_id.len;

    var void_fba = std.heap.FixedBufferAllocator.init(&void_buffer);
    const void_allocator = void_fba.allocator();
    var sap_fba = std.heap.FixedBufferAllocator.init(&sap_buffer);

    bootSplash(void_allocator);
    var sys_hunter = hunter.Hunter.init(void_allocator, &sap_fba);
    defer sys_hunter.deinit();

    var is_tabula_rasa: bool = false;
    if (sys_hunter.history.items.len == 0) { is_tabula_rasa = true; } 
    else {
        const first_entry = sys_hunter.history.items[0];
        if (!std.mem.startsWith(u8, first_entry, "@AVIUM_RESONANCE:")) { is_tabula_rasa = true; }
    }
    
    var is_assist_modal: bool = false;
    var is_memo_modal: bool = false;
    var is_radio_modal: bool = false;
    var pending_memo_content: [4096]u8 = undefined;
    var pending_memo_len: usize = 0;

    var journal: [4096]u8 = undefined;
    var journal_len: usize = 0;
    var esc_seq: [8]u8 = undefined; 
    var esc_len: usize = 0;
    var seq_buf: [6]u8 = .{0} ** 6;
    var blink_timer: usize = 0;
    var is_high_cycle: bool = true;
    var dirty: bool = true;

    while (true) {
        try sys_hunter.tick();

        if (pulse_timer > 0) {
            pulse_timer -= 1;
            dirty = true;
        }

        if (codex.transcieve(vinculum_fd)) |byte| {
            dirty = true;
            
            if (is_tabula_rasa) {
                if (byte == '\n' or byte == '\r') {
                    if (journal_len > 0) {
                        const socius_alias = journal[0..journal_len];
                        var sik_buf: [16]u8 = .{ '0' } ** 16;
                        if (std.fs.cwd().openFile(".birdsong.sik", .{})) |f| {
                            _ = f.readAll(&sik_buf) catch 0; f.close();
                        } else |_| {}

                        var id_buf: [128]u8 = undefined;
                        const id_str = std.fmt.bufPrint(&id_buf, "@AVIUM_RESONANCE:[{s}]//SOCIUS:{s}", .{sik_buf, socius_alias}) catch "@AVIUM_RESONANCE:ERR";
                        sys_hunter.mutex.lock();
                        const duped_id = sys_hunter.allocator.dupe(u8, id_str) catch { sys_hunter.mutex.unlock(); continue; };
                        sys_hunter.history.insert(sys_hunter.allocator, 0, duped_id) catch { sys_hunter.allocator.free(duped_id); };
                        sys_hunter.mutex.unlock();
                        
                        sys_hunter.createMemo("Genesis", "Avium Resonance Bound. Matrix Sealed.") catch {};
                        is_tabula_rasa = false; journal_len = 0;
                    }
                } else if (byte == 127 or byte == 8) {
                    if (journal_len > 0) journal_len -= 1;
                } else if (byte >= 32 and byte <= 126) {
                    if (journal_len < 64) { journal[journal_len] = byte; journal_len += 1; }
                }
            } 
            else if (is_memo_modal) {
                if (byte == '\n' or byte == '\r') {
                    if (journal_len > 0) {
                        sys_hunter.createMemo(journal[0..journal_len], pending_memo_content[0..pending_memo_len]) catch {};
                        is_memo_modal = false; journal_len = 0;
                    }
                } else if (byte == 27) {
                    is_memo_modal = false; journal_len = 0;
                } else if (byte == 127 or byte == 8) {
                    if (journal_len > 0) journal_len -= 1;
                } else if (byte >= 32 and byte <= 126) {
                    if (journal_len < 64) { journal[journal_len] = byte; journal_len += 1; }
                }
            }
            else if (is_radio_modal) {
                if (byte == '\n' or byte == '\r') {
                    is_radio_modal = false;
                    journal_len = 0;
                    pulse_timer = PULSE_MAX; 
                    saveResonance();
                } else if (byte == 27) { 
                    is_radio_modal = false; journal_len = 0;
                } else if (byte == ' ') { 
                    strikeRadio(void_allocator);
                } else if (byte == '\t') { 
                    radio_sel = (radio_sel + 1) % 4;
                } else if (esc_len > 0) {
                    if (esc_len < 8) {
                        esc_seq[esc_len] = byte; esc_len += 1;
                        if (esc_len == 3 and esc_seq[1] == '[') {
                            if (byte == 'D') { 
                                if (radio_sel == 0) { radio_f0 -= 5.0; }
                                else if (radio_sel == 1) { radio_decay -= 0.1; }
                                else if (radio_sel == 2) { radio_diss -= 0.05; }
                                else if (radio_sel == 3) { radio_phi -= 0.05; }
                            } else if (byte == 'C') { 
                                if (radio_sel == 0) { radio_f0 += 5.0; }
                                else if (radio_sel == 1) { radio_decay += 0.1; }
                                else if (radio_sel == 2) { radio_diss += 0.05; }
                                else if (radio_sel == 3) { radio_phi += 0.05; }
                            }
                            esc_len = 0;
                        }
                    } else { esc_len = 0; }
                } else if (byte == 27) {
                    esc_len = 1; esc_seq[0] = byte;
                }
            } 
            else {
                var k: usize = 0;
                while (k < 5) : (k += 1) { seq_buf[k] = seq_buf[k+1]; }
                seq_buf[5] = byte;

                var reflex_triggered = false;
                if (std.mem.eql(u8, &seq_buf, ".!XX-.")) { exitSequence(); } 
                else if (std.mem.endsWith(u8, &seq_buf, ".![-.")) { sys_hunter.shiftScope(1); if (journal_len >= 4) journal_len -= 4; reflex_triggered = true; } 
                else if (std.mem.endsWith(u8, &seq_buf, ".!]-.")) { sys_hunter.shiftScope(-1); if (journal_len >= 4) journal_len -= 4; reflex_triggered = true; } 
                else if (std.mem.endsWith(u8, &seq_buf, "//-.")) {
                    if (journal_len >= 4) journal_len -= 4;
                    const clean_slice = std.mem.trimRight(u8, journal[0..journal_len], " ");
                    @memcpy(pending_memo_content[0..clean_slice.len], clean_slice);
                    pending_memo_len = clean_slice.len;
                    is_memo_modal = true; journal_len = 0; reflex_triggered = true;
                }

                if (!reflex_triggered) {
                    if (byte == 27) { esc_len = 1; esc_seq[0] = byte; } 
                    else if (esc_len > 0) {
                        if (esc_len < 8) {
                            esc_seq[esc_len] = byte; esc_len += 1;
                            if (esc_len == 3 and esc_seq[1] == '[') {
                                if (byte == 'A') { sys_hunter.scrollBy(-1); esc_len = 0; }
                                else if (byte == 'B') { sys_hunter.scrollBy(1); esc_len = 0; }
                                else if (byte == 'C') { sys_hunter.navigateHistory(1) catch {}; esc_len = 0; }
                                else if (byte == 'D') { sys_hunter.navigateHistory(-1) catch {}; esc_len = 0; }
                            } else if (byte == '~') {
                                 if (esc_len >= 4 and esc_seq[1] == '[') {
                                    if (esc_seq[2] == '5') { sys_hunter.scrollBy(-15); }
                                    else if (esc_seq[2] == '6') { sys_hunter.scrollBy(15); }
                                }
                                esc_len = 0;
                            }
                        } else { esc_len = 0; }
                    } else {
                         if (byte == '\n' or byte == '\r') {
                            const cmd_slice = journal[0..journal_len];
                            const response = cortex.dispatch(cmd_slice);
                            switch (response.action) {
                                .CLEAR => {}, 
                                .EXIT => exitSequence(), 
                                .SHED => { sys_hunter.shed(); journal_len = 0; },
                                .SCOPE_IN => { sys_hunter.shiftScope(1); journal_len = 0; },
                                .SCOPE_OUT => { sys_hunter.shiftScope(-1); journal_len = 0; },
                                .MEMO => { 
                                    const txt = if (response.text.len > 0) response.text else cmd_slice;
                                    @memcpy(pending_memo_content[0..txt.len], txt);
                                    pending_memo_len = txt.len;
                                    is_memo_modal = true; journal_len = 0; 
                                },
                                .ASSIST => { is_assist_modal = !is_assist_modal; journal_len = 0; },
                                .RADIO => { is_radio_modal = true; journal_len = 0; },
                                .PRINT => {
                                    journal_len = 0;
                                    for (response.text) |c| { if (journal_len < 4096) { journal[journal_len] = c; journal_len += 1; } }
                                },
                                .HUNT => {
                                    if (std.mem.eql(u8, response.text, "v")) { sys_hunter.scrollBy(1); }
                                    else if (std.mem.eql(u8, response.text, "^")) { sys_hunter.scrollBy(-1); }
                                    else {
                                        var target = response.text;
                                        if (std.mem.startsWith(u8, target, "hunt ")) target = target[5..];
                                        sys_hunter.hunt(target) catch { sys_hunter.mutex.lock(); sys_hunter.status = "FETCH_ERR"; sys_hunter.mutex.unlock(); };
                                    }
                                    journal_len = 0;
                                },
                                .AUTO_HUNT => {
                                    var auto_buf: [256]u8 = undefined;
                                    const full_target = std.fmt.bufPrint(&auto_buf, "@://{s}", .{response.text}) catch response.text;
                                    sys_hunter.hunt(full_target) catch {};
                                    journal_len = 0;
                                },
                                .PIPE_MEMO => {},
                                .NONE => { journal_len = 0; }
                            }
                        } else if (byte == 127 or byte == 8) {
                            if (journal_len > 0) journal_len -= 1;
                        } else if (byte >= 32 and byte <= 126) {
                            if (journal_len < 4096) { journal[journal_len] = byte; journal_len += 1; }
                        }
                    }
                }
            }
        }

        blink_timer += 1;
        if (blink_timer > 35) { is_high_cycle = !is_high_cycle; blink_timer = 0; dirty = true; }

        if (dirty) {
            clear(0x00000000);
            drawHeader(is_high_cycle);
            
            sys_hunter.render(&back_buffer, WIDTH, HEIGHT);
            
            if (!sys_hunter.isActive()) { 
                print(20, 50, "TIMELINE Terminal. [NO_FOCUS][ZEN]", 0x00555555); 
            }
            
            const bar_y = getUriBarY(journal_len, sys_hunter.url.len);
            
            drawPulseOverlay();

            if (is_tabula_rasa) {
                const mw = 460; const mh = 160;
                const mx = (WIDTH / 2) - (mw / 2); const my = bar_y - mh;
                drawRect(mx - 2, my - 2, mw + 4, mh + 2, 0x00DC143C); 
                drawRect(mx, my, mw, mh, 0x00000000); 
                print(mx + 20, my + 20, "[ TABULA RASA // SOCIUS REQUIRED ]", 0x00DC143C); 
                drawRect(mx + 20, my + 35, mw - 40, 1, 0x00444444);
                print(mx + 20, my + 60, "AWAITING SOCIUS DESIGNATION:", 0x00AAAAAA);
                drawRect(mx + 20, my + 85, mw - 40, 24, 0x00222222);
                print(mx + 28, my + 93, journal[0..journal_len], 0x00FFFFFF);
                if (is_high_cycle) drawChar(mx + 28 + (journal_len * 8), my + 93, 0xDB, 0x00DC143C);
            } else if (is_memo_modal) {
                const mw = 460; const mh = 140;
                const mx = (WIDTH / 2) - (mw / 2); const my = bar_y - mh;
                drawRect(mx - 2, my - 2, mw + 4, mh + 2, 0x00FFBF00); 
                drawRect(mx, my, mw, mh, 0x00000000);
                print(mx + 20, my + 20, "[ TIMELINE // MEMO DESIGNATION ]", 0x00FFBF00); 
                drawRect(mx + 20, my + 35, mw - 40, 1, 0x00444444);
                print(mx + 20, my + 60, "ENTER ARTIFACT NAME:", 0x00AAAAAA);
                drawRect(mx + 20, my + 85, mw - 40, 24, 0x00222222);
                print(mx + 28, my + 93, journal[0..journal_len], 0x00FFFFFF);
                if (is_high_cycle) drawChar(mx + 28 + (journal_len * 8), my + 93, 0xDB, 0x00FFBF00);
            } else if (is_radio_modal) {
                const mw = 520; const mh = 160;
                const mx = (WIDTH / 2) - (mw / 2); const my = bar_y - mh;
                drawRect(mx - 2, my - 2, mw + 4, mh + 2, 0x00DC143C);
                drawRect(mx, my, mw, mh, 0x00000000);
                print(mx + 20, my + 20, "[ PHILOTIC RADIO // FREQ TUNING ]", 0x00DC143C);
                drawRect(mx + 20, my + 35, mw - 40, 1, 0x00444444);

                var radio_buf: [128]u8 = undefined;
                const c_f0 = if (radio_sel == 0) @as(u32, 0x00FFFFFF) else 0x00AAAAAA;
                const str_f0 = std.fmt.bufPrint(&radio_buf, "Song (Hz)  : {d:.1}", .{radio_f0}) catch "";
                print(mx + 20, my + 60, str_f0, c_f0);
                if (radio_sel == 0) { drawChar(mx + 8, my + 60, 0x1A, 0x00FFBF00); }

                const c_dec = if (radio_sel == 1) @as(u32, 0x00FFFFFF) else 0x00AAAAAA;
                const str_dec = std.fmt.bufPrint(&radio_buf, "Decay (d)  : {d:.2}", .{radio_decay}) catch "";
                print(mx + 20, my + 80, str_dec, c_dec);
                if (radio_sel == 1) { drawChar(mx + 8, my + 80, 0x1A, 0x00FFBF00); }

                const c_diss = if (radio_sel == 2) @as(u32, 0x00FFFFFF) else 0x00AAAAAA;
                const str_diss = std.fmt.bufPrint(&radio_buf, "Diss. (m)  : {d:.2}", .{radio_diss}) catch "";
                print(mx + 260, my + 60, str_diss, c_diss);
                if (radio_sel == 2) { drawChar(mx + 248, my + 60, 0x1A, 0x00FFBF00); }

                const c_phi = if (radio_sel == 3) @as(u32, 0x00FFFFFF) else 0x00AAAAAA;
                const str_phi = std.fmt.bufPrint(&radio_buf, "\xED\x1E-off (P) : {d:.3}", .{radio_phi}) catch "";
                print(mx + 260, my + 80, str_phi, c_phi);
                if (radio_sel == 3) { drawChar(mx + 248, my + 80, 0x1A, 0x00FFBF00); }

                print(mx + 20, my + 120, "[TAB] Sel  [< / >] Dial  [SPC] Strike  [ENT] Commit", 0x00555555);
                drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
            } else if (is_assist_modal) {
                const aw = 760; const ah = 400;
                const ax = (WIDTH / 2) - (aw / 2); const ay = bar_y - ah - 10;
                drawRect(ax - 2, ay - 2, aw + 4, ah + 2, 0x00FFBF00); 
                drawRect(ax, ay, aw, ah, 0x00000000);

                print(ax + 20, ay + 20, "[ @NSIBLE COMMAND BIBLE & ASSIST ]", 0x00FFBF00);
                drawRect(ax + 20, ay + 35, aw - 40, 1, 0x00444444);

                // Column 1
                print(ax + 20, ay + 50, "[ CORE NAVIGATION ]", 0x00AAAAAA);
                print(ax + 20, ay + 70, "mchn/        : View Local Root", 0x00FFFFFF);
                print(ax + 20, ay + 90, "mchn/<path>  : Traverse Local Disk", 0x00FFFFFF);
                print(ax + 20, ay + 110, "w3.<target>  : Shadow Flight (Web)", 0x00FFFFFF);

                print(ax + 20, ay + 150, "[ ARTIFACT FORGE ]", 0x00AAAAAA);
                print(ax + 20, ay + 170, "memo <txt>   : Quick Artifact", 0x00FFFFFF);
                print(ax + 20, ay + 190, "<Title> //-. : Titled Artifact", 0x00FFFFFF);
                print(ax + 20, ay + 210, "| memo       : Pipe (Pending)", 0x00FFFFFF);

                // Column 2
                print(ax + 380, ay + 50, "[ MATRIX MANIPULATION ]", 0x00AAAAAA);
                print(ax + 380, ay + 70, "shed / drop  : Destroy active node", 0x00FFFFFF);
                print(ax + 380, ay + 90, "v / ^        : Scroll Matrix down/up", 0x00FFFFFF);
                print(ax + 380, ay + 110, "zI / zO      : Shift Banyan Scope", 0x00FFFFFF);

                print(ax + 380, ay + 150, "[ SYSTEM COMMANDS ]", 0x00AAAAAA);
                print(ax + 380, ay + 170, "radio / tune : Philotic Resonance", 0x00FFFFFF);
                print(ax + 380, ay + 190, "cycle        : Print Local Tempus", 0x00FFFFFF);
                print(ax + 380, ay + 210, ".!XX-. / exit: Terminate Matrix", 0x00FFFFFF);

                drawRect(ax + 20, ay + 250, aw - 40, 1, 0x00444444);

                // Staged Calculator
                print(ax + 20, ay + 270, "[ CALCULATOR SUB-ROUTINE ]", 0x00DC143C); 
                print(ax + 20, ay + 290, ">> ARITHMETIC ENGINE : OFFLINE", 0x00555555);
                print(ax + 20, ay + 310, ">> STATUS            : Operator sleep required before AST deployment.", 0x00555555);
                print(ax + 20, ay + 330, ">> DIRECTIVE         : Phase 3 will map bare-metal mathematics.", 0x00555555);

                print(ax + 20, ay + ah - 30, ">> Type '?' or 'assist' to dismiss.", 0x00FFBF00);
                drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
            } else {
                drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
            }
            
            @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);
            dirty = false;
        }
        codex.zen(0.000004);
    }
}

// }-.]
