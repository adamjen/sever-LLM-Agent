const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const SirsParser = @import("sirs.zig");
const Type = SirsParser.Type;
const Expression = SirsParser.Expression;
const Statement = SirsParser.Statement;
const Program = SirsParser.Program;
const Function = SirsParser.Function;

pub const TypeCheckError = error{
    UndefinedVariable,
    UndefinedFunction,
    TypeMismatch,
    InvalidOperation,
    ReturnTypeMismatch,
    ArgumentCountMismatch,
    ArgumentTypeMismatch,
    InvalidSample,
    InvalidObservation,
    MissingReturn,
    OutOfMemory,
};

pub const TypeChecker = struct {
    allocator: Allocator,
    // Symbol table for current scope
    variables: StringHashMap(Type),
    // Current function context
    current_function: ?*Function,
    
    pub fn init(allocator: Allocator) TypeChecker {
        return TypeChecker{
            .allocator = allocator,
            .variables = StringHashMap(Type).init(allocator),
            .current_function = null,
        };
    }
    
    pub fn deinit(self: *TypeChecker) void {
        self.variables.deinit();
    }
    
    pub fn check(self: *TypeChecker, program: *Program) TypeCheckError!void {
        // Check that entry function exists
        if (!program.functions.contains(program.entry)) {
            std.debug.print("Error: Entry function '{s}' not found\n", .{program.entry});
            return TypeCheckError.UndefinedFunction;
        }
        
        // Type check all functions
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            
            try self.checkFunction(func_name, function, program);
        }
    }
    
    fn checkFunction(self: *TypeChecker, name: []const u8, function: *Function, program: *Program) TypeCheckError!void {
        _ = name;
        
        // Clear variable scope for new function
        self.variables.clearRetainingCapacity();
        self.current_function = function;
        
        // Add function parameters to scope
        for (function.args.items) |param| {
            self.variables.put(param.name, param.type) catch return TypeCheckError.OutOfMemory;
        }
        
        // Check function body
        var has_return = false;
        for (function.body.items) |*stmt| {
            try self.checkStatement(stmt, program);
            if (stmt.* == .@"return") {
                has_return = true;
            }
        }
        
        // Check that non-void functions have a return statement
        if (function.@"return" != .void and !has_return) {
            return TypeCheckError.MissingReturn;
        }
    }
    
    fn checkStatement(self: *TypeChecker, stmt: *Statement, program: *Program) TypeCheckError!void {
        switch (stmt.*) {
            .let => |*let_stmt| {
                const value_type = try self.checkExpression(&let_stmt.value, program);
                
                // If type is explicitly specified, check compatibility
                if (let_stmt.type) |expected_type| {
                    if (!self.typesCompatible(value_type, expected_type)) {
                        return TypeCheckError.TypeMismatch;
                    }
                    // Store the explicit type
                    self.variables.put(let_stmt.name, expected_type) catch return TypeCheckError.OutOfMemory;
                } else {
                    // Infer type from value
                    self.variables.put(let_stmt.name, value_type) catch return TypeCheckError.OutOfMemory;
                }
            },
            
            .assign => |*assign_stmt| {
                const target_type = try self.checkLValue(&assign_stmt.target, program);
                const value_type = try self.checkExpression(&assign_stmt.value, program);
                
                if (!self.typesCompatible(target_type, value_type)) {
                    return TypeCheckError.TypeMismatch;
                }
            },
            
            .@"if" => |*if_stmt| {
                const condition_type = try self.checkExpression(&if_stmt.condition, program);
                if (condition_type != .bool) {
                    return TypeCheckError.TypeMismatch;
                }
                
                // Check then branch
                for (if_stmt.then.items) |*then_stmt| {
                    try self.checkStatement(then_stmt, program);
                }
                
                // Check else branch if present
                if (if_stmt.@"else") |*else_stmts| {
                    for (else_stmts.items) |*else_stmt| {
                        try self.checkStatement(else_stmt, program);
                    }
                }
            },
            
            .@"while" => |*while_stmt| {
                const condition_type = try self.checkExpression(&while_stmt.condition, program);
                if (condition_type != .bool) {
                    return TypeCheckError.TypeMismatch;
                }
                
                for (while_stmt.body.items) |*body_stmt| {
                    try self.checkStatement(body_stmt, program);
                }
            },
            
            .@"return" => |*return_expr| {
                const return_type = try self.checkExpression(return_expr, program);
                
                if (self.current_function) |func| {
                    if (!self.typesCompatible(return_type, func.@"return")) {
                        return TypeCheckError.ReturnTypeMismatch;
                    }
                }
            },
            
            .observe => |*observe_stmt| {
                // Check that parameters match distribution requirements
                for (observe_stmt.params.items) |*param| {
                    _ = try self.checkExpression(param, program);
                }
                
                _ = try self.checkExpression(&observe_stmt.value, program);
            },
            
            .prob_assert => |*assert_stmt| {
                const condition_type = try self.checkExpression(&assert_stmt.condition, program);
                if (condition_type != .bool) {
                    return TypeCheckError.TypeMismatch;
                }
                
                // Confidence should be between 0 and 1
                if (assert_stmt.confidence < 0.0 or assert_stmt.confidence > 1.0) {
                    return TypeCheckError.InvalidOperation;
                }
            },
            
            .expression => |*expr| {
                _ = try self.checkExpression(expr, program);
            },
            
            .@"break", .@"continue" => {
                // These are valid in loop contexts - could add context checking
            },
            
            else => {
                // Handle other statement types
            },
        }
    }
    
    fn checkExpression(self: *TypeChecker, expr: *Expression, program: *Program) TypeCheckError!Type {
        switch (expr.*) {
            .literal => |literal| {
                return switch (literal) {
                    .integer => Type.i32, // Use i32 for integer literals by default
                    .float => Type.f64,
                    .string => Type.str,
                    .boolean => Type.bool,
                    .null => Type.void, // or optional type
                };
            },
            
            .variable => |var_name| {
                return self.variables.get(var_name) orelse {
                    std.debug.print("Error: Undefined variable '{s}'\n", .{var_name});
                    return TypeCheckError.UndefinedVariable;
                };
            },
            
            .call => |*call_expr| {
                // Check for built-in functions first
                if (self.isBuiltinFunction(call_expr.function)) {
                    return try self.checkBuiltinFunction(call_expr, program);
                }
                
                const function = program.functions.get(call_expr.function) orelse {
                    std.debug.print("Error: Undefined function '{s}'\n", .{call_expr.function});
                    return TypeCheckError.UndefinedFunction;
                };
                
                // Check argument count
                if (call_expr.args.items.len != function.args.items.len) {
                    return TypeCheckError.ArgumentCountMismatch;
                }
                
                // Check argument types
                for (call_expr.args.items, 0..) |*arg, i| {
                    const arg_type = try self.checkExpression(arg, program);
                    const expected_type = function.args.items[i].type;
                    
                    if (!self.typesCompatible(arg_type, expected_type)) {
                        return TypeCheckError.ArgumentTypeMismatch;
                    }
                }
                
                return function.@"return";
            },
            
            .op => |*op_expr| {
                return try self.checkOperation(op_expr, program);
            },
            
            .sample => |*sample_expr| {
                // Validate distribution parameters
                const dist_kind = self.getDistributionKind(sample_expr.distribution) orelse {
                    return TypeCheckError.InvalidSample;
                };
                
                const expected_param_count = self.getDistributionParamCount(dist_kind);
                if (sample_expr.params.items.len != expected_param_count) {
                    return TypeCheckError.InvalidSample;
                }
                
                // Check parameter types
                for (sample_expr.params.items) |*param| {
                    const param_type = try self.checkExpression(param, program);
                    // For now, assume all distribution parameters are numeric
                    if (!self.isNumericType(param_type)) {
                        return TypeCheckError.InvalidSample;
                    }
                }
                
                // Sample expressions return the sampled type (usually numeric)
                return self.getDistributionSampleType(dist_kind);
            },
            
            .index => |*index_expr| {
                const array_type = try self.checkExpression(index_expr.array, program);
                const index_type = try self.checkExpression(index_expr.index, program);
                
                if (!self.isIntegerType(index_type)) {
                    return TypeCheckError.TypeMismatch;
                }
                
                return switch (array_type) {
                    .array => |arr| arr.element.*,
                    .slice => |slice| slice.element.*,
                    else => TypeCheckError.InvalidOperation,
                };
            },
            
            .field => |*field_expr| {
                const object_type = try self.checkExpression(field_expr.object, program);
                
                return switch (object_type) {
                    .@"struct" => |struct_fields| {
                        if (struct_fields.get(field_expr.field)) |field_type_ptr| {
                            return field_type_ptr.*;
                        } else {
                            return TypeCheckError.UndefinedVariable;
                        }
                    },
                    else => TypeCheckError.InvalidOperation,
                };
            },
            
            else => {
                // Handle other expression types
                return Type.void;
            },
        }
    }
    
    fn checkLValue(self: *TypeChecker, lvalue: *const SirsParser.LValue, program: *Program) TypeCheckError!Type {
        switch (lvalue.*) {
            .variable => |var_name| {
                return self.variables.get(var_name) orelse TypeCheckError.UndefinedVariable;
            },
            .index => |*index_lvalue| {
                const array_type = try self.checkLValue(index_lvalue.array, program);
                const index_type = try self.checkExpression(@constCast(&index_lvalue.index), program);
                
                if (!self.isIntegerType(index_type)) {
                    return TypeCheckError.TypeMismatch;
                }
                
                return switch (array_type) {
                    .array => |arr| arr.element.*,
                    .slice => |slice| slice.element.*,
                    else => TypeCheckError.InvalidOperation,
                };
            },
            .field => |*field_lvalue| {
                const object_type = try self.checkLValue(field_lvalue.object, program);
                
                return switch (object_type) {
                    .@"struct" => |struct_fields| {
                        if (struct_fields.get(field_lvalue.field)) |field_type_ptr| {
                            return field_type_ptr.*;
                        } else {
                            return TypeCheckError.UndefinedVariable;
                        }
                    },
                    else => TypeCheckError.InvalidOperation,
                };
            },
        }
    }
    
    fn checkOperation(self: *TypeChecker, op_expr: anytype, program: *Program) TypeCheckError!Type {
        const args = &op_expr.args;
        
        switch (op_expr.kind) {
            .add, .sub, .mul, .div, .mod => {
                if (args.items.len != 2) return TypeCheckError.InvalidOperation;
                
                const left_type = try self.checkExpression(@constCast(&args.items[0]), program);
                const right_type = try self.checkExpression(@constCast(&args.items[1]), program);
                
                if (!self.isNumericType(left_type) or !self.isNumericType(right_type)) {
                    return TypeCheckError.TypeMismatch;
                }
                
                // Return the "wider" type
                return self.getArithmeticResultType(left_type, right_type);
            },
            
            .eq, .ne, .lt, .le, .gt, .ge => {
                if (args.items.len != 2) return TypeCheckError.InvalidOperation;
                
                const left_type = try self.checkExpression(@constCast(&args.items[0]), program);
                const right_type = try self.checkExpression(@constCast(&args.items[1]), program);
                
                if (!self.typesCompatible(left_type, right_type)) {
                    return TypeCheckError.TypeMismatch;
                }
                
                return Type.bool;
            },
            
            .@"and", .@"or" => {
                if (args.items.len != 2) return TypeCheckError.InvalidOperation;
                
                const left_type = try self.checkExpression(@constCast(&args.items[0]), program);
                const right_type = try self.checkExpression(@constCast(&args.items[1]), program);
                
                if (left_type != .bool or right_type != .bool) {
                    return TypeCheckError.TypeMismatch;
                }
                
                return Type.bool;
            },
            
            .not => {
                if (args.items.len != 1) return TypeCheckError.InvalidOperation;
                
                const operand_type = try self.checkExpression(@constCast(&args.items[0]), program);
                if (operand_type != .bool) {
                    return TypeCheckError.TypeMismatch;
                }
                
                return Type.bool;
            },
            
            else => {
                // Handle other operations
                return Type.void;
            },
        }
    }
    
    fn typesCompatible(_: *TypeChecker, type1: Type, type2: Type) bool {
        // Simple type compatibility check - can be extended
        return std.meta.eql(type1, type2);
    }
    
    fn isNumericType(_: *TypeChecker, t: Type) bool {
        return switch (t) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .f32, .f64 => true,
            else => false,
        };
    }
    
    fn isIntegerType(_: *TypeChecker, t: Type) bool {
        return switch (t) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => true,
            else => false,
        };
    }
    
    fn getArithmeticResultType(_: *TypeChecker, left: Type, right: Type) Type {
        // Simple type promotion rules
        if (left == .f64 or right == .f64) return Type.f64;
        if (left == .f32 or right == .f32) return Type.f32;
        if (left == .i64 or right == .i64) return Type.i64;
        if (left == .u64 or right == .u64) return Type.u64;
        return Type.i32;
    }
    
    fn getDistributionKind(_: *TypeChecker, dist_name: []const u8) ?SirsParser.DistributionKind {
        if (std.mem.eql(u8, dist_name, "uniform")) return .uniform;
        if (std.mem.eql(u8, dist_name, "normal")) return .normal;
        if (std.mem.eql(u8, dist_name, "categorical")) return .categorical;
        if (std.mem.eql(u8, dist_name, "bernoulli")) return .bernoulli;
        if (std.mem.eql(u8, dist_name, "exponential")) return .exponential;
        if (std.mem.eql(u8, dist_name, "gamma")) return .gamma;
        if (std.mem.eql(u8, dist_name, "beta")) return .beta;
        return null;
    }
    
    fn getDistributionParamCount(_: *TypeChecker, kind: SirsParser.DistributionKind) usize {
        return switch (kind) {
            .uniform => 2, // min, max
            .normal => 2,  // mean, std
            .categorical => 1, // probabilities array
            .bernoulli => 1,   // probability
            .exponential => 1, // rate
            .gamma => 2,       // shape, scale
            .beta => 2,        // alpha, beta
        };
    }
    
    fn getDistributionSampleType(_: *TypeChecker, kind: SirsParser.DistributionKind) Type {
        return switch (kind) {
            .uniform, .normal, .exponential, .gamma, .beta => Type.f64,
            .categorical => Type.i32,
            .bernoulli => Type.bool,
        };
    }
    
    fn isBuiltinFunction(_: *TypeChecker, function_name: []const u8) bool {
        return std.mem.eql(u8, function_name, "std_print") or
               std.mem.eql(u8, function_name, "std_print_int") or
               std.mem.eql(u8, function_name, "std_print_float");
    }
    
    fn checkBuiltinFunction(self: *TypeChecker, call_expr: anytype, program: *Program) TypeCheckError!Type {
        const function_name = call_expr.function;
        
        if (std.mem.eql(u8, function_name, "std_print")) {
            // std_print(message: []const u8) void
            if (call_expr.args.items.len != 1) {
                return TypeCheckError.ArgumentCountMismatch;
            }
            const arg_type = try self.checkExpression(@constCast(&call_expr.args.items[0]), program);
            if (arg_type != .str) {
                return TypeCheckError.ArgumentTypeMismatch;
            }
            return Type.void;
        } else if (std.mem.eql(u8, function_name, "std_print_int")) {
            // std_print_int(value: i32) void
            if (call_expr.args.items.len != 1) {
                return TypeCheckError.ArgumentCountMismatch;
            }
            const arg_type = try self.checkExpression(@constCast(&call_expr.args.items[0]), program);
            if (arg_type != .i32) {
                return TypeCheckError.ArgumentTypeMismatch;
            }
            return Type.void;
        } else if (std.mem.eql(u8, function_name, "std_print_float")) {
            // std_print_float(value: f64) void
            if (call_expr.args.items.len != 1) {
                return TypeCheckError.ArgumentCountMismatch;
            }
            const arg_type = try self.checkExpression(@constCast(&call_expr.args.items[0]), program);
            if (arg_type != .f64) {
                return TypeCheckError.ArgumentTypeMismatch;
            }
            return Type.void;
        }
        
        return TypeCheckError.UndefinedFunction;
    }
};