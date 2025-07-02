const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const SirsParser = @import("sirs.zig");
const Expression = SirsParser.Expression;
const Statement = SirsParser.Statement;
const Type = SirsParser.Type;

/// Graphical Model Extensions for Sever
/// This module provides enhanced syntax for defining probabilistic graphical models

/// Node types in a graphical model
pub const NodeType = enum {
    observed,        // Observed data
    latent,         // Latent/hidden variable
    parameter,      // Model parameter
    hyperparameter, // Hyperparameter
    deterministic,  // Deterministic function of other nodes
};

/// A node in the graphical model
pub const GraphicalNode = struct {
    name: []const u8,
    node_type: NodeType,
    distribution: ?[]const u8,          // Distribution name (null for deterministic)
    parameters: ArrayList(Expression),   // Distribution parameters or deterministic function
    parents: ArrayList([]const u8),     // Parent node names
    children: ArrayList([]const u8),    // Child node names (computed)
    observed_value: ?Expression,        // Value if observed
    plate_memberships: ArrayList([]const u8), // Plate names this node belongs to
    description: ?[]const u8,           // Optional documentation
    
    pub fn init(allocator: Allocator, name: []const u8, node_type: NodeType) GraphicalNode {
        return GraphicalNode{
            .name = name,
            .node_type = node_type,
            .distribution = null,
            .parameters = ArrayList(Expression).init(allocator),
            .parents = ArrayList([]const u8).init(allocator),
            .children = ArrayList([]const u8).init(allocator),
            .observed_value = null,
            .plate_memberships = ArrayList([]const u8).init(allocator),
            .description = null,
        };
    }
    
    pub fn deinit(self: *GraphicalNode) void {
        self.parameters.deinit();
        self.parents.deinit();
        self.children.deinit();
        self.plate_memberships.deinit();
    }
};

/// Plate notation for repeated structures
pub const Plate = struct {
    name: []const u8,
    size: Expression,               // Plate size (can be variable or literal)
    index_variable: []const u8,     // Loop index variable name
    condition: ?Expression,         // Optional condition for inclusion
    nested_plates: ArrayList([]const u8), // Names of nested plates
    description: ?[]const u8,
    
    pub fn init(allocator: Allocator, name: []const u8, size: Expression, index_var: []const u8) Plate {
        return Plate{
            .name = name,
            .size = size,
            .index_variable = index_var,
            .condition = null,
            .nested_plates = ArrayList([]const u8).init(allocator),
            .description = null,
        };
    }
    
    pub fn deinit(self: *Plate) void {
        self.nested_plates.deinit();
    }
};

/// Factor in a factor graph
pub const Factor = struct {
    name: []const u8,
    variables: ArrayList([]const u8),  // Connected variable names
    function_expr: Expression,         // Factor function/potential
    factor_type: FactorType,
    log_space: bool,                   // Whether function is in log space
    description: ?[]const u8,
    
    pub fn init(allocator: Allocator, name: []const u8, factor_type: FactorType) Factor {
        return Factor{
            .name = name,
            .variables = ArrayList([]const u8).init(allocator),
            .function_expr = undefined, // Must be set
            .factor_type = factor_type,
            .log_space = true, // Default to log space for numerical stability
            .description = null,
        };
    }
    
    pub fn deinit(self: *Factor) void {
        self.variables.deinit();
    }
};

pub const FactorType = enum {
    likelihood,     // P(data|parameters)
    prior,         // P(parameters)
    constraint,    // Hard constraint
    soft_constraint, // Soft constraint with penalty
    deterministic, // Deterministic relationship
};

