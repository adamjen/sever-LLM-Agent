const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const GraphicalModel = @import("graphical_model.zig");
const GraphicalNode = GraphicalModel.GraphicalNode;
const NodeType = GraphicalModel.NodeType;
const Plate = GraphicalModel.Plate;
const Factor = GraphicalModel.Factor;
const FactorType = GraphicalModel.FactorType;
const GraphicalModelBuilder = GraphicalModel.GraphicalModelBuilder;
const GraphicalModelCompiler = GraphicalModel.GraphicalModelCompiler;

const SirsParser = @import("sirs.zig");
const Expression = SirsParser.Expression;
const Statement = SirsParser.Statement;
const Literal = SirsParser.Literal;

test "GraphicalNode creation and basic functionality" {
    const allocator = testing.allocator;
    
    var node = GraphicalNode.init(allocator, "mu", .parameter);
    defer node.deinit();
    
    try testing.expectEqualStrings("mu", node.name);
    try testing.expect(node.node_type == .parameter);
    try testing.expect(node.distribution == null);
    
    // Test adding parameters
    const param_expr = Expression{ .literal = Literal{ .float = 0.0 } };
    try node.parameters.append(param_expr);
    try testing.expect(node.parameters.items.len == 1);
    
    // Test adding parents
    try node.parents.append("prior_mu");
    try testing.expectEqualStrings("prior_mu", node.parents.items[0]);
}

test "Plate creation and functionality" {
    const allocator = testing.allocator;
    
    const size_expr = Expression{ .literal = Literal{ .integer = 10 } };
    var plate = Plate.init(allocator, "data_plate", size_expr, "i");
    defer plate.deinit();
    
    try testing.expectEqualStrings("data_plate", plate.name);
    try testing.expectEqualStrings("i", plate.index_variable);
    try testing.expect(plate.condition == null);
    
    // Test nested plates
    try plate.nested_plates.append("inner_plate");
    try testing.expectEqualStrings("inner_plate", plate.nested_plates.items[0]);
}

test "Factor creation and functionality" {
    const allocator = testing.allocator;
    
    var factor = Factor.init(allocator, "likelihood_factor", .likelihood);
    defer factor.deinit();
    
    try testing.expectEqualStrings("likelihood_factor", factor.name);
    try testing.expect(factor.factor_type == .likelihood);
    try testing.expect(factor.log_space == true); // default
    
    // Test adding variables
    try factor.variables.append("x");
    try factor.variables.append("mu");
    try testing.expectEqualStrings("x", factor.variables.items[0]);
    try testing.expectEqualStrings("mu", factor.variables.items[1]);
}

test "GraphicalModel complete functionality" {
    const allocator = testing.allocator;
    
    var model = GraphicalModel.GraphicalModel.init(allocator, "test_model");
    defer model.deinit();
    
    try testing.expectEqualStrings("test_model", model.name);
    
    // Add a parameter node
    var mu_node = GraphicalNode.init(allocator, "mu", .parameter);
    mu_node.distribution = "normal";
    const param1 = Expression{ .literal = Literal{ .float = 0.0 } };
    const param2 = Expression{ .literal = Literal{ .float = 1.0 } };
    try mu_node.parameters.append(param1);
    try mu_node.parameters.append(param2);
    
    try model.addNode(mu_node);
    
    // Add an observed node
    var data_node = GraphicalNode.init(allocator, "x", .observed);
    data_node.distribution = "normal";
    data_node.observed_value = Expression{ .literal = Literal{ .float = 1.5 } };
    const obs_param1 = Expression{ .variable = "mu" };
    const obs_param2 = Expression{ .literal = Literal{ .float = 0.5 } };
    try data_node.parameters.append(obs_param1);
    try data_node.parameters.append(obs_param2);
    try data_node.parents.append("mu");
    
    try model.addNode(data_node);
    
    // Add dependency  
    if (model.nodes.getPtr("mu")) |mu_ptr| {
        try mu_ptr.children.append("x");
    }
    
    // Test model structure
    try testing.expect(model.nodes.count() == 2);
    try testing.expect(model.parameter_nodes.items.len == 1);  
    try testing.expect(model.data_nodes.items.len == 1);
    try testing.expectEqualStrings("mu", model.parameter_nodes.items[0]);
    try testing.expectEqualStrings("x", model.data_nodes.items[0]);
    
    // Test validation
    const is_valid = try model.validate();
    try testing.expect(is_valid);
}

