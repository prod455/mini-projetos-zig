const std = @import("std");

pub const EvalError = error{
    Empty,
    UnexpectedChar,
    UnexpectedEnd,
    DivisionByZero,
    TrailingJunk,
};

pub fn eval(source: []const u8) EvalError!f64 {
    var parser = Parser{ .source = source, .index = 0 };
    if (parser.skipSpace() == source.len) return error.Empty;
    const value = try parser.parseExpr();
    if (parser.skipSpace() != source.len) return error.TrailingJunk;
    return value;
}

const Parser = struct {
    source: []const u8,
    index: usize,

    fn skipSpace(self: *Parser) usize {
        while (self.index < self.source.len and std.ascii.isWhitespace(self.source[self.index])) {
            self.index += 1;
        }
        return self.index;
    }

    fn peek(self: *Parser) ?u8 {
        _ = self.skipSpace();
        if (self.index >= self.source.len) return null;
        return self.source[self.index];
    }

    fn eat(self: *Parser, expected: u8) bool {
        if (self.peek() == expected) {
            self.index += 1;
            return true;
        }
        return false;
    }

    fn parseExpr(self: *Parser) EvalError!f64 {
        var value = try self.parseTerm();
        while (true) {
            if (self.eat('+')) {
                value += try self.parseTerm();
            } else if (self.eat('-')) {
                value -= try self.parseTerm();
            } else break;
        }
        return value;
    }

    fn parseTerm(self: *Parser) EvalError!f64 {
        var value = try self.parseFactor();
        while (true) {
            if (self.eat('*')) {
                value *= try self.parseFactor();
            } else if (self.eat('/')) {
                const right = try self.parseFactor();
                if (right == 0) return error.DivisionByZero;
                value /= right;
            } else break;
        }
        return value;
    }

    fn parseFactor(self: *Parser) EvalError!f64 {
        if (self.eat('+')) return self.parseFactor();
        if (self.eat('-')) return -(try self.parseFactor());
        if (self.eat('(')) {
            const value = try self.parseExpr();
            if (!self.eat(')')) return error.UnexpectedEnd;
            return value;
        }
        return self.parseNumber();
    }

    fn parseNumber(self: *Parser) EvalError!f64 {
        const start = self.skipSpace();
        if (start >= self.source.len) return error.UnexpectedEnd;

        var i = start;
        var saw_digit = false;
        var saw_dot = false;
        while (i < self.source.len) {
            const c = self.source[i];
            if (std.ascii.isDigit(c)) {
                saw_digit = true;
                i += 1;
            } else if (c == '.' and !saw_dot) {
                saw_dot = true;
                i += 1;
            } else break;
        }
        if (!saw_digit) return error.UnexpectedChar;

        self.index = i;
        return std.fmt.parseFloat(f64, self.source[start..i]) catch error.UnexpectedChar;
    }
};

test "addition and precedence" {
    try std.testing.expectEqual(@as(f64, 14), try eval("2 + 3 * 4"));
    try std.testing.expectEqual(@as(f64, 20), try eval("(2 + 3) * 4"));
}

test "subtraction, division, and decimals" {
    try std.testing.expectEqual(@as(f64, 3), try (eval("10 - 7")));
    try std.testing.expectEqual(@as(f64, 5), try eval("10 / 2"));
    try std.testing.expectEqual(@as(f64, 3), try eval("1.5 * 2"));
}

test "unary minus" {
    try std.testing.expectEqual(@as(f64, 1), try eval("-2 + 3"));
    try std.testing.expectEqual(@as(f64, -6), try eval("2 * -3"));
}

test "errors" {
    try std.testing.expectError(error.Empty, eval("   "));
    try std.testing.expectError(error.DivisionByZero, eval("1 / 0"));
    try std.testing.expectError(error.TrailingJunk, eval("1 + 2 9"));
    try std.testing.expectError(error.UnexpectedChar, eval("2 + a"));
    try std.testing.expectError(error.UnexpectedEnd, eval("(2 + 3"));
}
