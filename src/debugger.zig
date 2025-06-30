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

/// Debug information for source mapping
pub const DebugInfo = struct {
    line: u32,
    column: u32,
    file: []const u8,
    function_name: []const u8,
};

/// Breakpoint information
pub const Breakpoint = struct {
    id: u32,
    file: []const u8,
    line: u32,
    enabled: bool,
    condition: ?[]const u8, // Optional condition for conditional breakpoints
    hit_count: u32,
};

/// Debug symbol information
pub const DebugSymbol = struct {
    name: []const u8,
    type: []const u8,
    scope: []const u8,
    location: DebugInfo,
};

/// Stack frame information for debugging
pub const StackFrame = struct {
    function_name: []const u8,
    file: []const u8,
    line: u32,
    variables: StringHashMap([]const u8), // Variable name -> value representation
};

/// Debugger error types
pub const DebugError = error{
    BreakpointNotFound,
    InvalidBreakpoint,
    InvalidExpression,
    OutOfMemory,
    IoError,
};

/// Main debugger interface
pub const Debugger = struct {
    allocator: Allocator,
    breakpoints: ArrayList(Breakpoint),
    debug_symbols: ArrayList(DebugSymbol),
    current_frame: ?StackFrame,
    call_stack: ArrayList(StackFrame),
    next_breakpoint_id: u32,
    debug_mode: bool,
    
    pub fn init(allocator: Allocator) Debugger {
        return Debugger{
            .allocator = allocator,
            .breakpoints = ArrayList(Breakpoint).init(allocator),
            .debug_symbols = ArrayList(DebugSymbol).init(allocator),
            .current_frame = null,
            .call_stack = ArrayList(StackFrame).init(allocator),
            .next_breakpoint_id = 1,
            .debug_mode = false,
        };
    }
    
    pub fn deinit(self: *Debugger) void {
        self.breakpoints.deinit();
        self.debug_symbols.deinit();
        self.call_stack.deinit();
        if (self.current_frame) |*frame| {
            frame.variables.deinit();
        }
    }
    
    /// Enable or disable debug mode
    pub fn setDebugMode(self: *Debugger, enabled: bool) void {
        self.debug_mode = enabled;
        if (enabled) {
            print("Debug mode enabled\n", .{});
        } else {
            print("Debug mode disabled\n", .{});
        }
    }
    
    /// Add a breakpoint at the specified location
    pub fn addBreakpoint(self: *Debugger, file: []const u8, line: u32, condition: ?[]const u8) DebugError!u32 {
        const breakpoint = Breakpoint{
            .id = self.next_breakpoint_id,
            .file = file,
            .line = line,
            .enabled = true,
            .condition = condition,
            .hit_count = 0,
        };
        
        try self.breakpoints.append(breakpoint);
        self.next_breakpoint_id += 1;
        
        print("Breakpoint {d} set at {s}:{d}\n", .{ breakpoint.id, file, line });
        if (condition) |cond| {
            print("  Condition: {s}\n", .{cond});
        }
        
        return breakpoint.id;
    }
    
    /// Remove a breakpoint by ID
    pub fn removeBreakpoint(self: *Debugger, breakpoint_id: u32) DebugError!void {
        for (self.breakpoints.items, 0..) |bp, i| {
            if (bp.id == breakpoint_id) {
                _ = self.breakpoints.swapRemove(i);
                print("Breakpoint {d} removed\n", .{breakpoint_id});
                return;
            }
        }
        return DebugError.BreakpointNotFound;
    }
    
    /// Enable or disable a breakpoint
    pub fn toggleBreakpoint(self: *Debugger, breakpoint_id: u32) DebugError!void {
        for (self.breakpoints.items) |*bp| {
            if (bp.id == breakpoint_id) {
                bp.enabled = !bp.enabled;
                print("Breakpoint {d} {s}\n", .{ breakpoint_id, if (bp.enabled) "enabled" else "disabled" });
                return;
            }
        }
        return DebugError.BreakpointNotFound;
    }
    
    /// List all breakpoints
    pub fn listBreakpoints(self: *Debugger) void {
        if (self.breakpoints.items.len == 0) {
            print("No breakpoints set\n", .{});
            return;
        }
        
        print("Breakpoints:\n", .{});
        for (self.breakpoints.items) |bp| {
            const status = if (bp.enabled) "enabled" else "disabled";
            print("  {d}: {s}:{d} ({s}) [hit {d} times]\n", .{ bp.id, bp.file, bp.line, status, bp.hit_count });
            if (bp.condition) |cond| {
                print("      Condition: {s}\n", .{cond});
            }
        }
    }
    
    /// Check if execution should break at the given location
    pub fn shouldBreak(self: *Debugger, file: []const u8, line: u32) bool {
        if (!self.debug_mode) return false;
        
        for (self.breakpoints.items) |*bp| {
            if (bp.enabled and std.mem.eql(u8, bp.file, file) and bp.line == line) {
                bp.hit_count += 1;
                
                // For now, ignore conditions (would need expression evaluator)
                // In a full implementation, we'd evaluate the condition here
                if (bp.condition != null) {
                    print("Conditional breakpoint hit (condition not evaluated yet): {s}\n", .{bp.condition.?});
                }
                
                print("Breakpoint {d} hit at {s}:{d}\n", .{ bp.id, file, line });
                return true;
            }
        }
        
        return false;
    }
    
    /// Add debug symbol information
    pub fn addSymbol(self: *Debugger, name: []const u8, symbol_type: []const u8, scope: []const u8, location: DebugInfo) DebugError!void {
        const symbol = DebugSymbol{
            .name = name,
            .type = symbol_type,
            .scope = scope,
            .location = location,
        };
        try self.debug_symbols.append(symbol);
    }
    
    /// Look up debug symbols by name
    pub fn findSymbol(self: *Debugger, name: []const u8) ?DebugSymbol {
        for (self.debug_symbols.items) |symbol| {
            if (std.mem.eql(u8, symbol.name, name)) {
                return symbol;
            }
        }
        return null;
    }
    
    /// Print call stack
    pub fn printCallStack(self: *Debugger) void {
        if (self.call_stack.items.len == 0) {
            print("Call stack is empty\n", .{});
            return;
        }
        
        print("Call stack:\n", .{});
        for (self.call_stack.items, 0..) |frame, i| {
            print("  #{d}: {s} at {s}:{d}\n", .{ i, frame.function_name, frame.file, frame.line });
        }
    }
    
    /// Enter a new function (push stack frame)
    pub fn enterFunction(self: *Debugger, function_name: []const u8, file: []const u8, line: u32) DebugError!void {
        const new_frame = StackFrame{
            .function_name = function_name,
            .file = file,
            .line = line,
            .variables = StringHashMap([]const u8).init(self.allocator),
        };
        
        try self.call_stack.append(new_frame);
        self.current_frame = new_frame;
        
        if (self.debug_mode) {
            print("Entering function: {s} at {s}:{d}\n", .{ function_name, file, line });
        }
    }
    
    /// Exit current function (pop stack frame)
    pub fn exitFunction(self: *Debugger) void {
        if (self.call_stack.items.len > 0) {
            var popped_frame = self.call_stack.pop();
            popped_frame.variables.deinit();
            
            if (self.debug_mode) {
                print("Exiting function: {s}\n", .{popped_frame.function_name});
            }
            
            // Update current frame to the previous one
            if (self.call_stack.items.len > 0) {
                self.current_frame = self.call_stack.items[self.call_stack.items.len - 1];
            } else {
                self.current_frame = null;
            }
        }
    }
    
    /// Set variable value in current frame
    pub fn setVariable(self: *Debugger, name: []const u8, value: []const u8) DebugError!void {
        if (self.current_frame) |*frame| {
            try frame.variables.put(name, value);
        }
    }
    
    /// Get variable value from current frame
    pub fn getVariable(self: *Debugger, name: []const u8) ?[]const u8 {
        if (self.current_frame) |frame| {
            return frame.variables.get(name);
        }
        return null;
    }
    
    /// Print all variables in current scope
    pub fn printVariables(self: *Debugger) void {
        if (self.current_frame) |frame| {
            if (frame.variables.count() == 0) {
                print("No variables in current scope\n", .{});
                return;
            }
            
            print("Variables in current scope:\n", .{});
            var var_iter = frame.variables.iterator();
            while (var_iter.next()) |entry| {
                print("  {s} = {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        } else {
            print("No current execution frame\n", .{});
        }
    }
    
    /// Interactive debugging command processor
    pub fn processDebugCommand(self: *Debugger, command: []const u8) void {
        var parts = std.mem.splitScalar(u8, command, ' ');
        const cmd = parts.next() orelse return;
        
        if (std.mem.eql(u8, cmd, "break") or std.mem.eql(u8, cmd, "b")) {
            const location = parts.next() orelse {
                print("Usage: break <file>:<line> [condition]\n", .{});
                return;
            };
            
            // Parse file:line format
            var location_parts = std.mem.splitScalar(u8, location, ':');
            const file = location_parts.next() orelse {
                print("Invalid breakpoint format. Use file:line\n", .{});
                return;
            };
            const line_str = location_parts.next() orelse {
                print("Invalid breakpoint format. Use file:line\n", .{});
                return;
            };
            
            const line = std.fmt.parseInt(u32, line_str, 10) catch {
                print("Invalid line number: {s}\n", .{line_str});
                return;
            };
            
            const condition = parts.next(); // Optional condition
            _ = self.addBreakpoint(file, line, condition) catch |err| {
                print("Failed to add breakpoint: {}\n", .{err});
            };
            
        } else if (std.mem.eql(u8, cmd, "delete") or std.mem.eql(u8, cmd, "d")) {
            const id_str = parts.next() orelse {
                print("Usage: delete <breakpoint_id>\n", .{});
                return;
            };
            
            const id = std.fmt.parseInt(u32, id_str, 10) catch {
                print("Invalid breakpoint ID: {s}\n", .{id_str});
                return;
            };
            
            self.removeBreakpoint(id) catch |err| {
                print("Failed to remove breakpoint: {}\n", .{err});
            };
            
        } else if (std.mem.eql(u8, cmd, "list") or std.mem.eql(u8, cmd, "l")) {
            self.listBreakpoints();
            
        } else if (std.mem.eql(u8, cmd, "stack") or std.mem.eql(u8, cmd, "bt")) {
            self.printCallStack();
            
        } else if (std.mem.eql(u8, cmd, "vars") or std.mem.eql(u8, cmd, "v")) {
            self.printVariables();
            
        } else if (std.mem.eql(u8, cmd, "print") or std.mem.eql(u8, cmd, "p")) {
            const var_name = parts.next() orelse {
                print("Usage: print <variable_name>\n", .{});
                return;
            };
            
            if (self.getVariable(var_name)) |value| {
                print("{s} = {s}\n", .{ var_name, value });
            } else {
                print("Variable '{s}' not found\n", .{var_name});
            }
            
        } else if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "h")) {
            self.printHelp();
            
        } else {
            print("Unknown command: {s}. Type 'help' for available commands.\n", .{cmd});
        }
    }
    
    /// Print debugging help
    fn printHelp(self: *Debugger) void {
        _ = self;
        print("Sever Debugger Commands:\n", .{});
        print("  break, b <file>:<line> [condition] - Set breakpoint\n", .{});
        print("  delete, d <id>                     - Remove breakpoint\n", .{});
        print("  list, l                            - List breakpoints\n", .{});
        print("  stack, bt                          - Show call stack\n", .{});
        print("  vars, v                            - Show variables in current scope\n", .{});
        print("  print, p <variable>                - Print variable value\n", .{});
        print("  help, h                            - Show this help\n", .{});
    }
};

