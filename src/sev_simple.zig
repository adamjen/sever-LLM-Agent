const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const SirsParser = @import("sirs.zig");
const Expression = SirsParser.Expression;
const Statement = SirsParser.Statement;
const Type = SirsParser.Type;
const Function = SirsParser.Function;
const Program = SirsParser.Program;
const Parameter = SirsParser.Parameter;
const Literal = SirsParser.Literal;
const OpKind = SirsParser.OpKind;

/// Simple SEV parser that works with our generated format
pub const SevSimpleParser = struct {
    allocator: Allocator,
    input: []const u8,
    pos: usize,

    const ParseError = error{
        UnexpectedToken,
        UnexpectedEof,
        InvalidSyntax,
        OutOfMemory,
    };

    pub fn init(allocator: Allocator, input: []const u8) SevSimpleParser {
        return SevSimpleParser{
            .allocator = allocator,
            .input = input,
            .pos = 0,
        };
    }

    pub fn parse(self: *SevSimpleParser) !Program {
        // Expected format: Pmain|Dmain[]I;La:I=10;Lb:I=20;Lsum:I=(a+b);Lproduct:I=(a*b);R(sum+product)
        
        if (!self.consume('P')) return ParseError.InvalidSyntax;
        
        const entry = try self.parseIdentifier();
        if (!self.consume('|')) return ParseError.InvalidSyntax;
        
        var functions = StringHashMap(Function).init(self.allocator);
        
        // Parse the single function (for now)
        const func = try self.parseFunction();
        try functions.put(entry, func);
        
        return Program{
            .entry = entry,
            .entry_allocated = false,
            .functions = functions,
            .types = StringHashMap(Type).init(self.allocator),
            .generic_types = StringHashMap(SirsParser.GenericType).init(self.allocator),
            .interfaces = StringHashMap(SirsParser.Interface).init(self.allocator),
            .trait_impls = ArrayList(SirsParser.TraitImpl).init(self.allocator),
            .constants = StringHashMap(SirsParser.Constant).init(self.allocator),
            .allocator = self.allocator,
        };
    }

    fn parseFunction(self: *SevSimpleParser) !Function {
        // Expected: Dmain[]I;La:I=10;Lb:I=20;Lsum:I=(a+b);Lproduct:I=(a*b);R(sum+product)
        if (!self.consume('D')) return ParseError.InvalidSyntax;
        
        // Skip function name (we already have it)
        _ = try self.parseIdentifier();
        
        // Parse args - for now assume empty []
        if (!self.consume('[')) return ParseError.InvalidSyntax;
        if (!self.consume(']')) return ParseError.InvalidSyntax;
        
        // Parse return type
        const return_type = try self.parseType();
        
        if (!self.consume(';')) return ParseError.InvalidSyntax;
        
        // Parse statements
        var body = ArrayList(Statement).init(self.allocator);
        
        while (self.pos < self.input.len) {
            const stmt = try self.parseStatement();
            try body.append(stmt);
            
            // Consume semicolon if present
            if (self.pos < self.input.len and self.peek() == ';') {
                _ = self.advance();
            }
        }
        
        return Function{
            .args = ArrayList(Parameter).init(self.allocator),
            .@"return" = return_type,
            .body = body,
        };
    }

    fn parseStatement(self: *SevSimpleParser) !Statement {
        const ch = self.peek();
        
        switch (ch) {
            'L' => return try self.parseLetStatement(),
            'R' => return try self.parseReturnStatement(),
            else => return ParseError.InvalidSyntax,
        }
    }

    fn parseLetStatement(self: *SevSimpleParser) !Statement {
        // Expected: La:I=10 or Lsum:I=(a+b)
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
                .mutable = false,
                .value = value,
            },
        };
    }

    fn parseReturnStatement(self: *SevSimpleParser) !Statement {
        // Expected: R(sum+product)
        if (!self.consume('R')) return ParseError.InvalidSyntax;
        
        const value = try self.parseExpression();
        return Statement{
            .@"return" = value,
        };
    }

    fn parseExpression(self: *SevSimpleParser) !Expression {
        const ch = self.peek();
        
        switch (ch) {
            '(' => return try self.parseParenthesizedExpression(),
            '0'...'9' => return try self.parseNumber(),
            'a'...'z', 'A'...'Z', '_' => return try self.parseVariable(),
            else => return ParseError.UnexpectedToken,
        }
    }

    fn parseParenthesizedExpression(self: *SevSimpleParser) !Expression {
        // Expected: (a+b) or (sum+product)
        if (!self.consume('(')) return ParseError.InvalidSyntax;
        
        const left = try self.parseVariable();
        const op_char = self.advance();
        const right = try self.parseVariable();
        
        if (!self.consume(')')) return ParseError.InvalidSyntax;
        
        // Convert operator character to OpKind
        const op_kind = switch (op_char) {
            '+' => OpKind.add,
            '-' => OpKind.sub,
            '*' => OpKind.mul,
            '/' => OpKind.div,
            else => return ParseError.InvalidSyntax,
        };
        
        var args = ArrayList(Expression).init(self.allocator);
        try args.append(left);
        try args.append(right);
        
        return Expression{
            .op = .{
                .kind = op_kind,
                .args = args,
            },
        };
    }

    fn parseNumber(self: *SevSimpleParser) !Expression {
        const start = self.pos;
        
        while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
            self.pos += 1;
        }
        
        const num_str = self.input[start..self.pos];
        const value = std.fmt.parseInt(i32, num_str, 10) catch return ParseError.InvalidSyntax;
        
        return Expression{
            .literal = Literal{ .integer = value },
        };
    }

    fn parseVariable(self: *SevSimpleParser) !Expression {
        const name = try self.parseIdentifier();
        return Expression{ .variable = name };
    }

    fn parseType(self: *SevSimpleParser) !Type {
        const ch = self.advance();
        return switch (ch) {
            'I' => Type.i32,
            'F' => Type.f64,
            'B' => Type.bool,
            'S' => Type.str,
            else => ParseError.InvalidSyntax,
        };
    }

    fn parseIdentifier(self: *SevSimpleParser) ![]const u8 {
        const start = self.pos;
        
        while (self.pos < self.input.len and 
               (std.ascii.isAlphanumeric(self.input[self.pos]) or self.input[self.pos] == '_')) {
            self.pos += 1;
        }
        
        if (start == self.pos) return ParseError.InvalidSyntax;
        
        return self.input[start..self.pos];
    }

    fn peek(self: *SevSimpleParser) u8 {
        if (self.pos >= self.input.len) return 0;
        return self.input[self.pos];
    }

    fn advance(self: *SevSimpleParser) u8 {
        if (self.pos >= self.input.len) return 0;
        const ch = self.input[self.pos];
        self.pos += 1;
        return ch;
    }

    fn consume(self: *SevSimpleParser, expected: u8) bool {
        if (self.peek() == expected) {
            _ = self.advance();
            return true;
        }
        return false;
    }
};