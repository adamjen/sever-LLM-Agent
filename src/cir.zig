const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const SirsParser = @import("sirs.zig");
const ErrorReporter = @import("error_reporter.zig").ErrorReporter;

/// Core Intermediate Representation (CIR)
/// This is a lower-level representation that's closer to the target machine
/// but still platform-independent. It enables optimizations and simplifies
/// code generation.

pub const CirError = error{
    UnsupportedOperation,
    InvalidType,
    UndefinedVariable,
    UndefinedFunction,
    OutOfMemory,
};

/// CIR Value types - more explicit than SIRS types
pub const CirType = union(enum) {
    void,
    i1,   // boolean
    i8, i16, i32, i64,
    u8, u16, u32, u64,
    f32, f64,
    ptr: *CirType,     // pointer to type
    array: struct {
        element: *CirType,
        size: u32,
    },
    func: struct {
        params: ArrayList(CirType),
        return_type: *CirType,
    },
    struct_type: StringHashMap(*CirType),
};

/// CIR Value representation
pub const CirValue = union(enum) {
    // Constants
    void_const,
    bool_const: bool,
    int_const: struct { value: i64, type: CirType },
    float_const: struct { value: f64, type: CirType },
    string_const: []const u8,
    null_const,
    
    // Variables and temporaries
    variable: struct { name: []const u8, type: CirType },
    temporary: struct { id: u32, type: CirType },
    
    // Complex values
    function_ref: []const u8,
    global_ref: []const u8,
};

/// CIR Operations - simplified and more explicit than SIRS operations
pub const CirOp = enum {
    // Arithmetic
    add, sub, mul, div, mod,
    
    // Comparison
    eq, ne, lt, le, gt, ge,
    
    // Logical
    and_op, or_op, not_op,
    
    // Bitwise
    bit_and, bit_or, bit_xor, bit_not,
    shl, shr,
    
    // Memory
    load, store,
    alloca,         // stack allocation
    
    // Type conversion
    bitcast, trunc, extend, int_to_float, float_to_int,
    
    // Control flow
    branch, conditional_branch, call, ret,
    
    // Special
    phi,            // SSA phi node
    undef,          // undefined value
};

/// CIR Instruction
pub const CirInstruction = struct {
    id: u32,                    // unique instruction ID
    op: CirOp,
    operands: ArrayList(CirValue),
    result_type: ?CirType,
    result_name: ?[]const u8,   // for named results
    
    pub fn init(allocator: Allocator, id: u32, op: CirOp) CirInstruction {
        return CirInstruction{
            .id = id,
            .op = op,
            .operands = ArrayList(CirValue).init(allocator),
            .result_type = null,
            .result_name = null,
        };
    }
    
    pub fn deinit(self: *CirInstruction) void {
        self.operands.deinit();
    }
};

