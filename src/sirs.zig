const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const SirsError = error{
    InvalidJson,
    MissingField,
    InvalidType,
    InvalidExpression,
    InvalidStatement,
    OutOfMemory,
};

pub const Type = union(enum) {
    void,
    bool,
    i8, i16, i32, i64,
    u8, u16, u32, u64,
    f32, f64,
    str,
    array: struct {
        element: *Type,
        size: u32,
    },
    slice: struct {
        element: *Type,
    },
    @"struct": std.StringHashMap(*Type),
    @"union": std.StringHashMap(*Type),
    optional: *Type,
    function: struct {
        args: ArrayList(Type),
        @"return": *Type,
    },
    distribution: struct {
        kind: DistributionKind,
        param_types: ArrayList(Type),
    },
};

pub const DistributionKind = enum {
    uniform,
    normal,
    categorical,
    bernoulli,
    exponential,
    gamma,
    beta,
};

pub const Literal = union(enum) {
    integer: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    null,
};

pub const Expression = union(enum) {
    literal: Literal,
    variable: []const u8,
    call: struct {
        function: []const u8,
        args: ArrayList(Expression),
    },
    op: struct {
        kind: OpKind,
        args: ArrayList(Expression),
    },
    index: struct {
        array: *Expression,
        index: *Expression,
    },
    field: struct {
        object: *Expression,
        field: []const u8,
    },
    array: ArrayList(Expression),
    @"struct": std.StringHashMap(Expression),
    sample: struct {
        distribution: []const u8,
        params: ArrayList(Expression),
    },
    infer: struct {
        model: *Expression,
        data: *Expression,
    },
    cast: struct {
        value: *Expression,
        type: Type,
    },
};

pub const OpKind = enum {
    add, sub, mul, div, mod, pow,
    eq, ne, lt, le, gt, ge,
    @"and", @"or", not,
    bitand, bitor, bitxor, bitnot,
    shl, shr,
};

pub const LValue = union(enum) {
    variable: []const u8,
    index: struct {
        array: *LValue,
        index: Expression,
    },
    field: struct {
        object: *LValue,
        field: []const u8,
    },
};

pub const Pattern = union(enum) {
    literal: Literal,
    variable: []const u8,
    wildcard,
    @"struct": std.StringHashMap(Pattern),
};

pub const Statement = union(enum) {
    let: struct {
        name: []const u8,
        type: ?Type,
        mutable: bool,
        value: Expression,
    },
    assign: struct {
        target: LValue,
        value: Expression,
    },
    @"if": struct {
        condition: Expression,
        then: ArrayList(Statement),
        @"else": ?ArrayList(Statement),
    },
    match: struct {
        value: Expression,
        cases: ArrayList(struct {
            pattern: Pattern,
            body: ArrayList(Statement),
        }),
    },
    @"while": struct {
        condition: Expression,
        body: ArrayList(Statement),
    },
    @"for": struct {
        variable: []const u8,
        iterable: Expression,
        body: ArrayList(Statement),
    },
    @"return": Expression,
    @"break",
    @"continue",
    observe: struct {
        distribution: []const u8,
        params: ArrayList(Expression),
        value: Expression,
    },
    prob_assert: struct {
        condition: Expression,
        confidence: f64,
    },
    expression: Expression,
};

pub const Parameter = struct {
    name: []const u8,
    type: Type,
};

pub const Function = struct {
    args: ArrayList(Parameter),
    @"return": Type,
    body: ArrayList(Statement),
    @"inline": bool = false,
    pure: bool = false,
};

pub const Constant = struct {
    type: Type,
    value: Expression,
};

pub const Program = struct {
    entry: []const u8,
    functions: std.StringHashMap(Function),
    types: std.StringHashMap(Type),
    constants: std.StringHashMap(Constant),
    
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) Program {
        return Program{
            .entry = "",
            .functions = std.StringHashMap(Function).init(allocator),
            .types = std.StringHashMap(Type).init(allocator),
            .constants = std.StringHashMap(Constant).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Program) void {
        self.functions.deinit();
        self.types.deinit();
        self.constants.deinit();
    }
};

