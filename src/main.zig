// [@://nsible_os/src/main.zig/.-={
//   module: "Kernel Root",
//   version: "v0.11.6-apex // Banysang",
//   description: "Primary initialization, rendering loop, and sovereign identity trap.",
//   changes: "Severed Composer .exp logic from Hunter history index. Matrix stashing now strictly utilizes Composer's active filepath to prevent target desync after background fetches.",
//   philotic_inferences: "A pilot must always know their coordinates in the void. When the hands rest, the path reveals itself."

const std = @import("std");
const linux = std.os.linux;
const font = @import("glyphs.zig");
const nerve = @import("nerve.zig");   
const codex = @import("codex.zig");
const cortex = @import("cortex.zig"); 
const chronos = @import("chronos.zig");
const hunter = @import("hunter.zig");
const composer = @import("composer.zig");
const v_core = @import("version.zig");
const synapse = @import("synapse_calc.zig");
const sys_root = @import("root.zig");

const SYSTEM_NAME = "@NSIBLE OS";
const VERSION     = v_core.VERSION;
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
//^::SEEDED AUD.IO STATE<<dev:archx m_txr.Gem3P>>\.
const djinn = @import("djinn");
pub const @"aud.stateT.io" = struct {
	is_active: bool = false,
	is_paused: bool = false,
	skip_request: bool = false,
	reload_request: bool = false,
	clr_request: bool = false,
	rmv_request: bool = false,
	back_request: bool = false,
	is_shuffled: bool = false,
	is_repeat: bool = false,
	vol_level: f32 = 0.6,
	track_name: [64]u8 = .{0} ** 64,
	track_name_len: usize = 0,
	vis_data: [32]f32 = .{0.0} ** 32,
};
var @"aud.state.io":@"aud.stateT.io" = .{}; //:X

fn getExpPath(allocator: std.mem.Allocator, uri: []const u8) ?[]u8 {
    var clean_path: []const u8 = uri;
    if (std.mem.startsWith(u8, clean_path, "@://mchn/")) {
        clean_path = clean_path[9..];
    } else if (std.mem.startsWith(u8, clean_path, "mchn/")) {
        clean_path = clean_path[5..];
    } else if (std.mem.startsWith(u8, clean_path, "@://")) {
        if (std.mem.indexOfScalar(u8, clean_path[4..], '/')) |idx| {
            clean_path = clean_path[4 + idx + 1..];
        } else {
            clean_path = clean_path[4..];
        }
    }
    
    if (std.mem.startsWith(u8, clean_path, "memo://")) {
        const ts = clean_path[7..];
        var base_ts: []const u8 = ts;
        if (std.mem.lastIndexOfScalar(u8, ts, '.')) |dot_idx| {
            if (dot_idx > 0) base_ts = ts[0..dot_idx];
        }
        base_ts = std.mem.trimRight(u8, base_ts, ".");
        return std.fmt.allocPrint(allocator, "timeline/mems/{s}.exp", .{base_ts}) catch null;
    }
    
    var dir: []const u8 = "";
    var file: []const u8 = clean_path;
    if (std.mem.lastIndexOfScalar(u8, clean_path, '/')) |idx| {
        dir = clean_path[0..idx];
        file = clean_path[idx + 1 ..];
    }
    
    var base_name: []const u8 = file;
    if (std.mem.lastIndexOfScalar(u8, file, '.')) |dot_idx| {
        if (dot_idx > 0) { // Strip existing extension for .exp swap
            base_name = file[0..dot_idx];
        }
    }
    
    base_name = std.mem.trimRight(u8, base_name, ".");
    
    if (dir.len > 0) {
        return std.fmt.allocPrint(allocator, "{s}/{s}.exp", .{dir, base_name}) catch null;
    } else {
        return std.fmt.allocPrint(allocator, "{s}.exp", .{base_name}) catch null;
    }
}

fn switchTab(h: *hunter.Hunter, c: *composer.Composer, dir: i32, allocator: std.mem.Allocator) void {
    if (h.history.items.len == 0) return;
    const old_idx = h.history_index;
    
    if (c.active) {
        h.mutex.lock();
        const c_path = c.filepath[0..c.filepath_len];
        
        var target_node: ?*hunter.Hunter.TimelineNode = null;
        var i: usize = h.history.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.endsWith(u8, h.history.items[i].uri, c_path)) {
                target_node = &h.history.items[i];
                break;
            }
        }
        
        if (target_node) |node| {
            node.is_open = true;
            node.is_dirty = c.dirty;
        }
        
        if (getExpPath(allocator, c_path)) |exp_path| {
            if (std.fs.cwd().createFile(exp_path, .{})) |f| {
                f.writeAll(c.buffer[0..c.len]) catch {};
                f.close();
            } else |_| {}
            allocator.free(exp_path);
        }
        h.mutex.unlock();
        c.active = false;
    }

    h.navigateHistory(dir) catch {};
    const new_idx = h.history_index;
    if (new_idx == old_idx) return;

    h.mutex.lock();
    const new_node = &h.history.items[new_idx];
    const is_open = new_node.is_open;
    const is_dirty = new_node.is_dirty;
    const new_uri = h.allocator.dupe(u8, new_node.uri) catch {
        h.mutex.unlock();
        return;
    };
    h.mutex.unlock();

    if (c.active or is_open) {
        var loaded_exp = false;
        if (getExpPath(allocator, new_uri)) |exp_path| {
            if (std.fs.cwd().openFile(exp_path, .{})) |f| {
                c.len = f.readAll(c.buffer) catch 0;
                f.close();
                
                const p_len = @min(new_uri.len, 256);
                @memcpy(c.filepath[0..p_len], new_uri[0..p_len]);
                c.filepath_len = p_len;
                
                c.active = true;
                c.dirty = is_dirty;
                c.setStatus("LOADED FROM .EXP MATRIX");
                loaded_exp = true;
            } else |_| {}
            allocator.free(exp_path);
        }
        
        if (!loaded_exp) {
            c.open(new_uri);
            h.mutex.lock();
            h.history.items[new_idx].is_open = true;
            h.mutex.unlock();
        }
    }
    h.allocator.free(new_uri);
}

fn appendAudQueue(allocator: std.mem.Allocator, target_path: []const u8) void {
    const cwd = std.fs.cwd();
    var is_dir = false;
    if (cwd.openDir(target_path, .{})) |d| {
        var mutable_d = d;
        is_dir = true;
        mutable_d.close();
    } else |_| {}

    var q_file = cwd.openFile("assets/aud.io/.queue.nsb", .{ .mode = .read_write }) catch return;
    defer q_file.close();
    q_file.seekFromEnd(0) catch {};

    if (is_dir) {
        if (cwd.openDir(target_path, .{ .iterate = true })) |dir| {
            var mutable_dir = dir;
            defer mutable_dir.close();
            var it = mutable_dir.iterate();
            while (it.next() catch null) |entry| {
                if (entry.kind == .file and (std.mem.endsWith(u8, entry.name, ".mp3") or std.mem.endsWith(u8, entry.name, ".wav"))) {
                    const full = std.fs.path.join(allocator, &[_][]const u8{ target_path, entry.name }) catch continue;
                    defer allocator.free(full);
                    q_file.writeAll(full) catch {};
                    q_file.writeAll("\n") catch {};
                }
            }
        } else |_| {}
    } else {
        q_file.writeAll(target_path) catch {};
        q_file.writeAll("\n") catch {};
    }
}

