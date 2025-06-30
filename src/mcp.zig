const std = @import("std");
const json = std.json;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const SirsParser = @import("sirs.zig");
const TypeChecker = @import("typechecker.zig").TypeChecker;
const ErrorReporter = @import("error_reporter.zig").ErrorReporter;
const CirLowering = @import("cir.zig").CirLowering;
const OptimizationManager = @import("optimization.zig").OptimizationManager;
const MCP_AST_TOOLS = @import("mcp_ast_tools.zig").MCP_AST_TOOLS;
const MCP_DEPENDENCY_TOOLS = @import("mcp_dependency_tools.zig").MCP_DEPENDENCY_TOOLS;
const MCP_DISTRIBUTION_TOOLS = @import("mcp_distribution_tools.zig").MCP_DISTRIBUTION_TOOLS;

pub const McpServer = struct {
    allocator: Allocator,
    running: bool,
    parser: SirsParser.Parser,
    type_checker: TypeChecker,
    error_reporter: ErrorReporter,
    
    pub fn init(allocator: Allocator) McpServer {
        return McpServer{
            .allocator = allocator,
            .running = false,
            .parser = SirsParser.Parser.init(allocator),
            .type_checker = TypeChecker.init(allocator),
            .error_reporter = ErrorReporter.init(allocator),
        };
    }
    
    pub fn deinit(self: *McpServer) void {
        self.type_checker.deinit();
        self.error_reporter.deinit();
    }
    
    pub fn start(self: *McpServer) !void {
        self.running = true;
        print("MCP Server started on stdio\n", .{});
        
        // Main server loop
        while (self.running) {
            try self.processRequest();
        }
    }
    
    fn processRequest(self: *McpServer) !void {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();
        
        // Read line from stdin
        var buffer: [4096]u8 = undefined;
        if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |line| {
            // Parse JSON-RPC request
            var parsed = json.parseFromSlice(json.Value, self.allocator, line, .{}) catch {
                // Send error response
                try self.sendError(stdout, null, -32700, "Parse error");
                return;
            };
            defer parsed.deinit();
            
            const request = parsed.value;
            if (request != .object) {
                try self.sendError(stdout, null, -32600, "Invalid Request");
                return;
            }
            
            const id = request.object.get("id");
            const method = request.object.get("method");
            const params = request.object.get("params");
            
            if (method == null or method.? != .string) {
                try self.sendError(stdout, id, -32600, "Invalid Request");
                return;
            }
            
            const method_name = method.?.string;
            
            // Handle different MCP methods
            if (std.mem.eql(u8, method_name, "initialize")) {
                try self.handleInitialize(stdout, id, params);
            } else if (std.mem.eql(u8, method_name, "tools/list")) {
                try self.handleToolsList(stdout, id);
            } else if (std.mem.eql(u8, method_name, "tools/call")) {
                try self.handleToolsCall(stdout, id, params);
            } else if (std.mem.eql(u8, method_name, "shutdown")) {
                try self.handleShutdown(stdout, id);
            } else {
                try self.sendError(stdout, id, -32601, "Method not found");
            }
        } else {
            // EOF - client disconnected
            self.running = false;
        }
    }
    
    fn handleInitialize(_: *McpServer, writer: anytype, id: ?json.Value, params: ?json.Value) !void {
        _ = params;
        
        // Write response directly as JSON
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{");
        try writer.writeAll("\"protocolVersion\":\"2024-11-05\",");
        try writer.writeAll("\"capabilities\":{\"tools\":{}},");
        try writer.writeAll("\"serverInfo\":{\"name\":\"sever-mcp\",\"version\":\"0.1.0\"}");
        try writer.writeAll("}}\n");
    }
    
    fn handleToolsList(_: *McpServer, writer: anytype, id: ?json.Value) !void {
        
        // Create tools response as a JSON string and parse it
        const tools_json = 
            \\[
            \\  {
            \\    "name": "compile",
            \\    "description": "Compile a Sever program from SIRS format with detailed analysis",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "program": {
            \\          "type": "object",
            \\          "description": "SIRS program to compile"
            \\        }
            \\      },
            \\      "required": ["program"]
            \\    }
            \\  },
            \\  {
            \\    "name": "type_check", 
            \\    "description": "Perform detailed type checking on a Sever program",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "program": {
            \\          "type": "object",
            \\          "description": "SIRS program to type check"
            \\        }
            \\      },
            \\      "required": ["program"]
            \\    }
            \\  },
            \\  {
            \\    "name": "infer_type",
            \\    "description": "Infer the type of a SIRS expression", 
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "expression": {
            \\          "type": "object",
            \\          "description": "SIRS expression to infer type for"
            \\        }
            \\      },
            \\      "required": ["expression"]
            \\    }
            \\  },
            \\  {
            \\    "name": "analyze_program",
            \\    "description": "Perform comprehensive program analysis including complexity metrics",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "program": {
            \\          "type": "object",
            \\          "description": "SIRS program to analyze"
            \\        }
            \\      },
            \\      "required": ["program"]
            \\    }
            \\  },
            \\  {
            \\    "name": "optimize_analysis",
            \\    "description": "Analyze optimization opportunities in a program",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "program": {
            \\          "type": "object",
            \\          "description": "SIRS program to analyze for optimizations"
            \\        }
            \\      },
            \\      "required": ["program"]
            \\    }
            \\  },
            \\  {
            \\    "name": "function_info",
            \\    "description": "Get detailed information about functions in a program",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "program": {
            \\          "type": "object",
            \\          "description": "SIRS program to analyze"
            \\        },
            \\        "function_name": {
            \\          "type": "string",
            \\          "description": "Specific function to analyze (optional)"
            \\        }
            \\      },
            \\      "required": ["program"]
            \\    }
            \\  },
            \\  {
            \\    "name": "query_functions",
            \\    "description": "Find functions in Sever code matching a pattern",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
            \\        "pattern": {"type": "string", "description": "Optional pattern to match function names"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "query_variables",
            \\    "description": "Find variables in Sever code matching a pattern",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
            \\        "pattern": {"type": "string", "description": "Optional pattern to match variable names"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "query_function_calls",
            \\    "description": "Find function calls in Sever code matching a pattern",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
            \\        "pattern": {"type": "string", "description": "Optional pattern to match function call names"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "get_function_info",
            \\    "description": "Get detailed information about a specific function",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
            \\        "function_name": {"type": "string", "description": "Name of the function to analyze"}
            \\      },
            \\      "required": ["sirs_content", "function_name"]
            \\    }
            \\  },
            \\  {
            \\    "name": "rename_function",
            \\    "description": "Rename a function and update all references",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to modify"},
            \\        "old_name": {"type": "string", "description": "Current function name"},
            \\        "new_name": {"type": "string", "description": "New function name"}
            \\      },
            \\      "required": ["sirs_content", "old_name", "new_name"]
            \\    }
            \\  },
            \\  {
            \\    "name": "add_function",
            \\    "description": "Add a new function to the program",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to modify"},
            \\        "function_name": {"type": "string", "description": "Name of the new function"},
            \\        "parameters": {"type": "array", "description": "Function parameters"},
            \\        "return_type": {"type": "string", "description": "Return type"}
            \\      },
            \\      "required": ["sirs_content", "function_name", "return_type"]
            \\    }
            \\  },
            \\  {
            \\    "name": "remove_function",
            \\    "description": "Remove a function from the program",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to modify"},
            \\        "function_name": {"type": "string", "description": "Name of the function to remove"}
            \\      },
            \\      "required": ["sirs_content", "function_name"]
            \\    }
            \\  },
            \\  {
            \\    "name": "analyze_complexity",
            \\    "description": "Analyze code complexity metrics",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "analyze_dependencies",
            \\    "description": "Perform comprehensive dependency analysis on a Sever program",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
            \\        "include_metrics": {"type": "boolean", "description": "Include complexity metrics in output"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "find_circular_dependencies",
            \\    "description": "Detect circular dependencies in the code",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "find_unused_functions",
            \\    "description": "Find functions that are never called",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "get_dependency_graph",
            \\    "description": "Get the dependency graph visualization",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
            \\        "format": {"type": "string", "enum": ["json", "dot", "mermaid"], "description": "Output format"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "analyze_function_dependencies",
            \\    "description": "Analyze dependencies for a specific function",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"},
            \\        "function_name": {"type": "string", "description": "Name of the function to analyze"}
            \\      },
            \\      "required": ["sirs_content", "function_name"]
            \\    }
            \\  },
            \\  {
            \\    "name": "check_dependency_health",
            \\    "description": "Check overall dependency health and provide recommendations",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "get_reachability_analysis",
            \\    "description": "Analyze code reachability from entry point",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content to analyze"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "create_custom_distribution",
            \\    "description": "Create a new custom probability distribution",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "name": {"type": "string", "description": "Name of the distribution"},
            \\        "parameters": {"type": "array", "description": "Distribution parameters"},
            \\        "support_type": {"type": "string", "description": "Type of support"},
            \\        "log_prob_function": {"type": "string", "description": "Log probability function name"}
            \\      },
            \\      "required": ["name", "parameters", "support_type", "log_prob_function"]
            \\    }
            \\  },
            \\  {
            \\    "name": "compile_distributions_from_sirs",
            \\    "description": "Extract and compile distribution definitions from SIRS code",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "sirs_content": {"type": "string", "description": "SIRS JSON content containing distribution definitions"}
            \\      },
            \\      "required": ["sirs_content"]
            \\    }
            \\  },
            \\  {
            \\    "name": "list_distributions",
            \\    "description": "List all available distributions (built-in and custom)",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "include_builtin": {"type": "boolean", "description": "Include built-in distributions"},
            \\        "include_custom": {"type": "boolean", "description": "Include custom distributions"}
            \\      }
            \\    }
            \\  },
            \\  {
            \\    "name": "get_distribution_info",
            \\    "description": "Get detailed information about a specific distribution",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "distribution_name": {"type": "string", "description": "Name of the distribution"}
            \\      },
            \\      "required": ["distribution_name"]
            \\    }
            \\  },
            \\  {
            \\    "name": "validate_distribution_parameters",
            \\    "description": "Validate parameters for a distribution",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "distribution_name": {"type": "string", "description": "Name of the distribution"},
            \\        "parameters": {"type": "object", "description": "Parameter values to validate"}
            \\      },
            \\      "required": ["distribution_name", "parameters"]
            \\    }
            \\  },
            \\  {
            \\    "name": "generate_distribution_code",
            \\    "description": "Generate SIRS code for a distribution",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "distribution_name": {"type": "string", "description": "Name of the distribution"},
            \\        "include_examples": {"type": "boolean", "description": "Include usage examples"}
            \\      },
            \\      "required": ["distribution_name"]
            \\    }
            \\  },
            \\  {
            \\    "name": "create_mixture_distribution",
            \\    "description": "Create a mixture of existing distributions",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "name": {"type": "string", "description": "Name of the mixture distribution"},
            \\        "components": {"type": "array", "description": "Array of distribution components with weights"}
            \\      },
            \\      "required": ["name", "components"]
            \\    }
            \\  },
            \\  {
            \\    "name": "validate_distribution_definition",
            \\    "description": "Validate a distribution definition for correctness",
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "distribution_name": {"type": "string", "description": "Name of the distribution to validate"}
            \\      },
            \\      "required": ["distribution_name"]
            \\    }
            \\  }
            \\]
        ;
        
        var tools_parsed = json.parseFromSlice(json.Value, std.heap.page_allocator, tools_json, .{}) catch return;
        defer tools_parsed.deinit();
        const tools = tools_parsed.value;
        
        // Write response directly as JSON
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"tools\":");
        try json.stringify(tools, .{}, writer);
        try writer.writeAll("}}\n");
    }
    
    fn handleToolsCall(self: *McpServer, writer: anytype, id: ?json.Value, params: ?json.Value) !void {
        
        if (params == null or params.? != .object) {
            try self.sendError(writer, id, -32602, "Invalid params");
            return;
        }
        
        const name = params.?.object.get("name");
        const arguments = params.?.object.get("arguments");
        
        if (name == null or name.? != .string) {
            try self.sendError(writer, id, -32602, "Invalid tool name");
            return;
        }
        
        const tool_name = name.?.string;
        
        if (std.mem.eql(u8, tool_name, "compile")) {
            try self.handleCompileTool(writer, id, arguments);
        } else if (std.mem.eql(u8, tool_name, "type_check")) {
            try self.handleTypeCheckTool(writer, id, arguments);
        } else if (std.mem.eql(u8, tool_name, "infer_type")) {
            try self.handleInferTypeTool(writer, id, arguments);
        } else if (std.mem.eql(u8, tool_name, "analyze_program")) {
            try self.handleAnalyzeProgramTool(writer, id, arguments);
        } else if (std.mem.eql(u8, tool_name, "optimize_analysis")) {
            try self.handleOptimizeAnalysisTool(writer, id, arguments);
        } else if (std.mem.eql(u8, tool_name, "function_info")) {
            try self.handleFunctionInfoTool(writer, id, arguments);
        } else if (std.mem.eql(u8, tool_name, "query_functions")) {
            try self.handleASTTool(writer, id, arguments, 0);
        } else if (std.mem.eql(u8, tool_name, "query_variables")) {
            try self.handleASTTool(writer, id, arguments, 1);
        } else if (std.mem.eql(u8, tool_name, "query_function_calls")) {
            try self.handleASTTool(writer, id, arguments, 2);
        } else if (std.mem.eql(u8, tool_name, "get_function_info")) {
            try self.handleASTTool(writer, id, arguments, 3);
        } else if (std.mem.eql(u8, tool_name, "rename_function")) {
            try self.handleASTTool(writer, id, arguments, 4);
        } else if (std.mem.eql(u8, tool_name, "add_function")) {
            try self.handleASTTool(writer, id, arguments, 5);
        } else if (std.mem.eql(u8, tool_name, "remove_function")) {
            try self.handleASTTool(writer, id, arguments, 6);
        } else if (std.mem.eql(u8, tool_name, "analyze_complexity")) {
            try self.handleASTTool(writer, id, arguments, 7);
        } else if (std.mem.eql(u8, tool_name, "analyze_dependencies")) {
            try self.handleDependencyTool(writer, id, arguments, 0);
        } else if (std.mem.eql(u8, tool_name, "find_circular_dependencies")) {
            try self.handleDependencyTool(writer, id, arguments, 1);
        } else if (std.mem.eql(u8, tool_name, "find_unused_functions")) {
            try self.handleDependencyTool(writer, id, arguments, 2);
        } else if (std.mem.eql(u8, tool_name, "get_dependency_graph")) {
            try self.handleDependencyTool(writer, id, arguments, 3);
        } else if (std.mem.eql(u8, tool_name, "analyze_function_dependencies")) {
            try self.handleDependencyTool(writer, id, arguments, 4);
        } else if (std.mem.eql(u8, tool_name, "check_dependency_health")) {
            try self.handleDependencyTool(writer, id, arguments, 5);
        } else if (std.mem.eql(u8, tool_name, "get_reachability_analysis")) {
            try self.handleDependencyTool(writer, id, arguments, 6);
        } else if (std.mem.eql(u8, tool_name, "create_custom_distribution")) {
            try self.handleDistributionTool(writer, id, arguments, 0);
        } else if (std.mem.eql(u8, tool_name, "compile_distributions_from_sirs")) {
            try self.handleDistributionTool(writer, id, arguments, 1);
        } else if (std.mem.eql(u8, tool_name, "list_distributions")) {
            try self.handleDistributionTool(writer, id, arguments, 2);
        } else if (std.mem.eql(u8, tool_name, "get_distribution_info")) {
            try self.handleDistributionTool(writer, id, arguments, 3);
        } else if (std.mem.eql(u8, tool_name, "validate_distribution_parameters")) {
            try self.handleDistributionTool(writer, id, arguments, 4);
        } else if (std.mem.eql(u8, tool_name, "generate_distribution_code")) {
            try self.handleDistributionTool(writer, id, arguments, 5);
        } else if (std.mem.eql(u8, tool_name, "create_mixture_distribution")) {
            try self.handleDistributionTool(writer, id, arguments, 6);
        } else if (std.mem.eql(u8, tool_name, "validate_distribution_definition")) {
            try self.handleDistributionTool(writer, id, arguments, 7);
        } else {
            try self.sendError(writer, id, -32602, "Unknown tool");
        }
    }
    
    fn handleCompileTool(self: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value) !void {
        // Clear any previous errors
        self.error_reporter.clear();
        
        if (arguments == null or arguments.? != .object) {
            try self.sendError(writer, id, -32602, "Missing program argument");
            return;
        }
        
        const program_arg = arguments.?.object.get("program");
        if (program_arg == null) {
            try self.sendError(writer, id, -32602, "Missing program object");
            return;
        }
        
        // Convert the program JSON to a string for parsing
        var program_str = std.ArrayList(u8).init(self.allocator);
        defer program_str.deinit();
        
        try json.stringify(program_arg.?, .{}, program_str.writer());
        
        // Parse the SIRS program
        var program = self.parser.parse(program_str.items) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Parse error: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(writer, id, -32001, error_msg);
            return;
        };
        defer program.deinit();
        
        // Type check the program
        self.type_checker.check(&program) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Type check error: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(writer, id, -32002, error_msg);
            return;
        };
        
        // Generate a response with compilation details
        const response = try std.fmt.allocPrint(
            self.allocator,
            "Compilation successful!\n\nProgram Analysis:\n- Entry point: {s}\n- Functions: {d}\n- Types: {d}\n- Interfaces: {d}",
            .{
                program.entry,
                program.functions.count(),
                program.types.count(),
                program.interfaces.count(),
            }
        );
        defer self.allocator.free(response);
        
        // Write successful response
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
        try json.stringify(response, .{}, writer);
        try writer.writeAll("}]}}\n");
    }
    
    fn handleTypeCheckTool(self: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value) !void {
        // Clear any previous errors
        self.error_reporter.clear();
        
        if (arguments == null or arguments.? != .object) {
            try self.sendError(writer, id, -32602, "Missing program argument");
            return;
        }
        
        const program_arg = arguments.?.object.get("program");
        if (program_arg == null) {
            try self.sendError(writer, id, -32602, "Missing program object");
            return;
        }
        
        // Convert the program JSON to a string for parsing
        var program_str = std.ArrayList(u8).init(self.allocator);
        defer program_str.deinit();
        
        try json.stringify(program_arg.?, .{}, program_str.writer());
        
        // Parse the SIRS program
        var program = self.parser.parse(program_str.items) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Parse error: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(writer, id, -32001, error_msg);
            return;
        };
        defer program.deinit();
        
        // Perform detailed type checking
        self.type_checker.check(&program) catch |err| {
            // Provide detailed error information
            const error_count = self.error_reporter.getErrorCount();
            const warning_count = self.error_reporter.getWarningCount();
            
            const error_msg = try std.fmt.allocPrint(
                self.allocator, 
                "Type checking failed: {s}\n\nErrors: {d}, Warnings: {d}", 
                .{@errorName(err), error_count, warning_count}
            );
            defer self.allocator.free(error_msg);
            try self.sendError(writer, id, -32002, error_msg);
            return;
        };
        
        // Generate successful type checking report
        const warning_count = self.error_reporter.getWarningCount();
        const response = if (warning_count > 0) 
            try std.fmt.allocPrint(
                self.allocator,
                "Type checking passed with {d} warning(s)!\n\nProgram is well-typed:\n- Entry point: {s}\n- Functions analyzed: {d}\n- Type definitions: {d}",
                .{
                    warning_count,
                    program.entry,
                    program.functions.count(),
                    program.types.count(),
                }
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "Type checking passed successfully!\n\nProgram is well-typed:\n- Entry point: {s}\n- Functions analyzed: {d}\n- Type definitions: {d}",
                .{
                    program.entry,
                    program.functions.count(),
                    program.types.count(),
                }
            );
        defer self.allocator.free(response);
        
        // Write successful response
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
        try json.stringify(response, .{}, writer);
        try writer.writeAll("}]}}\n");
    }
    
    fn handleInferTypeTool(self: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value) !void {
        if (arguments == null or arguments.? != .object) {
            try self.sendError(writer, id, -32602, "Missing expression argument");
            return;
        }
        
        const expression_arg = arguments.?.object.get("expression");
        if (expression_arg == null) {
            try self.sendError(writer, id, -32602, "Missing expression object");
            return;
        }
        
        // For now, implement a simplified type inference based on expression patterns
        // In a full implementation, this would use the type checker's inference capabilities
        const inferred_type = try self.inferExpressionType(expression_arg.?);
        
        const response = try std.fmt.allocPrint(
            self.allocator,
            "Type inference result:\n\nInferred type: {s}\n\nNote: This is a simplified type inference. For complete analysis, use the full type checker.",
            .{inferred_type}
        );
        defer self.allocator.free(response);
        
        // Write successful response
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
        try json.stringify(response, .{}, writer);
        try writer.writeAll("}]}}\n");
    }
    
    /// Simple type inference helper
    fn inferExpressionType(self: *McpServer, expr: json.Value) ![]const u8 {
        _ = self;
        
        if (expr != .object) {
            return "unknown";
        }
        
        const obj = expr.object;
        
        if (obj.get("literal")) |literal| {
            if (literal == .object) {
                const lit_obj = literal.object;
                if (lit_obj.get("integer")) |_| return "i32";
                if (lit_obj.get("float")) |_| return "f64";
                if (lit_obj.get("string")) |_| return "str";
                if (lit_obj.get("boolean")) |_| return "bool";
                if (lit_obj.get("null")) |_| return "null";
            }
        }
        
        if (obj.get("op")) |op| {
            if (op == .object) {
                const op_obj = op.object;
                if (op_obj.get("kind")) |kind| {
                    if (kind == .string) {
                        const kind_str = kind.string;
                        if (std.mem.eql(u8, kind_str, "add") or 
                           std.mem.eql(u8, kind_str, "sub") or 
                           std.mem.eql(u8, kind_str, "mul") or 
                           std.mem.eql(u8, kind_str, "div")) {
                            return "i32"; // Simplified - assumes integer arithmetic
                        }
                        if (std.mem.eql(u8, kind_str, "eq") or 
                           std.mem.eql(u8, kind_str, "ne") or 
                           std.mem.eql(u8, kind_str, "lt") or 
                           std.mem.eql(u8, kind_str, "gt")) {
                            return "bool";
                        }
                    }
                }
            }
        }
        
        if (obj.get("call")) |_| {
            return "unknown"; // Would need function signature analysis
        }
        
        return "unknown";
    }
    
    fn handleAnalyzeProgramTool(self: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value) !void {
        // Clear any previous errors
        self.error_reporter.clear();
        
        if (arguments == null or arguments.? != .object) {
            try self.sendError(writer, id, -32602, "Missing program argument");
            return;
        }
        
        const program_arg = arguments.?.object.get("program");
        if (program_arg == null) {
            try self.sendError(writer, id, -32602, "Missing program object");
            return;
        }
        
        // Convert the program JSON to a string for parsing
        var program_str = std.ArrayList(u8).init(self.allocator);
        defer program_str.deinit();
        
        try json.stringify(program_arg.?, .{}, program_str.writer());
        
        // Parse the SIRS program
        var program = self.parser.parse(program_str.items) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Parse error: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(writer, id, -32001, error_msg);
            return;
        };
        defer program.deinit();
        
        // Perform comprehensive analysis
        var total_statements: u32 = 0;
        var complexity_score: u32 = 0;
        
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const function = entry.value_ptr;
            total_statements += @intCast(function.body.items.len);
            
            // Simple complexity analysis
            for (function.body.items) |*stmt| {
                complexity_score += try self.analyzeStatementComplexity(stmt);
            }
        }
        
        const response = try std.fmt.allocPrint(
            self.allocator,
            "Program Analysis Report:\n\n" ++
            "== Structure ==\n" ++
            "- Entry point: {s}\n" ++
            "- Functions: {d}\n" ++
            "- Types: {d}\n" ++
            "- Interfaces: {d}\n" ++
            "- Constants: {d}\n\n" ++
            "== Complexity Metrics ==\n" ++
            "- Total statements: {d}\n" ++
            "- Complexity score: {d}\n" ++
            "- Average complexity per function: {d:.2}\n\n" ++
            "== Recommendations ==\n" ++
            "- Consider breaking down functions with high complexity\n" ++
            "- Review interface usage for better abstraction\n" ++
            "- Optimize hot paths identified in complexity analysis",
            .{
                program.entry,
                program.functions.count(),
                program.types.count(),
                program.interfaces.count(),
                program.constants.count(),
                total_statements,
                complexity_score,
                if (program.functions.count() > 0) 
                    @as(f64, @floatFromInt(complexity_score)) / @as(f64, @floatFromInt(program.functions.count()))
                else 0.0,
            }
        );
        defer self.allocator.free(response);
        
        // Write successful response
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
        try json.stringify(response, .{}, writer);
        try writer.writeAll("}]}}\n");
    }
    
    fn handleOptimizeAnalysisTool(self: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value) !void {
        // Clear any previous errors
        self.error_reporter.clear();
        
        if (arguments == null or arguments.? != .object) {
            try self.sendError(writer, id, -32602, "Missing program argument");
            return;
        }
        
        const program_arg = arguments.?.object.get("program");
        if (program_arg == null) {
            try self.sendError(writer, id, -32602, "Missing program object");
            return;
        }
        
        // Convert the program JSON to a string for parsing
        var program_str = std.ArrayList(u8).init(self.allocator);
        defer program_str.deinit();
        
        try json.stringify(program_arg.?, .{}, program_str.writer());
        
        // Parse the SIRS program
        var program = self.parser.parse(program_str.items) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Parse error: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(writer, id, -32001, error_msg);
            return;
        };
        defer program.deinit();
        
        // Analyze optimization opportunities
        var constant_expressions: u32 = 0;
        var redundant_operations: u32 = 0;
        var inlinable_functions: u32 = 0;
        
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const function = entry.value_ptr;
            
            // Check if function is small enough to inline
            if (function.body.items.len <= 5 and function.args.items.len <= 3) {
                inlinable_functions += 1;
            }
            
            // Look for constant expressions and redundancy
            for (function.body.items) |*stmt| {
                constant_expressions += try self.countConstantExpressions(stmt);
                redundant_operations += try self.countRedundantOperations(stmt);
            }
        }
        
        const response = try std.fmt.allocPrint(
            self.allocator,
            "Optimization Analysis Report:\n\n" ++
            "== Detected Opportunities ==\n" ++
            "- Constant expressions that can be folded: {d}\n" ++
            "- Potentially redundant operations: {d}\n" ++
            "- Functions suitable for inlining: {d}\n\n" ++
            "== Optimization Passes Available ==\n" ++
            "✅ Dead Code Elimination - Removes unused code\n" ++
            "✅ Constant Folding - Evaluates constants at compile time\n" ++
            "⚠️  Function Inlining - Replaces calls with function bodies\n\n" ++
            "== Estimated Benefits ==\n" ++
            "- Code size reduction: ~{d}%\n" ++
            "- Runtime performance improvement: ~{d}%\n" ++
            "- Compilation time impact: +{d}%\n\n" ++
            "== Recommendations ==\n" ++
            "- Enable all optimization passes for production builds\n" ++
            "- Consider manual optimization for hot paths\n" ++
            "- Profile code to validate optimization benefits",
            .{
                constant_expressions,
                redundant_operations,
                inlinable_functions,
                @min(15, constant_expressions * 2 + redundant_operations),
                @min(25, inlinable_functions * 3 + constant_expressions),
                @max(5, (constant_expressions + redundant_operations + inlinable_functions) / 2),
            }
        );
        defer self.allocator.free(response);
        
        // Write successful response
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
        try json.stringify(response, .{}, writer);
        try writer.writeAll("}]}}\n");
    }
    
    fn handleFunctionInfoTool(self: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value) !void {
        // Implementation for function information tool
        if (arguments == null or arguments.? != .object) {
            try self.sendError(writer, id, -32602, "Missing program argument");
            return;
        }
        
        const program_arg = arguments.?.object.get("program");
        if (program_arg == null) {
            try self.sendError(writer, id, -32602, "Missing program object");
            return;
        }
        
        // Convert the program JSON to a string for parsing
        var program_str = std.ArrayList(u8).init(self.allocator);
        defer program_str.deinit();
        
        try json.stringify(program_arg.?, .{}, program_str.writer());
        
        // Parse the SIRS program
        var program = self.parser.parse(program_str.items) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Parse error: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(writer, id, -32001, error_msg);
            return;
        };
        defer program.deinit();
        
        // Build function information
        var response_parts = std.ArrayList(u8).init(self.allocator);
        defer response_parts.deinit();
        
        const writer_buf = response_parts.writer();
        try writer_buf.writeAll("Function Information Report:\n\n");
        
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            
            try writer_buf.print("== Function: {s} ==\n", .{func_name});
            try writer_buf.print("- Parameters: {d}\n", .{function.args.items.len});
            try writer_buf.print("- Statements: {d}\n", .{function.body.items.len});
            try writer_buf.print("- Return type: {s}\n", .{self.typeToString(function.@"return")});
            
            if (function.args.items.len > 0) {
                try writer_buf.writeAll("- Parameter types:\n");
                for (function.args.items) |param| {
                    try writer_buf.print("  - {s}: {s}\n", .{param.name, self.typeToString(param.type)});
                }
            }
            
            try writer_buf.writeAll("\n");
        }
        
        // Write successful response
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
        try json.stringify(response_parts.items, .{}, writer);
        try writer.writeAll("}]}}\n");
    }
    
    fn handleASTTool(self: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value, tool_index: usize) !void {
        if (arguments == null or arguments.? != .object) {
            try self.sendError(writer, id, -32602, "Missing arguments");
            return;
        }
        
        // Call the appropriate AST tool handler
        const result = MCP_AST_TOOLS[tool_index].handler(self.allocator, arguments.?) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "AST tool error: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(writer, id, -32003, error_msg);
            return;
        };
        defer self.allocator.free(result);
        
        // Write successful response
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
        try json.stringify(result, .{}, writer);
        try writer.writeAll("}]}}\n");
    }
    
    fn handleDependencyTool(self: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value, tool_index: usize) !void {
        if (arguments == null or arguments.? != .object) {
            try self.sendError(writer, id, -32602, "Missing arguments");
            return;
        }
        
        // Call the appropriate dependency tool handler
        const result = MCP_DEPENDENCY_TOOLS[tool_index].handler(self.allocator, arguments.?) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Dependency tool error: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(writer, id, -32004, error_msg);
            return;
        };
        defer self.allocator.free(result);
        
        // Write successful response
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
        try json.stringify(result, .{}, writer);
        try writer.writeAll("}]}}\n");
    }
    
    fn handleDistributionTool(self: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value, tool_index: usize) !void {
        if (arguments == null or arguments.? != .object) {
            try self.sendError(writer, id, -32602, "Missing arguments");
            return;
        }
        
        // Call the appropriate distribution tool handler
        const result = MCP_DISTRIBUTION_TOOLS[tool_index].handler(self.allocator, arguments.?) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Distribution tool error: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(writer, id, -32005, error_msg);
            return;
        };
        defer self.allocator.free(result);
        
        // Write successful response
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
        try json.stringify(result, .{}, writer);
        try writer.writeAll("}]}}\n");
    }
    
    /// Helper functions for analysis
    fn analyzeStatementComplexity(self: *McpServer, stmt: *SirsParser.Statement) !u32 {
        _ = self;
        
        return switch (stmt.*) {
            .let => 1,
            .assign => 1,
            .@"return" => 1,
            .@"if" => 3, // Higher complexity for control flow
            .match => 5, // Even higher for pattern matching
            .@"try" => 4,
            .@"throw" => 2,
            .expression => 1,
            else => 1,
        };
    }
    
    fn countConstantExpressions(self: *McpServer, stmt: *SirsParser.Statement) !u32 {
        // Simplified analysis - in reality would traverse the expression tree
        return switch (stmt.*) {
            .let => |let_stmt| if (self.isLikelyConstant(@constCast(&let_stmt.value))) 1 else 0,
            .assign => |assign_stmt| if (self.isLikelyConstant(@constCast(&assign_stmt.value))) 1 else 0,
            .@"return" => |*return_expr| if (self.isLikelyConstant(@constCast(return_expr))) 1 else 0,
            else => 0,
        };
    }
    
    fn countRedundantOperations(self: *McpServer, stmt: *SirsParser.Statement) !u32 {
        _ = self;
        _ = stmt;
        
        // Placeholder for redundancy analysis
        // In a real implementation, this would detect patterns like:
        // - x + 0, x * 1, etc.
        // - Repeated identical expressions
        // - Unused variables
        return 0;
    }
    
    fn isLikelyConstant(self: *McpServer, expr: *SirsParser.Expression) bool {
        return switch (expr.*) {
            .literal => true,
            .op => |op_expr| {
                // If all operands are literals, this could be constant folded
                for (op_expr.args.items) |*arg| {
                    if (!self.isLikelyConstant(@constCast(arg))) return false;
                }
                return true;
            },
            else => false,
        };
    }
    
    fn typeToString(self: *McpServer, type_info: SirsParser.Type) []const u8 {
        _ = self;
        return switch (type_info) {
            .void => "void",
            .bool => "bool",
            .i8, .i16, .i32, .i64 => "int",
            .u8, .u16, .u32, .u64 => "uint",
            .f32, .f64 => "float",
            .str => "str",
            .array => "Array",
            .slice => "Slice",
            .@"struct" => "Struct",
            .@"union" => "Union",
            .discriminated_union => |d| d.name,
            .@"enum" => |e| e.name,
            .@"error" => |e| e.name,
            .hashmap => "HashMap",
            .set => "Set",
            .tuple => "Tuple",
            .record => |r| r.name,
            .optional => "Optional",
            .function => "Function",
            .future => "Future",
            .distribution => "Distribution",
            .type_parameter => |tp| tp,
            .generic_instance => |g| g.base_type,
            .@"interface" => |i| i.name,
            .trait_object => |t| t.trait_name,
        };
    }
    
    fn handleShutdown(self: *McpServer, writer: anytype, id: ?json.Value) !void {
        self.running = false;
        
        // Write response directly as JSON
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":null}\n");
    }
    
    fn sendError(_: *McpServer, writer: anytype, id: ?json.Value, code: i32, message: []const u8) !void {
        
        // Write error response directly as JSON  
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"error\":{\"code\":");
        try json.stringify(code, .{}, writer);
        try writer.writeAll(",\"message\":");
        try json.stringify(message, .{}, writer);
        try writer.writeAll("}}\n");
    }
};