/// Complete graphical model specification
pub const GraphicalModel = struct {
    name: []const u8,
    nodes: StringHashMap(GraphicalNode),
    plates: StringHashMap(Plate),
    factors: StringHashMap(Factor),
    data_nodes: ArrayList([]const u8),      // Names of observed nodes
    parameter_nodes: ArrayList([]const u8), // Names of parameter nodes
    inference_target: ?[]const u8,          // Primary inference target
    allocator: Allocator,
    
    pub fn init(allocator: Allocator, name: []const u8) GraphicalModel {
        return GraphicalModel{
            .name = name,
            .nodes = StringHashMap(GraphicalNode).init(allocator),
            .plates = StringHashMap(Plate).init(allocator),
            .factors = StringHashMap(Factor).init(allocator),
            .data_nodes = ArrayList([]const u8).init(allocator),
            .parameter_nodes = ArrayList([]const u8).init(allocator),
            .inference_target = null,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *GraphicalModel) void {
        // Clean up nodes
        var node_iter = self.nodes.iterator();
        while (node_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.nodes.deinit();
        
        // Clean up plates
        var plate_iter = self.plates.iterator();
        while (plate_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.plates.deinit();
        
        // Clean up factors
        var factor_iter = self.factors.iterator();
        while (factor_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.factors.deinit();
        
        self.data_nodes.deinit();
        self.parameter_nodes.deinit();
    }
    
    /// Add a node to the model
    pub fn addNode(self: *GraphicalModel, node: GraphicalNode) !void {
        try self.nodes.put(node.name, node);
        
        // Track data and parameter nodes
        switch (node.node_type) {
            .observed => try self.data_nodes.append(node.name),
            .parameter, .hyperparameter => try self.parameter_nodes.append(node.name),
            else => {},
        }
    }
    
    /// Add a plate to the model
    pub fn addPlate(self: *GraphicalModel, plate: Plate) !void {
        try self.plates.put(plate.name, plate);
    }
    
    /// Add a factor to the model
    pub fn addFactor(self: *GraphicalModel, factor: Factor) !void {
        try self.factors.put(factor.name, factor);
    }
    
    /// Compute the topological order of nodes for inference
    pub fn computeTopologicalOrder(self: *GraphicalModel) !ArrayList([]const u8) {
        // Simple topological sort implementation
        var visited = StringHashMap(bool).init(self.allocator);
        defer visited.deinit();
        
        var temp_visited = StringHashMap(bool).init(self.allocator);
        defer temp_visited.deinit();
        
        var result = ArrayList([]const u8).init(self.allocator);
        
        var node_iter = self.nodes.iterator();
        while (node_iter.next()) |entry| {
            if (!visited.contains(entry.key_ptr.*)) {
                try self.topologicalSortUtil(entry.key_ptr.*, &visited, &temp_visited, &result);
            }
        }
        
        // Reverse the result to get proper dependency order (parents before children)
        std.mem.reverse([]const u8, result.items);
        
        return result;
    }
    
    fn topologicalSortUtil(self: *GraphicalModel, node_name: []const u8, visited: *StringHashMap(bool), temp_visited: *StringHashMap(bool), result: *ArrayList([]const u8)) !void {
        try temp_visited.put(node_name, true);
        
        if (self.nodes.get(node_name)) |node| {
            for (node.children.items) |child_name| {
                if (temp_visited.contains(child_name)) {
                    // Cycle detected - for now just continue
                    continue;
                }
                if (!visited.contains(child_name)) {
                    try self.topologicalSortUtil(child_name, visited, temp_visited, result);
                }
            }
        }
        
        _ = temp_visited.remove(node_name);
        try visited.put(node_name, true);
        try result.append(node_name);
    }
    
    /// Validate the model for consistency
    pub fn validate(self: *GraphicalModel) !bool {
        // Check for cycles in non-temporal models
        // Check that all parent references exist
        // Check that observed nodes have values
        // Check that all distribution parameters are valid
        
        var node_iter = self.nodes.iterator();
        while (node_iter.next()) |entry| {
            const node = entry.value_ptr.*;
            
            // Check parent references
            for (node.parents.items) |parent_name| {
                if (!self.nodes.contains(parent_name)) {
                    std.debug.print("Error: Node '{s}' references non-existent parent '{s}'\n", .{ node.name, parent_name });
                    return false;
                }
            }
            
            // Check observed nodes have values
            if (node.node_type == .observed and node.observed_value == null) {
                std.debug.print("Error: Observed node '{s}' has no observed value\n", .{node.name});
                return false;
            }
        }
        
        return true;
    }
};

/// Compiler for graphical models to SIRS code
pub const GraphicalModelCompiler = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) GraphicalModelCompiler {
        return GraphicalModelCompiler{
            .allocator = allocator,
        };
    }
    
    /// Compile a graphical model to SIRS statements
    pub fn compile(self: *GraphicalModelCompiler, model: *GraphicalModel) !ArrayList(Statement) {
        var statements = ArrayList(Statement).init(self.allocator);
        
        // Validate model first
        if (!try model.validate()) {
            return error.InvalidModel;
        }
        
        // Get topological order for correct variable definition order
        const topo_order = try model.computeTopologicalOrder();
        defer topo_order.deinit();
        
        // Generate statements for each node in topological order
        for (topo_order.items) |node_name| {
            const node = model.nodes.get(node_name).?;
            
            switch (node.node_type) {
                .parameter, .hyperparameter => {
                    // Generate prior statements
                    try self.generatePriorStatement(&statements, node);
                },
                .latent => {
                    // Generate latent variable statements
                    try self.generateLatentStatement(&statements, node);
                },
                .observed => {
                    // Generate observation statements
                    try self.generateObservationStatement(&statements, node);
                },
                .deterministic => {
                    // Generate deterministic assignments
                    try self.generateDeterministicStatement(&statements, node);
                },
            }
        }
        
        return statements;
    }
    
    fn generatePriorStatement(self: *GraphicalModelCompiler, statements: *ArrayList(Statement), node: GraphicalNode) !void {
        _ = self;
        
        if (node.distribution) |dist_name| {
            const stmt = Statement{
                .let = .{
                    .name = node.name,
                    .type = null,
                    .mutable = false,
                    .value = Expression{
                        .sample = .{
                            .distribution = dist_name,
                            .params = node.parameters,
                        },
                    },
                },
            };
            try statements.append(stmt);
        }
    }
    
    fn generateLatentStatement(self: *GraphicalModelCompiler, statements: *ArrayList(Statement), node: GraphicalNode) !void {
        _ = self;
        
        if (node.distribution) |dist_name| {
            const stmt = Statement{
                .let = .{
                    .name = node.name,
                    .type = null,
                    .mutable = false,
                    .value = Expression{
                        .sample = .{
                            .distribution = dist_name,
                            .params = node.parameters,
                        },
                    },
                },
            };
            try statements.append(stmt);
        }
    }
    
    fn generateObservationStatement(self: *GraphicalModelCompiler, statements: *ArrayList(Statement), node: GraphicalNode) !void {
        _ = self;
        
        if (node.distribution) |dist_name| {
            if (node.observed_value) |value| {
                const stmt = Statement{
                    .observe = .{
                        .distribution = dist_name,
                        .params = node.parameters,
                        .value = value,
                    },
                };
                try statements.append(stmt);
            }
        }
    }
    
    fn generateDeterministicStatement(self: *GraphicalModelCompiler, statements: *ArrayList(Statement), node: GraphicalNode) !void {
        _ = self;
        
        if (node.parameters.items.len > 0) {
            const stmt = Statement{
                .let = .{
                    .name = node.name,
                    .type = null,
                    .mutable = false,
                    .value = node.parameters.items[0], // First parameter is the expression
                },
            };
            try statements.append(stmt);
        }
    }
};

/// Builder pattern for creating graphical models
pub const GraphicalModelBuilder = struct {
    model: GraphicalModel,
    current_plate: ?[]const u8,
    
    pub fn init(allocator: Allocator, name: []const u8) GraphicalModelBuilder {
        return GraphicalModelBuilder{
            .model = GraphicalModel.init(allocator, name),
            .current_plate = null,
        };
    }
    
    pub fn deinit(self: *GraphicalModelBuilder) void {
        self.model.deinit();
    }
    
    /// Add a parameter node
    pub fn addParameter(self: *GraphicalModelBuilder, name: []const u8, distribution: []const u8, params: []const Expression) !*GraphicalModelBuilder {
        var node = GraphicalNode.init(self.model.allocator, name, .parameter);
        node.distribution = distribution;
        for (params) |param| {
            try node.parameters.append(param);
        }
        
        if (self.current_plate) |plate_name| {
            try node.plate_memberships.append(plate_name);
        }
        
        try self.model.addNode(node);
        return self;
    }
    
    /// Add an observed node
    pub fn addObserved(self: *GraphicalModelBuilder, name: []const u8, distribution: []const u8, params: []const Expression, value: Expression) !*GraphicalModelBuilder {
        var node = GraphicalNode.init(self.model.allocator, name, .observed);
        node.distribution = distribution;
        node.observed_value = value;
        for (params) |param| {
            try node.parameters.append(param);
        }
        
        if (self.current_plate) |plate_name| {
            try node.plate_memberships.append(plate_name);
        }
        
        try self.model.addNode(node);
        return self;
    }
    
    /// Add a latent variable
    pub fn addLatent(self: *GraphicalModelBuilder, name: []const u8, distribution: []const u8, params: []const Expression) !*GraphicalModelBuilder {
        var node = GraphicalNode.init(self.model.allocator, name, .latent);
        node.distribution = distribution;
        for (params) |param| {
            try node.parameters.append(param);
        }
        
        if (self.current_plate) |plate_name| {
            try node.plate_memberships.append(plate_name);
        }
        
        try self.model.addNode(node);
        return self;
    }
    
    /// Start a plate block
    pub fn startPlate(self: *GraphicalModelBuilder, name: []const u8, size: Expression, index_var: []const u8) !*GraphicalModelBuilder {
        const plate = Plate.init(self.model.allocator, name, size, index_var);
        try self.model.addPlate(plate);
        self.current_plate = name;
        return self;
    }
    
    /// End the current plate block
    pub fn endPlate(self: *GraphicalModelBuilder) *GraphicalModelBuilder {
        self.current_plate = null;
        return self;
    }
    
    /// Add dependency between nodes
    pub fn addDependency(self: *GraphicalModelBuilder, parent: []const u8, child: []const u8) !*GraphicalModelBuilder {
        if (self.model.nodes.getPtr(parent)) |parent_node| {
            try parent_node.children.append(child);
        }
        
        if (self.model.nodes.getPtr(child)) |child_node| {
            try child_node.parents.append(parent);
        }
        
        return self;
    }
    
    /// Build the final model
    pub fn build(self: *GraphicalModelBuilder) GraphicalModel {
        return self.model;
    }
};