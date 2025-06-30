const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const SirsParser = @import("sirs.zig");
const Program = SirsParser.Program;
const Function = SirsParser.Function;
const Statement = SirsParser.Statement;
const Expression = SirsParser.Expression;
const Type = SirsParser.Type;
const Literal = SirsParser.Literal;

/// Query types for AST searching
pub const QueryType = enum {
    function,
    variable,
    function_call,
    literal,
    type_usage,
    pattern,
    all_nodes,
};

/// Query result containing matched AST nodes
pub const QueryResult = struct {
    node_type: QueryType,
    location: SourceLocation,
    content: []const u8,
    metadata: ?[]const u8, // Additional context-specific information
    
    pub fn deinit(self: *QueryResult, allocator: Allocator) void {
        allocator.free(self.content);
        if (self.metadata) |meta| {
            allocator.free(meta);
        }
    }
};

/// Source location information
pub const SourceLocation = struct {
    function_name: []const u8,
    line: u32,
    column: u32,
    context: []const u8, // Brief context description
};

/// AST traversal visitor pattern
pub const ASTVisitor = struct {
    allocator: Allocator,
    results: ArrayList(QueryResult),
    query_type: QueryType,
    search_term: ?[]const u8,
    current_function: ?[]const u8,
    
    pub fn init(allocator: Allocator, query_type: QueryType, search_term: ?[]const u8) ASTVisitor {
        return ASTVisitor{
            .allocator = allocator,
            .results = ArrayList(QueryResult).init(allocator),
            .query_type = query_type,
            .search_term = search_term,
            .current_function = null,
        };
    }
    
    pub fn deinit(self: *ASTVisitor) void {
        for (self.results.items) |*result| {
            result.deinit(self.allocator);
        }
        self.results.deinit();
    }
    
    pub fn visitProgram(self: *ASTVisitor, program: *Program) !void {
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            self.current_function = func_name;
            try self.visitFunction(func_name, function);
        }
    }
    
    fn visitFunction(self: *ASTVisitor, name: []const u8, function: *Function) !void {
        // Check if we're searching for this function
        if (self.query_type == .function) {
            if (self.search_term == null or std.mem.indexOf(u8, name, self.search_term.?) != null) {
                try self.addResult(.{
                    .node_type = .function,
                    .location = .{
                        .function_name = name,
                        .line = 1, // Would need proper source mapping
                        .column = 1,
                        .context = "function definition",
                    },
                    .content = try self.allocator.dupe(u8, name),
                    .metadata = try std.fmt.allocPrint(self.allocator, "args:{d} return:{s}", .{
                        function.args.items.len,
                        @tagName(function.@"return"),
                    }),
                });
            }
        }
        
        // Visit function parameters
        for (function.args.items) |param| {
            try self.visitParameter(param);
        }
        
        // Visit function body
        for (function.body.items) |*stmt| {
            try self.visitStatement(stmt);
        }
    }
    
    fn visitParameter(self: *ASTVisitor, param: SirsParser.Parameter) !void {
        if (self.query_type == .variable) {
            if (self.search_term == null or std.mem.indexOf(u8, param.name, self.search_term.?) != null) {
                try self.addResult(.{
                    .node_type = .variable,
                    .location = .{
                        .function_name = self.current_function orelse "unknown",
                        .line = 1,
                        .column = 1,
                        .context = "function parameter",
                    },
                    .content = try self.allocator.dupe(u8, param.name),
                    .metadata = try std.fmt.allocPrint(self.allocator, "type:{s}", .{@tagName(param.type)}),
                });
            }
        }
    }
    
    fn visitStatement(self: *ASTVisitor, stmt: *Statement) anyerror!void {
        switch (stmt.*) {
            .let => |let_stmt| {
                // Check variable declarations
                if (self.query_type == .variable) {
                    if (self.search_term == null or std.mem.indexOf(u8, let_stmt.name, self.search_term.?) != null) {
                        try self.addResult(.{
                            .node_type = .variable,
                            .location = .{
                                .function_name = self.current_function orelse "unknown",
                                .line = 1,
                                .column = 1,
                                .context = "variable declaration",
                            },
                            .content = try self.allocator.dupe(u8, let_stmt.name),
                            .metadata = try std.fmt.allocPrint(self.allocator, "type:{s} mutable:{}", .{
                                if (let_stmt.type) |t| @tagName(t) else "inferred",
                                let_stmt.mutable,
                            }),
                        });
                    }
                }
                try self.visitExpression(@constCast(&let_stmt.value));
            },
            .@"if" => |if_stmt| {
                try self.visitExpression(@constCast(&if_stmt.condition));
                for (if_stmt.then.items) |*then_stmt| {
                    try self.visitStatement(then_stmt);
                }
                if (if_stmt.@"else") |else_stmts| {
                    for (else_stmts.items) |*else_stmt| {
                        try self.visitStatement(else_stmt);
                    }
                }
            },
            .@"while" => |while_stmt| {
                try self.visitExpression(@constCast(&while_stmt.condition));
                for (while_stmt.body.items) |*body_stmt| {
                    try self.visitStatement(body_stmt);
                }
            },
            .expression => |expr| {
                try self.visitExpression(@constCast(&expr));
            },
            .@"return" => |return_expr| {
                try self.visitExpression(@constCast(&return_expr));
            },
            else => {},
        }
    }
    
    fn visitExpression(self: *ASTVisitor, expr: *Expression) anyerror!void {
        switch (expr.*) {
            .variable => |var_name| {
                // Check variable usage
                if (self.query_type == .variable) {
                    if (self.search_term == null or std.mem.indexOf(u8, var_name, self.search_term.?) != null) {
                        try self.addResult(.{
                            .node_type = .variable,
                            .location = .{
                                .function_name = self.current_function orelse "unknown",
                                .line = 1,
                                .column = 1,
                                .context = "variable usage",
                            },
                            .content = try self.allocator.dupe(u8, var_name),
                            .metadata = try self.allocator.dupe(u8, "usage"),
                        });
                    }
                }
            },
            .call => |call_expr| {
                // Check function calls
                if (self.query_type == .function_call) {
                    if (self.search_term == null or std.mem.indexOf(u8, call_expr.function, self.search_term.?) != null) {
                        try self.addResult(.{
                            .node_type = .function_call,
                            .location = .{
                                .function_name = self.current_function orelse "unknown",
                                .line = 1,
                                .column = 1,
                                .context = "function call",
                            },
                            .content = try self.allocator.dupe(u8, call_expr.function),
                            .metadata = try std.fmt.allocPrint(self.allocator, "args:{d}", .{call_expr.args.items.len}),
                        });
                    }
                }
                
                // Visit arguments
                for (call_expr.args.items) |*arg| {
                    try self.visitExpression(@constCast(arg));
                }
            },
            .literal => |literal| {
                try self.visitLiteral(literal);
            },
            .op => |op_expr| {
                for (op_expr.args.items) |*arg| {
                    try self.visitExpression(@constCast(arg));
                }
            },
            else => {},
        }
    }
    
    fn visitLiteral(self: *ASTVisitor, literal: Literal) !void {
        if (self.query_type == .literal) {
            const literal_str = switch (literal) {
                .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
                .float => |f| try std.fmt.allocPrint(self.allocator, "{d}", .{f}),
                .boolean => |b| try std.fmt.allocPrint(self.allocator, "{}", .{b}),
                .string => |s| try self.allocator.dupe(u8, s),
                .null => try self.allocator.dupe(u8, "null"),
            };
            defer self.allocator.free(literal_str);
            
            if (self.search_term == null or std.mem.indexOf(u8, literal_str, self.search_term.?) != null) {
                try self.addResult(.{
                    .node_type = .literal,
                    .location = .{
                        .function_name = self.current_function orelse "unknown",
                        .line = 1,
                        .column = 1,
                        .context = "literal value",
                    },
                    .content = try self.allocator.dupe(u8, literal_str),
                    .metadata = try std.fmt.allocPrint(self.allocator, "type:{s}", .{@tagName(literal)}),
                });
            }
        }
    }
    
    fn addResult(self: *ASTVisitor, result: QueryResult) !void {
        try self.results.append(result);
    }
};

