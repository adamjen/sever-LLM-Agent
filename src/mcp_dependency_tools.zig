const std = @import("std");
const json = std.json;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const SirsParser = @import("sirs.zig");
const Program = SirsParser.Program;
const DependencyAnalyzer = @import("dependency_analyzer.zig").DependencyAnalyzer;
const DependencyAnalysis = @import("dependency_analyzer.zig").DependencyAnalysis;
const Dependency = @import("dependency_analyzer.zig").Dependency;
const DependencyType = @import("dependency_analyzer.zig").DependencyType;

/// MCP Tool for dependency analysis operations
pub const MCPDependencyTool = struct {
    name: []const u8,
    description: []const u8,
    input_schema: []const u8,
    handler: *const fn (allocator: Allocator, arguments: json.Value) anyerror![]const u8,
};

/// Registry of available MCP dependency tools
pub const MCP_DEPENDENCY_TOOLS = [_]MCPDependencyTool{
    .{
        .name = "analyze_dependencies",
        .description = "Perform comprehensive dependency analysis on a Sever program",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
        \\    "include_metrics": {"type": "boolean", "description": "Include complexity metrics in output"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = analyzeDependencies,
    },
    .{
        .name = "find_circular_dependencies",
        .description = "Detect circular dependencies in the code",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = findCircularDependencies,
    },
    .{
        .name = "find_unused_functions",
        .description = "Find functions that are never called",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = findUnusedFunctions,
    },
    .{
        .name = "get_dependency_graph",
        .description = "Get the dependency graph visualization",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
        \\    "format": {"type": "string", "enum": ["json", "dot", "mermaid"], "description": "Output format"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = getDependencyGraph,
    },
    .{
        .name = "analyze_function_dependencies",
        .description = "Analyze dependencies for a specific function",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
        \\    "function_name": {"type": "string", "description": "Name of the function to analyze"}
        \\  },
        \\  "required": ["sirs_content", "function_name"]
        \\}
        ,
        .handler = analyzeFunctionDependencies,
    },
    .{
        .name = "check_dependency_health",
        .description = "Check overall dependency health and provide recommendations",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = checkDependencyHealth,
    },
    .{
        .name = "get_reachability_analysis",
        .description = "Analyze code reachability from entry point",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = getReachabilityAnalysis,
    },
};

/// Parse SIRS content from JSON string
fn parseSIRSContent(allocator: Allocator, sirs_content: []const u8) !Program {
    var parser = SirsParser.Parser.init(allocator);
    return try parser.parse(sirs_content);
}