test "GraphicalModel topological ordering" {
    const allocator = testing.allocator;
    
    var model = GraphicalModel.GraphicalModel.init(allocator, "topo_test");
    defer model.deinit();
    
    // Create nodes: mu -> sigma -> data
    const mu_node = GraphicalNode.init(allocator, "mu", .parameter);
    try model.addNode(mu_node);
    
    var sigma_node = GraphicalNode.init(allocator, "sigma", .parameter);
    try sigma_node.parents.append("mu");
    try model.addNode(sigma_node);
    
    var data_node = GraphicalNode.init(allocator, "data", .observed);
    try data_node.parents.append("mu");  
    try data_node.parents.append("sigma");
    data_node.observed_value = Expression{ .literal = Literal{ .float = 1.0 } };
    try model.addNode(data_node);
    
    // Add children relationships
    if (model.nodes.getPtr("mu")) |mu_ptr| {
        try mu_ptr.children.append("sigma");
        try mu_ptr.children.append("data");
    }
    if (model.nodes.getPtr("sigma")) |sigma_ptr| {
        try sigma_ptr.children.append("data");
    }
    
    // Compute topological order
    const topo_order = try model.computeTopologicalOrder();
    defer topo_order.deinit();
    
    
    try testing.expect(topo_order.items.len == 3);
    
    // Find positions of nodes in topological order
    var mu_pos: ?usize = null;
    var sigma_pos: ?usize = null;
    var data_pos: ?usize = null;
    
    for (topo_order.items, 0..) |node_name, i| {
        if (std.mem.eql(u8, node_name, "mu")) mu_pos = i;
        if (std.mem.eql(u8, node_name, "sigma")) sigma_pos = i;
        if (std.mem.eql(u8, node_name, "data")) data_pos = i;
    }
    
    try testing.expect(mu_pos != null);
    try testing.expect(sigma_pos != null);
    try testing.expect(data_pos != null);
    
    // mu should come before sigma and data
    try testing.expect(mu_pos.? < sigma_pos.?);
    try testing.expect(mu_pos.? < data_pos.?);
    // sigma should come before data  
    try testing.expect(sigma_pos.? < data_pos.?);
}

test "GraphicalModelBuilder fluent API" {
    const allocator = testing.allocator;
    
    var builder = GraphicalModelBuilder.init(allocator, "builder_test");
    defer builder.deinit();
    
    // Build a simple linear regression model using fluent API
    const mu_params = [_]Expression{
        Expression{ .literal = Literal{ .float = 0.0 } },
        Expression{ .literal = Literal{ .float = 10.0 } },
    };
    
    const sigma_params = [_]Expression{
        Expression{ .literal = Literal{ .float = 1.0 } },
        Expression{ .literal = Literal{ .float = 1.0 } },
    };
    
    const data_params = [_]Expression{
        Expression{ .variable = "mu" },
        Expression{ .variable = "sigma" },
    };
    
    const observed_value = Expression{ .literal = Literal{ .float = 2.5 } };
    
    // Build model with method chaining
    _ = try (try (try (try (try builder.addParameter("mu", "normal", &mu_params))
        .addParameter("sigma", "gamma", &sigma_params))
        .addObserved("data", "normal", &data_params, observed_value))
        .addDependency("mu", "data"))
        .addDependency("sigma", "data");
    
    // Test the built model
    const model = builder.build();
    try testing.expect(model.nodes.count() == 3);
    try testing.expect(model.parameter_nodes.items.len == 2);
    try testing.expect(model.data_nodes.items.len == 1);
    
    // Test validation
    var mutable_model = model;
    const is_valid = try mutable_model.validate();
    try testing.expect(is_valid);
}

