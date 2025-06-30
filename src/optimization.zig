const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const cir = @import("cir.zig");
const CirModule = cir.CirModule;
const CirFunction = cir.CirFunction;
const CirBasicBlock = cir.CirBasicBlock;
const CirInstruction = cir.CirInstruction;
const CirValue = cir.CirValue;
const CirOp = cir.CirOp;

/// Optimization error types
pub const OptError = error{
    OutOfMemory,
    InvalidFunction,
};

/// Dead Code Elimination optimization pass
/// Removes instructions that produce values that are never used
/// and eliminates unreachable basic blocks
pub const DeadCodeElimination = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) DeadCodeElimination {
        return DeadCodeElimination{
            .allocator = allocator,
        };
    }
    
    /// Run dead code elimination on a CIR module
    pub fn optimize(self: *DeadCodeElimination, module: *CirModule) OptError!void {
        var func_iter = module.functions.iterator();
        while (func_iter.next()) |entry| {
            const function = entry.value_ptr;
            try self.optimizeFunction(function);
        }
    }
    
    /// Run dead code elimination on a single function
    fn optimizeFunction(self: *DeadCodeElimination, function: *CirFunction) OptError!void {
        // Step 1: Remove unreachable basic blocks
        try self.removeUnreachableBlocks(function);
        
        // Step 2: Perform dead instruction elimination
        try self.eliminateDeadInstructions(function);
    }
    
    /// Remove basic blocks that are unreachable from the entry block
    fn removeUnreachableBlocks(self: *DeadCodeElimination, function: *CirFunction) OptError!void {
        if (function.basic_blocks.items.len == 0) return;
        
        // Mark reachable blocks using DFS from entry block
        var reachable = StringHashMap(bool).init(self.allocator);
        defer reachable.deinit();
        
        var worklist = ArrayList([]const u8).init(self.allocator);
        defer worklist.deinit();
        
        // Start from entry block (first block)
        const entry_label = function.basic_blocks.items[0].label;
        try reachable.put(entry_label, true);
        try worklist.append(entry_label);
        
        // DFS to find all reachable blocks
        while (worklist.items.len > 0) {
            const current_label = worklist.pop() orelse break;
            
            // Find the basic block with this label
            for (function.basic_blocks.items) |*bb| {
                if (std.mem.eql(u8, bb.label, current_label)) {
                    // Mark all successor blocks as reachable
                    for (bb.successors.items) |successor_label| {
                        if (!reachable.contains(successor_label)) {
                            try reachable.put(successor_label, true);
                            try worklist.append(successor_label);
                        }
                    }
                    break;
                }
            }
        }
        
        // Remove unreachable blocks
        var i: usize = 0;
        while (i < function.basic_blocks.items.len) {
            const bb_label = function.basic_blocks.items[i].label;
            if (!reachable.contains(bb_label)) {
                // This block is unreachable, remove it
                var removed_bb = function.basic_blocks.swapRemove(i);
                removed_bb.deinit();
            } else {
                i += 1;
            }
        }
    }
    
    /// Eliminate dead instructions (instructions whose results are never used)
    fn eliminateDeadInstructions(self: *DeadCodeElimination, function: *CirFunction) OptError!void {
        var changed = true;
        
        // Iterate until no more changes (fixpoint)
        while (changed) {
            changed = false;
            
            // Track which temporaries are used
            var used_temps = AutoHashMap(u32, bool).init(self.allocator);
            defer used_temps.deinit();
            
            // First pass: mark all used temporaries
            for (function.basic_blocks.items) |*bb| {
                for (bb.instructions.items) |*inst| {
                    // Mark all operand temporaries as used
                    for (inst.operands.items) |operand| {
                        switch (operand) {
                            .temporary => |temp| {
                                try used_temps.put(temp.id, true);
                            },
                            else => {},
                        }
                    }
                    
                    // Special handling for control flow instructions - they're always live
                    switch (inst.op) {
                        .ret, .branch, .conditional_branch, .call => {
                            // These instructions have side effects and must be kept
                            // Mark any temporary they produce as used
                            if (inst.result_type != null) {
                                // This instruction produces a result, find its temp ID
                                // We'll need to infer this from context or track it better
                                // For now, we'll be conservative and not remove call instructions
                            }
                        },
                        else => {},
                    }
                }
            }
            
            // Second pass: remove instructions that produce unused temporaries
            for (function.basic_blocks.items) |*bb| {
                var i: usize = 0;
                while (i < bb.instructions.items.len) {
                    const inst = &bb.instructions.items[i];
                    var should_remove = false;
                    
                    // Check if this instruction can be removed
                    switch (inst.op) {
                        // Never remove control flow or side-effect instructions
                        .ret, .branch, .conditional_branch, .call, .store => {
                            // These have side effects, always keep
                        },
                        
                        // Pure instructions that might be removable
                        .add, .sub, .mul, .div, .mod,
                        .eq, .ne, .lt, .le, .gt, .ge,
                        .and_op, .or_op, .not_op,
                        .bit_and, .bit_or, .bit_xor, .bit_not,
                        .shl, .shr,
                        .load, .alloca,
                        .bitcast, .trunc, .extend, .int_to_float, .float_to_int,
                        .phi, .undef => {
                            // Check if the result of this instruction is used
                            if (inst.result_type != null) {
                                // This instruction produces a result
                                // We need to check if this result temp is used
                                // For now, we'll use a heuristic: if it's a pure operation
                                // and we haven't seen its result temp ID in the used set,
                                // we can potentially remove it
                                
                                // This is simplified - in a real implementation we'd track
                                // the mapping between instructions and their result temporaries
                                // more precisely
                                should_remove = self.isInstructionDead(inst, &used_temps);
                            }
                        },
                    }
                    
                    if (should_remove) {
                        var removed_inst = bb.instructions.swapRemove(i);
                        removed_inst.deinit();
                        changed = true;
                    } else {
                        i += 1;
                    }
                }
            }
        }
    }
    
    /// Check if an instruction is dead (its result is never used)
    /// This is a simplified heuristic for now
    fn isInstructionDead(self: *DeadCodeElimination, inst: *CirInstruction, used_temps: *AutoHashMap(u32, bool)) bool {
        _ = self;
        _ = inst;
        _ = used_temps;
        
        // For now, be conservative and don't remove instructions
        // A more sophisticated implementation would:
        // 1. Track the exact mapping between instructions and result temporaries
        // 2. Build a proper def-use chain
        // 3. More accurately determine which instructions are dead
        
        return false;
    }
};