/// AST Query Engine
pub const ASTQueryEngine = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) ASTQueryEngine {
        return ASTQueryEngine{
            .allocator = allocator,
        };
    }
    
    /// Find all functions matching a pattern
    pub fn findFunctions(self: *ASTQueryEngine, program: *Program, pattern: ?[]const u8) ![]QueryResult {
        var visitor = ASTVisitor.init(self.allocator, .function, pattern);
        defer visitor.deinit();
        
        try visitor.visitProgram(program);
        
        // Transfer ownership of results
        const results = try self.allocator.alloc(QueryResult, visitor.results.items.len);
        for (visitor.results.items, 0..) |result, i| {
            results[i] = result;
        }
        visitor.results.clearRetainingCapacity(); // Prevent double-free
        
        return results;
    }
    
    /// Find all variables matching a pattern
    pub fn findVariables(self: *ASTQueryEngine, program: *Program, pattern: ?[]const u8) ![]QueryResult {
        var visitor = ASTVisitor.init(self.allocator, .variable, pattern);
        defer visitor.deinit();
        
        try visitor.visitProgram(program);
        
        const results = try self.allocator.alloc(QueryResult, visitor.results.items.len);
        for (visitor.results.items, 0..) |result, i| {
            results[i] = result;
        }
        visitor.results.clearRetainingCapacity();
        
        return results;
    }
    
    /// Find all function calls matching a pattern
    pub fn findFunctionCalls(self: *ASTQueryEngine, program: *Program, pattern: ?[]const u8) ![]QueryResult {
        var visitor = ASTVisitor.init(self.allocator, .function_call, pattern);
        defer visitor.deinit();
        
        try visitor.visitProgram(program);
        
        const results = try self.allocator.alloc(QueryResult, visitor.results.items.len);
        for (visitor.results.items, 0..) |result, i| {
            results[i] = result;
        }
        visitor.results.clearRetainingCapacity();
        
        return results;
    }
    
    /// Find all literals matching a pattern
    pub fn findLiterals(self: *ASTQueryEngine, program: *Program, pattern: ?[]const u8) ![]QueryResult {
        var visitor = ASTVisitor.init(self.allocator, .literal, pattern);
        defer visitor.deinit();
        
        try visitor.visitProgram(program);
        
        const results = try self.allocator.alloc(QueryResult, visitor.results.items.len);
        for (visitor.results.items, 0..) |result, i| {
            results[i] = result;
        }
        visitor.results.clearRetainingCapacity();
        
        return results;
    }
    
    /// Get function signature and metadata
    pub fn getFunctionInfo(self: *ASTQueryEngine, program: *Program, func_name: []const u8) !?FunctionInfo {
        if (program.functions.get(func_name)) |function| {
            var params = try self.allocator.alloc(ParameterInfo, function.args.items.len);
            for (function.args.items, 0..) |param, i| {
                params[i] = ParameterInfo{
                    .name = try self.allocator.dupe(u8, param.name),
                    .type_name = try self.allocator.dupe(u8, @tagName(param.type)),
                };
            }
            
            return FunctionInfo{
                .name = try self.allocator.dupe(u8, func_name),
                .parameters = params,
                .return_type = try self.allocator.dupe(u8, @tagName(function.@"return")),
                .body_size = function.body.items.len,
                .is_inline = function.@"inline",
                .is_pure = function.pure,
            };
        }
        return null;
    }
    
    /// Cleanup results
    pub fn freeResults(self: *ASTQueryEngine, results: []QueryResult) void {
        for (results) |*result| {
            result.deinit(self.allocator);
        }
        self.allocator.free(results);
    }
};

