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

/// Types of dependencies that can be analyzed
pub const DependencyType = enum {
    function_call,
    type_usage,
    variable_reference,
    module_import,
    interface_implementation,
};

/// Information about a single dependency
pub const Dependency = struct {
    source: []const u8,      // What depends on the target
    target: []const u8,      // What is being depended upon
    dependency_type: DependencyType,
    location: SourceLocation,
    metadata: ?[]const u8,   // Additional context information
    
    pub fn deinit(self: *Dependency, allocator: Allocator) void {
        allocator.free(self.source);
        allocator.free(self.target);
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
    context: []const u8,
};

/// Dependency graph node
pub const DependencyNode = struct {
    name: []const u8,
    dependencies: ArrayList([]const u8),      // What this node depends on
    dependents: ArrayList([]const u8),        // What depends on this node
    node_type: NodeType,
    metadata: StringHashMap([]const u8),
    
    pub const NodeType = enum {
        function,
        type_definition,
        constant,
        variable,
        module,
        interface,
    };
    
    pub fn init(allocator: Allocator, name: []const u8, node_type: NodeType) DependencyNode {
        return DependencyNode{
            .name = name,
            .dependencies = ArrayList([]const u8).init(allocator),
            .dependents = ArrayList([]const u8).init(allocator),
            .node_type = node_type,
            .metadata = StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *DependencyNode, allocator: Allocator) void {
        allocator.free(self.name);
        self.dependencies.deinit();
        self.dependents.deinit();
        
        var meta_iter = self.metadata.iterator();
        while (meta_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.metadata.deinit();
    }
};

/// Dependency analysis results
pub const DependencyAnalysis = struct {
    dependencies: ArrayList(Dependency),
    dependency_graph: StringHashMap(DependencyNode),
    circular_dependencies: ArrayList(ArrayList([]const u8)),
    unused_functions: ArrayList([]const u8),
    entry_point_reachable: ArrayList([]const u8),
    complexity_metrics: ComplexityMetrics,
    
    pub const ComplexityMetrics = struct {
        total_nodes: u32,
        total_edges: u32,
        max_depth: u32,
        cyclomatic_complexity: u32,
        coupling_factor: f64,
    };
    
    pub fn init(allocator: Allocator) DependencyAnalysis {
        return DependencyAnalysis{
            .dependencies = ArrayList(Dependency).init(allocator),
            .dependency_graph = StringHashMap(DependencyNode).init(allocator),
            .circular_dependencies = ArrayList(ArrayList([]const u8)).init(allocator),
            .unused_functions = ArrayList([]const u8).init(allocator),
            .entry_point_reachable = ArrayList([]const u8).init(allocator),
            .complexity_metrics = ComplexityMetrics{
                .total_nodes = 0,
                .total_edges = 0,
                .max_depth = 0,
                .cyclomatic_complexity = 0,
                .coupling_factor = 0.0,
            },
        };
    }
    
    pub fn deinit(self: *DependencyAnalysis, allocator: Allocator) void {
        // Free dependencies
        for (self.dependencies.items) |*dep| {
            dep.deinit(allocator);
        }
        self.dependencies.deinit();
        
        // Free dependency graph
        var graph_iter = self.dependency_graph.iterator();
        while (graph_iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.dependency_graph.deinit();
        
        // Free circular dependencies
        for (self.circular_dependencies.items) |*cycle| {
            for (cycle.items) |name| {
                allocator.free(name);
            }
            cycle.deinit();
        }
        self.circular_dependencies.deinit();
        
        // Free unused functions
        for (self.unused_functions.items) |name| {
            allocator.free(name);
        }
        self.unused_functions.deinit();
        
        // Free reachable functions
        for (self.entry_point_reachable.items) |name| {
            allocator.free(name);
        }
        self.entry_point_reachable.deinit();
    }
};

/// Main dependency analyzer
pub const DependencyAnalyzer = struct {
    allocator: Allocator,
    current_function: ?[]const u8,
    function_calls: StringHashMap(ArrayList([]const u8)),
    type_usages: StringHashMap(ArrayList([]const u8)),
    variable_references: StringHashMap(ArrayList([]const u8)),
    
    pub fn init(allocator: Allocator) DependencyAnalyzer {
        return DependencyAnalyzer{
            .allocator = allocator,
            .current_function = null,
            .function_calls = StringHashMap(ArrayList([]const u8)).init(allocator),
            .type_usages = StringHashMap(ArrayList([]const u8)).init(allocator),
            .variable_references = StringHashMap(ArrayList([]const u8)).init(allocator),
        };
    }
    
    pub fn deinit(self: *DependencyAnalyzer) void {
        // Free function calls
        var calls_iter = self.function_calls.iterator();
        while (calls_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |call| {
                self.allocator.free(call);
            }
            entry.value_ptr.deinit();
        }
        self.function_calls.deinit();
        
        // Free type usages
        var types_iter = self.type_usages.iterator();
        while (types_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |usage| {
                self.allocator.free(usage);
            }
            entry.value_ptr.deinit();
        }
        self.type_usages.deinit();
        
        // Free variable references
        var vars_iter = self.variable_references.iterator();
        while (vars_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |ref| {
                self.allocator.free(ref);
            }
            entry.value_ptr.deinit();
        }
        self.variable_references.deinit();
    }
    
    /// Analyze dependencies in a program
    pub fn analyze(self: *DependencyAnalyzer, program: *Program) !DependencyAnalysis {
        var analysis = DependencyAnalysis.init(self.allocator);
        
        // Build dependency graph
        try self.buildDependencyGraph(program, &analysis);
        
        // Detect circular dependencies
        try self.detectCircularDependencies(&analysis);
        
        // Find unused functions
        try self.findUnusedFunctions(program, &analysis);
        
        // Analyze reachability from entry point
        try self.analyzeReachability(program, &analysis);
        
        // Calculate complexity metrics
        try self.calculateComplexityMetrics(&analysis);
        
        return analysis;
    }
    
    /// Build the dependency graph by analyzing the program
    fn buildDependencyGraph(self: *DependencyAnalyzer, program: *Program, analysis: *DependencyAnalysis) !void {
        // Add all functions as nodes
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            
            var node = DependencyNode.init(self.allocator, try self.allocator.dupe(u8, func_name), .function);
            
            // Add metadata
            const param_count = try std.fmt.allocPrint(self.allocator, "{d}", .{function.args.items.len});
            const return_type = try self.allocator.dupe(u8, @tagName(function.@"return"));
            const body_size = try std.fmt.allocPrint(self.allocator, "{d}", .{function.body.items.len});
            
            try node.metadata.put(try self.allocator.dupe(u8, "parameter_count"), param_count);
            try node.metadata.put(try self.allocator.dupe(u8, "return_type"), return_type);
            try node.metadata.put(try self.allocator.dupe(u8, "body_size"), body_size);
            try node.metadata.put(try self.allocator.dupe(u8, "is_inline"), try self.allocator.dupe(u8, if (function.@"inline") "true" else "false"));
            try node.metadata.put(try self.allocator.dupe(u8, "is_pure"), try self.allocator.dupe(u8, if (function.pure) "true" else "false"));
            
            try analysis.dependency_graph.put(try self.allocator.dupe(u8, func_name), node);
        }
        
        // Analyze function dependencies
        func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            
            self.current_function = func_name;
            try self.analyzeFunctionDependencies(func_name, function, analysis);
        }
        
        // Add type dependencies
        try self.analyzeTypeDependencies(program, analysis);
        
        // Add constant dependencies
        try self.analyzeConstantDependencies(program, analysis);
    }
    
    /// Analyze dependencies within a single function
    fn analyzeFunctionDependencies(self: *DependencyAnalyzer, func_name: []const u8, function: *Function, analysis: *DependencyAnalysis) !void {
        // Analyze parameter types
        for (function.args.items) |param| {
            try self.analyzeTypeUsage(func_name, param.type, analysis, "parameter");
        }
        
        // Analyze return type
        try self.analyzeTypeUsage(func_name, function.@"return", analysis, "return_type");
        
        // Analyze function body
        for (function.body.items) |*stmt| {
            try self.analyzeStatement(func_name, stmt, analysis);
        }
    }
    
    /// Analyze dependencies in a statement
    fn analyzeStatement(self: *DependencyAnalyzer, func_name: []const u8, stmt: *Statement, analysis: *DependencyAnalysis) !void {
        switch (stmt.*) {
            .let => |let_stmt| {
                if (let_stmt.type) |var_type| {
                    try self.analyzeTypeUsage(func_name, var_type, analysis, "variable_type");
                }
                try self.analyzeExpression(func_name, @constCast(&let_stmt.value), analysis);
            },
            .assign => |assign_stmt| {
                try self.analyzeExpression(func_name, @constCast(&assign_stmt.value), analysis);
            },
            .@"if" => |if_stmt| {
                try self.analyzeExpression(func_name, @constCast(&if_stmt.condition), analysis);
                for (if_stmt.then.items) |*then_stmt| {
                    try self.analyzeStatement(func_name, @constCast(then_stmt), analysis);
                }
                if (if_stmt.@"else") |else_stmts| {
                    for (else_stmts.items) |*else_stmt| {
                        try self.analyzeStatement(func_name, @constCast(else_stmt), analysis);
                    }
                }
            },
            .@"while" => |while_stmt| {
                try self.analyzeExpression(func_name, @constCast(&while_stmt.condition), analysis);
                for (while_stmt.body.items) |*body_stmt| {
                    try self.analyzeStatement(func_name, @constCast(body_stmt), analysis);
                }
            },
            .expression => |expr| {
                try self.analyzeExpression(func_name, @constCast(&expr), analysis);
            },
            .@"return" => |return_expr| {
                try self.analyzeExpression(func_name, @constCast(&return_expr), analysis);
            },
            else => {},
        }
    }
    
    /// Analyze dependencies in an expression
    fn analyzeExpression(self: *DependencyAnalyzer, func_name: []const u8, expr: *Expression, analysis: *DependencyAnalysis) !void {
        switch (expr.*) {
            .call => |call_expr| {
                // Record function call dependency
                try self.addDependency(analysis, func_name, call_expr.function, .function_call, "function call");
                
                // Update dependency graph
                if (analysis.dependency_graph.getPtr(func_name)) |source_node| {
                    try source_node.dependencies.append(try self.allocator.dupe(u8, call_expr.function));
                }
                
                if (analysis.dependency_graph.getPtr(call_expr.function)) |target_node| {
                    try target_node.dependents.append(try self.allocator.dupe(u8, func_name));
                }
                
                // Analyze arguments
                for (call_expr.args.items) |*arg| {
                    try self.analyzeExpression(func_name, arg, analysis);
                }
            },
            .variable => |var_name| {
                // Record variable reference
                try self.addDependency(analysis, func_name, var_name, .variable_reference, "variable access");
            },
            .op => |op_expr| {
                for (op_expr.args.items) |*arg| {
                    try self.analyzeExpression(func_name, arg, analysis);
                }
            },
            .literal => {},
            else => {},
        }
    }
    
    /// Analyze type usage dependencies (for *Type pointers)
    fn analyzeTypeUsagePtr(self: *DependencyAnalyzer, func_name: []const u8, type_info: *Type, analysis: *DependencyAnalysis, context: []const u8) Allocator.Error!void {
        try self.analyzeTypeUsage(func_name, type_info.*, analysis, context);
    }
    
    /// Analyze type usage dependencies (for Type values)
    fn analyzeTypeUsage(self: *DependencyAnalyzer, func_name: []const u8, type_info: Type, analysis: *DependencyAnalysis, context: []const u8) Allocator.Error!void {
        switch (type_info) {
            .@"struct" => |struct_fields| {
                var field_iter = struct_fields.iterator();
                while (field_iter.next()) |entry| {
                    try self.analyzeTypeUsagePtr(func_name, entry.value_ptr.*, analysis, context);
                }
            },
            .@"union" => |union_fields| {
                var field_iter = union_fields.iterator();
                while (field_iter.next()) |entry| {
                    try self.analyzeTypeUsagePtr(func_name, entry.value_ptr.*, analysis, context);
                }
            },
            .@"enum" => |enum_def| {
                try self.addDependency(analysis, func_name, enum_def.name, .type_usage, context);
            },
            .@"error" => |error_def| {
                try self.addDependency(analysis, func_name, error_def.name, .type_usage, context);
                if (error_def.message_type) |msg_type| {
                    try self.analyzeTypeUsagePtr(func_name, msg_type, analysis, context);
                }
            },
            .discriminated_union => |union_def| {
                try self.addDependency(analysis, func_name, union_def.name, .type_usage, context);
                for (union_def.variants.items) |variant_type| {
                    try self.analyzeTypeUsagePtr(func_name, variant_type, analysis, context);
                }
            },
            .array => |array_def| {
                try self.analyzeTypeUsagePtr(func_name, array_def.element, analysis, context);
            },
            .slice => |slice_def| {
                try self.analyzeTypeUsagePtr(func_name, slice_def.element, analysis, context);
            },
            .hashmap => |map_def| {
                try self.analyzeTypeUsagePtr(func_name, map_def.key, analysis, context);
                try self.analyzeTypeUsagePtr(func_name, map_def.value, analysis, context);
            },
            .set => |set_def| {
                try self.analyzeTypeUsagePtr(func_name, set_def.element, analysis, context);
            },
            .tuple => |tuple_types| {
                for (tuple_types.items) |tuple_type| {
                    try self.analyzeTypeUsagePtr(func_name, tuple_type, analysis, context);
                }
            },
            .record => |record_def| {
                try self.addDependency(analysis, func_name, record_def.name, .type_usage, context);
            },
            .optional => |opt_type| {
                try self.analyzeTypeUsagePtr(func_name, opt_type, analysis, context);
            },
            .function => |func_sig| {
                for (func_sig.args.items) |arg_type| {
                    try self.analyzeTypeUsage(func_name, arg_type, analysis, context);
                }
                try self.analyzeTypeUsagePtr(func_name, func_sig.@"return", analysis, context);
            },
            .future => |future_type| {
                try self.analyzeTypeUsagePtr(func_name, future_type, analysis, context);
            },
            .distribution => |dist_def| {
                for (dist_def.param_types.items) |param_type| {
                    try self.analyzeTypeUsage(func_name, param_type, analysis, context);
                }
            },
            .generic_instance => |generic_def| {
                try self.addDependency(analysis, func_name, generic_def.base_type, .type_usage, context);
                for (generic_def.type_args.items) |type_arg| {
                    try self.analyzeTypeUsagePtr(func_name, type_arg, analysis, context);
                }
            },
            .@"interface" => |interface_def| {
                try self.addDependency(analysis, func_name, interface_def.name, .interface_implementation, context);
            },
            .trait_object => |trait_def| {
                try self.addDependency(analysis, func_name, trait_def.trait_name, .interface_implementation, context);
            },
            else => {}, // Primitive types don't create dependencies
        }
    }
    
    /// Analyze type definition dependencies
    fn analyzeTypeDependencies(self: *DependencyAnalyzer, program: *Program, analysis: *DependencyAnalysis) !void {
        var type_iter = program.types.iterator();
        while (type_iter.next()) |entry| {
            const type_name = entry.key_ptr.*;
            const type_def = entry.value_ptr;
            
            const node = DependencyNode.init(self.allocator, try self.allocator.dupe(u8, type_name), .type_definition);
            try analysis.dependency_graph.put(try self.allocator.dupe(u8, type_name), node);
            
            try self.analyzeTypeUsage(type_name, type_def.*, analysis, "type_definition");
        }
    }
    
    /// Analyze constant dependencies
    fn analyzeConstantDependencies(self: *DependencyAnalyzer, program: *Program, analysis: *DependencyAnalysis) !void {
        var const_iter = program.constants.iterator();
        while (const_iter.next()) |entry| {
            const const_name = entry.key_ptr.*;
            const const_def = entry.value_ptr;
            
            const node = DependencyNode.init(self.allocator, try self.allocator.dupe(u8, const_name), .constant);
            try analysis.dependency_graph.put(try self.allocator.dupe(u8, const_name), node);
            
            try self.analyzeTypeUsage(const_name, const_def.type, analysis, "constant_type");
            try self.analyzeExpression(const_name, @constCast(&const_def.value), analysis);
        }
    }
    
    /// Add a dependency to the analysis
    fn addDependency(self: *DependencyAnalyzer, analysis: *DependencyAnalysis, source: []const u8, target: []const u8, dep_type: DependencyType, context: []const u8) !void {
        const dependency = Dependency{
            .source = try self.allocator.dupe(u8, source),
            .target = try self.allocator.dupe(u8, target),
            .dependency_type = dep_type,
            .location = SourceLocation{
                .function_name = self.current_function orelse source,
                .line = 1, // Would need proper source mapping
                .column = 1,
                .context = context,
            },
            .metadata = try std.fmt.allocPrint(self.allocator, "type:{s}", .{@tagName(dep_type)}),
        };
        
        try analysis.dependencies.append(dependency);
    }
    
    /// Detect circular dependencies using DFS
    fn detectCircularDependencies(self: *DependencyAnalyzer, analysis: *DependencyAnalysis) !void {
        var visited = StringHashMap(bool).init(self.allocator);
        defer visited.deinit();
        
        var recursion_stack = StringHashMap(bool).init(self.allocator);
        defer recursion_stack.deinit();
        
        var current_path = ArrayList([]const u8).init(self.allocator);
        defer current_path.deinit();
        
        var graph_iter = analysis.dependency_graph.iterator();
        while (graph_iter.next()) |entry| {
            const node_name = entry.key_ptr.*;
            if (!visited.contains(node_name)) {
                try self.dfsDetectCycles(node_name, analysis, &visited, &recursion_stack, &current_path);
            }
        }
    }
    
    /// DFS helper for cycle detection
    fn dfsDetectCycles(self: *DependencyAnalyzer, node_name: []const u8, analysis: *DependencyAnalysis, visited: *StringHashMap(bool), recursion_stack: *StringHashMap(bool), current_path: *ArrayList([]const u8)) !void {
        try visited.put(node_name, true);
        try recursion_stack.put(node_name, true);
        try current_path.append(node_name);
        
        if (analysis.dependency_graph.get(node_name)) |node| {
            for (node.dependencies.items) |dep_name| {
                if (!visited.contains(dep_name)) {
                    try self.dfsDetectCycles(dep_name, analysis, visited, recursion_stack, current_path);
                } else if (recursion_stack.contains(dep_name)) {
                    // Found a cycle - extract the cycle path
                    var cycle = ArrayList([]const u8).init(self.allocator);
                    var found_start = false;
                    for (current_path.items) |path_node| {
                        if (std.mem.eql(u8, path_node, dep_name)) {
                            found_start = true;
                        }
                        if (found_start) {
                            try cycle.append(try self.allocator.dupe(u8, path_node));
                        }
                    }
                    try cycle.append(try self.allocator.dupe(u8, dep_name)); // Close the cycle
                    try analysis.circular_dependencies.append(cycle);
                }
            }
        }
        
        _ = current_path.pop();
        _ = recursion_stack.remove(node_name);
    }
    
    /// Find functions that are never called
    fn findUnusedFunctions(self: *DependencyAnalyzer, program: *Program, analysis: *DependencyAnalysis) !void {
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            
            // Skip entry function
            if (std.mem.eql(u8, func_name, program.entry)) {
                continue;
            }
            
            // Check if function has any dependents
            if (analysis.dependency_graph.get(func_name)) |node| {
                if (node.dependents.items.len == 0) {
                    try analysis.unused_functions.append(try self.allocator.dupe(u8, func_name));
                }
            }
        }
    }
    
    /// Analyze reachability from entry point
    fn analyzeReachability(self: *DependencyAnalyzer, program: *Program, analysis: *DependencyAnalysis) !void {
        var reachable = StringHashMap(bool).init(self.allocator);
        defer reachable.deinit();
        
        var to_visit = ArrayList([]const u8).init(self.allocator);
        defer to_visit.deinit();
        
        // Start from entry point
        try to_visit.append(program.entry);
        try reachable.put(program.entry, true);
        
        while (to_visit.items.len > 0) {
            const current = to_visit.items[to_visit.items.len - 1];
            _ = to_visit.pop();
            
            if (analysis.dependency_graph.get(current)) |node| {
                for (node.dependencies.items) |dep_name| {
                    if (!reachable.contains(dep_name)) {
                        try reachable.put(dep_name, true);
                        try to_visit.append(dep_name);
                        try analysis.entry_point_reachable.append(try self.allocator.dupe(u8, dep_name));
                    }
                }
            }
        }
    }
    
    /// Calculate complexity metrics
    fn calculateComplexityMetrics(self: *DependencyAnalyzer, analysis: *DependencyAnalysis) !void {
        _ = self;
        
        analysis.complexity_metrics.total_nodes = @intCast(analysis.dependency_graph.count());
        
        var total_edges: u32 = 0;
        var max_dependencies: u32 = 0;
        
        var graph_iter = analysis.dependency_graph.iterator();
        while (graph_iter.next()) |entry| {
            const node = entry.value_ptr.*;
            const edge_count: u32 = @intCast(node.dependencies.items.len);
            total_edges += edge_count;
            
            if (edge_count > max_dependencies) {
                max_dependencies = edge_count;
            }
        }
        
        analysis.complexity_metrics.total_edges = total_edges;
        analysis.complexity_metrics.max_depth = max_dependencies;
        analysis.complexity_metrics.cyclomatic_complexity = @intCast(analysis.circular_dependencies.items.len);
        
        // Calculate coupling factor (average dependencies per node)
        if (analysis.complexity_metrics.total_nodes > 0) {
            analysis.complexity_metrics.coupling_factor = @as(f64, @floatFromInt(total_edges)) / @as(f64, @floatFromInt(analysis.complexity_metrics.total_nodes));
        }
    }
};