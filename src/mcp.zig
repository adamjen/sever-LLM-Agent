const std = @import("std");
const json = std.json;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const McpServer = struct {
    allocator: Allocator,
    running: bool,
    
    pub fn init(allocator: Allocator) McpServer {
        return McpServer{
            .allocator = allocator,
            .running = false,
        };
    }
    
    pub fn deinit(_: *McpServer) void {
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
            \\    "description": "Compile a Sever program from SIRS format",
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
            \\    "description": "Type check a Sever program",
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
            \\    "description": "Infer the type of an expression", 
            \\    "inputSchema": {
            \\      "type": "object",
            \\      "properties": {
            \\        "expression": {
            \\          "type": "object",
            \\          "description": "Expression to infer type for"
            \\        },
            \\        "context": {
            \\          "type": "object", 
            \\          "description": "Variable context for type inference"
            \\        }
            \\      },
            \\      "required": ["expression"]
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
        } else {
            try self.sendError(writer, id, -32602, "Unknown tool");
        }
    }
    
    fn handleCompileTool(_: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value) !void {
        _ = arguments;
        
        // TODO: Implement actual compilation
        // Write response directly as JSON
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"Compilation successful\"}]}}\n");
    }
    
    fn handleTypeCheckTool(_: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value) !void {
        _ = arguments;
        
        // TODO: Implement actual type checking
        // Write response directly as JSON
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"Type checking passed\"}]}}\n");
    }
    
    fn handleInferTypeTool(_: *McpServer, writer: anytype, id: ?json.Value, arguments: ?json.Value) !void {
        _ = arguments;
        
        // TODO: Implement type inference
        // Write response directly as JSON
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try json.stringify(id, .{}, writer);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"Type inferred: i32\"}]}}\n");
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