/// Debug information generator for SIRS programs
pub const DebugInfoGenerator = struct {
    allocator: Allocator,
    debugger: *Debugger,
    
    pub fn init(allocator: Allocator, debugger: *Debugger) DebugInfoGenerator {
        return DebugInfoGenerator{
            .allocator = allocator,
            .debugger = debugger,
        };
    }
    
    /// Generate debug information for a program
    pub fn generateDebugInfo(self: *DebugInfoGenerator, program: *Program, source_file: []const u8) DebugError!void {
        // Add function symbols
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            
            const debug_info = DebugInfo{
                .line = 1, // Would need source mapping for real line numbers
                .column = 1,
                .file = source_file,
                .function_name = func_name,
            };
            
            try self.debugger.addSymbol(func_name, "function", "global", debug_info);
            
            // Add parameter symbols
            for (function.args.items) |param| {
                const param_debug_info = DebugInfo{
                    .line = 1,
                    .column = 1,
                    .file = source_file,
                    .function_name = func_name,
                };
                
                const type_str = self.typeToString(param.type);
                try self.debugger.addSymbol(param.name, type_str, func_name, param_debug_info);
            }
        }
    }
    
    /// Convert type to string representation
    fn typeToString(self: *DebugInfoGenerator, type_info: SirsParser.Type) []const u8 {
        _ = self;
        return switch (type_info) {
            .void => "void",
            .i32 => "i32",
            .i64 => "i64",
            .f32 => "f32",
            .f64 => "f64",
            .bool => "bool",
            .str => "string",
            .array => |arr| {
                // Simplified - would need proper array type representation
                _ = arr;
                return "array";
            },
            else => "unknown",
        };
    }
};

/// Runtime debug hooks that can be inserted into generated code
pub const DebugHooks = struct {
    /// Debug hook function that can be called from generated code
    pub fn debugHook(file: []const u8, line: u32, function_name: []const u8) void {
        // This would be called from generated code at strategic points
        print("DEBUG: {s}:{d} in {s}\n", .{ file, line, function_name });
        
        // In a full implementation, this would:
        // 1. Check for breakpoints
        // 2. Update call stack
        // 3. Provide interactive debugging interface
    }
    
    /// Function entry hook
    pub fn functionEntryHook(function_name: []const u8, file: []const u8, line: u32) void {
        print("ENTER: {s} at {s}:{d}\n", .{ function_name, file, line });
    }
    
    /// Function exit hook
    pub fn functionExitHook(function_name: []const u8) void {
        print("EXIT: {s}\n", .{function_name});
    }
    
    /// Variable assignment hook
    pub fn variableAssignHook(var_name: []const u8, value: []const u8) void {
        print("ASSIGN: {s} = {s}\n", .{ var_name, value });
    }
};