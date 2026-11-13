const std = @import("std");
const Io = std.Io;
const autocalc = @import("autocalc");
const live_repl = @import("live_repl");

const App = struct {
    ans: ?f64 = null,
    preview: [96]u8 = undefined,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len >= 2) {
        try printOnce(init.io, args[1..]);
        return;
    }

    var app = App{};
    try live_repl.run(init, .{
        .context = @ptrCast(&app),
        .infer = infer,
        .keep = keep,
    });
}

fn printOnce(io: Io, args: []const []const u8) !void {
    var expression: std.ArrayList(u8) = .empty;
    defer expression.deinit(std.heap.page_allocator);
    for (args, 0..) |arg, index| {
        if (index != 0) try expression.append(std.heap.page_allocator, ' ');
        try expression.appendSlice(std.heap.page_allocator, arg);
    }

    var stdout_buffer: [256]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    const value = autocalc.eval(expression.items) catch |err| {
        try stdout.print("invalid expression: {s}\n", .{@errorName(err)});
        try stdout.flush();
        return err;
    };
    try stdout.print("{d}\n", .{value});
    try stdout.flush();
}

fn infer(context: *anyopaque, line: []const u8) live_repl.Inference {
    const app: *App = @ptrCast(@alignCast(context));
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0) return .{};

    var expanded: [1024]u8 = undefined;
    const source = expandAns(trimmed, app.ans, &expanded) catch return .{};
    const value = autocalc.eval(source) catch return .{};
    const held = std.fmt.bufPrint(&app.preview, "= {d}", .{value}) catch return .{};
    return .{ .held = held };
}

fn keep(context: *anyopaque, line: []const u8) live_repl.After {
    const app: *App = @ptrCast(@alignCast(context));
    const trimmed = std.mem.trim(u8, line, " \t");
    if (std.mem.eql(u8, trimmed, "exit") or std.mem.eql(u8, trimmed, "quit")) {
        return .enough;
    }

    var expanded: [1024]u8 = undefined;
    const source = expandAns(trimmed, app.ans, &expanded) catch return .another;
    if (autocalc.eval(source)) |value| app.ans = value else |_| {}
    return .another;
}

const ExpandError = error{ NoAns, LineTooLong };

fn expandAns(line: []const u8, ans: ?f64, out: []u8) ExpandError![]u8 {
    var written: usize = 0;
    var index: usize = 0;
    while (index < line.len) {
        if (isAnsAt(line, index)) {
            const value = ans orelse return error.NoAns;
            var number: [64]u8 = undefined;
            const text = std.fmt.bufPrint(&number, "{d}", .{value}) catch return error.LineTooLong;
            if (written + text.len > out.len) return error.LineTooLong;
            @memcpy(out[written..][0..text.len], text);
            written += text.len;
            index += 3;
            continue;
        }
        if (written >= out.len) return error.LineTooLong;
        out[written] = line[index];
        written += 1;
        index += 1;
    }
    return out[0..written];
}

fn isAnsAt(line: []const u8, index: usize) bool {
    if (index + 3 > line.len) return false;
    if (!std.mem.eql(u8, line[index..][0..3], "ans")) return false;
    if (index > 0 and isIdent(line[index - 1])) return false;
    if (index + 3 < line.len and isIdent(line[index + 3])) return false;
    return true;
}

fn isIdent(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}
