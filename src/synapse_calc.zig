// [@://nsible_os/src/synapse_calc.zig/.-={
//   module: "AST Arithmetic & Synapse Engine",
//   version: "0.10.10-nightly // Banysang",
//   description: "Zero-allocation recursive descent parser for bare-metal mathematics.",
//   changes: "Deployed AST logic. Bound persistent GZL state memory to assets/synapses/synapse.calc.",
//   philotic_inferences: "Math is the absolute truth of the matrix. We do not evaluate; we parse reality."

const std = @import("std");

pub const AST = struct {
    pub fn evaluate(input: []const u8, rcl_val: f64) f64 {
        var clean = std.mem.trim(u8, input, " \t");
        if (clean.len == 0) return 0.0;

        if (std.mem.startsWith(u8, clean, "rand")) {
            var prng = std.rand.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
            return prng.random().float(f64);
        }
        if (std.mem.startsWith(u8, clean, "hash ")) {
            const target = clean[5..];
            var hash: u64 = 5381;
            for (target) |c| { hash = ((hash << 5) +% hash) +% c; }
            return @as(f64, @floatFromInt(hash % 1000000)); 
        }
        if (std.mem.eql(u8, clean, "rcl")) return rcl_val;

        var parser = Parser.init(clean, rcl_val);
        return parser.parseExpr() catch 0.0;
    }
};

const Parser = struct {
    str: []const u8,
    pos: usize,
    rcl: f64,

    pub fn init(str: []const u8, rcl: f64) Parser {
        return .{ .str = str, .pos = 0, .rcl = rcl };
    }

    fn peek(self: *Parser) ?u8 {
        while (self.pos < self.str.len and self.str[self.pos] == ' ') self.pos += 1;
        if (self.pos >= self.str.len) return null;
        return self.str[self.pos];
    }

    fn consume(self: *Parser) void {
        self.pos += 1;
    }

    pub fn parseExpr(self: *Parser) anyerror!f64 {
        var left = try self.parseTerm();
        while (self.peek()) |c| {
            if (c == '+') { self.consume(); left += try self.parseTerm(); }
            else if (c == '-') { self.consume(); left -= try self.parseTerm(); }
            else break;
        }
        return left;
    }

    fn parseTerm(self: *Parser) anyerror!f64 {
        var left = try self.parseFactor();
        while (self.peek()) |c| {
            if (c == '*') { self.consume(); left *= try self.parseFactor(); }
            else if (c == '/') {
                self.consume();
                const right = try self.parseFactor();
                if (right != 0.0) left /= right else left = 0.0;
            }
            else break;
        }
        return left;
    }

    fn parseFactor(self: *Parser) anyerror!f64 {
        const c_opt = self.peek();
        if (c_opt == null) return 0.0;
        const c = c_opt.?;

        if (c == '(') {
            self.consume();
            const val = try self.parseExpr();
            if (self.peek() == ')') self.consume();
            return val;
        }

        if (std.mem.startsWith(u8, self.str[self.pos..], "sin(")) {
            self.pos += 4;
            const val = try self.parseExpr();
            if (self.peek() == ')') self.consume();
            return @sin(val);
        }
        if (std.mem.startsWith(u8, self.str[self.pos..], "cos(")) {
            self.pos += 4;
            const val = try self.parseExpr();
            if (self.peek() == ')') self.consume();
            return @cos(val);
        }
        if (std.mem.startsWith(u8, self.str[self.pos..], "rcl")) {
            self.pos += 3;
            return self.rcl;
        }

        var start = self.pos;
        while (self.pos < self.str.len) {
            const ch = self.str[self.pos];
            if ((ch >= '0' and ch <= '9') or ch == '.') {
                self.pos += 1;
            } else break;
        }
        if (start == self.pos) return 0.0;
        return std.fmt.parseFloat(f64, self.str[start..self.pos]) catch 0.0;
    }
};

pub fn manageSynapseMemory(val: ?f64) f64 {
    const fs = std.fs.cwd();
    fs.makeDir("assets") catch |e| { if (e != error.PathAlreadyExists) return 0.0; };
    fs.makeDir("assets/synapses") catch |e| { if (e != error.PathAlreadyExists) return 0.0; };

    const path = "assets/synapses/synapse.calc";
    
    if (val) |v| {
        if (fs.createFile(path, .{})) |file| {
            var buf: [512]u8 = undefined;
            const data = std.fmt.bufPrint(&buf, 
                "// [@://nsible_os/assets/synapses/synapse.calc/.-={{\n" ++
                "//   module: \"Synapse Memory\",\n" ++
                "//   value: \"{d:.4}\"\n" ++
                "// }}-.]\n", .{v}) catch return 0.0;
            file.writeAll(data) catch {};
            file.close();
        } else |_| {}
        return v;
    } else {
        var rcl_val: f64 = 0.0;
        if (fs.openFile(path, .{})) |file| {
            var buf: [512]u8 = undefined;
            if (file.readAll(&buf)) |br| {
                const content = buf[0..br];
                if (std.mem.indexOf(u8, content, "value: \"")) |idx| {
                    const start = idx + 8;
                    if (std.mem.indexOfScalarPos(u8, content, start, '"')) |end| {
                        rcl_val = std.fmt.parseFloat(f64, content[start..end]) catch 0.0;
                    }
                }
            } else |_| {}
            file.close();
        } else |_| {}
        return rcl_val;
    }
}

// }-.]