/// Constant folding and propagation optimization pass
/// Evaluates constant expressions at compile time and propagates known constant values
pub const ConstantFolding = struct {
    allocator: Allocator,
    constant_values: AutoHashMap(u32, CirValue), // Maps temporary IDs to their constant values
    
    pub fn init(allocator: Allocator) ConstantFolding {
        return ConstantFolding{
            .allocator = allocator,
            .constant_values = AutoHashMap(u32, CirValue).init(allocator),
        };
    }
    
    pub fn deinit(self: *ConstantFolding) void {
        self.constant_values.deinit();
    }
    
    /// Run constant folding on a CIR module
    pub fn optimize(self: *ConstantFolding, module: *CirModule) OptError!void {
        var func_iter = module.functions.iterator();
        while (func_iter.next()) |entry| {
            const function = entry.value_ptr;
            try self.optimizeFunction(function);
        }
    }
    
    /// Run constant folding on a single function
    fn optimizeFunction(self: *ConstantFolding, function: *CirFunction) OptError!void {
        // Clear constant values for each function
        self.constant_values.clearRetainingCapacity();
        
        // Iterate until no more changes (fixpoint for constant propagation)
        var changed = true;
        while (changed) {
            changed = false;
            
            for (function.basic_blocks.items) |*bb| {
                for (bb.instructions.items) |*inst| {
                    const inst_changed = try self.foldInstruction(inst);
                    if (inst_changed) {
                        changed = true;
                    }
                }
            }
        }
    }
    
    /// Attempt to fold a single instruction if all operands are constants
    /// Returns true if the instruction was modified
    fn foldInstruction(self: *ConstantFolding, inst: *CirInstruction) OptError!bool {
        // First, try to propagate constants into operands
        var operands_changed = false;
        for (inst.operands.items, 0..) |*operand, i| {
            switch (operand.*) {
                .temporary => |temp| {
                    if (self.constant_values.get(temp.id)) |constant_value| {
                        // Replace temporary with its constant value
                        inst.operands.items[i] = constant_value;
                        operands_changed = true;
                    }
                },
                else => {},
            }
        }
        
        // Check if all operands are now constants
        var all_constants = true;
        var constants = ArrayList(CirValue).init(self.allocator);
        defer constants.deinit();
        
        for (inst.operands.items) |operand| {
            switch (operand) {
                .int_const, .float_const, .bool_const, .string_const, .null_const => {
                    try constants.append(operand);
                },
                else => {
                    all_constants = false;
                    break;
                },
            }
        }
        
        if (!all_constants or constants.items.len < 1) {
            return operands_changed; // Can't fold this instruction further
        }
        
        // Attempt to fold based on operation type
        var folded_result: ?CirValue = null;
        
        switch (inst.op) {
            .add => {
                if (constants.items.len == 2 and 
                    constants.items[0] == .int_const and 
                    constants.items[1] == .int_const) {
                    
                    const a = constants.items[0].int_const.value;
                    const b = constants.items[1].int_const.value;
                    const result = a + b;
                    
                    folded_result = CirValue{ .int_const = .{ .value = result, .type = constants.items[0].int_const.type } };
                }
            },
            
            .sub => {
                if (constants.items.len == 2 and 
                    constants.items[0] == .int_const and 
                    constants.items[1] == .int_const) {
                    
                    const a = constants.items[0].int_const.value;
                    const b = constants.items[1].int_const.value;
                    const result = a - b;
                    
                    folded_result = CirValue{ .int_const = .{ .value = result, .type = constants.items[0].int_const.type } };
                }
            },
            
            .mul => {
                if (constants.items.len == 2 and 
                    constants.items[0] == .int_const and 
                    constants.items[1] == .int_const) {
                    
                    const a = constants.items[0].int_const.value;
                    const b = constants.items[1].int_const.value;
                    const result = a * b;
                    
                    folded_result = CirValue{ .int_const = .{ .value = result, .type = constants.items[0].int_const.type } };
                }
            },
            
            .div => {
                if (constants.items.len == 2 and 
                    constants.items[0] == .int_const and 
                    constants.items[1] == .int_const and
                    constants.items[1].int_const.value != 0) {
                    
                    const a = constants.items[0].int_const.value;
                    const b = constants.items[1].int_const.value;
                    const result = @divTrunc(a, b);
                    
                    folded_result = CirValue{ .int_const = .{ .value = result, .type = constants.items[0].int_const.type } };
                }
            },
            
            .eq => {
                if (constants.items.len == 2 and 
                    constants.items[0] == .int_const and 
                    constants.items[1] == .int_const) {
                    
                    const a = constants.items[0].int_const.value;
                    const b = constants.items[1].int_const.value;
                    const result = a == b;
                    
                    folded_result = CirValue{ .bool_const = result };
                }
            },
            
            .ne => {
                if (constants.items.len == 2 and 
                    constants.items[0] == .int_const and 
                    constants.items[1] == .int_const) {
                    
                    const a = constants.items[0].int_const.value;
                    const b = constants.items[1].int_const.value;
                    const result = a != b;
                    
                    folded_result = CirValue{ .bool_const = result };
                }
            },
            
            .lt => {
                if (constants.items.len == 2 and 
                    constants.items[0] == .int_const and 
                    constants.items[1] == .int_const) {
                    
                    const a = constants.items[0].int_const.value;
                    const b = constants.items[1].int_const.value;
                    const result = a < b;
                    
                    folded_result = CirValue{ .bool_const = result };
                }
            },
            
            .and_op => {
                if (constants.items.len == 2 and 
                    constants.items[0] == .bool_const and 
                    constants.items[1] == .bool_const) {
                    
                    const a = constants.items[0].bool_const;
                    const b = constants.items[1].bool_const;
                    const result = a and b;
                    
                    folded_result = CirValue{ .bool_const = result };
                }
            },
            
            .or_op => {
                if (constants.items.len == 2 and 
                    constants.items[0] == .bool_const and 
                    constants.items[1] == .bool_const) {
                    
                    const a = constants.items[0].bool_const;
                    const b = constants.items[1].bool_const;
                    const result = a or b;
                    
                    folded_result = CirValue{ .bool_const = result };
                }
            },
            
            .not_op => {
                if (constants.items.len == 1 and 
                    constants.items[0] == .bool_const) {
                    
                    const a = constants.items[0].bool_const;
                    const result = !a;
                    
                    folded_result = CirValue{ .bool_const = result };
                }
            },
            
            else => {
                // Operation not foldable or not implemented yet
            },
        }
        
        // If we were able to fold the instruction, update it
        if (folded_result) |result| {
            // Replace instruction operands with the folded result
            inst.operands.clearRetainingCapacity();
            try inst.operands.append(result);
            inst.op = .undef; // Mark as a constant load (simplified)
            
            // Track this as a constant for future propagation
            // Note: In a real implementation, we'd need to track which temporary
            // this instruction produces and map it to the constant value
            // For now, this is simplified
            
            return true; // Instruction was changed
        }
        
        return operands_changed;
    }
};