/// Function metadata for analysis
pub const FunctionInfo = struct {
    name: []const u8,
    parameters: []ParameterInfo,
    return_type: []const u8,
    body_size: usize,
    is_inline: bool,
    is_pure: bool,
    
    pub fn deinit(self: *FunctionInfo, allocator: Allocator) void {
        allocator.free(self.name);
        for (self.parameters) |*param| {
            param.deinit(allocator);
        }
        allocator.free(self.parameters);
        allocator.free(self.return_type);
    }
};

/// Parameter metadata
pub const ParameterInfo = struct {
    name: []const u8,
    type_name: []const u8,
    
    pub fn deinit(self: *ParameterInfo, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.type_name);
    }
};

/// AST Manipulation Engine
pub const ASTManipulator = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) ASTManipulator {
        return ASTManipulator{
            .allocator = allocator,
        };
    }
    
    /// Add a new function to the program
    pub fn addFunction(self: *ASTManipulator, program: *Program, name: []const u8, function: Function) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        try program.functions.put(name_copy, function);
    }
    
    /// Remove a function from the program
    pub fn removeFunction(self: *ASTManipulator, program: *Program, name: []const u8) bool {
        _ = self;
        return program.functions.remove(name);
    }
    
    /// Rename a function
    pub fn renameFunction(self: *ASTManipulator, program: *Program, old_name: []const u8, new_name: []const u8) !bool {
        if (program.functions.get(old_name)) |function| {
            _ = program.functions.remove(old_name);
            const new_name_copy = try self.allocator.dupe(u8, new_name);
            try program.functions.put(new_name_copy, function);
            
            // Update all function calls throughout the program
            try self.updateFunctionCalls(program, old_name, new_name);
            return true;
        }
        return false;
    }
    
    /// Add a parameter to a function
    pub fn addParameter(self: *ASTManipulator, function: *Function, param: SirsParser.Parameter) !void {
        const param_copy = SirsParser.Parameter{
            .name = try self.allocator.dupe(u8, param.name),
            .type = param.type,
        };
        try function.args.append(param_copy);
    }
    
    /// Remove a parameter from a function
    pub fn removeParameter(self: *ASTManipulator, function: *Function, param_name: []const u8) bool {
        _ = self;
        for (function.args.items, 0..) |param, i| {
            if (std.mem.eql(u8, param.name, param_name)) {
                _ = function.args.swapRemove(i);
                return true;
            }
        }
        return false;
    }
    
    /// Add a statement to a function body
    pub fn addStatement(self: *ASTManipulator, function: *Function, stmt: Statement, position: ?usize) !void {
        _ = self;
        if (position) |pos| {
            try function.body.insert(pos, stmt);
        } else {
            try function.body.append(stmt);
        }
    }
    
    /// Remove a statement from a function body
    pub fn removeStatement(self: *ASTManipulator, function: *Function, position: usize) ?Statement {
        _ = self;
        if (position < function.body.items.len) {
            return function.body.swapRemove(position);
        }
        return null;
    }
    
    /// Update all function calls from old_name to new_name
    fn updateFunctionCalls(self: *ASTManipulator, program: *Program, old_name: []const u8, new_name: []const u8) Allocator.Error!void {
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const function = entry.value_ptr;
            try self.updateFunctionCallsInStatements(function.body.items, old_name, new_name);
        }
    }
    
    fn updateFunctionCallsInStatements(self: *ASTManipulator, statements: []const Statement, old_name: []const u8, new_name: []const u8) Allocator.Error!void {
        for (statements) |*stmt| {
            try self.updateFunctionCallsInStatement(@constCast(stmt), old_name, new_name);
        }
    }
    
    fn updateFunctionCallsInStatement(self: *ASTManipulator, stmt: *Statement, old_name: []const u8, new_name: []const u8) Allocator.Error!void {
        switch (stmt.*) {
            .let => |*let_stmt| {
                try self.updateFunctionCallsInExpression(&let_stmt.value, old_name, new_name);
            },
            .@"if" => |*if_stmt| {
                try self.updateFunctionCallsInExpression(&if_stmt.condition, old_name, new_name);
                try self.updateFunctionCallsInStatements(if_stmt.then.items, old_name, new_name);
                if (if_stmt.@"else") |else_stmts| {
                    try self.updateFunctionCallsInStatements(else_stmts.items, old_name, new_name);
                }
            },
            .@"while" => |*while_stmt| {
                try self.updateFunctionCallsInExpression(&while_stmt.condition, old_name, new_name);
                try self.updateFunctionCallsInStatements(while_stmt.body.items, old_name, new_name);
            },
            .expression => |*expr| {
                try self.updateFunctionCallsInExpression(expr, old_name, new_name);
            },
            .@"return" => |*return_expr| {
                try self.updateFunctionCallsInExpression(return_expr, old_name, new_name);
            },
            else => {},
        }
    }
    
    fn updateFunctionCallsInExpression(self: *ASTManipulator, expr: *Expression, old_name: []const u8, new_name: []const u8) Allocator.Error!void {
        switch (expr.*) {
            .call => |*call_expr| {
                if (std.mem.eql(u8, call_expr.function, old_name)) {
                    self.allocator.free(call_expr.function);
                    call_expr.function = try self.allocator.dupe(u8, new_name);
                }
                for (call_expr.args.items) |*arg| {
                    try self.updateFunctionCallsInExpression(arg, old_name, new_name);
                }
            },
            .op => |*op_expr| {
                for (op_expr.args.items) |*arg| {
                    try self.updateFunctionCallsInExpression(arg, old_name, new_name);
                }
            },
            else => {},
        }
    }
};

