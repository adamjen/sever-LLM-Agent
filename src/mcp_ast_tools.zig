const std = @import("std");
const json = std.json;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const SirsParser = @import("sirs.zig");
const Program = SirsParser.Program;
const Function = SirsParser.Function;
const Statement = SirsParser.Statement;
const ASTQueryEngine = @import("ast_query.zig").ASTQueryEngine;
const ASTManipulator = @import("ast_query.zig").ASTManipulator;
const ASTCodegen = @import("ast_query.zig").ASTCodegen;
const QueryResult = @import("ast_query.zig").QueryResult;
const FunctionInfo = @import("ast_query.zig").FunctionInfo;

/// MCP Tool for AST operations
pub const MCPASTTool = struct {
    name: []const u8,
    description: []const u8,
    input_schema: []const u8,
    handler: *const fn (allocator: Allocator, arguments: json.Value) anyerror![]const u8,
};

/// Registry of available MCP AST tools
pub const MCP_AST_TOOLS = [_]MCPASTTool{
    .{
        .name = "query_functions",
        .description = "Find functions in Sever code matching a pattern",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
        \\    "pattern": {"type": "string", "description": "Optional pattern to match function names"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = queryFunctions,
    },
    .{
        .name = "query_variables",
        .description = "Find variables in Sever code matching a pattern",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
        \\    "pattern": {"type": "string", "description": "Optional pattern to match variable names"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = queryVariables,
    },
    .{
        .name = "query_function_calls",
        .description = "Find function calls in Sever code matching a pattern",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
        \\    "pattern": {"type": "string", "description": "Optional pattern to match function call names"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = queryFunctionCalls,
    },
    .{
        .name = "get_function_info",
        .description = "Get detailed information about a specific function",
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
        .handler = getFunctionInfo,
    },
    .{
        .name = "rename_function",
        .description = "Rename a function and update all references",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to modify"},
        \\    "old_name": {"type": "string", "description": "Current function name"},
        \\    "new_name": {"type": "string", "description": "New function name"}
        \\  },
        \\  "required": ["sirs_content", "old_name", "new_name"]
        \\}
        ,
        .handler = renameFunction,
    },
    .{
        .name = "add_function",
        .description = "Add a new function to the program",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to modify"},
        \\    "function_name": {"type": "string", "description": "Name of the new function"},
        \\    "parameters": {"type": "array", "description": "Function parameters"},
        \\    "return_type": {"type": "string", "description": "Return type"}
        \\  },
        \\  "required": ["sirs_content", "function_name", "return_type"]
        \\}
        ,
        .handler = addFunction,
    },
    .{
        .name = "remove_function",
        .description = "Remove a function from the program",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to modify"},
        \\    "function_name": {"type": "string", "description": "Name of the function to remove"}
        \\  },
        \\  "required": ["sirs_content", "function_name"]
        \\}
        ,
        .handler = removeFunction,
    },
    .{
        .name = "analyze_complexity",
        .description = "Analyze code complexity metrics",
        .input_schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"}
        \\  },
        \\  "required": ["sirs_content"]
        \\}
        ,
        .handler = analyzeComplexity,
    },
};

/// Parse SIRS content from JSON string
fn parseSIRSContent(allocator: Allocator, sirs_content: []const u8) !Program {
    var parser = SirsParser.Parser.init(allocator);
    return try parser.parse(sirs_content);
}

