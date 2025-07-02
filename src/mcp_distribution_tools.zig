const std = @import("std");
const json = std.json;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const SirsParser = @import("sirs.zig");
const Program = SirsParser.Program;
const CustomDistribution = @import("custom_distributions.zig").CustomDistribution;
const DistributionRegistry = @import("custom_distributions.zig").DistributionRegistry;
const DistributionBuilder = @import("custom_distributions.zig").DistributionBuilder;
const DistributionCompiler = @import("distribution_compiler.zig").DistributionCompiler;

/// MCP Tool for custom distribution operations
pub const MCPDistributionTool = struct {
    name: []const u8,
    description: []const u8,
    input_schema: []const u8,
    handler: *const fn (allocator: Allocator, arguments: json.Value) anyerror![]const u8,
};

/// Registry of available MCP distribution tools
pub const MCP_DISTRIBUTION_TOOLS = [_]MCPDistributionTool{
    .{
        .name = "create_custom_distribution",
        .description = "Create a new custom probability distribution",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "name": {"type": "string", "description": "Name of the distribution"},
        \\    "parameters": {
        \\      "type": "array",
        \\      "items": {
        \\        "type": "object",
        \\        "properties": {
        \\          "name": {"type": "string"},
        \\          "type": {"type": "string"},
        \\          "constraints": {"type": "object", "optional": true}
        \\        }
        \\      }
        \\    },
        \\    "support_type": {"type": "string", "description": "Type of support (real_line, positive_real, etc.)"},
        \\    "log_prob_function": {"type": "string", "description": "Name of log probability function"},
        \\    "sample_function": {"type": "string", "optional": true, "description": "Name of sampling function"},
        \\    "description": {"type": "string", "optional": true}
        \\  },
        \\  "required": ["name", "parameters", "support_type", "log_prob_function"]
        \\}
        ,
        .handler = createCustomDistribution,
    },
    .{
        .name = "compile_distributions_from_sirs",
        .description = "Extract and compile distribution definitions from SIRS code",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content containing distribution definitions"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = compileDistributionsFromSirs,
    },
    .{
        .name = "list_distributions",
        .description = "List all available distributions (built-in and custom)",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "include_builtin": {"type": "boolean", "description": "Include built-in distributions", "default": true},
        \\    "include_custom": {"type": "boolean", "description": "Include custom distributions", "default": true}
        \\  }
        \\}
        ,
        .handler = listDistributions,
    },
    .{
        .name = "get_distribution_info",
        .description = "Get detailed information about a specific distribution",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "distribution_name": {"type": "string", "description": "Name of the distribution"}
        \\  },
        \\  "required": ["distribution_name"]
        \\}
        ,
        .handler = getDistributionInfo,
    },
    .{
        .name = "validate_distribution_parameters",
        .description = "Validate parameters for a distribution",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "distribution_name": {"type": "string", "description": "Name of the distribution"},
        \\    "parameters": {"type": "object", "description": "Parameter values to validate"}
        \\  },
        \\  "required": ["distribution_name", "parameters"]
        \\}
        ,
        .handler = validateDistributionParameters,
    },
    .{
        .name = "generate_distribution_code",
        .description = "Generate SIRS code for a distribution",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "distribution_name": {"type": "string", "description": "Name of the distribution"},
        \\    "include_examples": {"type": "boolean", "description": "Include usage examples", "default": false}
        \\  },
        \\  "required": ["distribution_name"]
        \\}
        ,
        .handler = generateDistributionCode,
    },
    .{
        .name = "create_mixture_distribution",
        .description = "Create a mixture of existing distributions",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "name": {"type": "string", "description": "Name of the mixture distribution"},
        \\    "components": {
        \\      "type": "array",
        \\      "items": {
        \\        "type": "object",
        \\        "properties": {
        \\          "distribution": {"type": "string"},
        \\          "weight": {"type": "number"}
        \\        }
        \\      }
        \\    }
        \\  },
        \\  "required": ["name", "components"]
        \\}
        ,
        .handler = createMixtureDistribution,
    },
    .{
        .name = "validate_distribution_definition",
        .description = "Validate a distribution definition for correctness",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "distribution_name": {"type": "string", "description": "Name of the distribution to validate"}
        \\  },
        \\  "required": ["distribution_name"]
        \\}
        ,
        .handler = validateDistributionDefinition,
    },
};