/// Function inlining optimization pass
/// Replaces function calls with the function body when beneficial
pub const FunctionInlining = struct {
    allocator: Allocator,
    inlined_count: u32,
    
    pub fn init(allocator: Allocator) FunctionInlining {
        return FunctionInlining{
            .allocator = allocator,
            .inlined_count = 0,
        };
    }
    
    /// Run function inlining on a CIR module
    pub fn optimize(self: *FunctionInlining, module: *CirModule) OptError!void {
        self.inlined_count = 0;
        
        // Step 1: Analyze all functions to determine inlining candidates
        var inline_candidates = ArrayList([]const u8).init(self.allocator);
        defer inline_candidates.deinit();
        
        var func_iter = module.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            
            if (self.shouldInlineFunction(function)) {
                try inline_candidates.append(func_name);
            }
        }
        
        // Step 2: For each function, attempt to inline candidate calls
        func_iter = module.functions.iterator();
        while (func_iter.next()) |entry| {
            const function = entry.value_ptr;
            try self.inlineFunctionCalls(function, module, &inline_candidates);
        }
        
        // Step 3: Remove fully inlined functions if they're no longer needed
        // (This is simplified - in a real implementation we'd do call graph analysis)
        for (inline_candidates.items) |candidate_name| {
            if (self.canRemoveFunction(candidate_name, module)) {
                _ = module.functions.remove(candidate_name);
            }
        }
    }
    
    /// Determine if a function should be inlined based on heuristics
    fn shouldInlineFunction(self: *FunctionInlining, function: *CirFunction) bool {
        _ = self;
        
        // Heuristics for inlining:
        // 1. Small functions (few basic blocks and instructions)
        // 2. Functions with few parameters
        // 3. Non-recursive functions
        // 4. Functions called only a few times
        
        // Simple heuristic: inline if function is small
        if (function.basic_blocks.items.len > 3) return false; // Too many blocks
        if (function.params.items.len > 4) return false; // Too many parameters
        if (function.is_external) return false; // Can't inline external functions
        
        // Count total instructions
        var total_instructions: u32 = 0;
        for (function.basic_blocks.items) |*bb| {
            total_instructions += @intCast(bb.instructions.items.len);
        }
        
        // Inline if small enough (threshold: 10 instructions)
        return total_instructions <= 10;
    }
    
    /// Inline function calls within a function
    fn inlineFunctionCalls(self: *FunctionInlining, caller: *CirFunction, module: *CirModule, candidates: *ArrayList([]const u8)) OptError!void {
        for (caller.basic_blocks.items) |*bb| {
            var inst_index: usize = 0;
            while (inst_index < bb.instructions.items.len) {
                const inst = &bb.instructions.items[inst_index];
                
                if (inst.op == .call and inst.operands.items.len > 0) {
                    // Check if this is a call to an inlinable function
                    switch (inst.operands.items[0]) {
                        .function_ref => |func_name| {
                            if (self.isInlineCandidate(func_name, candidates)) {
                                // Attempt to inline this call
                                if (self.inlineCall(bb, inst_index, func_name, module)) |_| {
                                    self.inlined_count += 1;
                                    // Don't increment inst_index since we modified the instruction list
                                    continue;
                                } else |_| {
                                    // Inlining failed, continue with next instruction
                                }
                            }
                        },
                        else => {},
                    }
                }
                inst_index += 1;
            }
        }
    }
    
    /// Check if a function name is in the inline candidates list
    fn isInlineCandidate(self: *FunctionInlining, func_name: []const u8, candidates: *ArrayList([]const u8)) bool {
        _ = self;
        
        for (candidates.items) |candidate| {
            if (std.mem.eql(u8, func_name, candidate)) {
                return true;
            }
        }
        return false;
    }
    
    /// Inline a specific function call
    fn inlineCall(self: *FunctionInlining, bb: *CirBasicBlock, call_index: usize, func_name: []const u8, module: *CirModule) OptError!void {
        const callee = module.functions.get(func_name) orelse return OptError.InvalidFunction;
        
        // For now, implement a simplified inlining for single-block functions
        if (callee.basic_blocks.items.len != 1) {
            return OptError.InvalidFunction; // Only inline simple functions for now
        }
        
        const callee_block = &callee.basic_blocks.items[0];
        
        // Create variable renaming map to avoid conflicts
        var var_rename_map = StringHashMap(u32).init(self.allocator);
        defer var_rename_map.deinit();
        
        var next_temp_id: u32 = 1000; // Start with high numbers to avoid conflicts
        
        // Remove the call instruction
        var removed_call = bb.instructions.swapRemove(call_index);
        removed_call.deinit();
        
        // Insert the callee's instructions at the call site
        for (callee_block.instructions.items) |*callee_inst| {
            if (callee_inst.op == .ret) {
                // Handle return instruction - don't copy it, just handle the return value
                continue;
            }
            
            // Clone and rename the instruction
            const new_inst = try self.cloneAndRenameInstruction(callee_inst, &var_rename_map, &next_temp_id);
            try bb.instructions.insert(call_index, new_inst);
        }
    }
    
    /// Clone an instruction and rename variables to avoid conflicts
    fn cloneAndRenameInstruction(self: *FunctionInlining, inst: *CirInstruction, rename_map: *StringHashMap(u32), next_temp_id: *u32) OptError!CirInstruction {
        var new_inst = CirInstruction.init(self.allocator, inst.id, inst.op);
        new_inst.result_type = inst.result_type;
        
        // Clone and rename operands
        for (inst.operands.items) |operand| {
            const renamed_operand = try self.renameOperand(operand, rename_map, next_temp_id);
            try new_inst.operands.append(renamed_operand);
        }
        
        return new_inst;
    }
    
    /// Rename an operand to avoid variable conflicts
    fn renameOperand(self: *FunctionInlining, operand: CirValue, rename_map: *StringHashMap(u32), next_temp_id: *u32) OptError!CirValue {
        _ = self;
        
        return switch (operand) {
            .temporary => |temp| {
                // Create a new temporary ID to avoid conflicts
                const new_id = next_temp_id.*;
                next_temp_id.* += 1;
                return CirValue{ .temporary = .{ .id = new_id, .type = temp.type } };
            },
            .variable => |var_info| {
                // Look up or create renamed variable
                const existing_rename = rename_map.get(var_info.name);
                const new_id = existing_rename orelse blk: {
                    const id = next_temp_id.*;
                    next_temp_id.* += 1;
                    try rename_map.put(var_info.name, id);
                    break :blk id;
                };
                
                return CirValue{ .temporary = .{ .id = new_id, .type = var_info.type } };
            },
            else => operand, // Constants and other values don't need renaming
        };
    }
    
    /// Check if a function can be removed after inlining
    fn canRemoveFunction(self: *FunctionInlining, func_name: []const u8, module: *CirModule) bool {
        _ = self;
        
        // Simple check: if it's not the entry point and not external, it can be removed
        // In a real implementation, we'd do proper call graph analysis
        
        // Don't remove external functions
        const function = module.functions.get(func_name) orelse return false;
        if (function.is_external) return false;
        
        // Don't remove functions with many basic blocks (they might have complex control flow)
        if (function.basic_blocks.items.len > 1) return false;
        
        // For now, be conservative and don't remove functions
        // A full implementation would track call sites and usage
        return false;
    }
};