/// CIR Basic Block - contains instructions with single entry/exit
pub const CirBasicBlock = struct {
    label: []const u8,
    instructions: ArrayList(CirInstruction),
    predecessors: ArrayList([]const u8),
    successors: ArrayList([]const u8),
    allocator: Allocator,
    
    pub fn init(allocator: Allocator, label: []const u8) CirBasicBlock {
        return CirBasicBlock{
            .label = label,
            .instructions = ArrayList(CirInstruction).init(allocator),
            .predecessors = ArrayList([]const u8).init(allocator),
            .successors = ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *CirBasicBlock) void {
        self.allocator.free(self.label);
        for (self.instructions.items) |*inst| {
            inst.deinit();
        }
        self.instructions.deinit();
        self.predecessors.deinit();
        self.successors.deinit();
    }
};

/// CIR Function parameter
pub const CirParam = struct {
    name: []const u8,
    type: CirType,
};

/// CIR Function
pub const CirFunction = struct {
    name: []const u8,
    params: ArrayList(CirParam),
    return_type: CirType,
    basic_blocks: ArrayList(CirBasicBlock),
    is_external: bool,      // for external/builtin functions
    
    pub fn init(allocator: Allocator, name: []const u8) CirFunction {
        return CirFunction{
            .name = name,
            .params = ArrayList(CirParam).init(allocator),
            .return_type = CirType.void,
            .basic_blocks = ArrayList(CirBasicBlock).init(allocator),
            .is_external = false,
        };
    }
    
    pub fn deinit(self: *CirFunction) void {
        self.params.deinit();
        for (self.basic_blocks.items) |*bb| {
            bb.deinit();
        }
        self.basic_blocks.deinit();
    }
};

/// CIR Module - top-level container
pub const CirModule = struct {
    name: []const u8,
    functions: StringHashMap(CirFunction),
    globals: StringHashMap(CirValue),
    types: StringHashMap(CirType),
    allocator: Allocator,
    
    pub fn init(allocator: Allocator, name: []const u8) CirModule {
        return CirModule{
            .name = name,
            .functions = StringHashMap(CirFunction).init(allocator),
            .globals = StringHashMap(CirValue).init(allocator),
            .types = StringHashMap(CirType).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *CirModule) void {
        // Free function names and their contents
        var func_iter = self.functions.iterator();
        while (func_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.functions.deinit();
        self.globals.deinit();
        self.types.deinit();
    }
};

/// CIR Lowering Pass - converts SIRS to CIR
pub const CirLowering = struct {
    allocator: Allocator,
    error_reporter: *ErrorReporter,
    module: CirModule,
    next_temp_id: u32,
    next_inst_id: u32,
    next_bb_id: u32,
    current_function: ?*CirFunction,
    current_bb: ?*CirBasicBlock,
    variable_map: StringHashMap(CirValue),  // maps SIRS variables to CIR values
    type_ptrs: ArrayList(*CirType),         // tracks allocated type pointers for cleanup
    
    pub fn init(allocator: Allocator, error_reporter: *ErrorReporter, module_name: []const u8) CirLowering {
        return CirLowering{
            .allocator = allocator,
            .error_reporter = error_reporter,
            .module = CirModule.init(allocator, module_name),
            .next_temp_id = 0,
            .next_inst_id = 0,
            .next_bb_id = 0,
            .current_function = null,
            .current_bb = null,
            .variable_map = StringHashMap(CirValue).init(allocator),
            .type_ptrs = ArrayList(*CirType).init(allocator),
        };
    }
    
    pub fn deinit(self: *CirLowering) void {
        self.module.deinit();
        self.variable_map.deinit();
        
        // Free all allocated type pointers
        for (self.type_ptrs.items) |type_ptr| {
            self.allocator.destroy(type_ptr);
        }
        self.type_ptrs.deinit();
    }
    
    /// Convert SIRS Program to CIR Module
    pub fn lower(self: *CirLowering, program: *SirsParser.Program) CirError!CirModule {
        // First, lower all function signatures
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const sirs_func = entry.value_ptr;
            
            try self.lowerFunctionSignature(func_name, sirs_func);
        }
        
        // Then, lower all function bodies
        func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const sirs_func = entry.value_ptr;
            
            try self.lowerFunctionBody(func_name, sirs_func);
        }
        
        return self.module;
    }
    
    fn lowerFunctionSignature(self: *CirLowering, name: []const u8, sirs_func: *SirsParser.Function) CirError!void {
        var cir_func = CirFunction.init(self.allocator, name);
        
        // Convert parameters
        for (sirs_func.args.items) |param| {
            const cir_type = try self.lowerType(param.type);
            try cir_func.params.append(CirParam{ .name = param.name, .type = cir_type });
        }
        
        // Convert return type
        cir_func.return_type = try self.lowerType(sirs_func.@"return");
        
        const name_copy = try self.allocator.dupe(u8, name);
        try self.module.functions.put(name_copy, cir_func);
    }
    
    fn lowerFunctionBody(self: *CirLowering, name: []const u8, sirs_func: *SirsParser.Function) CirError!void {
        const cir_func = self.module.functions.getPtr(name) orelse return CirError.UndefinedFunction;
        self.current_function = cir_func;
        
        // Clear variable mappings for new function
        self.variable_map.clearRetainingCapacity();
        
        // Map parameters to CIR values
        for (cir_func.params.items) |param| {
            const param_value = CirValue{ .variable = .{ .name = param.name, .type = param.type } };
            try self.variable_map.put(param.name, param_value);
        }
        
        // Create entry basic block
        const entry_label = try std.fmt.allocPrint(self.allocator, "{s}_entry", .{name});
        var entry_bb = CirBasicBlock.init(self.allocator, entry_label);
        self.current_bb = &entry_bb;
        
        // Lower function body statements
        for (sirs_func.body.items) |*stmt| {
            try self.lowerStatement(stmt);
        }
        
        try cir_func.basic_blocks.append(entry_bb);
        self.current_function = null;
        self.current_bb = null;
    }
    
    fn lowerType(self: *CirLowering, sirs_type: SirsParser.Type) CirError!CirType {
        return switch (sirs_type) {
            .void => CirType.void,
            .bool => CirType.i1,
            .i8 => CirType.i8,
            .i16 => CirType.i16,
            .i32 => CirType.i32,
            .i64 => CirType.i64,
            .u8 => CirType.u8,
            .u16 => CirType.u16,
            .u32 => CirType.u32,
            .u64 => CirType.u64,
            .f32 => CirType.f32,
            .f64 => CirType.f64,
            .str => CirType{ .ptr = try self.createType(CirType.i8) },
            .array => |arr| {
                const elem_type = try self.createType(try self.lowerType(arr.element.*));
                return CirType{ .array = .{ .element = elem_type, .size = arr.size } };
            },
            .slice => |slice| {
                const elem_type = try self.createType(try self.lowerType(slice.element.*));
                return CirType{ .ptr = elem_type };
            },
            .optional => |opt| {
                // For now, treat optional as a simple pointer (null = 0)
                return CirType{ .ptr = try self.createType(try self.lowerType(opt.*)) };
            },
            else => {
                try self.error_reporter.reportError(null, "Unsupported type in CIR lowering", .{});
                return CirError.InvalidType;
            },
        };
    }
    
    fn createType(self: *CirLowering, cir_type: CirType) CirError!*CirType {
        const type_ptr = self.allocator.create(CirType) catch return CirError.OutOfMemory;
        type_ptr.* = cir_type;
        self.type_ptrs.append(type_ptr) catch return CirError.OutOfMemory;
        return type_ptr;
    }
    
    fn lowerStatement(self: *CirLowering, stmt: *SirsParser.Statement) CirError!void {
        switch (stmt.*) {
            .let => |*let_stmt| {
                const value = try self.lowerExpression(&let_stmt.value);
                try self.variable_map.put(let_stmt.name, value);
            },
            .assign => |*assign_stmt| {
                const value = try self.lowerExpression(&assign_stmt.value);
                const target = try self.lowerLValue(&assign_stmt.target);
                
                // Create store instruction
                var store_inst = CirInstruction.init(self.allocator, self.next_inst_id, .store);
                self.next_inst_id += 1;
                
                try store_inst.operands.append(target);
                try store_inst.operands.append(value);
                
                if (self.current_bb) |bb| {
                    try bb.instructions.append(store_inst);
                }
            },
            .@"return" => |*return_expr| {
                const value = try self.lowerExpression(return_expr);
                
                var ret_inst = CirInstruction.init(self.allocator, self.next_inst_id, .ret);
                self.next_inst_id += 1;
                
                try ret_inst.operands.append(value);
                
                if (self.current_bb) |bb| {
                    try bb.instructions.append(ret_inst);
                }
            },
            .@"if" => |*if_stmt| {
                return try self.lowerIfStatement(if_stmt);
            },
            .match => |*match_stmt| {
                return try self.lowerMatchStatement(match_stmt);
            },
            .@"try" => |*try_stmt| {
                return try self.lowerTryStatement(try_stmt);
            },
            .@"throw" => |*throw_expr| {
                // For now, treat throw as a simplified operation
                _ = try self.lowerExpression(throw_expr);
                
                // Create a simplified throw instruction (return error)
                var throw_inst = CirInstruction.init(self.allocator, self.next_inst_id, .ret);
                self.next_inst_id += 1;
                
                // For simplicity, just return a null value (error handling will be improved later)
                try throw_inst.operands.append(CirValue.null_const);
                
                if (self.current_bb) |bb| {
                    try bb.instructions.append(throw_inst);
                }
            },
            .expression => |*expr| {
                _ = try self.lowerExpression(expr);
            },
            else => {
                try self.error_reporter.reportError(null, "Unsupported statement in CIR lowering", .{});
                return CirError.UnsupportedOperation;
            },
        }
    }
    
    fn lowerExpression(self: *CirLowering, expr: *SirsParser.Expression) CirError!CirValue {
        return switch (expr.*) {
            .literal => |literal| {
                return switch (literal) {
                    .integer => |i| CirValue{ .int_const = .{ .value = i, .type = CirType.i32 } },
                    .float => |f| CirValue{ .float_const = .{ .value = f, .type = CirType.f64 } },
                    .string => |s| CirValue{ .string_const = s },
                    .boolean => |b| CirValue{ .bool_const = b },
                    .null => CirValue.null_const,
                };
            },
            .variable => |var_name| {
                return self.variable_map.get(var_name) orelse {
                    try self.error_reporter.reportError(null, "Undefined variable '{s}' in CIR lowering", .{var_name});
                    return CirError.UndefinedVariable;
                };
            },
            .op => |*op_expr| {
                return try self.lowerOperation(op_expr);
            },
            .call => |*call_expr| {
                return try self.lowerCall(call_expr);
            },
            .array => |*array_expr| {
                return try self.lowerArray(array_expr);
            },
            .index => |*index_expr| {
                return try self.lowerIndex(index_expr);
            },
            .field => |*field_expr| {
                return try self.lowerField(field_expr);
            },
            .@"struct" => |*struct_expr| {
                return try self.lowerStruct(struct_expr);
            },
            .enum_constructor => |*enum_expr| {
                return try self.lowerEnumConstructor(enum_expr);
            },
            .hashmap => |*hashmap_expr| {
                return try self.lowerHashMap(hashmap_expr);
            },
            .set => |*set_expr| {
                return try self.lowerSet(set_expr);
            },
            .tuple => |*tuple_expr| {
                return try self.lowerTuple(tuple_expr);
            },
            .record => |*record_expr| {
                return try self.lowerRecord(record_expr);
            },
            .@"await" => |await_expr| {
                // For await expressions, we simply lower the inner expression
                // In a full async implementation, this would handle async frames
                return try self.lowerExpression(await_expr);
            },
            else => {
                try self.error_reporter.reportError(null, "Unsupported expression type in CIR lowering", .{});
                return CirError.UnsupportedOperation;
            },
        };
    }
    
    fn lowerOperation(self: *CirLowering, op_expr: anytype) CirError!CirValue {
        const cir_op = switch (op_expr.kind) {
            .add => CirOp.add,
            .sub => CirOp.sub,
            .mul => CirOp.mul,
            .div => CirOp.div,
            .mod => CirOp.mod,
            .eq => CirOp.eq,
            .ne => CirOp.ne,
            .lt => CirOp.lt,
            .le => CirOp.le,
            .gt => CirOp.gt,
            .ge => CirOp.ge,
            .@"and" => CirOp.and_op,
            .@"or" => CirOp.or_op,
            .not => CirOp.not_op,
            else => {
                try self.error_reporter.reportError(null, "Unsupported operation in CIR lowering", .{});
                return CirError.UnsupportedOperation;
            },
        };
        
        // Create instruction for the operation
        var inst = CirInstruction.init(self.allocator, self.next_inst_id, cir_op);
        self.next_inst_id += 1;
        
        // Lower operands
        for (op_expr.args.items) |*arg| {
            const operand = try self.lowerExpression(arg);
            try inst.operands.append(operand);
        }
        
        // Create temporary for result
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        // Determine result type (simplified for now)
        inst.result_type = CirType.i32;
        
        if (self.current_bb) |bb| {
            try bb.instructions.append(inst);
        }
        
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType.i32 } };
    }
    
    fn lowerCall(self: *CirLowering, call_expr: anytype) CirError!CirValue {
        var call_inst = CirInstruction.init(self.allocator, self.next_inst_id, .call);
        self.next_inst_id += 1;
        
        // Add function reference
        try call_inst.operands.append(CirValue{ .function_ref = call_expr.function });
        
        // Add arguments
        for (call_expr.args.items) |*arg| {
            const operand = try self.lowerExpression(arg);
            try call_inst.operands.append(operand);
        }
        
        // Create temporary for result
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        call_inst.result_type = CirType.i32; // Simplified
        
        if (self.current_bb) |bb| {
            try bb.instructions.append(call_inst);
        }
        
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType.i32 } };
    }
    
    fn lowerLValue(self: *CirLowering, lvalue: *SirsParser.LValue) CirError!CirValue {
        return switch (lvalue.*) {
            .variable => |var_name| {
                return self.variable_map.get(var_name) orelse {
                    try self.error_reporter.reportError(null, "Undefined variable '{s}' in lvalue", .{var_name});
                    return CirError.UndefinedVariable;
                };
            },
            else => {
                try self.error_reporter.reportError(null, "Unsupported lvalue in CIR lowering", .{});
                return CirError.UnsupportedOperation;
            },
        };
    }
    
    fn lowerArray(self: *CirLowering, array_expr: anytype) CirError!CirValue {
        // For now, we'll create a simple array allocation and initialization
        // This is a simplified implementation - a full version would handle
        // different array types and proper memory management
        
        var alloca_inst = CirInstruction.init(self.allocator, self.next_inst_id, .alloca);
        self.next_inst_id += 1;
        
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        alloca_inst.result_type = CirType{ .ptr = try self.createType(CirType.i32) };
        
        if (self.current_bb) |bb| {
            try bb.instructions.append(alloca_inst);
        }
        
        // Store each element (simplified)
        for (array_expr.items, 0..) |*elem, i| {
            const elem_value = try self.lowerExpression(elem);
            
            var store_inst = CirInstruction.init(self.allocator, self.next_inst_id, .store);
            self.next_inst_id += 1;
            
            const index_value = CirValue{ .int_const = .{ .value = @intCast(i), .type = CirType.i32 } };
            try store_inst.operands.append(CirValue{ .temporary = .{ .id = temp_id, .type = CirType{ .ptr = try self.createType(CirType.i32) } } });
            try store_inst.operands.append(index_value);
            try store_inst.operands.append(elem_value);
            
            if (self.current_bb) |bb| {
                try bb.instructions.append(store_inst);
            }
        }
        
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType{ .ptr = try self.createType(CirType.i32) } } };
    }
    
    fn lowerIndex(self: *CirLowering, index_expr: anytype) CirError!CirValue {
        const array_value = try self.lowerExpression(index_expr.array);
        const index_value = try self.lowerExpression(index_expr.index);
        
        var load_inst = CirInstruction.init(self.allocator, self.next_inst_id, .load);
        self.next_inst_id += 1;
        
        try load_inst.operands.append(array_value);
        try load_inst.operands.append(index_value);
        
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        load_inst.result_type = CirType.i32; // Simplified
        
        if (self.current_bb) |bb| {
            try bb.instructions.append(load_inst);
        }
        
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType.i32 } };
    }
    
    fn lowerField(self: *CirLowering, field_expr: anytype) CirError!CirValue {
        const object_value = try self.lowerExpression(field_expr.object);
        
        // For now, treat field access as a simple offset load
        var load_inst = CirInstruction.init(self.allocator, self.next_inst_id, .load);
        self.next_inst_id += 1;
        
        try load_inst.operands.append(object_value);
        
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        load_inst.result_type = CirType.i32; // Simplified
        
        if (self.current_bb) |bb| {
            try bb.instructions.append(load_inst);
        }
        
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType.i32 } };
    }
    
    fn lowerStruct(self: *CirLowering, struct_expr: anytype) CirError!CirValue {
        // Allocate space for the struct
        var alloca_inst = CirInstruction.init(self.allocator, self.next_inst_id, .alloca);
        self.next_inst_id += 1;
        
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        alloca_inst.result_type = CirType{ .ptr = try self.createType(CirType.i32) }; // Simplified
        
        if (self.current_bb) |bb| {
            try bb.instructions.append(alloca_inst);
        }
        
        // Store each field (simplified)
        var field_iter = struct_expr.iterator();
        while (field_iter.next()) |entry| {
            const field_value = try self.lowerExpression(@constCast(entry.value_ptr));
            
            var store_inst = CirInstruction.init(self.allocator, self.next_inst_id, .store);
            self.next_inst_id += 1;
            
            try store_inst.operands.append(CirValue{ .temporary = .{ .id = temp_id, .type = CirType{ .ptr = try self.createType(CirType.i32) } } });
            try store_inst.operands.append(field_value);
            
            if (self.current_bb) |bb| {
                try bb.instructions.append(store_inst);
            }
        }
        
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType{ .ptr = try self.createType(CirType.i32) } } };
    }
    
    fn lowerEnumConstructor(self: *CirLowering, enum_expr: anytype) CirError!CirValue {
        // For now, we'll represent enums as simple integers with the variant index
        // In a full implementation, we'd handle associated values properly
        
        // Create a constant representing the enum variant
        // This is simplified - a real implementation would:
        // 1. Look up the variant index in the enum definition
        // 2. Handle associated values properly
        // 3. Generate appropriate tagged union representation
        
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        // For now, just return a constant representing the enum variant
        // In practice, this would be more sophisticated
        _ = enum_expr.enum_type; // Will be used for proper enum handling
        _ = enum_expr.variant;   // Will be used for variant lookup
        
        if (enum_expr.value) |value_expr| {
            // If there's an associated value, lower it
            _ = try self.lowerExpression(value_expr);
        }
        
        // Return a simplified enum representation as integer
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType.i32 } };
    }
    
    fn lowerHashMap(self: *CirLowering, hashmap_expr: anytype) CirError!CirValue {
        // For now, create a simplified hashmap representation
        // In a full implementation, this would create proper hashmap allocation and initialization
        
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        // Allocate space for the hashmap
        var alloca_inst = CirInstruction.init(self.allocator, self.next_inst_id, .alloca);
        self.next_inst_id += 1;
        
        alloca_inst.result_type = CirType{ .ptr = try self.createType(CirType.i32) }; // Simplified
        
        if (self.current_bb) |bb| {
            try bb.instructions.append(alloca_inst);
        }
        
        // Initialize map entries (simplified)
        var map_iter = hashmap_expr.iterator();
        while (map_iter.next()) |entry| {
            _ = try self.lowerExpression(@constCast(entry.value_ptr));
            // In a full implementation, we'd generate map insertion instructions
        }
        
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType{ .ptr = try self.createType(CirType.i32) } } };
    }
    
    fn lowerSet(self: *CirLowering, set_expr: anytype) CirError!CirValue {
        // For now, create a simplified set representation
        // In a full implementation, this would create proper set allocation and initialization
        
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        // Allocate space for the set
        var alloca_inst = CirInstruction.init(self.allocator, self.next_inst_id, .alloca);
        self.next_inst_id += 1;
        
        alloca_inst.result_type = CirType{ .ptr = try self.createType(CirType.i32) }; // Simplified
        
        if (self.current_bb) |bb| {
            try bb.instructions.append(alloca_inst);
        }
        
        // Initialize set elements (simplified)
        for (set_expr.items) |*elem| {
            _ = try self.lowerExpression(elem);
            // In a full implementation, we'd generate set insertion instructions
        }
        
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType{ .ptr = try self.createType(CirType.i32) } } };
    }
    
    fn lowerMatchStatement(self: *CirLowering, match_stmt: anytype) CirError!void {
        // Lower the value being matched
        const match_value = try self.lowerExpression(&match_stmt.value);
        
        // Create basic blocks for each case and a final continuation block
        const current_func = self.current_function orelse return CirError.UndefinedFunction;
        
        var case_blocks = std.ArrayList(*CirBasicBlock).init(self.allocator);
        defer case_blocks.deinit();
        
        var next_blocks = std.ArrayList(*CirBasicBlock).init(self.allocator);
        defer next_blocks.deinit();
        
        // Create continuation block (where control flow merges after match)
        const cont_label = try std.fmt.allocPrint(self.allocator, "match_cont_{d}", .{self.next_bb_id});
        self.next_bb_id += 1;
        const cont_bb = CirBasicBlock.init(self.allocator, cont_label);
        
        // Create blocks for each match case
        for (match_stmt.cases.items, 0..) |_, i| {
            // Case block: where the case body executes
            const case_label = try std.fmt.allocPrint(self.allocator, "match_case_{d}_{d}", .{ self.next_bb_id, i });
            self.next_bb_id += 1;
            const case_bb_ptr = try self.allocator.create(CirBasicBlock);
            case_bb_ptr.* = CirBasicBlock.init(self.allocator, case_label);
            
            // Next block: where control goes if this case doesn't match
            const next_label = try std.fmt.allocPrint(self.allocator, "match_next_{d}_{d}", .{ self.next_bb_id, i });
            self.next_bb_id += 1;
            const next_bb_ptr = try self.allocator.create(CirBasicBlock);
            next_bb_ptr.* = CirBasicBlock.init(self.allocator, next_label);
            
            try case_blocks.append(case_bb_ptr);
            try next_blocks.append(next_bb_ptr);
        }
        
        // Generate pattern matching logic
        for (match_stmt.cases.items, 0..) |*case, i| {
            // Switch to the appropriate next block for pattern checking
            if (i > 0) {
                self.current_bb = next_blocks.items[i - 1];
            }
            
            // Generate pattern matching condition
            const pattern_matches = try self.lowerPattern(&case.pattern, match_value);
            
            // Create conditional branch based on pattern match
            var branch_inst = CirInstruction.init(self.allocator, self.next_inst_id, .conditional_branch);
            self.next_inst_id += 1;
            
            try branch_inst.operands.append(pattern_matches);
            // Note: In a real implementation, we'd specify the target blocks here
            
            if (self.current_bb) |bb| {
                try bb.instructions.append(branch_inst);
            }
            
            // Generate case body in case block
            self.current_bb = case_blocks.items[i];
            
            // For now, we'll use a simplified approach without variable cloning
            // In a full implementation, we'd implement proper scoping
            
            // Bind pattern variables (simplified)
            try self.bindPatternVariables(&case.pattern, match_value);
            
            // Lower case body statements
            for (case.body.items) |*stmt| {
                try self.lowerStatement(stmt);
            }
            
            // Branch to continuation block
            const jump_inst = CirInstruction.init(self.allocator, self.next_inst_id, .branch);
            self.next_inst_id += 1;
            
            if (self.current_bb) |bb| {
                try bb.instructions.append(jump_inst);
            }
        }
        
        // Add all created blocks to the function
        for (case_blocks.items) |case_bb| {
            try current_func.basic_blocks.append(case_bb.*);
            self.allocator.destroy(case_bb);
        }
        for (next_blocks.items) |next_bb| {
            try current_func.basic_blocks.append(next_bb.*);
            self.allocator.destroy(next_bb);
        }
        try current_func.basic_blocks.append(cont_bb);
        
        // Set current block to continuation
        self.current_bb = &current_func.basic_blocks.items[current_func.basic_blocks.items.len - 1];
    }
    
    fn lowerTryStatement(self: *CirLowering, try_stmt: anytype) CirError!void {
        // For now, implement a simplified try-catch by just executing the try body
        // In a full implementation, this would create proper exception handling blocks
        
        // Lower try body statements
        for (try_stmt.body.items) |*stmt| {
            try self.lowerStatement(stmt);
        }
        
        // For simplicity, skip catch and finally blocks in CIR for now
        // A full implementation would create exception handling basic blocks
        _ = try_stmt.catch_clauses;
        _ = try_stmt.finally_body;
    }
    
    fn lowerIfStatement(self: *CirLowering, if_stmt: anytype) CirError!void {
        // For now, implement a simplified if statement by just executing the then branch
        // In a full implementation, this would create proper conditional branching
        
        // Lower the condition (but don't use it for now)
        _ = try self.lowerExpression(&if_stmt.condition);
        
        // Lower then branch statements
        for (if_stmt.then.items) |*stmt| {
            try self.lowerStatement(stmt);
        }
        
        // For simplicity, skip else branch in CIR for now
        _ = if_stmt.@"else";
    }
    
    fn lowerPattern(self: *CirLowering, pattern: *SirsParser.Pattern, match_value: CirValue) CirError!CirValue {
        return switch (pattern.*) {
            .literal => |literal| {
                // Generate comparison with literal value
                const pattern_value = switch (literal) {
                    .integer => |i| CirValue{ .int_const = .{ .value = i, .type = CirType.i32 } },
                    .float => |f| CirValue{ .float_const = .{ .value = f, .type = CirType.f64 } },
                    .string => |s| CirValue{ .string_const = s },
                    .boolean => |b| CirValue{ .bool_const = b },
                    .null => CirValue.null_const,
                };
                
                // Create equality comparison
                var eq_inst = CirInstruction.init(self.allocator, self.next_inst_id, .eq);
                self.next_inst_id += 1;
                
                try eq_inst.operands.append(match_value);
                try eq_inst.operands.append(pattern_value);
                
                const temp_id = self.next_temp_id;
                self.next_temp_id += 1;
                
                eq_inst.result_type = CirType.i1;
                
                if (self.current_bb) |bb| {
                    try bb.instructions.append(eq_inst);
                }
                
                return CirValue{ .temporary = .{ .id = temp_id, .type = CirType.i1 } };
            },
            
            .variable => |_| {
                // Variable patterns always match - return true
                return CirValue{ .bool_const = true };
            },
            
            .wildcard => {
                // Wildcard patterns always match - return true
                return CirValue{ .bool_const = true };
            },
            
            .@"struct" => |_| {
                // Simplified struct pattern matching - for now just return true
                // In a full implementation, this would check individual fields
                return CirValue{ .bool_const = true };
            },
            
            .@"enum" => |_| {
                // Simplified enum pattern matching - for now just return true
                // In a full implementation, this would check enum tag and associated values
                return CirValue{ .bool_const = true };
            },
        };
    }
    
    fn bindPatternVariables(self: *CirLowering, pattern: *SirsParser.Pattern, match_value: CirValue) CirError!void {
        switch (pattern.*) {
            .variable => |var_name| {
                // Bind the variable to the matched value
                try self.variable_map.put(var_name, match_value);
            },
            .@"struct" => |*struct_patterns| {
                // For struct patterns, we'd extract each field and bind sub-patterns
                // This is simplified - a full implementation would handle field extraction
                var iter = struct_patterns.iterator();
                while (iter.next()) |entry| {
                    const field_pattern = entry.value_ptr;
                    try self.bindPatternVariables(field_pattern, match_value); // Simplified
                }
            },
            .@"enum" => |*enum_pattern| {
                // For enum patterns, bind any value patterns
                if (enum_pattern.value_pattern) |value_pattern| {
                    // In a full implementation, we'd extract the associated value
                    try self.bindPatternVariables(value_pattern, match_value); // Simplified
                }
            },
            .literal, .wildcard => {
                // These patterns don't bind variables
            },
        }
    }
    
    fn lowerTuple(self: *CirLowering, tuple_expr: anytype) CirError!CirValue {
        // For now, return a simplified representation
        // In a full implementation, this would allocate space for the tuple and 
        // initialize each element
        _ = tuple_expr;
        
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        // Return a simplified temporary value
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType.i32 } };
    }
    
    fn lowerRecord(self: *CirLowering, record_expr: anytype) CirError!CirValue {
        // For now, return a simplified representation
        // In a full implementation, this would allocate space for the record and
        // initialize each field
        _ = record_expr;
        
        const temp_id = self.next_temp_id;
        self.next_temp_id += 1;
        
        // Return a simplified temporary value
        return CirValue{ .temporary = .{ .id = temp_id, .type = CirType.i32 } };
    }
};