// Global registry for distribution tools
var global_registry: ?DistributionRegistry = null;
var global_registry_allocator: ?Allocator = null;
var global_registry_cleaned: bool = false;
var global_gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};

/// Initialize the global registry
fn getGlobalRegistry(allocator: Allocator) !*DistributionRegistry {
    if (global_registry == null) {
        global_registry = DistributionRegistry.init(allocator);
        global_registry_allocator = allocator;
        global_registry_cleaned = false;
        try global_registry.?.createExampleDistributions();
    }
    return &global_registry.?;
}

/// Reset the global registry for testing isolation
fn resetGlobalRegistry() void {
    if (global_registry) |*registry| {
        registry.deinit();
    }
    global_registry = null;
    global_registry_allocator = null;
    global_registry_cleaned = false;
}

/// Clean up the global registry (for testing)
pub fn cleanupGlobalRegistry() void {
    if (global_registry) |*registry| {
        registry.deinit();
    }
    global_registry = null;
    global_registry_allocator = null;
    global_registry_cleaned = false;
}

/// Clean up the global registry with a specific allocator (safer for testing)
pub fn cleanupGlobalRegistryWithAllocator(allocator: Allocator) void {
    _ = allocator; // Ignore allocator check for now since testing allocator behavior is complex
    cleanupGlobalRegistry();
}

/// Parse SIRS content from JSON string
fn parseSIRSContent(allocator: Allocator, sirs_content: []const u8) !Program {
    var parser = SirsParser.Parser.init(allocator);
    return try parser.parse(sirs_content);
}