/// Optimization manager that coordinates multiple optimization passes
pub const OptimizationManager = struct {
    allocator: Allocator,
    dead_code_elimination: DeadCodeElimination,
    constant_folding: ConstantFolding,
    function_inlining: FunctionInlining,
    
    pub fn init(allocator: Allocator) OptimizationManager {
        return OptimizationManager{
            .allocator = allocator,
            .dead_code_elimination = DeadCodeElimination.init(allocator),
            .constant_folding = ConstantFolding.init(allocator),
            .function_inlining = FunctionInlining.init(allocator),
        };
    }
    
    pub fn deinit(self: *OptimizationManager) void {
        self.constant_folding.deinit();
    }
    
    /// Run all enabled optimizations on a CIR module
    pub fn optimize(self: *OptimizationManager, module: *CirModule) OptError!void {
        // Run optimizations in a beneficial order
        // 1. Constant folding first (creates more optimization opportunities)
        try self.constant_folding.optimize(module);
        
        // 2. Dead code elimination (removes code made dead by constant folding)
        try self.dead_code_elimination.optimize(module);
        
        // 3. Function inlining (would run last as it can create more optimization opportunities)
        try self.function_inlining.optimize(module);
        
        // Could run another round of DCE after inlining
        try self.dead_code_elimination.optimize(module);
    }
};