const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const SirsParser = @import("sirs.zig");
const Expression = SirsParser.Expression;
const Statement = SirsParser.Statement;
const Type = SirsParser.Type;
const Function = SirsParser.Function;

/// Ultra-compact SEV (Sever) format parser
/// Optimized for minimum token usage by LLMs
pub const SevParser = struct {
    allocator: Allocator,
    input: []const u8,
    pos: usize,

    const ParseError = error{
        UnexpectedToken,
        UnexpectedEof,
        InvalidSyntax,
        OutOfMemory,
    };

    pub fn init(allocator: Allocator, input: []const u8) SevParser {
        return SevParser{
            .allocator = allocator,
            .input = input,
            .pos = 0,
        };
    }

    pub fn parse(self: *SevParser) !SirsParser.Program {
        // SEV format: P<entry>|<functions>
        if (!self.consume('P')) return ParseError.InvalidSyntax;
        
        const entry = try self.parseIdentifier();
        if (!self.consume('|')) return ParseError.InvalidSyntax;
        
        var functions = StringHashMap(Function).init(self.allocator);
        
        while (self.pos < self.input.len) {
            const func = try self.parseFunction();
            try functions.put(func.name, func);
        }
        
        return SirsParser.Program{
            .entry = entry,
            .functions = functions,
        };
    }

    fn parseFunction(self: *SevParser) !Function {
        // Format: D<name>[<args>]<return>;<body>
        if (!self.consume('D')) return ParseError.InvalidSyntax;
        
        _ = try self.parseIdentifier();
        
        if (!self.consume('[')) return ParseError.InvalidSyntax;
        var args = ArrayList(SirsParser.Parameter).init(self.allocator);
        
        while (self.peek() != ']') {
            const arg_name = try self.parseIdentifier();
            if (!self.consume(':')) return ParseError.InvalidSyntax;
            const arg_type = try self.parseType();
            
            try args.append(SirsParser.Parameter{
                .name = arg_name,
                .type = arg_type,
            });
            
            if (self.peek() == ',') {
                _ = self.advance();
            }
        }
        
        if (!self.consume(']')) return ParseError.InvalidSyntax;
        
        const return_type = try self.parseType();
        
        if (!self.consume(';')) return ParseError.InvalidSyntax;
        
        var body = ArrayList(Statement).init(self.allocator);
        
        while (self.pos < self.input.len and self.peek() != 'D') {
            const stmt = try self.parseStatement();
            try body.append(stmt);
            
            if (self.peek() == ';') {
                _ = self.advance();
            }
        }
        
        return Function{
            .args = args,
            .@"return" = return_type,
            .body = body,
        };
    }

    fn parseStatement(self: *SevParser) !Statement {
        const ch = self.peek();
        
        switch (ch) {
            'L' => return try self.parseLetStatement(),
            'R' => return try self.parseReturnStatement(),
            'I' => return try self.parseIfStatement(),
            'W' => return try self.parseWhileStatement(),
            else => {
                // Expression statement
                const expr = try self.parseExpression();
                return Statement{ .expression = expr };
            },
        }
    }

    fn parseLetStatement(self: *SevParser) !Statement {
        // Format: L<name>:<type>=<value>
        if (!self.consume('L')) return ParseError.InvalidSyntax;
        
        const name = try self.parseIdentifier();
        if (!self.consume(':')) return ParseError.InvalidSyntax;
        const var_type = try self.parseType();
        if (!self.consume('=')) return ParseError.InvalidSyntax;
        const value = try self.parseExpression();
        
        return Statement{
            .let = .{
                .name = name,
                .type = var_type,
                .value = value,
            },
        };
    }

    fn parseReturnStatement(self: *SevParser) !Statement {
        // Format: R<expr>
        if (!self.consume('R')) return ParseError.InvalidSyntax;
        
        const value = try self.parseExpression();
        return Statement{
            .return_stmt = value,
        };
    }

    fn parseIfStatement(self: *SevParser) !Statement {
        // Format: I<condition>?<then>:<else>
        if (!self.consume('I')) return ParseError.InvalidSyntax;
        
        const condition = try self.parseExpression();
        if (!self.consume('?')) return ParseError.InvalidSyntax;
        
        _ = try self.parseStatement();
        
        var else_branch: ?*Statement = null;
        if (self.consume(':')) {
            const else_stmt = try self.allocator.create(Statement);
            else_stmt.* = try self.parseStatement();
            else_branch = else_stmt;
        }
        
        return Statement{
            .if_stmt = .{
                .condition = condition,
                .then_branch = try self.allocator.create(Statement),
                .else_branch = else_branch,
            },
        };
    }

    fn parseWhileStatement(self: *SevParser) !Statement {
        // Format: W<condition>(<body>)
        if (!self.consume('W')) return ParseError.InvalidSyntax;
        
        const condition = try self.parseExpression();
        if (!self.consume('(')) return ParseError.InvalidSyntax;
        
        var body = ArrayList(Statement).init(self.allocator);
        
        while (self.peek() != ')') {
            const stmt = try self.parseStatement();
            try body.append(stmt);
            
            if (self.peek() == ';') {
                _ = self.advance();
            }
        }
        
        if (!self.consume(')')) return ParseError.InvalidSyntax;
        
        return Statement{
            .while_stmt = .{
                .condition = condition,
                .body = body.toOwnedSlice() catch unreachable,
            },
        };
    }

    fn parseExpression(self: *SevParser) !Expression {
        return try self.parseComparison();
    }

    fn parseComparison(self: *SevParser) !Expression {
        var left = try self.parseArithmetic();
        
        while (true) {
            const op = switch (self.peek()) {
                '=' => if (self.peekNext() == '=') {
                    _ = self.advance();
                    _ = self.advance();
                    break "==";
                } else break,
                '!' => if (self.peekNext() == '=') {
                    _ = self.advance();
                    _ = self.advance();
                    break "!=";
                } else break,
                '<' => if (self.peekNext() == '=') {
                    _ = self.advance();
                    _ = self.advance();
                    break "<=";
                } else {
                    _ = self.advance();
                    break "<";
                },
                '>' => if (self.peekNext() == '=') {
                    _ = self.advance();
                    _ = self.advance();
                    break ">=";
                } else {
                    _ = self.advance();
                    break ">";
                },
                else => break,
            };
            
            const right = try self.parseArithmetic();
            const expr = try self.allocator.create(Expression);
            expr.* = Expression{
                .binary = .{
                    .left = try self.allocator.create(Expression),
                    .operator = op,
                    .right = try self.allocator.create(Expression),
                },
            };
            expr.binary.left.* = left;
            expr.binary.right.* = right;
            left = expr.*;
        }
        
        return left;
    }

    fn parseArithmetic(self: *SevParser) !Expression {
        var left = try self.parseTerm();
        
        while (true) {
            const op = switch (self.peek()) {
                '+' => {
                    _ = self.advance();
                    break "+";
                },
                '-' => {
                    _ = self.advance();
                    break "-";
                },
                else => break,
            };
            
            const right = try self.parseTerm();
            const expr = try self.allocator.create(Expression);
            expr.* = Expression{
                .binary = .{
                    .left = try self.allocator.create(Expression),
                    .operator = op,
                    .right = try self.allocator.create(Expression),
                },
            };
            expr.binary.left.* = left;
            expr.binary.right.* = right;
            left = expr.*;
        }
        
        return left;
    }

    fn parseTerm(self: *SevParser) !Expression {
        var left = try self.parseFactor();
        
        while (true) {
            const op = switch (self.peek()) {
                '*' => {
                    _ = self.advance();
                    break "*";
                },
                '/' => {
                    _ = self.advance();
                    break "/";
                },
                '%' => {
                    _ = self.advance();
                    break "%";
                },
                else => break,
            };
            
            const right = try self.parseFactor();
            const expr = try self.allocator.create(Expression);
            expr.* = Expression{
                .binary = .{
                    .left = try self.allocator.create(Expression),
                    .operator = op,
                    .right = try self.allocator.create(Expression),
                },
            };
            expr.binary.left.* = left;
            expr.binary.right.* = right;
            left = expr.*;
        }
        
        return left;
    }

    fn parseFactor(self: *SevParser) !Expression {
        const ch = self.peek();
        
        switch (ch) {
            '(' => {
                _ = self.advance();
                const expr = try self.parseExpression();
                if (!self.consume(')')) return ParseError.InvalidSyntax;
                return expr;
            },
            'C' => return try self.parseCall(),
            '0'...'9' => return try self.parseNumber(),
            'a'...'z', 'A', 'B', 'D'...'Z', '_' => return try self.parseVariable(),
            else => return ParseError.UnexpectedToken,
        }
    }

    fn parseCall(self: *SevParser) !Expression {
        // Format: C<name>(<args>)
        if (!self.consume('C')) return ParseError.InvalidSyntax;
        
        const name = try self.parseIdentifier();
        if (!self.consume('(')) return ParseError.InvalidSyntax;
        
        var args = ArrayList(Expression).init(self.allocator);
        
        while (self.peek() != ')') {
            const arg = try self.parseExpression();
            try args.append(arg);
            
            if (self.peek() == ',') {
                _ = self.advance();
            }
        }
        
        if (!self.consume(')')) return ParseError.InvalidSyntax;
        
        return Expression{
            .call = .{
                .name = name,
                .args = args.toOwnedSlice() catch unreachable,
            },
        };
    }

    fn parseNumber(self: *SevParser) !Expression {
        const start = self.pos;
        
        while (self.pos < self.input.len and 
               (std.ascii.isDigit(self.input[self.pos]) or self.input[self.pos] == '.')) {
            self.pos += 1;
        }
        
        const num_str = self.input[start..self.pos];
        
        if (std.mem.indexOf(u8, num_str, ".") != null) {
            const value = std.fmt.parseFloat(f64, num_str) catch return ParseError.InvalidSyntax;
            return Expression{ .literal = .{ .float = value } };
        } else {
            const value = std.fmt.parseInt(i32, num_str, 10) catch return ParseError.InvalidSyntax;
            return Expression{ .literal = .{ .integer = value } };
        }
    }

    fn parseVariable(self: *SevParser) !Expression {
        const name = try self.parseIdentifier();
        return Expression{ .variable = name };
    }

    fn parseType(self: *SevParser) !Type {
        const ch = self.advance();
        return switch (ch) {
            'I' => Type.i32,
            'F' => Type.f64,
            'B' => Type.bool,
            'S' => Type.str,
            else => ParseError.InvalidSyntax,
        };
    }

    fn parseIdentifier(self: *SevParser) ![]const u8 {
        const start = self.pos;
        
        while (self.pos < self.input.len and 
               (std.ascii.isAlphanumeric(self.input[self.pos]) or self.input[self.pos] == '_')) {
            self.pos += 1;
        }
        
        if (start == self.pos) return ParseError.InvalidSyntax;
        
        return self.input[start..self.pos];
    }

    fn peek(self: *SevParser) u8 {
        if (self.pos >= self.input.len) return 0;
        return self.input[self.pos];
    }

    fn peekNext(self: *SevParser) u8 {
        if (self.pos + 1 >= self.input.len) return 0;
        return self.input[self.pos + 1];
    }

    fn advance(self: *SevParser) u8 {
        if (self.pos >= self.input.len) return 0;
        const ch = self.input[self.pos];
        self.pos += 1;
        return ch;
    }

    fn consume(self: *SevParser, expected: u8) bool {
        if (self.peek() == expected) {
            _ = self.advance();
            return true;
        }
        return false;
    }
};