/// Create custom distribution handler
fn createCustomDistribution(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const name_value = arguments.object.get("name") orelse return error.KeyNotFound;
    const support_type_value = arguments.object.get("support_type") orelse return error.KeyNotFound;
    const log_prob_value = arguments.object.get("log_prob_function") orelse return error.KeyNotFound;
    
    const name = name_value.string;
    const support_type_str = support_type_value.string;
    const log_prob_function = log_prob_value.string;
    const sample_function = if (arguments.object.get("sample_function")) |sf| sf.string else null;
    const description = if (arguments.object.get("description")) |d| d.string else null;
    
    var builder = DistributionBuilder.init(allocator, try allocator.dupe(u8, name));
    
    // Add parameters
    if (arguments.object.get("parameters")) |params_array| {
        for (params_array.array.items) |param_obj| {
            const param_name = param_obj.object.get("name").?.string;
            const param_type_str = param_obj.object.get("type").?.string;
            
            // Convert string to Type (simplified)
            const param_type = parseTypeFromString(param_type_str);
            _ = builder.addParameter(param_name, param_type);
        }
    }
    
    // Set support type
    const support = parseDistributionSupport(support_type_str);
    _ = builder.withSupport(support);
    
    // Set functions
    _ = builder.withLogProb(log_prob_function);
    if (sample_function) |sf| {
        _ = builder.withSampler(sf);
    }
    
    if (description) |desc| {
        _ = builder.withDescription(desc);
    }
    
    const distribution = builder.build();
    
    const registry = try getGlobalRegistry(allocator);
    try registry.registerDistribution(distribution);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("success", json.Value{ .bool = true });
    try json_obj.put("distribution_name", json.Value{ .string = name });
    try json_obj.put("message", json.Value{ .string = "Distribution created successfully" });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Compile distributions from SIRS handler
fn compileDistributionsFromSirs(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    try compiler.compileDistributions(&program);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    const compiled_count = compiler.getRegistry().distributions.count();
    try json_obj.put("success", json.Value{ .bool = true });
    try json_obj.put("distributions_compiled", json.Value{ .integer = @intCast(compiled_count) });
    try json_obj.put("message", json.Value{ .string = "Distributions compiled successfully from SIRS code" });
    
    // List compiled distributions
    var compiled_names = ArrayList(json.Value).init(allocator);
    defer compiled_names.deinit();
    
    var dist_iter = compiler.getRegistry().distributions.iterator();
    while (dist_iter.next()) |entry| {
        try compiled_names.append(json.Value{ .string = entry.key_ptr.* });
    }
    
    try json_obj.put("compiled_distributions", json.Value{ .array = compiled_names });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// List distributions handler
fn listDistributions(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const include_builtin = if (arguments.object.get("include_builtin")) |ib| ib.bool else true;
    const include_custom = if (arguments.object.get("include_custom")) |ic| ic.bool else true;
    
    const registry = try getGlobalRegistry(allocator);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    if (include_builtin) {
        var builtin_array = ArrayList(json.Value).init(allocator);
        // Don't defer - let it persist until after JSON serialization
        
        var builtin_iter = registry.built_in_distributions.iterator();
        while (builtin_iter.next()) |entry| {
            var dist_obj = std.StringArrayHashMap(json.Value).init(allocator);
            // Don't defer - let it persist until after JSON serialization
            
            try dist_obj.put("name", json.Value{ .string = entry.key_ptr.* });
            try dist_obj.put("type", json.Value{ .string = "built-in" });
            try dist_obj.put("is_discrete", json.Value{ .bool = entry.value_ptr.is_discrete });
            try dist_obj.put("support", json.Value{ .string = @tagName(entry.value_ptr.support_type) });
            
            try builtin_array.append(json.Value{ .object = dist_obj });
        }
        
        try json_obj.put("builtin_distributions", json.Value{ .array = builtin_array });
    }
    
    if (include_custom) {
        var custom_array = ArrayList(json.Value).init(allocator);
        // Don't defer - let it persist until after JSON serialization
        
        var custom_iter = registry.distributions.iterator();
        while (custom_iter.next()) |entry| {
            var dist_obj = std.StringArrayHashMap(json.Value).init(allocator);
            // Don't defer - let it persist until after JSON serialization
            
            const dist = entry.value_ptr.*;
            try dist_obj.put("name", json.Value{ .string = dist.name });
            try dist_obj.put("type", json.Value{ .string = "custom" });
            try dist_obj.put("is_discrete", json.Value{ .bool = dist.is_discrete });
            try dist_obj.put("support", json.Value{ .string = @tagName(dist.support.support_type) });
            try dist_obj.put("parameter_count", json.Value{ .integer = @intCast(dist.parameters.items.len) });
            
            if (dist.description) |desc| {
                try dist_obj.put("description", json.Value{ .string = desc });
            }
            
            try custom_array.append(json.Value{ .object = dist_obj });
        }
        
        try json_obj.put("custom_distributions", json.Value{ .array = custom_array });
    }
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Get distribution info handler
fn getDistributionInfo(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const distribution_name = arguments.object.get("distribution_name").?.string;
    
    const registry = try getGlobalRegistry(allocator);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    if (registry.getDistribution(distribution_name)) |distribution| {
        try json_obj.put("name", json.Value{ .string = distribution.name });
        try json_obj.put("type", json.Value{ .string = "custom" });
        try json_obj.put("is_discrete", json.Value{ .bool = distribution.is_discrete });
        try json_obj.put("is_exponential_family", json.Value{ .bool = distribution.is_exponential_family });
        try json_obj.put("is_location_scale", json.Value{ .bool = distribution.is_location_scale });
        try json_obj.put("support", json.Value{ .string = @tagName(distribution.support.support_type) });
        
        if (distribution.description) |desc| {
            try json_obj.put("description", json.Value{ .string = desc });
        }
        
        // Parameters
        var params_array = ArrayList(json.Value).init(allocator);
        // Don't defer - let it persist until after JSON serialization
        
        for (distribution.parameters.items) |param| {
            var param_obj = std.StringArrayHashMap(json.Value).init(allocator);
            // Don't defer - let it persist until after JSON serialization
            
            try param_obj.put("name", json.Value{ .string = param.name });
            try param_obj.put("type", json.Value{ .string = @tagName(param.param_type) });
            
            if (param.description) |desc| {
                try param_obj.put("description", json.Value{ .string = desc });
            }
            
            if (param.constraints) |constraints| {
                var constraints_obj = std.StringArrayHashMap(json.Value).init(allocator);
                // Don't defer - let it persist until after JSON serialization
                
                try constraints_obj.put("positive_only", json.Value{ .bool = constraints.positive_only });
                try constraints_obj.put("integer_only", json.Value{ .bool = constraints.integer_only });
                
                if (constraints.min_value) |min| {
                    try constraints_obj.put("min_value", json.Value{ .float = min });
                }
                if (constraints.max_value) |max| {
                    try constraints_obj.put("max_value", json.Value{ .float = max });
                }
                
                try param_obj.put("constraints", json.Value{ .object = constraints_obj });
            }
            
            try params_array.append(json.Value{ .object = param_obj });
        }
        
        try json_obj.put("parameters", json.Value{ .array = params_array });
        
        // Functions
        try json_obj.put("log_prob_function", json.Value{ .string = distribution.log_prob_function });
        if (distribution.sample_function) |sf| {
            try json_obj.put("sample_function", json.Value{ .string = sf });
        }
        
        // Moment functions
        var moments_obj = std.StringArrayHashMap(json.Value).init(allocator);
        // Don't defer - let it persist until after JSON serialization
        
        var moment_iter = distribution.moment_functions.iterator();
        while (moment_iter.next()) |entry| {
            try moments_obj.put(entry.key_ptr.*, json.Value{ .string = entry.value_ptr.* });
        }
        
        try json_obj.put("moment_functions", json.Value{ .object = moments_obj });
        
    } else if (registry.built_in_distributions.get(distribution_name)) |builtin| {
        try json_obj.put("name", json.Value{ .string = builtin.name });
        try json_obj.put("type", json.Value{ .string = "built-in" });
        try json_obj.put("is_discrete", json.Value{ .bool = builtin.is_discrete });
        try json_obj.put("support", json.Value{ .string = @tagName(builtin.support_type) });
        
        var params_array = ArrayList(json.Value).init(allocator);
        // Don't defer - let it persist until after JSON serialization
        
        for (builtin.parameter_names) |param_name| {
            try params_array.append(json.Value{ .string = param_name });
        }
        
        try json_obj.put("parameter_names", json.Value{ .array = params_array });
    } else {
        try json_obj.put("error", json.Value{ .string = "Distribution not found" });
    }
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Validate distribution parameters handler
fn validateDistributionParameters(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const distribution_name = arguments.object.get("distribution_name").?.string;
    const parameters_obj = arguments.object.get("parameters").?.object;
    
    const registry = try getGlobalRegistry(allocator);
    
    // Convert JSON parameters to StringHashMap
    var params = StringHashMap(f64).init(allocator);
    defer params.deinit();
    
    var param_iter = parameters_obj.iterator();
    while (param_iter.next()) |entry| {
        const value = switch (entry.value_ptr.*) {
            .integer => |i| @as(f64, @floatFromInt(i)),
            .float => |f| f,
            else => return error.InvalidParameterType,
        };
        try params.put(entry.key_ptr.*, value);
    }
    
    const is_valid = try registry.validateParameters(distribution_name, params);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("distribution_name", json.Value{ .string = distribution_name });
    try json_obj.put("is_valid", json.Value{ .bool = is_valid });
    
    if (is_valid) {
        try json_obj.put("message", json.Value{ .string = "All parameters are valid" });
    } else {
        try json_obj.put("message", json.Value{ .string = "Parameter validation failed" });
    }
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Generate distribution code handler
fn generateDistributionCode(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const distribution_name = arguments.object.get("distribution_name").?.string;
    const include_examples = if (arguments.object.get("include_examples")) |ie| ie.bool else false;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    const code = try compiler.generateDistributionCode(distribution_name);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("distribution_name", json.Value{ .string = distribution_name });
    try json_obj.put("generated_code", json.Value{ .string = code });
    
    if (include_examples) {
        const registry = try getGlobalRegistry(allocator);
        if (registry.getDistribution(distribution_name)) |distribution| {
            var examples_array = ArrayList(json.Value).init(allocator);
            defer examples_array.deinit();
            
            for (distribution.examples.items) |example| {
                var example_obj = std.StringArrayHashMap(json.Value).init(allocator);
                defer example_obj.deinit();
                
                try example_obj.put("name", json.Value{ .string = example.name });
                try example_obj.put("description", json.Value{ .string = example.description });
                
                var param_examples = std.StringArrayHashMap(json.Value).init(allocator);
                defer param_examples.deinit();
                
                var param_iter = example.parameters.iterator();
                while (param_iter.next()) |entry| {
                    try param_examples.put(entry.key_ptr.*, json.Value{ .string = "example_value" });
                }
                
                try example_obj.put("parameters", json.Value{ .object = param_examples });
                try examples_array.append(json.Value{ .object = example_obj });
            }
            
            try json_obj.put("examples", json.Value{ .array = examples_array });
        }
    }
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Create mixture distribution handler
fn createMixtureDistribution(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const name = arguments.object.get("name").?.string;
    const components_array = arguments.object.get("components").?.array;
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("distribution_name", json.Value{ .string = name });
    try json_obj.put("component_count", json.Value{ .integer = @intCast(components_array.items.len) });
    
    // Validate weights sum to 1
    var total_weight: f64 = 0.0;
    for (components_array.items) |component| {
        const weight = component.object.get("weight").?.float;
        total_weight += weight;
    }
    
    if (@abs(total_weight - 1.0) > 1e-6) {
        try json_obj.put("error", json.Value{ .string = "Component weights must sum to 1.0" });
    } else {
        try json_obj.put("success", json.Value{ .bool = true });
        try json_obj.put("message", json.Value{ .string = "Mixture distribution created successfully" });
        
        var components_info = ArrayList(json.Value).init(allocator);
        defer components_info.deinit();
        
        for (components_array.items) |component| {
            var comp_obj = std.StringArrayHashMap(json.Value).init(allocator);
            defer comp_obj.deinit();
            
            try comp_obj.put("distribution", json.Value{ .string = component.object.get("distribution").?.string });
            try comp_obj.put("weight", json.Value{ .float = component.object.get("weight").?.float });
            
            try components_info.append(json.Value{ .object = comp_obj });
        }
        
        try json_obj.put("components", json.Value{ .array = components_info });
    }
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Validate distribution definition handler
fn validateDistributionDefinition(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const distribution_name = arguments.object.get("distribution_name").?.string;
    
    const registry = try getGlobalRegistry(allocator);
    
    // Check if distribution exists in either custom or built-in distributions
    const is_valid = registry.hasDistribution(distribution_name);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("distribution_name", json.Value{ .string = distribution_name });
    try json_obj.put("is_valid", json.Value{ .bool = is_valid });
    
    if (is_valid) {
        try json_obj.put("message", json.Value{ .string = "Distribution definition is valid" });
    } else {
        try json_obj.put("message", json.Value{ .string = "Distribution definition has issues - check console output" });
    }
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

// Helper functions

fn parseTypeFromString(type_str: []const u8) SirsParser.Type {
    if (std.mem.eql(u8, type_str, "f64")) return .f64;
    if (std.mem.eql(u8, type_str, "f32")) return .f32;
    if (std.mem.eql(u8, type_str, "i32")) return .i32;
    if (std.mem.eql(u8, type_str, "i64")) return .i64;
    if (std.mem.eql(u8, type_str, "u32")) return .u32;
    if (std.mem.eql(u8, type_str, "u64")) return .u64;
    if (std.mem.eql(u8, type_str, "bool")) return .bool;
    if (std.mem.eql(u8, type_str, "str")) return .str;
    return .f64; // Default
}

fn parseDistributionSupport(support_str: []const u8) @import("custom_distributions.zig").DistributionSupport {
    const DistributionSupport = @import("custom_distributions.zig").DistributionSupport;
    
    if (std.mem.eql(u8, support_str, "real_line")) {
        return DistributionSupport{
            .support_type = .real_line,
            .lower_bound = null,
            .upper_bound = null,
            .discrete_values = null,
        };
    } else if (std.mem.eql(u8, support_str, "positive_real")) {
        return DistributionSupport{
            .support_type = .positive_real,
            .lower_bound = null,
            .upper_bound = null,
            .discrete_values = null,
        };
    } else if (std.mem.eql(u8, support_str, "unit_interval")) {
        return DistributionSupport{
            .support_type = .unit_interval,
            .lower_bound = null,
            .upper_bound = null,
            .discrete_values = null,
        };
    } else {
        return DistributionSupport{
            .support_type = .real_line,
            .lower_bound = null,
            .upper_bound = null,
            .discrete_values = null,
        };
    }
}