/// Code generation for modified ASTs
pub const ASTCodegen = struct {
    allocator: Allocator,
    output: ArrayList(u8),
    indent_level: u32,
    
    pub fn init(allocator: Allocator) ASTCodegen {
        return ASTCodegen{
            .allocator = allocator,
            .output = ArrayList(u8).init(allocator),
            .indent_level = 0,
        };
    }
    
    pub fn deinit(self: *ASTCodegen) void {
        self.output.deinit();
    }
    
    /// Generate SIRS JSON from modified AST
    pub fn generateSIRS(self: *ASTCodegen, program: *Program) ![]const u8 {
        self.output.clearRetainingCapacity();
        self.indent_level = 0;
        
        try self.writeLine("{");
        self.indent_level += 1;
        
        try self.writeIndent();
        try self.write("\"program\": {");
        try self.writeLine("");
        self.indent_level += 1;
        
        // Entry point
        try self.writeIndent();
        try self.write("\"entry\": \"");
        try self.write(program.entry);
        try self.writeLine("\",");
        
        // Functions
        try self.writeIndent();
        try self.writeLine("\"functions\": {");
        self.indent_level += 1;
        
        var func_iter = program.functions.iterator();
        var first_func = true;
        while (func_iter.next()) |entry| {
            if (!first_func) try self.writeLine(",");
            first_func = false;
            
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            
            try self.writeIndent();
            try self.write("\"");
            try self.write(func_name);
            try self.write("\": ");
            try self.generateFunction(function);
        }
        try self.writeLine("");
        
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeLine("}");
        
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeLine("}");
        
        self.indent_level -= 1;
        try self.writeLine("}");
        
        return try self.allocator.dupe(u8, self.output.items);
    }
    
    fn generateFunction(self: *ASTCodegen, function: *Function) !void {
        try self.writeLine("{");
        self.indent_level += 1;
        
        // Arguments
        try self.writeIndent();
        try self.writeLine("\"args\": [");
        self.indent_level += 1;
        
        for (function.args.items, 0..) |param, i| {
            if (i > 0) try self.writeLine(",");
            try self.writeIndent();
            try self.write("{\"name\": \"");
            try self.write(param.name);
            try self.write("\", \"type\": \"");
            try self.write(@tagName(param.type));
            try self.write("\"}");
        }
        if (function.args.items.len > 0) try self.writeLine("");
        
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeLine("],");
        
        // Return type
        try self.writeIndent();
        try self.write("\"return\": \"");
        try self.write(@tagName(function.@"return"));
        try self.writeLine("\",");
        
        // Body
        try self.writeIndent();
        try self.writeLine("\"body\": [");
        try self.writeLine("// Statement generation would go here");
        try self.writeIndent();
        try self.writeLine("]");
        
        self.indent_level -= 1;
        try self.writeIndent();
        try self.write("}");
    }
    
    fn writeIndent(self: *ASTCodegen) !void {
        var i: u32 = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.write("  ");
        }
    }
    
    fn write(self: *ASTCodegen, text: []const u8) !void {
        try self.output.appendSlice(text);
    }
    
    fn writeLine(self: *ASTCodegen, text: []const u8) !void {
        try self.write(text);
        try self.write("\n");
    }
};

/// Pattern matching for complex queries
pub const ASTPattern = struct {
    pattern_type: PatternType,
    constraints: ArrayList(Constraint),
    
    const PatternType = enum {
        function_with_params,
        variable_usage_count,
        nested_function_calls,
        control_flow_depth,
    };
    
    const Constraint = struct {
        field: []const u8,
        operator: ComparisonOp,
        value: []const u8,
    };
    
    const ComparisonOp = enum {
        equals,
        greater_than,
        less_than,
        contains,
        regex_match,
    };
};