/// Convert query results to JSON
fn queryResultsToJSON(allocator: Allocator, results: []QueryResult) ![]const u8 {
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    var results_array = ArrayList(json.Value).init(allocator);
    defer results_array.deinit();
    
    for (results) |result| {
        var result_obj = std.StringArrayHashMap(json.Value).init(allocator);
        defer result_obj.deinit();
        
        try result_obj.put("type", json.Value{ .string = @tagName(result.node_type) });
        try result_obj.put("content", json.Value{ .string = result.content });
        try result_obj.put("function", json.Value{ .string = result.location.function_name });
        try result_obj.put("line", json.Value{ .integer = result.location.line });
        try result_obj.put("context", json.Value{ .string = result.location.context });
        
        if (result.metadata) |meta| {
            try result_obj.put("metadata", json.Value{ .string = meta });
        }
        
        try results_array.append(json.Value{ .object = result_obj });
    }
    
    try json_obj.put("results", json.Value{ .array = results_array });
    try json_obj.put("count", json.Value{ .integer = @intCast(results.len) });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Query functions handler
fn queryFunctions(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    const pattern = if (arguments.object.get("pattern")) |p| p.string else null;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var query_engine = ASTQueryEngine.init(allocator);
    const results = try query_engine.findFunctions(&program, pattern);
    defer query_engine.freeResults(results);
    
    return try queryResultsToJSON(allocator, results);
}

/// Query variables handler
fn queryVariables(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    const pattern = if (arguments.object.get("pattern")) |p| p.string else null;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var query_engine = ASTQueryEngine.init(allocator);
    const results = try query_engine.findVariables(&program, pattern);
    defer query_engine.freeResults(results);
    
    return try queryResultsToJSON(allocator, results);
}

/// Query function calls handler
fn queryFunctionCalls(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    const pattern = if (arguments.object.get("pattern")) |p| p.string else null;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var query_engine = ASTQueryEngine.init(allocator);
    const results = try query_engine.findFunctionCalls(&program, pattern);
    defer query_engine.freeResults(results);
    
    return try queryResultsToJSON(allocator, results);
}

/// Get function info handler
fn getFunctionInfo(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    const function_name = arguments.object.get("function_name").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var query_engine = ASTQueryEngine.init(allocator);
    
    if (try query_engine.getFunctionInfo(&program, function_name)) |func_info| {
        defer {
            var mutable_info = func_info;
            mutable_info.deinit(allocator);
        }
        
        var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
        defer json_obj.deinit();
        
        try json_obj.put("name", json.Value{ .string = func_info.name });
        try json_obj.put("return_type", json.Value{ .string = func_info.return_type });
        try json_obj.put("parameter_count", json.Value{ .integer = @intCast(func_info.parameters.len) });
        try json_obj.put("body_size", json.Value{ .integer = @intCast(func_info.body_size) });
        try json_obj.put("is_inline", json.Value{ .bool = func_info.is_inline });
        try json_obj.put("is_pure", json.Value{ .bool = func_info.is_pure });
        
        var params_array = ArrayList(json.Value).init(allocator);
        defer params_array.deinit();
        
        for (func_info.parameters) |param| {
            var param_obj = std.StringArrayHashMap(json.Value).init(allocator);
            defer param_obj.deinit();
            
            try param_obj.put("name", json.Value{ .string = param.name });
            try param_obj.put("type", json.Value{ .string = param.type_name });
            
            try params_array.append(json.Value{ .object = param_obj });
        }
        
        try json_obj.put("parameters", json.Value{ .array = params_array });
        
        var json_output = ArrayList(u8).init(allocator);
        defer json_output.deinit();
        
        try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
        return try allocator.dupe(u8, json_output.items);
    } else {
        return try allocator.dupe(u8, "{\"error\": \"Function not found\"}");
    }
}

/// Rename function handler
fn renameFunction(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    const old_name = arguments.object.get("old_name").?.string;
    const new_name = arguments.object.get("new_name").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var manipulator = ASTManipulator.init(allocator);
    const success = try manipulator.renameFunction(&program, old_name, new_name);
    
    if (success) {
        var codegen = ASTCodegen.init(allocator);
        defer codegen.deinit();
        
        const modified_sirs = try codegen.generateSIRS(&program);
        defer allocator.free(modified_sirs);
        
        var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
        defer json_obj.deinit();
        
        try json_obj.put("success", json.Value{ .bool = true });
        try json_obj.put("modified_sirs", json.Value{ .string = modified_sirs });
        try json_obj.put("message", json.Value{ .string = "Function renamed successfully" });
        
        var json_output = ArrayList(u8).init(allocator);
        defer json_output.deinit();
        
        try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
        return try allocator.dupe(u8, json_output.items);
    } else {
        return try allocator.dupe(u8, "{\"success\": false, \"error\": \"Function not found\"}");
    }
}

/// Add function handler
fn addFunction(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    const function_name = arguments.object.get("function_name").?.string;
    const return_type = arguments.object.get("return_type").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    // Create a new empty function
    var new_function = Function{
        .args = ArrayList(SirsParser.Parameter).init(allocator),
        .@"return" = parseTypeFromString(return_type),
        .body = ArrayList(Statement).init(allocator),
    };
    
    // Add parameters if provided
    if (arguments.object.get("parameters")) |params_value| {
        for (params_value.array.items) |param_value| {
            const param_name = param_value.object.get("name").?.string;
            const param_type = param_value.object.get("type").?.string;
            
            const param = SirsParser.Parameter{
                .name = try allocator.dupe(u8, param_name),
                .type = parseTypeFromString(param_type),
            };
            try new_function.args.append(param);
        }
    }
    
    var manipulator = ASTManipulator.init(allocator);
    try manipulator.addFunction(&program, function_name, new_function);
    
    var codegen = ASTCodegen.init(allocator);
    defer codegen.deinit();
    
    const modified_sirs = try codegen.generateSIRS(&program);
    defer allocator.free(modified_sirs);
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("success", json.Value{ .bool = true });
    try json_obj.put("modified_sirs", json.Value{ .string = modified_sirs });
    try json_obj.put("message", json.Value{ .string = "Function added successfully" });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Remove function handler
fn removeFunction(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    const function_name = arguments.object.get("function_name").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var manipulator = ASTManipulator.init(allocator);
    const success = manipulator.removeFunction(&program, function_name);
    
    if (success) {
        var codegen = ASTCodegen.init(allocator);
        defer codegen.deinit();
        
        const modified_sirs = try codegen.generateSIRS(&program);
        defer allocator.free(modified_sirs);
        
        var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
        defer json_obj.deinit();
        
        try json_obj.put("success", json.Value{ .bool = true });
        try json_obj.put("modified_sirs", json.Value{ .string = modified_sirs });
        try json_obj.put("message", json.Value{ .string = "Function removed successfully" });
        
        var json_output = ArrayList(u8).init(allocator);
        defer json_output.deinit();
        
        try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
        return try allocator.dupe(u8, json_output.items);
    } else {
        return try allocator.dupe(u8, "{\"success\": false, \"error\": \"Function not found\"}");
    }
}

/// Analyze complexity handler
fn analyzeComplexity(allocator: Allocator, arguments: json.Value) ![]const u8 {
    const sirs_content = arguments.object.get("sirs_content").?.string;
    
    var program = try parseSIRSContent(allocator, sirs_content);
    defer program.deinit();
    
    var json_obj = std.StringArrayHashMap(json.Value).init(allocator);
    defer json_obj.deinit();
    
    try json_obj.put("total_functions", json.Value{ .integer = @intCast(program.functions.count()) });
    
    var func_complexities = ArrayList(json.Value).init(allocator);
    defer func_complexities.deinit();
    
    var func_iter = program.functions.iterator();
    while (func_iter.next()) |entry| {
        const func_name = entry.key_ptr.*;
        const function = entry.value_ptr;
        
        var func_obj = std.StringArrayHashMap(json.Value).init(allocator);
        defer func_obj.deinit();
        
        try func_obj.put("name", json.Value{ .string = func_name });
        try func_obj.put("parameters", json.Value{ .integer = @intCast(function.args.items.len) });
        try func_obj.put("statements", json.Value{ .integer = @intCast(function.body.items.len) });
        try func_obj.put("is_inline", json.Value{ .bool = function.@"inline" });
        try func_obj.put("is_pure", json.Value{ .bool = function.pure });
        
        // Calculate complexity metrics
        const complexity = calculateCyclomaticComplexity(function);
        try func_obj.put("cyclomatic_complexity", json.Value{ .integer = @intCast(complexity) });
        
        try func_complexities.append(json.Value{ .object = func_obj });
    }
    
    try json_obj.put("functions", json.Value{ .array = func_complexities });
    
    var json_output = ArrayList(u8).init(allocator);
    defer json_output.deinit();
    
    try json.stringify(json.Value{ .object = json_obj }, .{}, json_output.writer());
    return try allocator.dupe(u8, json_output.items);
}

/// Parse type from string
fn parseTypeFromString(type_str: []const u8) SirsParser.Type {
    if (std.mem.eql(u8, type_str, "void")) return .void;
    if (std.mem.eql(u8, type_str, "i32")) return .i32;
    if (std.mem.eql(u8, type_str, "i64")) return .i64;
    if (std.mem.eql(u8, type_str, "f32")) return .f32;
    if (std.mem.eql(u8, type_str, "f64")) return .f64;
    if (std.mem.eql(u8, type_str, "bool")) return .bool;
    if (std.mem.eql(u8, type_str, "str")) return .str;
    return .void; // Default fallback
}

/// Calculate cyclomatic complexity of a function
fn calculateCyclomaticComplexity(function: *Function) u32 {
    var complexity: u32 = 1; // Base complexity
    
    for (function.body.items) |*stmt| {
        complexity += calculateStatementComplexity(stmt);
    }
    
    return complexity;
}

/// Calculate complexity contribution of a statement
fn calculateStatementComplexity(stmt: *Statement) u32 {
    return switch (stmt.*) {
        .@"if" => |if_stmt| {
            var complexity: u32 = 1; // if adds 1
            for (if_stmt.then.items) |*then_stmt| {
                complexity += calculateStatementComplexity(then_stmt);
            }
            if (if_stmt.@"else") |else_stmts| {
                for (else_stmts.items) |*else_stmt| {
                    complexity += calculateStatementComplexity(else_stmt);
                }
            }
            return complexity;
        },
        .@"while" => |while_stmt| {
            var complexity: u32 = 1; // while adds 1
            for (while_stmt.body.items) |*body_stmt| {
                complexity += calculateStatementComplexity(body_stmt);
            }
            return complexity;
        },
        else => 0,
    };
}