/// Analyze dependencies handler
fn analyzeDependencies(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    const include_metrics = if (arguments.object.get("include_metrics")) |m| m.bool else false;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    var analysis = try analyzer.analyze(&program);
    defer analysis.deinit(allocator);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    // Dependencies summary
    try json_obj.put("total_dependencies", json.Value{ .integer = @intCast(analysis.dependencies.items.len) });
    try json_obj.put("circular_dependencies_count", json.Value{ .integer = @intCast(analysis.circular_dependencies.items.len) });
    try json_obj.put("unused_functions_count", json.Value{ .integer = @intCast(analysis.unused_functions.items.len) });
    
    // Dependency breakdown by type
    var function_deps: u32 = 0;
    var type_deps: u32 = 0;
    var variable_deps: u32 = 0;
    
    for (analysis.dependencies.items) |dep| {
        switch (dep.dependency_type) {
            .function_call => function_deps += 1,
            .type_usage => type_deps += 1,
            .variable_reference => variable_deps += 1,
            else => {},
        }
    }
    
    var breakdown_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer breakdown_obj.deinit();
    try breakdown_obj.put("function_calls", json.Value{ .integer = function_deps });
    try breakdown_obj.put("type_usages", json.Value{ .integer = type_deps });
    try breakdown_obj.put("variable_references", json.Value{ .integer = variable_deps });
    try json_obj.put("dependency_breakdown", json.Value{ .object = breakdown_obj });
    
    // Include complexity metrics if requested
    if (include_metrics) {
        var metrics_obj = std.StringArrayHashMap(json.Value).init(allocator);
        defer metrics_obj.deinit();
        try metrics_obj.put("total_nodes", json.Value{ .integer = analysis.complexity_metrics.total_nodes });
        try metrics_obj.put("total_edges", json.Value{ .integer = analysis.complexity_metrics.total_edges });
        try metrics_obj.put("max_depth", json.Value{ .integer = analysis.complexity_metrics.max_depth });
        try metrics_obj.put("coupling_factor", json.Value{ .float = analysis.complexity_metrics.coupling_factor });
        try json_obj.put("complexity_metrics", json.Value{ .object = metrics_obj });
    }
    
    // Generate recommendations
    var recommendations = ArrayList(json.Value).init(allocator);
    defer recommendations.deinit();
    
    if (analysis.circular_dependencies.items.len > 0) {
        try recommendations.append(json.Value{ .string = "⚠️ Circular dependencies detected - consider refactoring to break cycles" });
    }
    
    if (analysis.unused_functions.items.len > 0) {
        try recommendations.append(json.Value{ .string = "🧹 Unused functions found - consider removing or documenting their purpose" });
    }
    
    if (analysis.complexity_metrics.coupling_factor > 3.0) {
        try recommendations.append(json.Value{ .string = "📈 High coupling detected - consider reducing dependencies between components" });
    }
    
    if (analysis.complexity_metrics.max_depth > 5) {
        try recommendations.append(json.Value{ .string = "🔗 Deep dependency chains found - consider flattening the architecture" });
    }
    
    try json_obj.put("recommendations", json.Value{ .array = recommendations });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Find circular dependencies handler
fn findCircularDependencies(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    var analysis = try analyzer.analyze(&program);
    defer analysis.deinit(allocator);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("cycles_found", json.Value{ .integer = @intCast(analysis.circular_dependencies.items.len) });
    
    var cycles_array = ArrayList(json.Value).init(allocator);
    defer cycles_array.deinit();
    
    for (analysis.circular_dependencies.items) |cycle| {
        var cycle_array = ArrayList(json.Value).init(allocator);
        defer cycle_array.deinit();
        
        for (cycle.items) |node_name| {
            try cycle_array.append(json.Value{ .string = node_name });
        }
        
        var cycle_obj = std.StringArrayHashMap(json.Value).init(allocator);
        defer cycle_obj.deinit();
        try cycle_obj.put("cycle", json.Value{ .array = cycle_array });
        try cycle_obj.put("length", json.Value{ .integer = @intCast(cycle.items.len) });
        
        try cycles_array.append(json.Value{ .object = cycle_obj });
    }
    
    try json_obj.put("cycles", json.Value{ .array = cycles_array });
    
    // Add recommendations for breaking cycles
    var recommendations = ArrayList(json.Value).init(allocator);
    defer recommendations.deinit();
    
    if (analysis.circular_dependencies.items.len > 0) {
        try recommendations.append(json.Value{ .string = "Consider introducing interfaces to break tight coupling" });
        try recommendations.append(json.Value{ .string = "Extract common functionality into separate modules" });
        try recommendations.append(json.Value{ .string = "Use dependency injection to invert control" });
        try recommendations.append(json.Value{ .string = "Consider the Dependency Inversion Principle" });
    } else {
        try recommendations.append(json.Value{ .string = "✅ No circular dependencies found - good architecture!" });
    }
    
    try json_obj.put("recommendations", json.Value{ .array = recommendations });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Find unused functions handler
fn findUnusedFunctions(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    var analysis = try analyzer.analyze(&program);
    defer analysis.deinit(allocator);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("unused_count", json.Value{ .integer = @intCast(analysis.unused_functions.items.len) });
    
    var unused_array = ArrayList(json.Value).init(allocator);
    defer unused_array.deinit();
    
    for (analysis.unused_functions.items) |func_name| {
        var func_obj = std.StringArrayHashMap(json.Value).init(allocator);
        defer func_obj.deinit();
        
        try func_obj.put("name", json.Value{ .string = func_name });
        
        // Get function metadata if available
        if (analysis.dependency_graph.get(func_name)) |node| {
            if (node.metadata.get("parameter_count")) |param_count| {
                try func_obj.put("parameter_count", json.Value{ .string = param_count });
            }
            if (node.metadata.get("body_size")) |body_size| {
                try func_obj.put("body_size", json.Value{ .string = body_size });
            }
        }
        
        try unused_array.append(json.Value{ .object = func_obj });
    }
    
    try json_obj.put("unused_functions", json.Value{ .array = unused_array });
    
    // Add recommendations
    var recommendations = ArrayList(json.Value).init(allocator);
    defer recommendations.deinit();
    
    if (analysis.unused_functions.items.len > 0) {
        try recommendations.append(json.Value{ .string = "Review unused functions - they may be dead code" });
        try recommendations.append(json.Value{ .string = "Consider if functions are meant for external API" });
        try recommendations.append(json.Value{ .string = "Add documentation for utility functions" });
        try recommendations.append(json.Value{ .string = "Remove truly unused code to reduce complexity" });
    } else {
        try recommendations.append(json.Value{ .string = "✅ No unused functions found - clean codebase!" });
    }
    
    try json_obj.put("recommendations", json.Value{ .array = recommendations });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Get dependency graph handler
fn getDependencyGraph(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    const format = if (arguments.object.get("format")) |f| f.string else "json";
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    var analysis = try analyzer.analyze(&program);
    defer analysis.deinit(allocator);
    
    if (std.mem.eql(u8, format, "mermaid")) {
        return try generateMermaidGraph(allocator, &analysis);
    } else if (std.mem.eql(u8, format, "dot")) {
        return try generateDotGraph(allocator, &analysis);
    } else {
        return try generateJsonGraph(allocator, &analysis);
    }
}

/// Generate Mermaid diagram format
fn generateMermaidGraph(allocator: Allocator, analysis: *DependencyAnalysis) ![]const u8 {
    var output = ArrayList(u8).init(allocator);
    defer output.deinit();
    
    const writer = output.writer();
    try writer.writeAll("graph TD\n");
    
    var graph_iter = analysis.dependency_graph.iterator();
    while (graph_iter.next()) |entry| {
        const node_name = entry.key_ptr.*;
        const node = entry.value_ptr.*;
        
        // Add node styling based on type
        const node_style = switch (node.node_type) {
            .function => "[",
            .type_definition => "{",
            .constant => "(",
            else => "[",
        };
        const node_style_end = switch (node.node_type) {
            .function => "]",
            .type_definition => "}",
            .constant => ")",
            else => "]",
        };
        
        for (node.dependencies.items) |dep_name| {
            try writer.print("    {s}{s}{s}{s} --> {s}\n", .{ node_name, node_style, node_name, node_style_end, dep_name });
        }
    }
    
    // Add styling for circular dependencies
    for (analysis.circular_dependencies.items) |cycle| {
        for (cycle.items, 0..) |node_name, i| {
            if (i < cycle.items.len - 1) {
                try writer.print("    {s} -.-> {s}\n", .{ node_name, cycle.items[i + 1] });
            }
        }
    }
    
    try writer.writeAll("\n    classDef function fill:#e1f5fe\n");
    try writer.writeAll("    classDef type fill:#f3e5f5\n");
    try writer.writeAll("    classDef constant fill:#e8f5e8\n");
    
    return try allocator.dupe(u8, output.items);
}

/// Generate DOT format for Graphviz
fn generateDotGraph(allocator: Allocator, analysis: *DependencyAnalysis) ![]const u8 {
    var output = ArrayList(u8).init(allocator);
    defer output.deinit();
    
    const writer = output.writer();
    try writer.writeAll("digraph dependencies {\n");
    try writer.writeAll("    node [shape=box];\n");
    
    var graph_iter = analysis.dependency_graph.iterator();
    while (graph_iter.next()) |entry| {
        const node_name = entry.key_ptr.*;
        const node = entry.value_ptr.*;
        
        // Add node styling
        const color = switch (node.node_type) {
            .function => "lightblue",
            .type_definition => "lightgreen",
            .constant => "lightyellow",
            else => "white",
        };
        
        try writer.print("    \"{s}\" [fillcolor={s}, style=filled];\n", .{ node_name, color });
        
        for (node.dependencies.items) |dep_name| {
            try writer.print("    \"{s}\" -> \"{s}\";\n", .{ node_name, dep_name });
        }
    }
    
    // Highlight circular dependencies
    for (analysis.circular_dependencies.items) |cycle| {
        for (cycle.items, 0..) |node_name, i| {
            if (i < cycle.items.len - 1) {
                try writer.print("    \"{s}\" -> \"{s}\" [color=red, style=dashed];\n", .{ node_name, cycle.items[i + 1] });
            }
        }
    }
    
    try writer.writeAll("}\n");
    
    return try allocator.dupe(u8, output.items);
}

/// Generate JSON format graph
fn generateJsonGraph(allocator: Allocator, analysis: *DependencyAnalysis) ![]const u8 {
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    var nodes_array = ArrayList(json.Value).init(allocator);
    defer nodes_array.deinit();
    
    var edges_array = ArrayList(json.Value).init(allocator);
    defer edges_array.deinit();
    
    var graph_iter = analysis.dependency_graph.iterator();
    while (graph_iter.next()) |entry| {
        const node_name = entry.key_ptr.*;
        const node = entry.value_ptr.*;
        
        // Add node
        var node_obj = std.StringArrayHashMap(json.Value).init(allocator);
        defer node_obj.deinit();
        try node_obj.put("id", json.Value{ .string = node_name });
        try node_obj.put("type", json.Value{ .string = @tagName(node.node_type) });
        try node_obj.put("dependencies_count", json.Value{ .integer = @intCast(node.dependencies.items.len) });
        try node_obj.put("dependents_count", json.Value{ .integer = @intCast(node.dependents.items.len) });
        
        try nodes_array.append(json.Value{ .object = node_obj });
        
        // Add edges
        for (node.dependencies.items) |dep_name| {
            var edge_obj = std.StringArrayHashMap(json.Value).init(allocator);
            defer edge_obj.deinit();
            try edge_obj.put("source", json.Value{ .string = node_name });
            try edge_obj.put("target", json.Value{ .string = dep_name });
            try edge_obj.put("type", json.Value{ .string = "dependency" });
            
            try edges_array.append(json.Value{ .object = edge_obj });
        }
    }
    
    try json_obj.put("nodes", json.Value{ .array = nodes_array });
    try json_obj.put("edges", json.Value{ .array = edges_array });
    try json_obj.put("circular_dependencies", json.Value{ .integer = @intCast(analysis.circular_dependencies.items.len) });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Analyze function dependencies handler
fn analyzeFunctionDependencies(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    const function_name = arguments.object.get("function_name").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    var analysis = try analyzer.analyze(&program);
    defer analysis.deinit(allocator);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("function", json.Value{ .string = function_name });
    
    if (analysis.dependency_graph.get(function_name)) |node| {
        try json_obj.put("dependencies_count", json.Value{ .integer = @intCast(node.dependencies.items.len) });
        try json_obj.put("dependents_count", json.Value{ .integer = @intCast(node.dependents.items.len) });
        
        var deps_array = ArrayList(json.Value).init(allocator);
        defer deps_array.deinit();
        for (node.dependencies.items) |dep| {
            try deps_array.append(json.Value{ .string = dep });
        }
        try json_obj.put("dependencies", json.Value{ .array = deps_array });
        
        var dependents_array = ArrayList(json.Value).init(allocator);
        defer dependents_array.deinit();
        for (node.dependents.items) |dep| {
            try dependents_array.append(json.Value{ .string = dep });
        }
        try json_obj.put("dependents", json.Value{ .array = dependents_array });
        
        // Add metadata
        var metadata_obj = std.StringArrayHashMap(json.Value).init(allocator);
        defer metadata_obj.deinit();
        var meta_iter = node.metadata.iterator();
        while (meta_iter.next()) |entry| {
            try metadata_obj.put(entry.key_ptr.*, json.Value{ .string = entry.value_ptr.* });
        }
        try json_obj.put("metadata", json.Value{ .object = metadata_obj });
    } else {
        try json_obj.put("error", json.Value{ .string = "Function not found" });
    }
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Check dependency health handler
fn checkDependencyHealth(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    var analysis = try analyzer.analyze(&program);
    defer analysis.deinit(allocator);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    // Calculate health score (0-100)
    var health_score: f64 = 100.0;
    
    // Deduct points for issues
    if (analysis.circular_dependencies.items.len > 0) {
        health_score -= @as(f64, @floatFromInt(analysis.circular_dependencies.items.len)) * 20.0;
    }
    
    if (analysis.unused_functions.items.len > 0) {
        health_score -= @as(f64, @floatFromInt(analysis.unused_functions.items.len)) * 5.0;
    }
    
    if (analysis.complexity_metrics.coupling_factor > 3.0) {
        health_score -= (analysis.complexity_metrics.coupling_factor - 3.0) * 10.0;
    }
    
    if (analysis.complexity_metrics.max_depth > 5) {
        health_score -= @as(f64, @floatFromInt(analysis.complexity_metrics.max_depth - 5)) * 5.0;
    }
    
    health_score = @max(0.0, health_score);
    
    try json_obj.put("health_score", json.Value{ .float = health_score });
    
    const health_grade = if (health_score >= 90) "A" else if (health_score >= 80) "B" else if (health_score >= 70) "C" else if (health_score >= 60) "D" else "F";
    try json_obj.put("health_grade", json.Value{ .string = health_grade });
    
    // Issues summary
    var issues_array = ArrayList(json.Value).init(allocator);
    defer issues_array.deinit();
    
    if (analysis.circular_dependencies.items.len > 0) {
        try issues_array.append(json.Value{ .string = "Circular dependencies detected" });
    }
    
    if (analysis.unused_functions.items.len > 0) {
        try issues_array.append(json.Value{ .string = "Unused functions found" });
    }
    
    if (analysis.complexity_metrics.coupling_factor > 3.0) {
        try issues_array.append(json.Value{ .string = "High coupling detected" });
    }
    
    if (analysis.complexity_metrics.max_depth > 5) {
        try issues_array.append(json.Value{ .string = "Deep dependency chains found" });
    }
    
    try json_obj.put("issues", json.Value{ .array = issues_array });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Get reachability analysis handler
fn getReachabilityAnalysis(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    var analysis = try analyzer.analyze(&program);
    defer analysis.deinit(allocator);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("entry_point", json.Value{ .string = program.entry });
    try json_obj.put("reachable_count", json.Value{ .integer = @intCast(analysis.entry_point_reachable.items.len) });
    try json_obj.put("total_functions", json.Value{ .integer = @intCast(program.functions.count()) });
    
    const reachability_percentage = if (program.functions.count() > 0) 
        (@as(f64, @floatFromInt(analysis.entry_point_reachable.items.len)) / @as(f64, @floatFromInt(program.functions.count()))) * 100.0
    else 0.0;
    try json_obj.put("reachability_percentage", json.Value{ .float = reachability_percentage });
    
    var reachable_array = ArrayList(json.Value).init(allocator);
    defer reachable_array.deinit();
    for (analysis.entry_point_reachable.items) |func_name| {
        try reachable_array.append(json.Value{ .string = func_name });
    }
    try json_obj.put("reachable_functions", json.Value{ .array = reachable_array });
    
    // Find unreachable functions
    var unreachable_array = ArrayList(json.Value).init(allocator);
    defer unreachable_array.deinit();
    
    var func_iter = program.functions.iterator();
    while (func_iter.next()) |entry| {
        const func_name = entry.key_ptr.*;
        var is_reachable = std.mem.eql(u8, func_name, program.entry);
        
        if (!is_reachable) {
            for (analysis.entry_point_reachable.items) |reachable_name| {
                if (std.mem.eql(u8, func_name, reachable_name)) {
                    is_reachable = true;
                    break;
                }
            }
        }
        
        if (!is_reachable) {
            try unreachable_array.append(json.Value{ .string = func_name });
        }
    }
    
    try json_obj.put("unreachable_functions", json.Value{ .array = unreachable_array });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}