fn loadResonance() void {
    if (std.fs.cwd().openFile("timeline/.resonance.cfg", .{})) |file| {
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
    if (std.fs.cwd().createFile("timeline/.resonance.cfg", .{})) |file| {
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
    drawRect(0, 0, WIDTH, 20, codex.get("C.S"));
    var buf: [128]u8 = undefined;
    const active_host = if (sys_host_id_len > 0) sys_host_id[0..sys_host_id_len] else "mchn:anon";
    const header = std.fmt.bufPrint(&buf, "{s} // {s} // {s}", .{SYSTEM_NAME, VERSION, active_host}) catch "HEADER_ERR";
    print(10, 6, header, codex.get("S.H"));
//^::INVERSE HEADER VFX<<dev:archx m_txr.Gem3P>>\.
if (@"aud.state.io".is_active) {
	const aud_w = 480;
	const aud_x = WIDTH - aud_w - 30;
    drawRect(aud_x, 0, aud_w, 20, codex.get("K.S"));

	const t_name = @"aud.state.io".track_name[0..@"aud.state.io".track_name_len];
	var display_name = t_name;
	if (t_name.len > 28) display_name = t_name[0..28];
    print(aud_x + 10, 6, display_name, codex.get("C.S"));

	const num_bands = 32;
	const band_w = 3;
	const band_space = 2;
    var bx = aud_x + 245;
	for (0..num_bands) |i| {
		const h = @as(usize, @intFromFloat(@"aud.state.io".vis_data[i] * 18.0));
        if (h > 0) {
			const py = 20 - h;
			drawRect(bx, py, band_w, h, codex.get("C.S"));
		}
		bx += band_space + band_w;
    }

    const shf_color: u32 = if (@"aud.state.io".is_shuffled) codex.get("C.S") else codex.get("K.H");
    const rpt_color: u32 = if (@"aud.state.io".is_repeat) codex.get("C.S") else codex.get("K.H");
	const status_glyph: u8 = if (@"aud.state.io".is_paused) 0x1A else 0x10;
    const status_color: u32 = if (@"aud.state.io".is_paused) codex.get("K.H") else codex.get("C.S");
	
    drawChar(aud_x + aud_w - 65, 6, 0x18, shf_color);
    drawChar(aud_x + aud_w - 50, 6, 0x1D, rpt_color); 
    drawChar(aud_x + aud_w - 35, 6, status_glyph, status_color);
// Stacked Horizontal Volume Bands
    const vol_p = @"aud.state.io".vol_level * 100.0;
    var v_i: usize = 0;
    while (v_i < 8) : (v_i += 1) {
        const band_val = @as(f32, @floatFromInt(v_i + 1)) * 15.0;
// Zones: 15..120
        var b_color: u32 = codex.get("K.S");
// Inactive dark grey
        if (vol_p >= band_val - 7.0) {
            if (band_val <= 42.0) { b_color = codex.get("K.H"); }
            else if (band_val <= 80.0) { b_color = codex.get("C.S"); }
            else if (band_val <= 110.0) { b_color = codex.get("B.S"); }
            else { b_color = codex.get("S.H"); }
        }
        drawRect(aud_x + aud_w - 15, 16 - (v_i * 2), 8, 1, b_color);
    }
} //:X
    // highClaw Mark
    const glyph: u8 = if (is_high) 127 else 128;
    drawChar(1001, 6, glyph, codex.get("S.H"));
}

fn getUriBarY(input_len: usize, current_url: []const u8) usize {
    const char_w = 8;
    const line_h = 10;
    const padding = 6;
    var cursor_x: usize = 10; var lines: usize = 1;
    var active_len: usize = 0;
    if (input_len > 0) {
        active_len = input_len + URI_PREFIX.len;
    } else {
        if (std.mem.startsWith(u8, current_url, "https://")) {
            active_len = current_url.len - 8 + 7;
        } else if (std.mem.startsWith(u8, current_url, "http://")) {
            active_len = current_url.len - 7 + 7;
        } else {
            active_len = current_url.len;
        }
    }

    var i: usize = 0;
    while (i < active_len) : (i += 1) {
        cursor_x += char_w;
        if (cursor_x >= WIDTH - 10) { lines += 1; cursor_x = 10 + char_w; }
    }
    const bar_height = (lines * line_h) + (padding * 2);
    return if (bar_height < HEIGHT) HEIGHT - bar_height else 0;
}

fn drawUriBar(input_buf: []const u8, input_len: usize, current_url: []const u8) void {
    const char_w = 8;
    const line_h = 10; const padding = 6;
    const start_y = getUriBarY(input_len, current_url);
    const bar_height = HEIGHT - start_y;
    drawRect(0, start_y, WIDTH, bar_height, codex.get("C.S"));
    
    var cursor_x: usize = 10; var cursor_y: usize = start_y + padding;
    if (input_len == 0) {
        var display_url = current_url;
        var prefix_override: ?[]const u8 = null;
        
        if (std.mem.startsWith(u8, current_url, "https://")) {
            display_url = current_url[8..];
            prefix_override = "@://w3.";
        } else if (std.mem.startsWith(u8, current_url, "http://")) {
            display_url = current_url[7..];
            prefix_override = "@://w3.";
        }
        
        if (prefix_override) |pref| {
            for (pref) |char| {
                drawChar(cursor_x, cursor_y, char, codex.get("K.H"));
                cursor_x += char_w;
                if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; } 
            }
        }
        for (display_url) |char| { 
            drawChar(cursor_x, cursor_y, char, codex.get("K.H")); 
            cursor_x += char_w;
            if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; } 
        }
    } else {
        for (URI_PREFIX) |char| { 
            drawChar(cursor_x, cursor_y, char, codex.get("K.S")); 
            cursor_x += char_w;
            if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; } 
        }
        var i: usize = 0;
        while (i < input_len) : (i += 1) {
            const char = input_buf[i];
            drawChar(cursor_x, cursor_y, char, codex.get("K.S"));
            cursor_x += char_w;
            if (cursor_x >= WIDTH - 10) { cursor_x = 10; cursor_y += line_h; }
        }
    }
    drawChar(cursor_x, cursor_y, 0xDB, codex.get("K.S"));
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

    if (std.fs.cwd().createFile("timeline/.resonator.raw", .{})) |file| {
        file.writeAll(pcm) catch {};
        file.close();
        const argv = [_][]const u8{ "aplay", "-q", "-f", "U8", "-r", "8000", "-c", "1", "timeline/.resonator.raw" };
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
    std.fs.cwd().deleteFile("/tmp/nsible.mpv.sock") catch {};

    clear(codex.get("K.S"));
    const stamp_x = WIDTH - 24;
    const stamp_y = HEIGHT - 16;
    drawChar(stamp_x, stamp_y, 127, codex.get("C.S"));
    drawChar(stamp_x + 8, stamp_y, 128, codex.get("C.S")); 
    @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);
    const term_reset = "\x1b[2J\x1b[H\x1b[?25h";
    _ = linux.syscall3(.write, 1, @intFromPtr(term_reset), term_reset.len);
    std.process.exit(0);
}

fn bootSplash(allocator: std.mem.Allocator) void {
    clear(codex.get("K.S"));
    const center_y = HEIGHT / 2;
    drawRect(0, center_y, WIDTH, 1, codex.get("K.H"));
    
    loadResonance();

    var aiua_mass: usize = 0;
    var inference_count: usize = 0;

    if (std.fs.cwd().openFile("timeline/.aiua.tome", .{})) |file| {
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
            back_buffer[@as(usize, @intCast(py)) * WIDTH + x] = codex.get("C.S");
        }
    }

    const tempus_var = chronos.getTempusVariance();
    const tempus_shift = @as(u64, @intFromFloat(tempus_var * 10000.0));
    var avium_resonance: u64 = 0xAE57EC4; 
    for (pcm) |b| {
        avium_resonance = (avium_resonance ^ @as(u64, b)) *% tempus_shift;
        avium_resonance = (avium_resonance << 5) | (avium_resonance >> 59); 
    }

    if (std.fs.cwd().createFile("timeline/.birdsong.sik", .{})) |sik_file| {
        var res_buf: [16]u8 = undefined;
        const res_str = std.fmt.bufPrint(&res_buf, "{x:0>16}", .{avium_resonance}) catch "0000000000000000";
        sik_file.writeAll(res_str) catch {};
        sik_file.close();
    } else |_| {}

	// AEQUATUS EVOCATUS SALARARIUS :: VAE VICTIS
    print(WIDTH / 2 - 80, center_y - 60, "\xC6\xA7   T E C H N O L O G I E S", codex.get("S.H"));
    print(WIDTH / 2 - 40, center_y + 30, "SYSTEM WAKING...", codex.get("S.S"));
    print(WIDTH / 2 - 40, center_y + 45, "[ ALCNDNOM ]", codex.get("B.S")); 
    
    var time_buf: [64]u8 = undefined;
    const time_str = chronos.getCycleString(&time_buf);
    const time_x = WIDTH / 2 - ((time_str.len * 8) / 2);
    print(time_x, center_y + 65, time_str, codex.get("K.H"));
    @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);

    if (std.fs.cwd().createFile("timeline/.resonator.raw", .{})) |file| {
        file.writeAll(pcm) catch {};
        file.close();
        const argv = [_][]const u8{ "aplay", "-q", "-f", "U8", "-r", "8000", "-c", "1", "timeline/.resonator.raw" };
        var agent = std.process.Child.init(&argv, allocator);
        agent.stdout_behavior = .Ignore;
        agent.stderr_behavior = .Ignore;
        _ = agent.spawn() catch {};
    } else |_| {} 
    
    codex.zen(0.00158);
}