pub const Parser = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) Parser {
        return Parser{
            .allocator = allocator,
        };
    }
    
    pub fn parse(self: *Parser, json_content: []const u8) SirsError!Program {
        var parsed = json.parseFromSlice(json.Value, self.allocator, json_content, .{}) catch return SirsError.InvalidJson;
        defer parsed.deinit();
        
        const root = parsed.value;
        if (root != .object) return SirsError.InvalidJson;
        
        const program_obj = root.object.get("program") orelse return SirsError.MissingField;
        if (program_obj != .object) return SirsError.InvalidJson;
        
        var program = Program.init(self.allocator);
        
        // Parse entry point
        const entry = program_obj.object.get("entry") orelse return SirsError.MissingField;
        if (entry != .string) return SirsError.InvalidType;
        program.entry = self.allocator.dupe(u8, entry.string) catch return SirsError.OutOfMemory;
        
        // Parse functions
        if (program_obj.object.get("functions")) |functions_obj| {
            if (functions_obj != .object) return SirsError.InvalidType;
            
            var func_iter = functions_obj.object.iterator();
            while (func_iter.next()) |entry_kv| {
                const func_name = entry_kv.key_ptr.*;
                const func_obj = entry_kv.value_ptr.*;
                
                const function = try self.parseFunction(func_obj);
                const func_name_copy = self.allocator.dupe(u8, func_name) catch return SirsError.OutOfMemory;
                program.functions.put(func_name_copy, function) catch return SirsError.OutOfMemory;
            }
        }
        
        return program;
    }
    
    fn parseFunction(self: *Parser, func_obj: json.Value) SirsError!Function {
        if (func_obj != .object) return SirsError.InvalidType;
        
        var function = Function{
            .args = ArrayList(Parameter).init(self.allocator),
            .@"return" = Type.void,
            .body = ArrayList(Statement).init(self.allocator),
        };
        
        // Parse arguments
        if (func_obj.object.get("args")) |args_obj| {
            if (args_obj != .array) return SirsError.InvalidType;
            
            for (args_obj.array.items) |arg_obj| {
                const param = try self.parseParameter(arg_obj);
                function.args.append(param) catch return SirsError.OutOfMemory;
            }
        }
        
        // Parse return type
        if (func_obj.object.get("return")) |return_obj| {
            function.@"return" = try self.parseType(return_obj);
        }
        
        // Parse body
        if (func_obj.object.get("body")) |body_obj| {
            if (body_obj != .array) return SirsError.InvalidType;
            
            for (body_obj.array.items) |stmt_obj| {
                const stmt = try self.parseStatement(stmt_obj);
                function.body.append(stmt) catch return SirsError.OutOfMemory;
            }
        }
        
        // Parse optional fields
        if (func_obj.object.get("inline")) |inline_obj| {
            if (inline_obj == .bool) function.@"inline" = inline_obj.bool;
        }
        
        if (func_obj.object.get("pure")) |pure_obj| {
            if (pure_obj == .bool) function.pure = pure_obj.bool;
        }
        
        return function;
    }
    
    fn parseParameter(self: *Parser, param_obj: json.Value) SirsError!Parameter {
        if (param_obj != .object) return SirsError.InvalidType;
        
        const name = param_obj.object.get("name") orelse return SirsError.MissingField;
        if (name != .string) return SirsError.InvalidType;
        
        const type_obj = param_obj.object.get("type") orelse return SirsError.MissingField;
        const param_type = try self.parseType(type_obj);
        
        return Parameter{
            .name = self.allocator.dupe(u8, name.string) catch return SirsError.OutOfMemory,
            .type = param_type,
        };
    }
    
    fn parseType(_: *Parser, type_obj: json.Value) SirsError!Type {
        if (type_obj == .string) {
            const type_str = type_obj.string;
            if (std.mem.eql(u8, type_str, "void")) return Type.void;
            if (std.mem.eql(u8, type_str, "bool")) return Type.bool;
            if (std.mem.eql(u8, type_str, "i8")) return Type.i8;
            if (std.mem.eql(u8, type_str, "i16")) return Type.i16;
            if (std.mem.eql(u8, type_str, "i32")) return Type.i32;
            if (std.mem.eql(u8, type_str, "i64")) return Type.i64;
            if (std.mem.eql(u8, type_str, "u8")) return Type.u8;
            if (std.mem.eql(u8, type_str, "u16")) return Type.u16;
            if (std.mem.eql(u8, type_str, "u32")) return Type.u32;
            if (std.mem.eql(u8, type_str, "u64")) return Type.u64;
            if (std.mem.eql(u8, type_str, "f32")) return Type.f32;
            if (std.mem.eql(u8, type_str, "f64")) return Type.f64;
            if (std.mem.eql(u8, type_str, "str")) return Type.str;
            return SirsError.InvalidType;
        }
        
        // Complex types would be parsed here
        return Type.void;
    }
    
    fn parseStatement(self: *Parser, stmt_obj: json.Value) SirsError!Statement {
        if (stmt_obj != .object) return SirsError.InvalidStatement;
        
        // Handle different statement types
        if (stmt_obj.object.get("let")) |let_obj| {
            return try self.parseLetStatement(let_obj);
        }
        
        if (stmt_obj.object.get("return")) |return_obj| {
            const expr = try self.parseExpression(return_obj);
            return Statement{ .@"return" = expr };
        }
        
        if (stmt_obj.object.get("expression")) |expr_obj| {
            const expr = try self.parseExpression(expr_obj);
            return Statement{ .expression = expr };
        }
        
        return SirsError.InvalidStatement;
    }
    
    fn parseLetStatement(self: *Parser, let_obj: json.Value) SirsError!Statement {
        if (let_obj != .object) return SirsError.InvalidStatement;
        
        const name = let_obj.object.get("name") orelse return SirsError.MissingField;
        if (name != .string) return SirsError.InvalidType;
        
        const value_obj = let_obj.object.get("value") orelse return SirsError.MissingField;
        const value = try self.parseExpression(value_obj);
        
        const mutable = if (let_obj.object.get("mutable")) |mut_obj| 
            if (mut_obj == .bool) mut_obj.bool else false
        else false;
        
        const type_opt = if (let_obj.object.get("type")) |type_obj|
            try self.parseType(type_obj)
        else null;
        
        return Statement{
            .let = .{
                .name = self.allocator.dupe(u8, name.string) catch return SirsError.OutOfMemory,
                .type = type_opt,
                .mutable = mutable,
                .value = value,
            },
        };
    }
    
    fn parseExpression(self: *Parser, expr_obj: json.Value) SirsError!Expression {
        if (expr_obj != .object) return SirsError.InvalidExpression;
        
        // Handle literal expressions
        if (expr_obj.object.get("literal")) |literal_obj| {
            return try self.parseLiteral(literal_obj);
        }
        
        // Handle variable expressions
        if (expr_obj.object.get("var")) |var_obj| {
            if (var_obj != .string) return SirsError.InvalidExpression;
            return Expression{
                .variable = self.allocator.dupe(u8, var_obj.string) catch return SirsError.OutOfMemory,
            };
        }
        
        // Handle sample expressions
        if (expr_obj.object.get("sample")) |sample_obj| {
            return try self.parseSampleExpression(sample_obj);
        }
        
        // Handle operation expressions
        if (expr_obj.object.get("op")) |op_obj| {
            return try self.parseOpExpression(op_obj);
        }
        
        // Handle call expressions
        if (expr_obj.object.get("call")) |call_obj| {
            return try self.parseCallExpression(call_obj);
        }
        
        return SirsError.InvalidExpression;
    }
    
    fn parseCallExpression(self: *Parser, call_obj: json.Value) SirsError!Expression {
        if (call_obj != .object) return SirsError.InvalidExpression;
        
        const function_name = call_obj.object.get("function") orelse return SirsError.MissingField;
        if (function_name != .string) return SirsError.InvalidExpression;
        
        const args_obj = call_obj.object.get("args") orelse return SirsError.MissingField;
        if (args_obj != .array) return SirsError.InvalidExpression;
        
        var args = ArrayList(Expression).init(self.allocator);
        for (args_obj.array.items) |arg_obj| {
            const arg = try self.parseExpression(arg_obj);
            args.append(arg) catch return SirsError.OutOfMemory;
        }
        
        return Expression{
            .call = .{
                .function = self.allocator.dupe(u8, function_name.string) catch return SirsError.OutOfMemory,
                .args = args,
            },
        };
    }
    
    fn parseLiteral(self: *Parser, literal_obj: json.Value) SirsError!Expression {
        switch (literal_obj) {
            .integer => |i| return Expression{ .literal = Literal{ .integer = i } },
            .float => |f| return Expression{ .literal = Literal{ .float = f } },
            .string => |s| return Expression{ .literal = Literal{ .string = self.allocator.dupe(u8, s) catch return SirsError.OutOfMemory } },
            .bool => |b| return Expression{ .literal = Literal{ .boolean = b } },
            .null => return Expression{ .literal = Literal.null },
            else => return SirsError.InvalidExpression,
        }
    }
    
    fn parseSampleExpression(self: *Parser, sample_obj: json.Value) SirsError!Expression {
        if (sample_obj != .object) return SirsError.InvalidExpression;
        
        const distribution = sample_obj.object.get("distribution") orelse return SirsError.MissingField;
        if (distribution != .string) return SirsError.InvalidType;
        
        var params = ArrayList(Expression).init(self.allocator);
        
        if (sample_obj.object.get("params")) |params_obj| {
            if (params_obj != .array) return SirsError.InvalidType;
            
            for (params_obj.array.items) |param_obj| {
                const param_expr = try self.parseExpression(param_obj);
                params.append(param_expr) catch return SirsError.OutOfMemory;
            }
        }
        
        return Expression{
            .sample = .{
                .distribution = self.allocator.dupe(u8, distribution.string) catch return SirsError.OutOfMemory,
                .params = params,
            },
        };
    }
    
    fn parseOpExpression(self: *Parser, op_obj: json.Value) SirsError!Expression {
        if (op_obj != .object) return SirsError.InvalidExpression;
        
        const kind_obj = op_obj.object.get("kind") orelse return SirsError.MissingField;
        if (kind_obj != .string) return SirsError.InvalidType;
        
        const op_kind = try self.parseOpKind(kind_obj.string);
        
        const args_obj = op_obj.object.get("args") orelse return SirsError.MissingField;
        if (args_obj != .array) return SirsError.InvalidType;
        
        var args = ArrayList(Expression).init(self.allocator);
        for (args_obj.array.items) |arg_obj| {
            const arg_expr = try self.parseExpression(arg_obj);
            args.append(arg_expr) catch return SirsError.OutOfMemory;
        }
        
        return Expression{
            .op = .{
                .kind = op_kind,
                .args = args,
            },
        };
    }
    
    fn parseOpKind(_: *Parser, op_str: []const u8) SirsError!OpKind {
        if (std.mem.eql(u8, op_str, "add")) return OpKind.add;
        if (std.mem.eql(u8, op_str, "sub")) return OpKind.sub;
        if (std.mem.eql(u8, op_str, "mul")) return OpKind.mul;
        if (std.mem.eql(u8, op_str, "div")) return OpKind.div;
        if (std.mem.eql(u8, op_str, "mod")) return OpKind.mod;
        if (std.mem.eql(u8, op_str, "pow")) return OpKind.pow;
        if (std.mem.eql(u8, op_str, "eq")) return OpKind.eq;
        if (std.mem.eql(u8, op_str, "ne")) return OpKind.ne;
        if (std.mem.eql(u8, op_str, "lt")) return OpKind.lt;
        if (std.mem.eql(u8, op_str, "le")) return OpKind.le;
        if (std.mem.eql(u8, op_str, "gt")) return OpKind.gt;
        if (std.mem.eql(u8, op_str, "ge")) return OpKind.ge;
        if (std.mem.eql(u8, op_str, "and")) return OpKind.@"and";
        if (std.mem.eql(u8, op_str, "or")) return OpKind.@"or";
        if (std.mem.eql(u8, op_str, "not")) return OpKind.not;
        if (std.mem.eql(u8, op_str, "bitand")) return OpKind.bitand;
        if (std.mem.eql(u8, op_str, "bitor")) return OpKind.bitor;
        if (std.mem.eql(u8, op_str, "bitxor")) return OpKind.bitxor;
        if (std.mem.eql(u8, op_str, "bitnot")) return OpKind.bitnot;
        if (std.mem.eql(u8, op_str, "shl")) return OpKind.shl;
        if (std.mem.eql(u8, op_str, "shr")) return OpKind.shr;
        
        return SirsError.InvalidExpression;
    }
};