test "GraphicalModelBuilder with plates" {
    const allocator = testing.allocator;
    
    var builder = GraphicalModelBuilder.init(allocator, "plate_test");
    defer builder.deinit();
    
    const size_expr = Expression{ .literal = Literal{ .integer = 5 } };
    
    const mu_params = [_]Expression{
        Expression{ .literal = Literal{ .float = 0.0 } },
        Expression{ .literal = Literal{ .float = 1.0 } },
    };
    
    const data_params = [_]Expression{
        Expression{ .variable = "mu" },
        Expression{ .literal = Literal{ .float = 0.5 } },
    };
    
    const observed_value = Expression{ .literal = Literal{ .float = 1.0 } };
    
    // Build model with plate
    _ = try (try (try (try builder.addParameter("mu", "normal", &mu_params))
        .startPlate("data_plate", size_expr, "i"))
        .addObserved("data", "normal", &data_params, observed_value))
        .endPlate()
        .addDependency("mu", "data");
    
    const model = builder.build();
    try testing.expect(model.nodes.count() == 2);
    try testing.expect(model.plates.count() == 1);
    
    // Check that data node is in the plate
    const data_node = model.nodes.get("data").?;
    try testing.expect(data_node.plate_memberships.items.len == 1);
    try testing.expectEqualStrings("data_plate", data_node.plate_memberships.items[0]);
}

test "GraphicalModelCompiler basic compilation" {
    const allocator = testing.allocator;
    
    // Build a simple model
    var builder = GraphicalModelBuilder.init(allocator, "compile_test");
    defer builder.deinit();
    
    const mu_params = [_]Expression{
        Expression{ .literal = Literal{ .float = 0.0 } },
        Expression{ .literal = Literal{ .float = 1.0 } },
    };
    
    const data_params = [_]Expression{
        Expression{ .variable = "mu" },
        Expression{ .literal = Literal{ .float = 0.5 } },
    };
    
    const observed_value = Expression{ .literal = Literal{ .float = 1.5 } };
    
    _ = try (try (try builder.addParameter("mu", "normal", &mu_params))
        .addObserved("data", "normal", &data_params, observed_value))
        .addDependency("mu", "data");
    
    var model = builder.build();
    
    // Compile to SIRS statements
    var compiler = GraphicalModelCompiler.init(allocator);
    const statements = try compiler.compile(&model);
    defer statements.deinit();
    
    // Should generate statements for mu (parameter) and data (observation)
    try testing.expect(statements.items.len >= 2);
    
    // Check that we have let and observe statements
    var has_let = false;
    var has_observe = false;
    
    for (statements.items) |stmt| {
        switch (stmt) {
            .let => has_let = true,
            .observe => has_observe = true,
            else => {},
        }
    }
    
    try testing.expect(has_let);
    try testing.expect(has_observe);
}

test "GraphicalModel validation with invalid references" {
    const allocator = testing.allocator;
    
    var model = GraphicalModel.GraphicalModel.init(allocator, "invalid_test");
    defer model.deinit();
    
    // Create a node with invalid parent reference
    var node = GraphicalNode.init(allocator, "data", .observed);
    try node.parents.append("nonexistent_parent");
    node.observed_value = Expression{ .literal = Literal{ .float = 1.0 } };
    
    try model.addNode(node);
    
    // Validation should fail
    const is_valid = try model.validate();
    try testing.expect(!is_valid);
}

test "GraphicalModel validation with missing observed values" {
    const allocator = testing.allocator;
    
    var model = GraphicalModel.GraphicalModel.init(allocator, "missing_obs_test");
    defer model.deinit();
    
    // Create observed node without observed value
    const node = GraphicalNode.init(allocator, "data", .observed);
    // Don't set observed_value
    
    try model.addNode(node);
    
    // Validation should fail
    const is_valid = try model.validate();
    try testing.expect(!is_valid);
}