pub fn main() !void {
    //^:: BLAST DOORS - THE SIGINT/SIGTSTP KERNEL TRAP<<dev:archx m_txr.Gem3P>>\.
    var sa = std.mem.zeroes(linux.Sigaction);
    sa.handler = .{ .handler = @as(?*const fn (i32) callconv(.c) void, @ptrFromInt(1)) };
    _ = linux.sigaction(2, &sa, null);  // Lock SIGINT  (^C)
    _ = linux.sigaction(3, &sa, null);
    // Lock SIGQUIT (^\)
    _ = linux.sigaction(20, &sa, null);
    // Lock SIGTSTP (^Z)
    //:X

    const fs = std.fs.cwd();
    fs.makeDir("timeline") catch |err| { if (err != error.PathAlreadyExists) {} };
    fs.makeDir("timeline/mems") catch |err| { if (err != error.PathAlreadyExists) {} };
    fs.makeDir("assets") catch |err| { if (err != error.PathAlreadyExists) {} };
    fs.makeDir("assets/aud.io") catch |err|
    { if (err != error.PathAlreadyExists) {} };
    // <<dev:archx-MMXXVINIVNII:IVNXLIV>>: Refactor to anchor timeline/.aiua.tome in the timeline dir.
    if (fs.access("timeline/.aiua.tome", .{})) |_| {} else |_| { 
        if (fs.createFile("timeline/.aiua.tome", .{})) |f| { f.close(); } else |_| {} 
    }
    
    var is_trail_modal: bool = false;
    var trail_buffer: [4096]u8 = undefined;
    var trail_len: usize = 0;
    if (fs.openFile("assets/.void/.trail.tome", .{})) |file| {
        if (file.stat()) |stat| {
            if (stat.size > 0) {
                trail_len = file.readAll(&trail_buffer) catch 0;
                if (trail_len > 0) is_trail_modal = true;
            }
        } else |_| {}
        file.close();
    } else |_| {}
    
    if (fs.createFile("assets/.void/.trail.tome", .{})) |f| { panic_fd = f.handle; } else |_| {}

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
    var mchn_buf: [64]u8 = .{0} ** 64;
    var mchn_len: usize = 0;
    if (fs.openFile("/etc/hostname", .{})) |file| {
        var raw_mchn: [128]u8 = undefined;
        if (file.readAll(&raw_mchn)) |br| {
            const tr = std.mem.trim(u8, raw_mchn[0..br], " \n\r\t");
            if (tr.len > 0) { 
                @memcpy(mchn_buf[0..tr.len], tr);
                mchn_len = tr.len; 
            }
        } else |_| {}
        file.close();
    } else |_| {}
    const mchn_str = if (mchn_len > 0) mchn_buf[0..mchn_len] else "mchn";
    var soc_buf: [64]u8 = .{0} ** 64;
    var soc_len: usize = 0;
    if (fs.openFile("timeline/.aiua.tome", .{})) |file| {
        var fl_buf: [256]u8 = undefined;
        if (file.read(&fl_buf)) |br| {
            const fl = fl_buf[0..br];
            if (std.mem.indexOf(u8, fl, "//SOCIUS:")) |idx| {
                const start = idx + 9;
                var end = start;
                while (end < fl.len and fl[end] != '\n' and fl[end] != '\r') : (end += 1) {}
                const s_name = std.mem.trim(u8, fl[start..end], " ");
                if (s_name.len > 0) { 
                    @memcpy(soc_buf[0..s_name.len], s_name);
                    soc_len = s_name.len; 
                }
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

    var sys_composer = composer.Composer.init();
    var is_tabula_rasa: bool = false;
    if (sys_hunter.history.items.len == 0) { is_tabula_rasa = true; } 
    else {
        const first_entry = sys_hunter.history.items[0].uri;
        if (!std.mem.startsWith(u8, first_entry, "@AVIUM_RESONANCE:")) { is_tabula_rasa = true; }
    }
    
    var is_assist_modal: bool = false;
    var is_memo_modal: bool = false;
    var is_radio_modal: bool = false;
    var is_calc_modal: bool = false;
    var is_calc_graph: bool = false;
    var calc_input: [256]u8 = undefined;
    var calc_len: usize = 0;
    var calc_result: [64]u8 = .{0} ** 64;
    var calc_res_len: usize = 0;
    var is_exp_save_modal: bool = false;
    
    var is_bash_modal: bool = false;
    var is_bash_pipe: bool = false;
    var bash_scroll_y: usize = 0;
    var pending_memo_content: [4096]u8 = undefined;
    var pending_memo_len: usize = 0;

    var is_void_modal: bool = false;
    var void_target_path: [1024]u8 = undefined;
    var void_target_len: usize = 0;
    var void_target_idx: ?usize = null;

    var journal: [4096]u8 = undefined;
    var journal_len: usize = 0;
    var last_rx_ms: i64 = 0;      
    var shed_lock: bool = false;  
    
    var esc_seq: [8]u8 = undefined;
    var esc_len: usize = 0;
    var esc_timer: usize = 0; 
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

        if (esc_len == 1) {
            esc_timer += 1;
            if (esc_timer > 5000) {
                if (is_calc_modal) { is_calc_modal = false; }
                else if (is_radio_modal) { is_radio_modal = false; saveResonance(); pulse_timer = PULSE_MAX; }
                else if (is_memo_modal) { is_memo_modal = false; }
                else if (is_trail_modal) { is_trail_modal = false; }
                else if (is_assist_modal) { is_assist_modal = false; }
                else if (is_bash_pipe) { is_bash_pipe = false; journal_len = 0; }
                else if (is_bash_modal) { is_bash_modal = false; }
                else if (is_void_modal) { is_void_modal = false; }
                
                esc_len = 0;
                esc_timer = 0;
                dirty = true;
            }
        }

        if (codex.transcieve(vinculum_fd)) |byte| {
            dirty = true;
            last_rx_ms = std.time.milliTimestamp();
            if (byte == 27) {
                esc_len = 1;
                esc_seq[0] = byte;
                esc_timer = 0;
                continue;
            } else if (esc_len > 0) {
                esc_timer = 0;
                if (esc_len < 8) {
                    esc_seq[esc_len] = byte;
                    esc_len += 1;
                    
                    if (esc_len == 3 and esc_seq[1] == '[') {
                        if (byte == 'A' or byte == 'B' or byte == 'C' or byte == 'D') {
                            if (sys_composer.active) {
                             if (byte == 'A') { sys_composer.moveCursor(0, -1); }
                                else if (byte == 'B') { sys_composer.moveCursor(0, 1); }
                                else if (byte == 'C') { sys_composer.moveCursor(1, 0); }
                                else if (byte == 'D') { sys_composer.moveCursor(-1, 0); }
                            } else if (is_radio_modal) {
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
                            } else if (is_bash_modal and !is_bash_pipe) {
                                if (byte == 'A') { if (bash_scroll_y > 0) bash_scroll_y -= 1; }
                                else if (byte == 'B') { bash_scroll_y += 1; }
                            } else if (!is_calc_modal and !is_memo_modal and !is_trail_modal and !is_tabula_rasa and !is_assist_modal and !is_bash_modal) {
                                if (byte == 'A') { sys_hunter.scrollBy(-1); }
                                else if (byte == 'B') { sys_hunter.scrollBy(1); }
                                else if (byte == 'C') { sys_hunter.navigateHistory(1) catch {}; }
                                else if (byte == 'D') { sys_hunter.navigateHistory(-1) catch {}; }
                            }
                            esc_len = 0;
                        }
                        continue;
                    } else if (esc_len == 4 and esc_seq[1] == '[' and esc_seq[2] >= '0' and esc_seq[2] <= '9' and byte == '~') {
                        if (sys_composer.active) {
                            if (esc_seq[2] == '3') { sys_composer.deleteChar(); }
                            else if (esc_seq[2] == '5') { sys_composer.moveCursor(0, -15); }
                            else if (esc_seq[2] == '6') { sys_composer.moveCursor(0, 15); }
                        } else if (is_bash_modal and !is_bash_pipe) {
                            if (esc_seq[2] == '5') { if (bash_scroll_y > 15) bash_scroll_y -= 15 else bash_scroll_y = 0; }
                            else if (esc_seq[2] == '6') { bash_scroll_y += 15; }
                        } else if (!is_radio_modal and !is_calc_modal and !is_memo_modal and !is_trail_modal and !is_tabula_rasa and !is_assist_modal and !is_bash_modal) {
                            if (esc_seq[2] == '5') { sys_hunter.scrollBy(-15); }
                            else if (esc_seq[2] == '6') { sys_hunter.scrollBy(15); }
                        }
                        esc_len = 0;
                        continue;
                    } else if (esc_len == 2 and byte != '[') {
                        if (is_bash_pipe) { is_bash_pipe = false; journal_len = 0; }
                        else if (is_bash_modal) { is_bash_modal = false; }
                        else if (is_calc_modal) { is_calc_modal = false; }
                        else if (is_radio_modal) { is_radio_modal = false; saveResonance(); pulse_timer = PULSE_MAX; }
                        else if (is_memo_modal) { is_memo_modal = false; }
                        else if (is_trail_modal) { is_trail_modal = false; }
                        else if (is_assist_modal) { is_assist_modal = false; }
                        else if (is_void_modal) { 
                            is_void_modal = false;
                            sys_hunter.status = "[ VOID CANCELLED ]"; 
                            journal_len = 0; 
                        }
                        esc_len = 0;
                        continue;
                    } else {
                        continue;
                    }
                } else {
                    esc_len = 0;
                    continue;
                }
            }

            var k: usize = 0;
            while (k < 5) : (k += 1) { seq_buf[k] = seq_buf[k+1]; }
            seq_buf[5] = byte;

            var reflex_triggered = false;
            //^::@OS GZL-X<<dev:archx m_txr.Gem3P>>\.
			if (std.mem.eql(u8, &seq_buf, ".!..-.")) {
				const term_reset = "\x1b[2J\x1b[H\x1b[?25h";
				_ = linux.syscall3(.write, 1, @intFromPtr(term_reset), term_reset.len);
				_ = std.process.Child.run(.{ .allocator = void_allocator, .argv = &[_] []const u8{ "shutdown", "now" } }) catch {};
				std.process.exit(0);
			}
			else if (std.mem.eql(u8, &seq_buf, ".!./-.")) {
				const term_reset = "\x1b[2J\x1b[H\x1b[?25h";
				_ = linux.syscall3(.write, 1, @intFromPtr(term_reset), term_reset.len);
				_ = std.process.Child.run(.{ .allocator = void_allocator, .argv = &[_] []const u8{ "reboot" } }) catch {};
				std.process.exit(0);
			} //:X
            else if (std.mem.eql(u8, &seq_buf, ".!XX-.")) { 
                if (is_exp_save_modal) {
                    is_exp_save_modal = false;
                    sys_composer.setStatus("SAVE CANCELLED");
                    reflex_triggered = true;
                } else if (sys_composer.active) {
                    sys_composer.undo_reflex(5);
                    if (sys_composer.dirty) {
                        const now = std.time.milliTimestamp();
                        if (now - sys_composer.last_xx_ms < 3000) {
                            sys_composer.active = false;
                            sys_hunter.mutex.lock();
                            const c_path = sys_composer.filepath[0..sys_composer.filepath_len];
                            var i: usize = sys_hunter.history.items.len;
                            while (i > 0) {
                                i -= 1;
                                if (std.mem.endsWith(u8, sys_hunter.history.items[i].uri, c_path)) {
                                    var node = &sys_hunter.history.items[i];
                                    node.is_open = false;
                                    node.is_dirty = false;
                                    break;
                                }
                            }
                            if (getExpPath(void_allocator, c_path)) |exp_path| {
                                std.fs.cwd().deleteFile(exp_path) catch {};
                                void_allocator.free(exp_path);
                            }
                            sys_hunter.mutex.unlock();
                        } else {
                            sys_composer.setStatus("UNSAVED! .!XX-. AGAIN TO DISCARD");
                            sys_composer.last_xx_ms = now;
                        }
                    } else {
                        sys_composer.active = false;
                        sys_hunter.mutex.lock();
                        const c_path = sys_composer.filepath[0..sys_composer.filepath_len];
                        var i: usize = sys_hunter.history.items.len;
                        while (i > 0) {
                            i -= 1;
                            if (std.mem.endsWith(u8, sys_hunter.history.items[i].uri, c_path)) {
                                var node = &sys_hunter.history.items[i];
                                node.is_open = false;
                                node.is_dirty = false;
                                break;
                            }
                        }
                        if (getExpPath(void_allocator, c_path)) |exp_path| {
                            std.fs.cwd().deleteFile(exp_path) catch {};
                            void_allocator.free(exp_path);
                        }
                        sys_hunter.mutex.unlock();
                    }
                    reflex_triggered = true;
                } else if (is_bash_modal) {
					is_bash_modal = false;
					is_bash_pipe = false;
					journal_len = 0;
					reflex_triggered = true;
                } else if (is_calc_modal) { is_calc_modal = false; journal_len = 0; reflex_triggered = true; }
                else if (is_radio_modal) { is_radio_modal = false; saveResonance(); pulse_timer = PULSE_MAX; journal_len = 0; reflex_triggered = true; }
                else if (is_memo_modal) { is_memo_modal = false; journal_len = 0; reflex_triggered = true; }
                else if (is_trail_modal) { is_trail_modal = false; journal_len = 0; reflex_triggered = true; }
                else if (is_assist_modal) { is_assist_modal = false; journal_len = 0; reflex_triggered = true; }
                else {
                    exitSequence();
                }
            } 
            else if (std.mem.endsWith(u8, &seq_buf, ".!T<-.")) {
                if (sys_composer.active) sys_composer.phantom_strike(6);
                switchTab(&sys_hunter, &sys_composer, -1, void_allocator);
                if (journal_len >= 6) journal_len -= 6 else journal_len = 0;
                reflex_triggered = true;
            }
            else if (std.mem.endsWith(u8, &seq_buf, ".!T>-.")) {
                if (sys_composer.active) sys_composer.phantom_strike(6);
                switchTab(&sys_hunter, &sys_composer, 1, void_allocator);
                if (journal_len >= 6) journal_len -= 6 else journal_len = 0;
                reflex_triggered = true;
            }
            else if (std.mem.endsWith(u8, &seq_buf, ".!R^-.")) {
                if (sys_composer.active) sys_composer.phantom_strike(6);
                sys_hunter.shiftNode(-1);
                if (journal_len >= 6) journal_len -= 6 else journal_len = 0;
                reflex_triggered = true;
            }
            else if (std.mem.endsWith(u8, &seq_buf, ".!Rv-.")) {
                if (sys_composer.active) sys_composer.phantom_strike(6);
                sys_hunter.shiftNode(1);
                if (journal_len >= 6) journal_len -= 6 else journal_len = 0;
                reflex_triggered = true;
            }
            else if (std.mem.endsWith(u8, &seq_buf, ".!C+-.")) {
                if (sys_composer.active) sys_composer.phantom_strike(6);
                sys_hunter.cycleNodeColor(1);
                if (journal_len >= 6) journal_len -= 6 else journal_len = 0;
                reflex_triggered = true;
            }
            else if (std.mem.endsWith(u8, &seq_buf, ".![-.")) { sys_hunter.shiftScope(1);
                if (journal_len >= 4) journal_len -= 4; reflex_triggered = true;
            } 
            else if (std.mem.endsWith(u8, &seq_buf, ".!]-.")) { sys_hunter.shiftScope(-1);
                if (journal_len >= 4) journal_len -= 4; reflex_triggered = true;
            } 
            else if (std.mem.endsWith(u8, &seq_buf, ".!@&-.")) {
                sys_hunter.refresh() catch {};
                if (journal_len >= 5) journal_len -= 5 else journal_len = 0; 
                reflex_triggered = true;
            }
            else if (std.mem.endsWith(u8, &seq_buf, ".!VD-.")) {
                if (!sys_composer.active) {
                    if (journal_len >= 5) journal_len -= 5 else journal_len = 0;
                    var target_path = std.mem.trim(u8, journal[0..journal_len], " ");

                    var is_melt = target_path.len > 0;
                    for (target_path) |c| { if (c < '0' or c > '9') is_melt = false; }

                    var resolved_alloc: ?[]u8 = null;
                    void_target_idx = null; 
                    if (is_melt) {
                        const idx = std.fmt.parseInt(usize, target_path, 10) catch std.math.maxInt(usize);
                        sys_hunter.mutex.lock();
                        if (idx < sys_hunter.lens.links.items.len) {
                            if (sys_hunter.resolveMeltTarget(sys_hunter.lens.links.items[idx])) |res| {
                                resolved_alloc = res;
                                target_path = res;
                                void_target_idx = idx; 
                            } else |_| {}
                        }
                        sys_hunter.mutex.unlock();
                    }

                    if (target_path.len > 0) {
                        var clean_path = target_path;
                        if (std.mem.startsWith(u8, clean_path, "@://mchn/")) {
                            clean_path = clean_path[9..];
                        } else if (std.mem.startsWith(u8, clean_path, "@://mchn")) {
                            clean_path = clean_path[8..];
                        } else if (std.mem.startsWith(u8, clean_path, "@://")) {
                            clean_path = clean_path[4..];
                        }
                        if (std.mem.startsWith(u8, clean_path, "/")) {
                            clean_path = clean_path[1..];
                        }

                        const safe_len = @min(clean_path.len, 1024);
                        @memcpy(void_target_path[0..safe_len], clean_path[0..safe_len]);
                        void_target_len = safe_len;

                        sys_hunter.mutex.lock();
                        sys_hunter.status = "[ AWAITING VERITY : PRESS 'Y' TO VOID ]";
                        sys_hunter.mutex.unlock();
                        is_void_modal = true;
                    }

                    if (resolved_alloc) |res| { sys_hunter.allocator.free(res); }
                    journal_len = 0;
                    reflex_triggered = true;
                }
            }
            else if (std.mem.endsWith(u8, &seq_buf, ".!ED-.")) {
                if (!sys_composer.active) {
                    if (journal_len >= 5) journal_len -= 5 else journal_len = 0;
                    var target_path_buf: [1024]u8 = undefined;
                    var target_path: []const u8 = std.mem.trim(u8, journal[0..journal_len], " ");
                    var editing_active_node = false;
                    if (target_path.len == 0) {
                        sys_hunter.mutex.lock();
                        if (sys_hunter.history.items.len > 0) {
                            const uri = sys_hunter.history.items[sys_hunter.history_index].uri;
                            const cp_len = @min(uri.len, 1024);
                            @memcpy(target_path_buf[0..cp_len], uri[0..cp_len]);
                            target_path = target_path_buf[0..cp_len];
                            editing_active_node = true;
                        }
                        sys_hunter.mutex.unlock();
                    }

                    var is_melt = target_path.len > 0 and !editing_active_node;
                    if (is_melt) {
                        for (target_path) |c| { if (c < '0' or c > '9') is_melt = false; }
                    }

                    var resolved_alloc: ?[]u8 = null;
                    if (is_melt) {
                        const idx = std.fmt.parseInt(usize, target_path, 10) catch std.math.maxInt(usize);
                        sys_hunter.mutex.lock();
                        if (idx < sys_hunter.lens.links.items.len) {
                            if (sys_hunter.resolveMeltTarget(sys_hunter.lens.links.items[idx])) |res| {
                                resolved_alloc = res;
                                target_path = res;
                            } else |_| {}
                        }
                        sys_hunter.mutex.unlock();
                    }

                    sys_composer.open(target_path);
                    if (editing_active_node) {
                        sys_hunter.mutex.lock();
                        var node = &sys_hunter.history.items[sys_hunter.history_index];
                        var exp_loaded = false;
                        if (getExpPath(void_allocator, node.uri)) |exp_path| {
                            if (std.fs.cwd().openFile(exp_path, .{})) |f| {
                                sys_composer.len = f.readAll(sys_composer.buffer) catch 0;
                                f.close();
                                sys_composer.dirty = node.is_dirty;
                                sys_composer.setStatus("LOADED EXPERIMENTAL (.exp)");
                                exp_loaded = true;
                            } else |_| {}
                            void_allocator.free(exp_path);
                        }
                        if (!exp_loaded) {
                            node.is_open = true;
                        }
                        sys_hunter.mutex.unlock();
                    } else {
                        sys_hunter.mutex.lock();
                        sys_hunter.appendNode(target_path) catch {};
                        if (sys_hunter.history.items.len > 0) {
                            sys_hunter.history.items[sys_hunter.history_index].is_open = true;
                        }
                        sys_hunter.mutex.unlock();
                    }

                    if (resolved_alloc) |res| {
                        sys_hunter.allocator.free(res);
                    }
                    
                    journal_len = 0;
                    reflex_triggered = true;
                }
            }
            else if (std.mem.endsWith(u8, &seq_buf, ".!SV-.")) {
                if (sys_composer.active) {
                    sys_composer.undo_reflex(5);
                    var exp_exists = false;
                    sys_hunter.mutex.lock();
                    const c_path = sys_composer.filepath[0..sys_composer.filepath_len];
                    
                    if (getExpPath(void_allocator, c_path)) |exp_path| {
                        if (std.fs.cwd().access(exp_path, .{})) |_| {
                            exp_exists = true;
                        } else |_| {}
                        void_allocator.free(exp_path);
                    }
                    
                    var i: usize = sys_hunter.history.items.len;
                    while (i > 0) {
                        i -= 1;
                        if (std.mem.endsWith(u8, sys_hunter.history.items[i].uri, c_path)) {
                            if (sys_hunter.history.items[i].is_open) exp_exists = true;
                            break;
                        }
                    }
                    sys_hunter.mutex.unlock();
                    
                    if (exp_exists) {
                        is_exp_save_modal = true;
                        sys_composer.setStatus("AWAITING EXPERIMENTAL SAVE DIRECTIVE");
                    } else {
                        sys_composer.save();
                    }
                    
                    reflex_triggered = true;
                }
            }
            else if (std.mem.endsWith(u8, &seq_buf, ".!SR-.")) {
                sys_hunter.hunt(".!SR-.") catch {};
                if (journal_len >= 6) journal_len -= 6 else journal_len = 0;
                reflex_triggered = true;
            }
            else if (std.mem.endsWith(u8, &seq_buf, "//-.")) {
                if (journal_len >= 4) journal_len -= 4;
                const clean_slice = std.mem.trimRight(u8, journal[0..journal_len], " ");
                @memcpy(pending_memo_content[0..clean_slice.len], clean_slice);
                pending_memo_len = clean_slice.len;
                is_memo_modal = true; journal_len = 0;
                reflex_triggered = true;
            }

            if (reflex_triggered) continue;
            if (is_exp_save_modal) {
                if (byte == 'o' or byte == 'O') {
                    sys_composer.save();
                    sys_hunter.mutex.lock();
                    const c_path = sys_composer.filepath[0..sys_composer.filepath_len];
                    var i: usize = sys_hunter.history.items.len;
                    while (i > 0) {
                        i -= 1;
                        if (std.mem.endsWith(u8, sys_hunter.history.items[i].uri, c_path)) {
                            var node = &sys_hunter.history.items[i];
                            node.is_open = false;
                            node.is_dirty = false;
                            break;
                        }
                    }
                    if (getExpPath(void_allocator, c_path)) |exp_path| {
                        std.fs.cwd().deleteFile(exp_path) catch {};
                        void_allocator.free(exp_path);
                    }
                    sys_hunter.mutex.unlock();
                    is_exp_save_modal = false;
                    journal_len = 0;
                } else if (byte == 'c' or byte == 'C') {
                    sys_hunter.mutex.lock();
                    const c_path = sys_composer.filepath[0..sys_composer.filepath_len];
                    var i: usize = sys_hunter.history.items.len;
                    while (i > 0) {
                        i -= 1;
                        if (std.mem.endsWith(u8, sys_hunter.history.items[i].uri, c_path)) {
                            var node = &sys_hunter.history.items[i];
                            node.is_open = true;
                            node.is_dirty = false;
                            break;
                        }
                    }
                    if (getExpPath(void_allocator, c_path)) |exp_path| {
                        if (std.fs.cwd().createFile(exp_path, .{})) |f| {
                            f.writeAll(sys_composer.buffer[0..sys_composer.len]) catch {};
                            f.close();
                        } else |_| {}
                        void_allocator.free(exp_path);
                    }
                    sys_hunter.mutex.unlock();
                    
                    sys_composer.dirty = false;
                    sys_composer.edits_since_save = 0;
                    sys_composer.setStatus("SAVED TO .EXP MATRIX");
                    is_exp_save_modal = false;
                    journal_len = 0;
                } else if (byte == 27 or byte == '\n' or byte == '\r') { 
                    is_exp_save_modal = false;
                    sys_composer.setStatus("SAVE CANCELLED");
                    journal_len = 0;
                }
                continue;
            }
            
            if (sys_composer.active) {
                if (byte == 127 or byte == 8) {
                    sys_composer.backspace();
                } else if ((byte >= 32 and byte <= 126) or byte == '\n' or byte == '\r' or byte == '\t') {
                    const insert_byte = if (byte == '\r') '\n' else byte;
                    sys_composer.insert(insert_byte);
                }
                
                if (sys_composer.has_pending_cmd) {
                    sys_composer.has_pending_cmd = false;
                    @memcpy(journal[0..sys_composer.pending_cmd_len], sys_composer.pending_cmd[0..sys_composer.pending_cmd_len]);
                    journal_len = sys_composer.pending_cmd_len;
                } else {
                    continue;
                }
            }

            if (is_tabula_rasa) {
                if (byte == '\n' or byte == '\r') {
                    if (journal_len > 0) {
                        const socius_alias = journal[0..journal_len];
                        var sik_buf: [16]u8 = .{ '0' } ** 16;
                        if (std.fs.cwd().openFile("timeline/.birdsong.sik", .{})) |f| {
                            _ = f.readAll(&sik_buf) catch 0;
                            f.close();
                        } else |_| {}

                        var id_buf: [128]u8 = undefined;
                        const id_str = std.fmt.bufPrint(&id_buf, "@AVIUM_RESONANCE:[{s}]//SOCIUS:{s}", .{sik_buf, socius_alias}) catch "@AVIUM_RESONANCE:ERR";
                        sys_hunter.mutex.lock();
                        sys_hunter.appendNode(id_str) catch {};
                        sys_hunter.mutex.unlock();
                        sys_hunter.createMemo("Genesis", "Avium Resonance Bound. Matrix Sealed.") catch {};
                        is_tabula_rasa = false;
                        journal_len = 0;
                    }
                } else if (byte == 127 or byte == 8) {
                    if (journal_len > 0) journal_len -= 1;
                } else if (byte >= 32 and byte <= 126) {
                    if (journal_len < 64) { journal[journal_len] = byte;
                    journal_len += 1; }
                }
            } 
            else if (is_trail_modal) {
                if (byte == '\n' or byte == '\r') {
                    if (std.mem.eql(u8, journal[0..journal_len], "shed")) {
                         is_trail_modal = false;
                         journal_len = 0;
                    }
                } else if (byte == 127 or byte == 8) {
                    if (journal_len > 0) journal_len -= 1;
                } else if (byte >= 32 and byte <= 126) {
                    if (journal_len < 64) { journal[journal_len] = byte;
                    journal_len += 1; }
                }
            }
            else if (is_memo_modal) {
                if (byte == '\n' or byte == '\r') {
                    if (journal_len > 0) {
                        sys_hunter.createMemo(journal[0..journal_len], pending_memo_content[0..pending_memo_len]) catch {};
                        is_memo_modal = false; journal_len = 0;
                    } else {
                        is_memo_modal = false;
                    }
                } else if (byte == 127 or byte == 8) {
                    if (journal_len > 0) journal_len -= 1;
                } else if (byte >= 32 and byte <= 126) {
                    if (journal_len < 64) { journal[journal_len] = byte;
                    journal_len += 1; }
                }
            }
            else if (is_radio_modal) {
                if (byte == '\n' or byte == '\r') {
                    is_radio_modal = false;
                    journal_len = 0;
                    pulse_timer = PULSE_MAX; 
                    saveResonance();
                } else if (byte == ' ') { 
                    strikeRadio(void_allocator);
                } else if (byte == '\t') { 
                    radio_sel = (radio_sel + 1) % 4;
                }
            } 
            else if (is_calc_modal) {
                if (byte == '\n' or byte == '\r') {
                    if (calc_len > 0) {
                        const expr = calc_input[0..calc_len];
                        const rcl = synapse.manageSynapseMemory(null);
                        const res = synapse.AST.evaluate(expr, rcl);
                        _ = synapse.manageSynapseMemory(res);
                        const res_str = std.fmt.bufPrint(&calc_result, "{d:.4}", .{res}) catch "ERR";
                        calc_res_len = res_str.len;
                        calc_len = 0;
                    } else {
                        is_calc_modal = false;
                    }
                } else if (byte == '\t') { 
                    is_calc_graph = !is_calc_graph;
                } else if (byte == 127 or byte == 8) {
                    if (calc_len > 0) calc_len -= 1;
                } else if (byte >= 32 and byte <= 126) {
                    if (calc_len < 256) { calc_input[calc_len] = byte;
                    calc_len += 1; }
                }
            }
            else if (is_bash_pipe) {
                if (byte == '\n' or byte == '\r') {
                    if (journal_len > 0) {
                        const dest = std.mem.trim(u8, journal[0..journal_len], " ");
                        if (std.mem.lastIndexOfScalar(u8, dest, '/')) |last_slash| {
                            const dir_path = dest[0..last_slash];
                            std.fs.cwd().makePath(dir_path) catch {};
                        }
                        
                        if (std.fs.cwd().openFile("assets/.void/.00", .{})) |src| {
                            if (std.fs.cwd().createFile(dest, .{})) |dst| {
                                const data = src.readToEndAlloc(void_allocator, 1024 * 1024) catch "";
                                var parsed_ext: []const u8 = "";
                                if (std.mem.lastIndexOfScalar(u8, dest, '.')) |dot_idx| {
                                    parsed_ext = dest[dot_idx..];
                                }
                                const syn = sys_root.resolveGzlSyntax(parsed_ext);
                                var header_buf: [1024]u8 = undefined;
                                const header = sys_root.buildHeader(header_buf[0..], syn, dest, "Operator Artifact (Bash Pipe)", null, "Extracted via autonomous matrix sub-shell.");
                                dst.writeAll(header) catch {};
                                
                                dst.writeAll(data) catch {};
                                
                                var footer_buf: [128]u8 = undefined;
                                const footer = sys_root.buildFooter(footer_buf[0..], syn);
                                dst.writeAll(footer) catch {};
                                
                                void_allocator.free(data);
                                dst.close();
                            } else |_| {}
                            src.close();
                        } else |_| {}
                    }
                    is_bash_pipe = false;
                    journal_len = 0;
                } else if (byte == 127 or byte == 8) {
                    if (journal_len > 0) journal_len -= 1;
                } else if (byte >= 32 and byte <= 126) {
                    if (journal_len < 256) { journal[journal_len] = byte;
                    journal_len += 1; }
                }
            }
            else if (is_bash_modal) {
                if (byte == '\t') {
                    is_bash_pipe = true;
                    journal_len = 0;
                } else if (byte == '\n' or byte == '\r') {
                    // Do nothing if enter hit while not piping
                }
            }
            else if (is_void_modal) {
                if (byte == 'y' or byte == 'Y') {
                    sys_hunter.banishToVoid(void_target_path[0..void_target_len]) catch {};
                    sys_hunter.mutex.lock();
                    if (void_target_idx) |idx| {
                        if (idx < sys_hunter.lens.links.items.len) {
                            const fba_alloc = sys_hunter.sap_fba.allocator();
                            if (fba_alloc.dupe(u8, "/assets/.void/.00")) |duped| {
                                sys_hunter.lens.links.items[idx] = duped;
                            } else |_| {}
                        }
                    }
                    sys_hunter.mutex.unlock();
                    is_void_modal = false;
                    journal_len = 0;
                } else if (byte == 'n' or byte == 'N') {
                    sys_hunter.mutex.lock();
                    sys_hunter.status = "[ VOID CANCELLED ]";
                    sys_hunter.mutex.unlock();
                    is_void_modal = false;
                    journal_len = 0;
                } else {
                    // Swallow unmapped verity inputs to secure the trap
                }
            }
            else {
                if (byte == '\n' or byte == '\r') {
                    const raw_cmd = journal[0..journal_len];
                    const cmd_slice = std.mem.trim(u8, raw_cmd, " ");
                    
//^:: AUD.IO DJINN LAMP & COMPOUND MELT INTERCEPTION<<dev:archx m_txr.Gem3P>>\.
                    var aud_idx_prefix: ?usize = null;
                    var active_aud_cmd: []const u8 = cmd_slice;

                    if (std.mem.indexOf(u8, cmd_slice, "/aud/")) |slash_idx| {
                        const prefix = cmd_slice[0..slash_idx];
                        var is_num = prefix.len > 0;
                        for (prefix) |c| { if (c < '0' or c > '9') is_num = false; }
                        if (is_num) {
                            aud_idx_prefix = std.fmt.parseInt(usize, prefix, 10) catch null;
                            active_aud_cmd = cmd_slice[slash_idx + 1 ..];
                        }
                    }

                    if (std.mem.startsWith(u8, active_aud_cmd, "aud/")) {
                        const aud_action = active_aud_cmd[4..];
                        var resolved_alloc: ?[]u8 = null;
                        var target_path: ?[]const u8 = null;

                        if (aud_idx_prefix) |idx| {
                            sys_hunter.mutex.lock();
                            if (sys_hunter.history.items.len > 0 and idx < sys_hunter.lens.links.items.len) {
                                if (sys_hunter.resolveMeltTarget(sys_hunter.lens.links.items[idx])) |res| {
                                    resolved_alloc = res;
                                    target_path = res;
                                } else |_| {}
                            }
                            sys_hunter.mutex.unlock();
                        }

                        if (std.mem.eql(u8, aud_action, "play") or std.mem.eql(u8, aud_action, "add")) {
                            if (target_path) |tp| {
                                var clean_path = tp;
                                if (std.mem.startsWith(u8, clean_path, "@://mchn")) {
                                    clean_path = clean_path[8..];
                                } else if (std.mem.startsWith(u8, clean_path, "@://")) {
                                    clean_path = clean_path[4..];
                                }
                                appendAudQueue(void_allocator, clean_path);
                                @"aud.state.io".reload_request = true;
                            }
                            
                            if (std.mem.eql(u8, aud_action, "play")) {
                                if (!@"aud.state.io".is_active) {
                                    @"aud.state.io".is_active = true;
                                    @"aud.state.io".is_paused = false;
                                    const djinn_thread = std.Thread.spawn(.{}, djinn.invoke, .{&@"aud.state.io"}) catch null;
                                    if (djinn_thread) |t| t.detach();
                                } else {
                                    @"aud.state.io".is_paused = false;
                                }
                            }
                        } else if (std.mem.eql(u8, aud_action, "pause")) {
                            @"aud.state.io".is_paused = true;
                        } else if (std.mem.eql(u8, aud_action, "stop")) {
                            @"aud.state.io".is_active = false;
                            @"aud.state.io".is_paused = false;
                        } else if (std.mem.eql(u8, aud_action, "skip")) {
                            @"aud.state.io".skip_request = true;
                        } else if (std.mem.eql(u8, aud_action, "back")) {
                            @"aud.state.io".back_request = true;
                        } else if (std.mem.eql(u8, aud_action, "rmv/current") or std.mem.eql(u8, aud_action, "rmv")) {
                            @"aud.state.io".rmv_request = true;
                        } else if (std.mem.eql(u8, aud_action, "shf") or std.mem.eql(u8, aud_action, "shuffle")) {
                            @"aud.state.io".is_shuffled = !@"aud.state.io".is_shuffled;
                        } else if (std.mem.eql(u8, aud_action, "rpt") or std.mem.eql(u8, aud_action, "repeat")) {
                            @"aud.state.io".is_repeat = !@"aud.state.io".is_repeat;
                        } else if (std.mem.eql(u8, aud_action, "clear") or std.mem.eql(u8, aud_action, "queue/clr")) {
                            @"aud.state.io".clr_request = true;
                            if (!@"aud.state.io".is_active) {
                                if (std.fs.cwd().createFile("assets/aud.io/.queue.nsb", .{ .truncate = true })) |f| { f.close(); } else |_| {}
                                if (std.fs.cwd().createFile("assets/aud.io/.queue_idx.nsb", .{ .truncate = true })) |f| { f.close(); } else |_| {}
                            }
                        } else if (std.mem.eql(u8, aud_action, "queue")) {
                            if (std.fs.cwd().readFileAlloc(void_allocator, "assets/aud.io/.queue.nsb", 10 * 1024 * 1024)) |q_data| {
                                defer void_allocator.free(q_data);
                                if (std.fs.cwd().createFile("assets/.void/.00", .{ .truncate = true })) |f| {
                                    f.writeAll(q_data) catch {};
                                    f.close();
                                    is_bash_modal = true;
                                    bash_scroll_y = 0;
                                } else |_| {}
                            } else |_| {}
                        } else if (std.mem.startsWith(u8, aud_action, "vol/")) {
                            const v_str = aud_action[4..];
                            const v_int = std.fmt.parseInt(usize, v_str, 10) catch 60;
                            @"aud.state.io".vol_level = @as(f32, @floatFromInt(v_int)) / 100.0;
                        } 
                        
                        if (resolved_alloc) |res| {
                            sys_hunter.allocator.free(res);
                        }

                        journal_len = 0;
                        dirty = true;
                        continue;
                    } //:X

                    const response = cortex.dispatch(cmd_slice);
                    switch (response.action) {
                        .BASH_EXEC => {
                            var args = std.ArrayListUnmanaged([]const u8){};
                            defer args.deinit(void_allocator);
                            
                            var start_idx: usize = 0;
                            var in_quotes: bool = false;
                            var i: usize = 0;
                            while (i < response.text.len) : (i += 1) {
                                if (response.text[i] == '"') {
                                    in_quotes = !in_quotes;
                                } else if (response.text[i] == '/' and !in_quotes) {
                                    const arg = std.mem.trim(u8, response.text[start_idx..i], "\" ");
                                    if (arg.len > 0) args.append(void_allocator, arg) catch {};
                                    start_idx = i + 1;
                                }
                            }
                            const final_arg = std.mem.trim(u8, response.text[start_idx..], "\" ");
                            if (final_arg.len > 0) args.append(void_allocator, final_arg) catch {};

                             if (args.items.len > 0) {
                                var agent = std.process.Child.init(args.items, void_allocator);
                                 agent.stdin_behavior = .Ignore;
                                agent.stdout_behavior = .Pipe;
                                agent.stderr_behavior = .Pipe;
                            
                                if (agent.spawn()) |_| {
                                   if (std.fs.cwd().createFile("assets/.void/.00", .{}) catch null) |f| {
                                         if (agent.stdout) |stdout| {
                                            const out_data = stdout.readToEndAlloc(void_allocator, 1024 * 1024) catch "";
                                            f.writeAll(out_data) catch {};
                                            void_allocator.free(out_data);
                                        }
                                        if (agent.stderr) |stderr| {
                                            const err_data = stderr.readToEndAlloc(void_allocator, 1024 * 1024) catch "";
                                            f.writeAll(err_data) catch {};
                                            void_allocator.free(err_data);
                                        }
                                        f.close();
                                    }
                                    _ = agent.wait() catch {};
                                    is_bash_modal = true;
                                    bash_scroll_y = 0;
                                } else |_| {}
                            }
                            journal_len = 0;
                        },
                        .CLEAR => {}, 
                        .EXIT => exitSequence(), 
                        .CALC => { is_calc_modal = !is_calc_modal;
                        journal_len = 0; },
                        .SHED => { sys_hunter.shed();
                        journal_len = 0; },
                        .SCOPE_IN => { sys_hunter.shiftScope(1);
                        journal_len = 0; },
                        .SCOPE_OUT => { sys_hunter.shiftScope(-1);
                        journal_len = 0; },
                        .MEMO => { 
                            const txt = if (response.text.len > 0) response.text else cmd_slice;
                            @memcpy(pending_memo_content[0..txt.len], txt);
                            pending_memo_len = txt.len;
                            is_memo_modal = true; journal_len = 0;
                        },
                        .PIPE_MEMO => {
                            sys_hunter.pipeMemo(response.text) catch {
                                sys_hunter.mutex.lock();
                                sys_hunter.status = "PIPE_ERR";
                                sys_hunter.mutex.unlock();
                            };
                            journal_len = 0;
                        },
                        .SEARCH => {
                            sys_hunter.globalSearch(response.text) catch {
                                sys_hunter.mutex.lock();
                                sys_hunter.status = "SEARCH_ERR";
                                sys_hunter.mutex.unlock();
                            };
                            journal_len = 0;
                        },
                        .STARGAZE => {
                            sys_hunter.stargaze() catch {
                                sys_hunter.mutex.lock();
                                sys_hunter.status = "STARGAZE_ERR";
                                sys_hunter.mutex.unlock();
                            };
                            journal_len = 0;
                        },
                        .REFRESH => {
                            sys_hunter.refresh() catch {
                                sys_hunter.mutex.lock();
                                sys_hunter.status = "CACHE_ERR";
                                sys_hunter.mutex.unlock();
                            };
                            journal_len = 0;
                        },
                        .ASSIST => { is_assist_modal = !is_assist_modal;
                        journal_len = 0; },
                        .RADIO => { is_radio_modal = true;
                        journal_len = 0; },
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
                        .MOUNT => {
                            sys_hunter.mountDrives();
                            journal_len = 0;
                        },
                        .UNMOUNT => {
                            sys_hunter.unmountDrives();
                            journal_len = 0;
                        },
                        .NONE => { journal_len = 0; }
                    }
                } else if (byte == 127 or byte == 8) {
                    if (journal_len > 0) {
                        journal_len -= 1;
                        if (journal_len == 0) shed_lock = true; 
                    } else {
                        if (!shed_lock) { 
                            sys_hunter.shed();
                            shed_lock = true;
                        }
                    }
                } else if (byte >= 32 and byte <= 126) {
                    shed_lock = false;
                    if (journal_len < 4096) { journal[journal_len] = byte; journal_len += 1; }
                }
            }
        } else {
            if (shed_lock) {
                if (std.time.milliTimestamp() - last_rx_ms > 750) {
                    shed_lock = false;
                }
            }
        }

        blink_timer += 1;
        if (blink_timer > 35) { is_high_cycle = !is_high_cycle; blink_timer = 0; dirty = true; }

        if (dirty) {
            clear(codex.get("K.S"));
            if (sys_composer.active) {
                drawHeader(is_high_cycle);
                // Global OS header parity overlay
                sys_composer.render(&back_buffer, WIDTH, HEIGHT);
                sys_hunter.renderTimeline(&back_buffer, WIDTH, HEIGHT);
                
                if (is_exp_save_modal) {
                    const effective_width = WIDTH - 65;
                    const mw = 480;
                    const mh = 140; 
                    const mx = (effective_width / 2) - (mw / 2);
                    const my = HEIGHT / 2 - (mh / 2);
                    drawRect(mx - 2, my - 2, mw + 4, mh + 2, codex.get("B.S")); 
                    drawRect(mx, my, mw, mh, codex.get("K.S"));
                    print(mx + 20, my + 20, "[ EXPERIMENTAL MATRIX ACTIVE ]", codex.get("B.S"));
                    drawRect(mx + 20, my + 35, mw - 40, 1, codex.get("K.H"));
                    print(mx + 20, my + 55, "This artifact possesses a detached .exp stasis.", codex.get("S.S"));
                    print(mx + 20, my + 80, "[O] OVERWRITE ORIGIN & VOID .EXP", codex.get("C.S"));
                    print(mx + 20, my + 100, "[C] CONTINUE SAVING AS .EXP", codex.get("S.H"));
                    print(mx + 20, my + 120, "[ESC] CANCEL", codex.get("K.H"));
                }
                
                drawPulseOverlay();
            } else {
                drawHeader(is_high_cycle);
                sys_hunter.render(&back_buffer, WIDTH, HEIGHT);
                
                if (!sys_hunter.isActive()) { 
                    print(20, 50, "TIMELINE Terminal. [NO_FOCUS][ZEN]", codex.get("K.H"));
                }
                
                const bar_y = getUriBarY(journal_len, sys_hunter.url);
                drawPulseOverlay();

                if (is_tabula_rasa) {
                    const mw = 460;
                    const mh = 160;
                    const mx = (WIDTH / 2) - (mw / 2); const my = bar_y - mh;
                    drawRect(mx - 2, my - 2, mw + 4, mh + 2, codex.get("C.S")); 
                    drawRect(mx, my, mw, mh, codex.get("K.S"));
                    print(mx + 20, my + 20, "[ TABULA RASA // SOCIUS REQUIRED ]", codex.get("C.S"));
                    drawRect(mx + 20, my + 35, mw - 40, 1, codex.get("K.H"));
                    print(mx + 20, my + 60, "AWAITING SOCIUS DESIGNATION:", codex.get("S.S"));
                    drawRect(mx + 20, my + 85, mw - 40, 24, codex.get("K.H"));
                    print(mx + 28, my + 93, journal[0..journal_len], codex.get("S.H"));
                    if (is_high_cycle) drawChar(mx + 28 + (journal_len * 8), my + 93, 0xDB, codex.get("C.S"));
                } 
                else if (is_trail_modal) {
                    const mw = 760;
                    const mh = 400; 
                    const mx = (WIDTH / 2) - (mw / 2);
                    const my = bar_y - mh - 10;
                    drawRect(mx - 2, my - 2, mw + 4, mh + 2, codex.get("C.S"));
                    drawRect(mx, my, mw, mh, codex.get("K.S"));
                    print(mx + 20, my + 20, "[ PREVIOUS CYCLE KERNEL PANIC RECOVERED ]", codex.get("C.S"));
                    drawRect(mx + 20, my + 35, mw - 40, 1, codex.get("K.H"));

                    var cx: usize = mx + 20;
                    var cy: usize = my + 50;
                    for (trail_buffer[0..trail_len]) |c| {
                        if (c == '\n') {
                            cx = mx + 20;
                            cy += 10;
                            if (cy > my + mh - 40) break;
                            continue;
                        }
                        if (c >= 32 and c <= 126) {
                            drawChar(cx, cy, c, codex.get("S.S"));
                            cx += 8;
                            if (cx > mx + mw - 20) {
                                cx = mx + 20;
                                cy += 10;
                                if (cy > my + mh - 40) break;
                            }
                        }
                    }

                    print(mx + 20, my + mh - 30, ">> Type 'shed' or empty [ENTER] to clear memory.", codex.get("B.S"));
                    drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
                }
                else if (is_memo_modal) {
                    const mw = 460;
                    const mh = 140;
                    const mx = (WIDTH / 2) - (mw / 2); const my = bar_y - mh;
                    drawRect(mx - 2, my - 2, mw + 4, mh + 2, codex.get("B.S")); 
                    drawRect(mx, my, mw, mh, codex.get("K.S"));
                    print(mx + 20, my + 20, "[ TIMELINE // MEMO DESIGNATION ]", codex.get("B.S"));
                    drawRect(mx + 20, my + 35, mw - 40, 1, codex.get("K.H"));
                    print(mx + 20, my + 60, "ENTER ARTIFACT NAME:", codex.get("S.S"));
                    drawRect(mx + 20, my + 85, mw - 40, 24, codex.get("K.H"));
                    print(mx + 28, my + 93, journal[0..journal_len], codex.get("S.H"));
                    if (is_high_cycle) drawChar(mx + 28 + (journal_len * 8), my + 93, 0xDB, codex.get("B.S"));
                } else if (is_radio_modal) {
                    const mw = 520;
                    const mh = 160;
                    const mx = (WIDTH / 2) - (mw / 2); const my = bar_y - mh;
                    drawRect(mx - 2, my - 2, mw + 4, mh + 2, codex.get("C.S"));
                    drawRect(mx, my, mw, mh, codex.get("K.S"));
                    print(mx + 20, my + 20, "[ PHILOTIC RADIO // FREQ TUNING ]", codex.get("C.S"));
                    drawRect(mx + 20, my + 35, mw - 40, 1, codex.get("K.H"));

                    var radio_buf: [128]u8 = undefined;
                    const c_f0 = if (radio_sel == 0) codex.get("S.H") else codex.get("S.S");
                    const str_f0 = std.fmt.bufPrint(&radio_buf, "Song (Hz)  : {d:.1}", .{radio_f0}) catch "";
                    print(mx + 20, my + 60, str_f0, c_f0);
                    if (radio_sel == 0) { drawChar(mx + 8, my + 60, 0x1A, codex.get("B.S")); }

                    const c_dec = if (radio_sel == 1) codex.get("S.H") else codex.get("S.S");
                    const str_dec = std.fmt.bufPrint(&radio_buf, "Decay (d)  : {d:.2}", .{radio_decay}) catch "";
                    print(mx + 20, my + 80, str_dec, c_dec);
                    if (radio_sel == 1) { drawChar(mx + 8, my + 80, 0x1A, codex.get("B.S")); }

                    const c_diss = if (radio_sel == 2) codex.get("S.H") else codex.get("S.S");
                    const str_diss = std.fmt.bufPrint(&radio_buf, "Diss. (m)  : {d:.2}", .{radio_diss}) catch "";
                    print(mx + 260, my + 60, str_diss, c_diss);
                    if (radio_sel == 2) { drawChar(mx + 248, my + 60, 0x1A, codex.get("B.S")); }

                    const c_phi = if (radio_sel == 3) codex.get("S.H") else codex.get("S.S");
                    const str_phi = std.fmt.bufPrint(&radio_buf, "\xED\x1E-off (P) : {d:.3}", .{radio_phi}) catch "";
                    print(mx + 260, my + 80, str_phi, c_phi);
                    if (radio_sel == 3) { drawChar(mx + 248, my + 80, 0x1A, codex.get("B.S")); }

                    print(mx + 20, my + 120, "[TAB] Sel  [< / >] Dial  [SPC] Strike  [ENT] Commit", codex.get("K.H"));
                    drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
                } else if (is_calc_modal) {
                    const cw = WIDTH - 40;
                    const ch: usize = if (is_calc_graph) 200 else 30;
                    const cx = 20;
                    const cy = bar_y - ch - 10;
                    
                    drawRect(cx - 2, cy - 2, cw + 4, ch + 2, codex.get("B.S"));
                    drawRect(cx, cy, cw, ch, codex.get("K.S"));
                    
                    print(cx + 10, cy + 10, "[ AST ] >", codex.get("C.S"));
                    print(cx + 90, cy + 10, calc_input[0..calc_len], codex.get("S.H"));
                    
                    if (calc_res_len > 0) {
                        print(cx + cw - 150, cy + 10, calc_result[0..calc_res_len], codex.get("B.S"));
                    }

                    if (is_calc_graph) {
                        drawRect(cx + 10, cy + 30, cw - 20, 1, codex.get("K.H"));
                        print(cx + 10, cy + 45, "[ GRAPH MODULE : AWAITING PHASE 4 TENSORS ]", codex.get("K.H"));
                        print(cx + 10, cy + ch - 20, "[TAB] Toggle Graph  [ENTER] Evaluate (Empty to Dismiss)", codex.get("S.S"));
                    }
                    drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
                } else if (is_assist_modal) {
                    const aw = 860;
                    const ah = 480; 
                    const ax = (WIDTH / 2) - (aw / 2);
                    const ay = bar_y - ah - 10;
                    drawRect(ax - 2, ay - 2, aw + 4, ah + 2, codex.get("B.S"));
                    drawRect(ax, ay, aw, ah, codex.get("K.S"));

                    print(ax + 20, ay + 20, "[ @NSIBLE COMMAND BIBLE & MATRIX PROTOCOLS ]", codex.get("B.S"));
                    drawRect(ax + 20, ay + 35, aw - 40, 1, codex.get("K.H"));
                    print(ax + 20, ay + 50, "[ CORE MATRIX TRAVERSAL ]", codex.get("S.S"));
                    print(ax + 20, ay + 70, "mchn/        : View Local Root Directory", codex.get("S.H"));
                    print(ax + 20, ay + 90, "w3.<target>  : Shadow Flight (Web Traversal)", codex.get("S.H"));
                    print(ax + 20, ay + 110, "w3?. <query> : Global Matrix Search", codex.get("S.H"));
                    print(ax + 20, ay + 130, "<Number>     : MELT Traverse (Follow Link [x])", codex.get("C.S"));
                    print(ax + 20, ay + 150, "stargaze     : Entropic Wind (Random Node)", codex.get("B.S"));
                    print(ax + 20, ay + 170, ".!T<-. / .!T>-.  : Switch Timeline Tab (even in Composer)", codex.get("S.H"));
                    print(ax + 20, ay + 190, ".!R^-. / .!Rv-.  : Shift Node Position on Timeline Rail", codex.get("S.H"));
                    print(ax + 20, ay + 210, ".!C+-.           : Cycle Node Color Identity", codex.get("S.H"));
                    print(ax + 20, ay + 230, "[ ARTIFACT FORGE & GZL ]", codex.get("S.S"));
                    print(ax + 20, ay + 250, "memo <txt>   : Quick Operator Artifact", codex.get("S.H"));
                    print(ax + 20, ay + 270, "<Title> //-. : Title & Save Artifact", codex.get("S.H"));
                    print(ax + 20, ay + 290, "| memo       : Pipe active target to timeline", codex.get("S.H"));
                    print(ax + 20, ay + 320, ">> GZL Syntax encodes artifacts with module,", codex.get("K.H"));
                    print(ax + 20, ay + 340, ">> timestamps, and philotic inferences.", codex.get("K.H"));
                    print(ax + 440, ay + 50, "[ SCOPE & SYSTEM ]", codex.get("S.S"));
                    print(ax + 440, ay + 70, "zI / zO      : Shift Banyan Scope Depth", codex.get("S.H"));
                    print(ax + 440, ay + 90, "               [0:RAW, 1:ZEN, 2:MTX, 3:ROOT]", codex.get("K.H"));
                    print(ax + 440, ay + 110, "shed / drop  : Destroy active node", codex.get("S.H"));
                    print(ax + 440, ay + 130, "radio / tune : Philotic Resonance Tuning", codex.get("S.H"));
                    print(ax + 440, ay + 150, ".!@&-.       : Force Cache Reload", codex.get("B.S"));
                    print(ax + 440, ay + 170, "cycle        : Print Local Tempus", codex.get("S.H"));
                    print(ax + 440, ay + 190, ".!XX-. / exit: Terminate Matrix / Close Tab", codex.get("S.H"));
                    drawRect(ax + 20, ay + 370, aw - 40, 1, codex.get("K.H"));
                    print(ax + 20, ay + 390, "[ AST ARITHMETIC ENGINE ]", codex.get("C.S"));
                    print(ax + 20, ay + 410, ">> STATUS : Native Recursive Descent Operational.", codex.get("K.H"));
                    print(ax + 20, ay + 430, ">> ACTIVE : Type 'calc' or '@://calc/' to invoke.", codex.get("K.H"));
                    print(ax + 20, ay + ah - 30, ">> Type '?' or 'assist' to dismiss.", codex.get("B.S"));
                    drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
                } else if (is_bash_modal) {
                    const mw = WIDTH - 40;
                    const mh = 300; 
                    const mx = 20; 
                    const my = bar_y - mh - 10;
                    drawRect(mx - 2, my - 2, mw + 4, mh + 2, codex.get("B.S")); 
                    drawRect(mx, my, mw, mh, codex.get("K.S"));
                    print(mx + 20, my + 10, "[ SHELL OUTPUT ]", codex.get("B.S"));
                    drawRect(mx + 20, my + 25, mw - 40, 1, codex.get("K.H"));

                    if (std.fs.cwd().openFile("assets/.void/.00", .{})) |file| {
                        const f_content = file.readToEndAlloc(void_allocator, 1024 * 1024) catch "";
                        defer void_allocator.free(f_content);
                        
                        var line_iter = std.mem.splitScalar(u8, f_content, '\n');
                        var curr_line: usize = 0;
                        var draw_y: usize = my + 35;
                        while (line_iter.next()) |line| {
                            if (curr_line >= bash_scroll_y) {
                                if (draw_y > my + mh - 30) break;
                                var dx: usize = mx + 20;
                                for (line) |c| {
                                    if (dx > mx + mw - 20) break;
                                    drawChar(dx, draw_y, c, codex.get("S.S"));
                                    dx += 8;
                                }
                                draw_y += 10;
                            }
                            curr_line += 1;
                        }
                        file.close();
                    } else |_| {}
                    
                    drawRect(mx + 20, my + mh - 25, mw - 40, 1, codex.get("K.H"));
                    print(mx + 20, my + mh - 18, "[ESC] Dismiss   [TAB] Pipe to File   [UP/DOWN] Scroll", codex.get("K.H"));
                    if (is_bash_pipe) {
                        const p_y = getUriBarY(journal_len + 14, "");
                        drawRect(0, p_y, WIDTH, HEIGHT - p_y, codex.get("B.S"));
                        print(10, p_y + 6, "DESTINATION > ", codex.get("K.S"));
                        print(122, p_y + 6, journal[0..journal_len], codex.get("K.S"));
                        if (is_high_cycle) drawChar(122 + (journal_len * 8), p_y + 6, 0xDB, codex.get("K.S"));
                    } else {
                        drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
                    }
                } else if (is_void_modal) {
                    const mw = 640;
                    const mh = 140; 
                    const mx = (WIDTH / 2) - (mw / 2);
                    const my = bar_y - mh - 10;
                    
                    drawRect(mx - 2, my - 2, mw + 4, mh + 2, codex.get("C.S"));
                    drawRect(mx, my, mw, mh, codex.get("K.H")); 
                    
                    print(mx + 20, my + 20, "[ TEMPORAL DECAY VOID :: VERITY LOCK ]", codex.get("C.S"));
                    drawRect(mx + 20, my + 35, mw - 40, 1, codex.get("K.H"));
                    
                    print(mx + 20, my + 50, "TARGET ARTIFACT:", codex.get("S.S"));
                    var display_target: []const u8 = void_target_path[0..void_target_len];
                    if (display_target.len > 70) display_target = display_target[0..70];
                    print(mx + 20, my + 70, display_target, codex.get("S.H"));
                    
                    drawRect(mx + 20, my + 95, mw - 40, 1, codex.get("K.H"));
                    print(mx + 20, my + 110, "EXECUTE BANISHMENT? [Y] CONFIRM  /  [N] CANCEL", codex.get("B.S"));
                    
                    drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
                } else {
                    drawUriBar(journal[0..journal_len], journal_len, sys_hunter.url);
                }
            }
            
            @memcpy(fb_pixels[0..(WIDTH * HEIGHT)], &back_buffer);
            dirty = false;
        }
        codex.zen(0.000004);
    }
}
// }-.]
