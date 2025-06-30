const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const SirsParser = @import("sirs.zig");
const Program = SirsParser.Program;
const Function = SirsParser.Function;
const Statement = SirsParser.Statement;
const Expression = SirsParser.Expression;
const Type = SirsParser.Type;

pub const CodeGenError = error{
    UnsupportedType,
    UnsupportedExpression,
    UnsupportedStatement,
    IoError,
    CompilationError,
    OutOfMemory,
};

pub const CodeGen = struct {
    allocator: Allocator,
    output: ArrayList(u8),
    indent_level: u32,
    current_function_name: ?[]const u8,
    current_function: ?*Function,
    
    pub fn init(allocator: Allocator) CodeGen {
        return CodeGen{
            .allocator = allocator,
            .output = ArrayList(u8).init(allocator),
            .indent_level = 0,
            .current_function_name = null,
            .current_function = null,
        };
    }
    
    pub fn deinit(self: *CodeGen) void {
        self.output.deinit();
    }
    
    pub fn generate(self: *CodeGen, program: *Program, output_file: []const u8) CodeGenError!void {
        // Clear output buffer
        self.output.clearRetainingCapacity();
        self.indent_level = 0;
        
        // Generate Zig code for the program
        try self.generateProgram(program);
        
        // Write to temporary Zig file
        const temp_zig_file = std.fmt.allocPrint(self.allocator, "{s}.zig", .{output_file}) catch return CodeGenError.OutOfMemory;
        defer self.allocator.free(temp_zig_file);
        
        const file = std.fs.cwd().createFile(temp_zig_file, .{}) catch return CodeGenError.IoError;
        defer file.close();
        
        file.writeAll(self.output.items) catch return CodeGenError.IoError;
        
        // Compile the Zig file to native binary
        try self.compileZigFile(temp_zig_file, output_file);
        
        // Clean up temporary file
        std.fs.cwd().deleteFile(temp_zig_file) catch {};
    }
    
    fn generateProgram(self: *CodeGen, program: *Program) CodeGenError!void {
        // Generate standard library imports
        try self.writeLine("const std = @import(\"std\");");
        try self.writeLine("const debug_print = std.debug.print;");
        try self.writeLine("const Allocator = std.mem.Allocator;");
        try self.writeLine("const math = std.math;");
        try self.writeLine("const time = std.time;");
        try self.writeLine("");
        
        // Generate custom type definitions (enums and errors)
        try self.generateCustomTypes(program);
        
        // Generate embedded runtime functions
        try self.writeLine("// Embedded Sever Runtime Functions");
        try self.writeLine("var gpa = std.heap.GeneralPurposeAllocator(.{}){};");
        try self.writeLine("var allocator = gpa.allocator();");
        try self.writeLine("var prng = std.Random.DefaultPrng.init(0);");
        try self.writeLine("var random = prng.random();");
        try self.writeLine("");
        try self.writeLine("fn sever_runtime_init(seed: ?u64) void {");
        try self.writeLine("    const actual_seed = seed orelse @as(u64, @intCast(time.timestamp()));");
        try self.writeLine("    prng = std.Random.DefaultPrng.init(actual_seed);");
        try self.writeLine("    random = prng.random();");
        try self.writeLine("}");
        try self.writeLine("");
        try self.writeLine("fn sample(distribution: []const u8, params: []const f64) f64 {");
        try self.writeLine("    if (std.mem.eql(u8, distribution, \"uniform\")) {");
        try self.writeLine("        const min = params[0];");
        try self.writeLine("        const max = params[1];");
        try self.writeLine("        return min + random.float(f64) * (max - min);");
        try self.writeLine("    } else if (std.mem.eql(u8, distribution, \"normal\")) {");
        try self.writeLine("        const mean = params[0];");
        try self.writeLine("        const std_dev = params[1];");
        try self.writeLine("        const rand1 = random.float(f64);");
        try self.writeLine("        const rand2 = random.float(f64);");
        try self.writeLine("        const z0 = math.sqrt(-2.0 * math.ln(rand1)) * math.cos(2.0 * math.pi * rand2);");
        try self.writeLine("        return mean + std_dev * z0;");
        try self.writeLine("    }");
        try self.writeLine("    return 0.0; // Default case");
        try self.writeLine("}");
        try self.writeLine("");
        try self.writeLine("fn observe(distribution: []const u8, params: []const f64, value: f64) void {");
        try self.writeLine("    _ = distribution; _ = params; _ = value; // TODO: Implement");
        try self.writeLine("}");
        try self.writeLine("");
        try self.writeLine("fn prob_assert(condition: bool, confidence: f64) void {");
        try self.writeLine("    _ = confidence;");
        try self.writeLine("    if (!condition) @panic(\"Probabilistic assertion failed\");");
        try self.writeLine("}");
        try self.writeLine("");
        
        // Generate standard library helper functions
        try self.writeLine("fn std_print(message: []const u8) void {");
        try self.writeLine("    debug_print(\"{s}\\n\", .{message});");
        try self.writeLine("}");
        try self.writeLine("");
        try self.writeLine("fn std_print_int(value: i32) void {");
        try self.writeLine("    debug_print(\"{d}\\n\", .{value});");
        try self.writeLine("}");
        try self.writeLine("");
        try self.writeLine("fn std_print_float(value: f64) void {");
        try self.writeLine("    debug_print(\"{d}\\n\", .{value});");
        try self.writeLine("}");
        try self.writeLine("");
        // Add string concatenation function that handles null termination
        try self.writeLine("fn string_concat_z(a: [:0]const u8, b: [:0]const u8) [:0]const u8 {");
        try self.writeLine("    const result = std.fmt.allocPrintZ(allocator, \"{s}{s}\", .{a, b}) catch return \"<concat_error>\";");
        try self.writeLine("    return result;");
        try self.writeLine("}");
        try self.writeLine("");
        
        // Add simplified add function with proper type handling
        try self.writeLine("fn sever_add(a: anytype, b: anytype) @TypeOf(a, b) {");
        try self.writeLine("    const T = @TypeOf(a, b);");
        try self.writeLine("    const info = @typeInfo(T);");
        try self.writeLine("    return switch (info) {");
        try self.writeLine("        .pointer => |ptr_info| if (ptr_info.child == u8) string_concat_z(a, b) else @compileError(\"Unsupported pointer type: \" ++ @typeName(T)),");
        try self.writeLine("        .int, .float, .comptime_int, .comptime_float => a + b,");
        try self.writeLine("        else => @compileError(\"Unsupported type for addition: \" ++ @typeName(T)),");
        try self.writeLine("    };");
        try self.writeLine("}");
        try self.writeLine("");
        
        // HTTP standard library functions
        try self.writeLine("// HTTP Client Functions");
        try self.writeLine("fn http_get(url: []const u8) []const u8 {");
        try self.writeLine("    var client = std.http.Client{ .allocator = allocator };");
        try self.writeLine("    defer client.deinit();");
        try self.writeLine("");
        try self.writeLine("    const uri = std.Uri.parse(url) catch return \"<error: invalid URL>\";");
        try self.writeLine("    var server_header_buffer: [16384]u8 = undefined;");
        try self.writeLine("    var req = client.open(.GET, uri, .{");
        try self.writeLine("        .server_header_buffer = &server_header_buffer,");
        try self.writeLine("    }) catch return \"<error: connection failed>\";");
        try self.writeLine("    defer req.deinit();");
        try self.writeLine("");
        try self.writeLine("    req.send() catch return \"<error: send failed>\";");
        try self.writeLine("    req.finish() catch return \"<error: finish failed>\";");
        try self.writeLine("    req.wait() catch return \"<error: wait failed>\";");
        try self.writeLine("");
        try self.writeLine("    if (req.response.status != .ok) {");
        try self.writeLine("        return \"<error: HTTP error>\";");
        try self.writeLine("    }");
        try self.writeLine("");
        try self.writeLine("    const body = req.reader().readAllAlloc(allocator, 1024 * 1024) catch return \"<error: read failed>\";");
        try self.writeLine("    return body;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn http_post(url: []const u8, body: []const u8) []const u8 {");
        try self.writeLine("    var client = std.http.Client{ .allocator = allocator };");
        try self.writeLine("    defer client.deinit();");
        try self.writeLine("");
        try self.writeLine("    const uri = std.Uri.parse(url) catch return \"<error: invalid URL>\";");
        try self.writeLine("    var server_header_buffer: [16384]u8 = undefined;");
        try self.writeLine("    var req = client.open(.POST, uri, .{");
        try self.writeLine("        .server_header_buffer = &server_header_buffer,");
        try self.writeLine("        .extra_headers = &.{");
        try self.writeLine("            .{ .name = \"content-type\", .value = \"application/json\" },");
        try self.writeLine("        },");
        try self.writeLine("    }) catch return \"<error: connection failed>\";");
        try self.writeLine("    defer req.deinit();");
        try self.writeLine("");
        try self.writeLine("    req.transfer_encoding = .{ .content_length = body.len };");
        try self.writeLine("    req.send() catch return \"<error: send failed>\";");
        try self.writeLine("    _ = req.writer().writeAll(body) catch return \"<error: write failed>\";");
        try self.writeLine("    req.finish() catch return \"<error: finish failed>\";");
        try self.writeLine("    req.wait() catch return \"<error: wait failed>\";");
        try self.writeLine("");
        try self.writeLine("    if (req.response.status != .ok and req.response.status != .created) {");
        try self.writeLine("        return \"<error: HTTP error>\";");
        try self.writeLine("    }");
        try self.writeLine("");
        try self.writeLine("    const response_body = req.reader().readAllAlloc(allocator, 1024 * 1024) catch return \"<error: read failed>\";");
        try self.writeLine("    return response_body;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn http_put(url: []const u8, body: []const u8) []const u8 {");
        try self.writeLine("    var client = std.http.Client{ .allocator = allocator };");
        try self.writeLine("    defer client.deinit();");
        try self.writeLine("");
        try self.writeLine("    const uri = std.Uri.parse(url) catch return \"<error: invalid URL>\";");
        try self.writeLine("    var server_header_buffer: [16384]u8 = undefined;");
        try self.writeLine("    var req = client.open(.PUT, uri, .{");
        try self.writeLine("        .server_header_buffer = &server_header_buffer,");
        try self.writeLine("        .extra_headers = &.{");
        try self.writeLine("            .{ .name = \"content-type\", .value = \"application/json\" },");
        try self.writeLine("        },");
        try self.writeLine("    }) catch return \"<error: connection failed>\";");
        try self.writeLine("    defer req.deinit();");
        try self.writeLine("");
        try self.writeLine("    req.transfer_encoding = .{ .content_length = body.len };");
        try self.writeLine("    req.send() catch return \"<error: send failed>\";");
        try self.writeLine("    _ = req.writer().writeAll(body) catch return \"<error: write failed>\";");
        try self.writeLine("    req.finish() catch return \"<error: finish failed>\";");
        try self.writeLine("    req.wait() catch return \"<error: wait failed>\";");
        try self.writeLine("");
        try self.writeLine("    const response_body = req.reader().readAllAlloc(allocator, 1024 * 1024) catch return \"<error: read failed>\";");
        try self.writeLine("    return response_body;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn http_delete(url: []const u8) []const u8 {");
        try self.writeLine("    var client = std.http.Client{ .allocator = allocator };");
        try self.writeLine("    defer client.deinit();");
        try self.writeLine("");
        try self.writeLine("    const uri = std.Uri.parse(url) catch return \"<error: invalid URL>\";");
        try self.writeLine("    var server_header_buffer: [16384]u8 = undefined;");
        try self.writeLine("    var req = client.open(.DELETE, uri, .{");
        try self.writeLine("        .server_header_buffer = &server_header_buffer,");
        try self.writeLine("    }) catch return \"<error: connection failed>\";");
        try self.writeLine("    defer req.deinit();");
        try self.writeLine("");
        try self.writeLine("    req.send() catch return \"<error: send failed>\";");
        try self.writeLine("    req.finish() catch return \"<error: finish failed>\";");
        try self.writeLine("    req.wait() catch return \"<error: wait failed>\";");
        try self.writeLine("");
        try self.writeLine("    const response_body = req.reader().readAllAlloc(allocator, 1024 * 1024) catch return \"<error: read failed>\";");
        try self.writeLine("    return response_body;");
        try self.writeLine("}");
        try self.writeLine("");
        
        // File I/O standard library functions
        try self.writeLine("// File I/O Functions");
        try self.writeLine("fn file_read(path: []const u8) []const u8 {");
        try self.writeLine("    const file = std.fs.cwd().openFile(path, .{}) catch return \"<error: file not found>\";");
        try self.writeLine("    defer file.close();");
        try self.writeLine("");
        try self.writeLine("    const file_length = file.getEndPos() catch return \"<error: cannot get file size>\";");
        try self.writeLine("    if (file_length > 10 * 1024 * 1024) return \"<error: file too large>\"; // 10MB limit");
        try self.writeLine("");
        try self.writeLine("    const contents = file.readToEndAlloc(allocator, file_length) catch return \"<error: read failed>\";");
        try self.writeLine("    return contents;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn file_write(path: []const u8, content: []const u8) bool {");
        try self.writeLine("    const file = std.fs.cwd().createFile(path, .{}) catch return false;");
        try self.writeLine("    defer file.close();");
        try self.writeLine("");
        try self.writeLine("    file.writeAll(content) catch return false;");
        try self.writeLine("    return true;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn file_append(path: []const u8, content: []const u8) bool {");
        try self.writeLine("    const file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch {");
        try self.writeLine("        // If file doesn't exist, create it");
        try self.writeLine("        const new_file = std.fs.cwd().createFile(path, .{}) catch return false;");
        try self.writeLine("        defer new_file.close();");
        try self.writeLine("        new_file.writeAll(content) catch return false;");
        try self.writeLine("        return true;");
        try self.writeLine("    };");
        try self.writeLine("    defer file.close();");
        try self.writeLine("");
        try self.writeLine("    file.seekFromEnd(0) catch return false;");
        try self.writeLine("    file.writeAll(content) catch return false;");
        try self.writeLine("    return true;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn file_exists(path: []const u8) bool {");
        try self.writeLine("    std.fs.cwd().access(path, .{}) catch return false;");
        try self.writeLine("    return true;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn file_delete(path: []const u8) bool {");
        try self.writeLine("    std.fs.cwd().deleteFile(path) catch return false;");
        try self.writeLine("    return true;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn file_size(path: []const u8) i64 {");
        try self.writeLine("    const file = std.fs.cwd().openFile(path, .{}) catch return -1;");
        try self.writeLine("    defer file.close();");
        try self.writeLine("");
        try self.writeLine("    const size = file.getEndPos() catch return -1;");
        try self.writeLine("    return @intCast(size);");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn dir_create(path: []const u8) bool {");
        try self.writeLine("    std.fs.cwd().makeDir(path) catch return false;");
        try self.writeLine("    return true;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn dir_exists(path: []const u8) bool {");
        try self.writeLine("    var dir = std.fs.cwd().openDir(path, .{}) catch return false;");
        try self.writeLine("    dir.close();");
        try self.writeLine("    return true;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn dir_list(path: []const u8) []const u8 {");
        try self.writeLine("    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return \"<error: cannot open directory>\";");
        try self.writeLine("    defer dir.close();");
        try self.writeLine("");
        try self.writeLine("    var result = std.ArrayList(u8).init(allocator);");
        try self.writeLine("    var iterator = dir.iterate();");
        try self.writeLine("");
        try self.writeLine("    while (iterator.next() catch return \"<error: iteration failed>\") |entry| {");
        try self.writeLine("        result.appendSlice(entry.name) catch return \"<error: out of memory>\";");
        try self.writeLine("        if (entry.kind == .directory) {");
        try self.writeLine("            result.appendSlice(\"/\") catch return \"<error: out of memory>\";");
        try self.writeLine("        }");
        try self.writeLine("        result.appendSlice(\"\\n\") catch return \"<error: out of memory>\";");
        try self.writeLine("    }");
        try self.writeLine("");
        try self.writeLine("    return result.toOwnedSlice() catch return \"<error: out of memory>\";");
        try self.writeLine("}");
        try self.writeLine("");
        
        // JSON standard library functions
        try self.writeLine("// JSON Functions");
        try self.writeLine("fn json_parse(json_str: []const u8) []const u8 {");
        try self.writeLine("    var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch return \"<error: invalid JSON>\";");
        try self.writeLine("    defer parsed.deinit();");
        try self.writeLine("");
        try self.writeLine("    // For now, just return a formatted representation");
        try self.writeLine("    const formatted = std.json.stringifyAlloc(allocator, parsed.value, .{ .whitespace = .indent_2 }) catch return \"<error: stringify failed>\";");
        try self.writeLine("    return formatted;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn json_get_string(json_str: []const u8, key: []const u8) []const u8 {");
        try self.writeLine("    var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch return \"<error: invalid JSON>\";");
        try self.writeLine("    defer parsed.deinit();");
        try self.writeLine("");
        try self.writeLine("    if (parsed.value != .object) return \"<error: not an object>\";");
        try self.writeLine("");
        try self.writeLine("    const value = parsed.value.object.get(key) orelse return \"<error: key not found>\";");
        try self.writeLine("    if (value != .string) return \"<error: value is not a string>\";");
        try self.writeLine("");
        try self.writeLine("    return allocator.dupe(u8, value.string) catch return \"<error: out of memory>\";");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn json_get_number(json_str: []const u8, key: []const u8) f64 {");
        try self.writeLine("    var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch return -1.0;");
        try self.writeLine("    defer parsed.deinit();");
        try self.writeLine("");
        try self.writeLine("    if (parsed.value != .object) return -1.0;");
        try self.writeLine("");
        try self.writeLine("    const value = parsed.value.object.get(key) orelse return -1.0;");
        try self.writeLine("    return switch (value) {");
        try self.writeLine("        .integer => |i| @floatFromInt(i),");
        try self.writeLine("        .float => |f| f,");
        try self.writeLine("        .number_string => |s| std.fmt.parseFloat(f64, s) catch -1.0,");
        try self.writeLine("        else => -1.0,");
        try self.writeLine("    };");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn json_get_bool(json_str: []const u8, key: []const u8) bool {");
        try self.writeLine("    var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch return false;");
        try self.writeLine("    defer parsed.deinit();");
        try self.writeLine("");
        try self.writeLine("    if (parsed.value != .object) return false;");
        try self.writeLine("");
        try self.writeLine("    const value = parsed.value.object.get(key) orelse return false;");
        try self.writeLine("    if (value != .bool) return false;");
        try self.writeLine("");
        try self.writeLine("    return value.bool;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn json_has_key(json_str: []const u8, key: []const u8) bool {");
        try self.writeLine("    var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch return false;");
        try self.writeLine("    defer parsed.deinit();");
        try self.writeLine("");
        try self.writeLine("    if (parsed.value != .object) return false;");
        try self.writeLine("");
        try self.writeLine("    return parsed.value.object.contains(key);");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn json_stringify_object(keys: []const []const u8, values: []const []const u8) []const u8 {");
        try self.writeLine("    if (keys.len != values.len) return \"<error: mismatched arrays>\";");
        try self.writeLine("");
        try self.writeLine("    var result = std.ArrayList(u8).init(allocator);");
        try self.writeLine("    result.appendSlice(\"{\") catch return \"<error: out of memory>\";");
        try self.writeLine("");
        try self.writeLine("    for (keys, values, 0..) |key, value, i| {");
        try self.writeLine("        if (i > 0) result.appendSlice(\",\") catch return \"<error: out of memory>\";");
        try self.writeLine("        result.appendSlice(\"\\\"\") catch return \"<error: out of memory>\";");
        try self.writeLine("        result.appendSlice(key) catch return \"<error: out of memory>\";");
        try self.writeLine("        result.appendSlice(\"\\\":\\\"\") catch return \"<error: out of memory>\";");
        try self.writeLine("        result.appendSlice(value) catch return \"<error: out of memory>\";");
        try self.writeLine("        result.appendSlice(\"\\\"\") catch return \"<error: out of memory>\";");
        try self.writeLine("    }");
        try self.writeLine("");
        try self.writeLine("    result.appendSlice(\"}\") catch return \"<error: out of memory>\";");
        try self.writeLine("    return result.toOwnedSlice() catch return \"<error: out of memory>\";");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn json_stringify_array(values: []const []const u8) []const u8 {");
        try self.writeLine("    var result = std.ArrayList(u8).init(allocator);");
        try self.writeLine("    result.appendSlice(\"[\") catch return \"<error: out of memory>\";");
        try self.writeLine("");
        try self.writeLine("    for (values, 0..) |value, i| {");
        try self.writeLine("        if (i > 0) result.appendSlice(\",\") catch return \"<error: out of memory>\";");
        try self.writeLine("        result.appendSlice(\"\\\"\") catch return \"<error: out of memory>\";");
        try self.writeLine("        result.appendSlice(value) catch return \"<error: out of memory>\";");
        try self.writeLine("        result.appendSlice(\"\\\"\") catch return \"<error: out of memory>\";");
        try self.writeLine("    }");
        try self.writeLine("");
        try self.writeLine("    result.appendSlice(\"]\") catch return \"<error: out of memory>\";");
        try self.writeLine("    return result.toOwnedSlice() catch return \"<error: out of memory>\";");
        try self.writeLine("}");
        try self.writeLine("");
        
        // String manipulation standard library functions
        try self.writeLine("// String Functions");
        try self.writeLine("fn str_length(s: []const u8) i32 {");
        try self.writeLine("    return @intCast(s.len);");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn str_substring(s: []const u8, start: i64, end: i64) []const u8 {");
        try self.writeLine("    if (start < 0 or end < 0 or start >= s.len or end > s.len or start >= end) {");
        try self.writeLine("        return \"<error: invalid range>\";");
        try self.writeLine("    }");
        try self.writeLine("    const start_idx: usize = @intCast(start);");
        try self.writeLine("    const end_idx: usize = @intCast(end);");
        try self.writeLine("    return allocator.dupe(u8, s[start_idx..end_idx]) catch return \"<error: out of memory>\";");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn str_contains(s: []const u8, needle: []const u8) bool {");
        try self.writeLine("    return std.mem.indexOf(u8, s, needle) != null;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn str_starts_with(s: []const u8, prefix: []const u8) bool {");
        try self.writeLine("    return std.mem.startsWith(u8, s, prefix);");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn str_ends_with(s: []const u8, suffix: []const u8) bool {");
        try self.writeLine("    return std.mem.endsWith(u8, s, suffix);");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn str_index_of(s: []const u8, needle: []const u8) i64 {");
        try self.writeLine("    if (std.mem.indexOf(u8, s, needle)) |index| {");
        try self.writeLine("        return @intCast(index);");
        try self.writeLine("    }");
        try self.writeLine("    return -1;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn str_replace(s: []const u8, needle: []const u8, replacement: []const u8) []const u8 {");
        try self.writeLine("    return std.mem.replaceOwned(u8, allocator, s, needle, replacement) catch return \"<error: replace failed>\";");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn str_to_upper(s: []const u8) []const u8 {");
        try self.writeLine("    var result = allocator.alloc(u8, s.len) catch return \"<error: out of memory>\";");
        try self.writeLine("    for (s, 0..) |char, i| {");
        try self.writeLine("        result[i] = std.ascii.toUpper(char);");
        try self.writeLine("    }");
        try self.writeLine("    return result;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn str_to_lower(s: []const u8) []const u8 {");
        try self.writeLine("    var result = allocator.alloc(u8, s.len) catch return \"<error: out of memory>\";");
        try self.writeLine("    for (s, 0..) |char, i| {");
        try self.writeLine("        result[i] = std.ascii.toLower(char);");
        try self.writeLine("    }");
        try self.writeLine("    return result;");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn str_trim(s: []const u8) []const u8 {");
        try self.writeLine("    const trimmed = std.mem.trim(u8, s, \" \\t\\n\\r\");");
        try self.writeLine("    return allocator.dupe(u8, trimmed) catch return \"<error: out of memory>\";");
        try self.writeLine("}");
        try self.writeLine("");
        
        try self.writeLine("fn str_equals(a: []const u8, b: []const u8) bool {");
        try self.writeLine("    return std.mem.eql(u8, a, b);");
        try self.writeLine("}");
        try self.writeLine("");
        
        // Generate all functions
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            
            try self.generateFunction(func_name, function);
            try self.writeLine("");
        }
        
        // Generate main function wrapper if entry point is not "main"
        if (!std.mem.eql(u8, program.entry, "main")) {
            try self.writeLine("pub fn main() !void {");
            self.indent_level += 1;
            try self.writeIndent();
            try self.writeLine("sever_runtime.init(null);");
            try self.writeIndent();
            try self.write("try ");
            try self.write(program.entry);
            try self.write("();");
            try self.writeLine("");
            self.indent_level -= 1;
            try self.writeLine("}");
        } else {
            // If main exists, add runtime initialization at the beginning
            const main_func = program.functions.get("main").?;
            if (main_func.body.items.len > 0) {
                try self.writeLine("// Runtime initialization will be added automatically");
            }
        }
    }
    
    fn generateFunction(self: *CodeGen, name: []const u8, function: *Function) CodeGenError!void {
        self.current_function_name = name;
        self.current_function = function;
        
        // Function signature
        if (std.mem.eql(u8, name, "main")) {
            try self.write("pub fn main() ");
        } else {
            try self.write("fn ");
            try self.write(name);
            try self.write("(");
            
            // Parameters
            for (function.args.items, 0..) |param, i| {
                if (i > 0) try self.write(", ");
                try self.write(param.name);
                try self.write(": ");
                try self.generateType(param.type);
            }
            
            try self.write(") ");
        }
        
        // Return type - main function should return !void and print result
        if (std.mem.eql(u8, name, "main")) {
            try self.write("!void");
        } else if (function.@"return" == .void) {
            try self.write("void");
        } else {
            try self.generateType(function.@"return");
        }
        
        try self.writeLine(" {");
        self.indent_level += 1;
        
        // Add runtime initialization for main function
        if (std.mem.eql(u8, name, "main")) {
            try self.writeIndent();
            try self.writeLine("sever_runtime_init(null);");
        }
        
        // Function body
        for (function.body.items) |*stmt| {
            try self.generateStatement(stmt);
        }
        
        self.indent_level -= 1;
        try self.writeLine("}");
    }
    
    fn generateStatement(self: *CodeGen, stmt: *Statement) CodeGenError!void {
        switch (stmt.*) {
            .let => |*let_stmt| {
                try self.writeIndent();
                if (let_stmt.mutable) {
                    try self.write("var ");
                } else {
                    try self.write("const ");
                }
                try self.write(let_stmt.name);
                
                if (let_stmt.type) |stmt_type| {
                    try self.write(": ");
                    try self.generateType(stmt_type);
                }
                
                try self.write(" = ");
                try self.generateExpression(&let_stmt.value);
                try self.writeLine(";");
            },
            
            .assign => |*assign_stmt| {
                try self.writeIndent();
                try self.generateLValue(&assign_stmt.target);
                try self.write(" = ");
                try self.generateExpression(&assign_stmt.value);
                try self.writeLine(";");
            },
            
            .@"if" => |*if_stmt| {
                try self.writeIndent();
                try self.write("if (");
                try self.generateExpression(&if_stmt.condition);
                try self.writeLine(") {");
                
                self.indent_level += 1;
                for (if_stmt.then.items) |*then_stmt| {
                    try self.generateStatement(then_stmt);
                }
                self.indent_level -= 1;
                
                if (if_stmt.@"else") |*else_stmts| {
                    try self.writeLine("} else {");
                    self.indent_level += 1;
                    for (else_stmts.items) |*else_stmt| {
                        try self.generateStatement(else_stmt);
                    }
                    self.indent_level -= 1;
                }
                
                try self.writeLine("}");
            },
            
            .@"while" => |*while_stmt| {
                try self.writeIndent();
                try self.write("while (");
                try self.generateExpression(&while_stmt.condition);
                try self.writeLine(") {");
                
                self.indent_level += 1;
                for (while_stmt.body.items) |*body_stmt| {
                    try self.generateStatement(body_stmt);
                }
                self.indent_level -= 1;
                
                try self.writeLine("}");
            },
            
            .@"return" => |*return_expr| {
                try self.writeIndent();
                // Check if we're in main function and need to print result instead of returning it
                if (self.current_function) |func| {
                    if (func.@"return" != .void and self.current_function_name != null and std.mem.eql(u8, self.current_function_name.?, "main")) {
                        // For main function, print the result and return void
                        try self.write("const _sever_main_result = ");
                        try self.generateExpression(return_expr);
                        try self.writeLine(";");
                        try self.writeIndent();
                        try self.writeLine("std_print_int(_sever_main_result);");
                        try self.writeIndent();
                        try self.writeLine("return;");
                    } else {
                        try self.write("return ");
                        try self.generateExpression(return_expr);
                        try self.writeLine(";");
                    }
                } else {
                    try self.write("return ");
                    try self.generateExpression(return_expr);
                    try self.writeLine(";");
                }
            },
            
            .@"break" => {
                try self.writeIndent();
                try self.writeLine("break;");
            },
            
            .@"continue" => {
                try self.writeIndent();
                try self.writeLine("continue;");
            },
            
            .observe => |*observe_stmt| {
                try self.writeIndent();
                try self.write("observe(\"");
                try self.write(observe_stmt.distribution);
                try self.write("\", &[_]f64{");
                
                for (observe_stmt.params.items, 0..) |*param, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateExpression(param);
                }
                
                try self.write("}, ");
                try self.generateExpression(&observe_stmt.value);
                try self.writeLine(");");
            },
            
            .prob_assert => |*assert_stmt| {
                try self.writeIndent();
                try self.write("prob_assert(");
                try self.generateExpression(&assert_stmt.condition);
                try self.write(", ");
                const confidence_str = std.fmt.allocPrint(self.allocator, "{d}", .{assert_stmt.confidence}) catch return CodeGenError.OutOfMemory;
                defer self.allocator.free(confidence_str);
                try self.write(confidence_str);
                try self.writeLine(");");
            },
            
            .match => |*match_stmt| {
                return try self.generateMatchStatement(match_stmt);
            },
            
            .@"try" => |*try_stmt| {
                return try self.generateTryStatement(try_stmt);
            },
            
            .@"throw" => |*throw_expr| {
                try self.writeIndent();
                // For now, generate a simple panic with the message
                try self.write("std.debug.panic(");
                try self.generateExpression(throw_expr);
                try self.writeLine(", .{});");
            },
            
            .expression => |*expr| {
                try self.writeIndent();
                try self.generateExpression(expr);
                try self.writeLine(";");
            },
            
            else => {
                return CodeGenError.UnsupportedStatement;
            },
        }
    }
    
    fn generateExpression(self: *CodeGen, expr: *Expression) CodeGenError!void {
        switch (expr.*) {
            .literal => |literal| {
                switch (literal) {
                    .integer => |i| {
                        const str = std.fmt.allocPrint(self.allocator, "{d}", .{i}) catch return CodeGenError.OutOfMemory;
                        defer self.allocator.free(str);
                        try self.write(str);
                    },
                    .float => |f| {
                        const str = std.fmt.allocPrint(self.allocator, "{d}", .{f}) catch return CodeGenError.OutOfMemory;
                        defer self.allocator.free(str);
                        try self.write(str);
                    },
                    .string => |s| {
                        try self.write("\"");
                        try self.write(s);
                        try self.write("\"");
                    },
                    .boolean => |b| try self.write(if (b) "true" else "false"),
                    .null => try self.write("null"),
                }
            },
            
            .variable => |var_name| {
                try self.write(var_name);
            },
            
            .call => |*call_expr| {
                try self.write(call_expr.function);
                try self.write("(");
                
                for (call_expr.args.items, 0..) |*arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateExpression(arg);
                }
                
                try self.write(")");
            },
            
            .op => |*op_expr| {
                try self.generateOperation(op_expr);
            },
            
            .index => |*index_expr| {
                try self.generateExpression(index_expr.array);
                try self.write("[");
                try self.generateExpression(index_expr.index);
                try self.write("]");
            },
            
            .field => |*field_expr| {
                try self.generateExpression(field_expr.object);
                try self.write(".");
                try self.write(field_expr.field);
            },
            
            .array => |*array_expr| {
                // Use Zig's automatic type inference for arrays
                if (array_expr.items.len > 0) {
                    try self.write("[_]@TypeOf(");
                    try self.generateExpression(@constCast(&array_expr.items[0]));
                    try self.write("){");
                    
                    for (array_expr.items, 0..) |*elem, i| {
                        if (i > 0) try self.write(", ");
                        try self.generateExpression(elem);
                    }
                    
                    try self.write("}");
                } else {
                    // Empty array - need explicit type, for now use void
                    try self.write("[_]void{}");
                }
            },
            
            .sample => |*sample_expr| {
                try self.write("sample(\"");
                try self.write(sample_expr.distribution);
                try self.write("\", &[_]f64{");
                
                for (sample_expr.params.items, 0..) |*param, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateExpression(param);
                }
                
                try self.write("})");
            },
            
            .cast => |*cast_expr| {
                try self.write("@as(");
                try self.generateType(cast_expr.type);
                try self.write(", ");
                try self.generateExpression(cast_expr.value);
                try self.write(")");
            },
            
            .@"struct" => |*struct_expr| {
                // Generate anonymous struct literal
                try self.write(".{");
                
                var field_iter = struct_expr.iterator();
                var first = true;
                while (field_iter.next()) |entry| {
                    if (!first) try self.write(", ");
                    first = false;
                    
                    const field_name = entry.key_ptr.*;
                    const field_value = entry.value_ptr;
                    
                    try self.write(".");
                    try self.write(field_name);
                    try self.write(" = ");
                    try self.generateExpression(@constCast(field_value));
                }
                
                try self.write("}");
            },
            
            .enum_constructor => |*enum_expr| {
                // Generate enum constructor call
                try self.write(enum_expr.enum_type);
                try self.write(".");
                try self.write(enum_expr.variant);
                
                // If there's an associated value, include it
                if (enum_expr.value) |value_expr| {
                    try self.write("(");
                    try self.generateExpression(value_expr);
                    try self.write(")");
                }
            },
            
            .hashmap => |*hashmap_expr| {
                // Generate hashmap literal using Zig's StringHashMap for string keys
                try self.write("blk: {\n");
                self.indent_level += 1;
                try self.writeIndent();
                try self.write("var map = std.StringHashMap(i32).init(allocator);\n");
                
                // Add all entries
                var map_iter = hashmap_expr.iterator();
                while (map_iter.next()) |entry| {
                    try self.writeIndent();
                    try self.write("try map.put(\"");
                    try self.write(entry.key_ptr.*);
                    try self.write("\", ");
                    try self.generateExpression(@constCast(entry.value_ptr));
                    try self.write(");\n");
                }
                
                try self.writeIndent();
                try self.write("break :blk map;\n");
                self.indent_level -= 1;
                try self.writeIndent();
                try self.write("}");
            },
            
            .set => |*set_expr| {
                // Generate set literal using HashMap with void values
                try self.write("blk: {\n");
                self.indent_level += 1;
                try self.writeIndent();
                try self.write("var set = std.HashMap(i32, void, std.hash_map.AutoContext(i32), std.hash_map.default_max_load_percentage).init(allocator);\n");
                
                for (set_expr.items) |*elem| {
                    try self.writeIndent();
                    try self.write("try set.put(");
                    try self.generateExpression(@constCast(elem));
                    try self.write(", {});\n");
                }
                
                try self.writeIndent();
                try self.write("break :blk set;\n");
                self.indent_level -= 1;
                try self.writeIndent();
                try self.write("}");
            },
            
            .tuple => |*tuple_expr| {
                // Generate tuple literal as anonymous struct
                try self.write(".{");
                
                for (tuple_expr.items, 0..) |*elem, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateExpression(@constCast(elem));
                }
                
                try self.write("}");
            },
            
            .record => |*record_expr| {
                // Generate record literal as named struct literal
                try self.write(record_expr.type_name);
                try self.write("{");
                
                var field_iter = record_expr.fields.iterator();
                var first = true;
                while (field_iter.next()) |entry| {
                    if (!first) try self.write(", ");
                    first = false;
                    
                    try self.write(".");
                    try self.write(entry.key_ptr.*);
                    try self.write(" = ");
                    try self.generateExpression(@constCast(entry.value_ptr));
                }
                
                try self.write("}");
            },
            
            else => {
                return CodeGenError.UnsupportedExpression;
            },
        }
    }
    
    fn generateOperation(self: *CodeGen, op_expr: anytype) CodeGenError!void {
        const args = &op_expr.args;
        
        switch (op_expr.kind) {
            .not => {
                try self.write("!");
                try self.generateExpression(@constCast(&args.items[0]));
            },
            
            .bitnot => {
                try self.write("~");
                try self.generateExpression(@constCast(&args.items[0]));
            },
            
            .add => {
                // For add operations, use the sever_add helper function that can handle
                // both numeric addition and string concatenation at compile time
                if (args.items.len >= 2) {
                    try self.write("sever_add(");
                    try self.generateExpression(@constCast(&args.items[0]));
                    try self.write(", ");
                    try self.generateExpression(@constCast(&args.items[1]));
                    try self.write(")");
                } else {
                    return CodeGenError.UnsupportedExpression;
                }
            },
            
            .div => {
                // For division operations, use @divTrunc for integer division in Zig
                if (args.items.len >= 2) {
                    try self.write("@divTrunc(");
                    try self.generateExpression(@constCast(&args.items[0]));
                    try self.write(", ");
                    try self.generateExpression(@constCast(&args.items[1]));
                    try self.write(")");
                } else {
                    return CodeGenError.UnsupportedExpression;
                }
            },
            
            else => {
                // Binary operations
                if (args.items.len >= 2) {
                    try self.write("(");
                    try self.generateExpression(@constCast(&args.items[0]));
                    try self.write(" ");
                    try self.write(try self.getOperatorSymbol(op_expr.kind));
                    try self.write(" ");
                    try self.generateExpression(@constCast(&args.items[1]));
                    try self.write(")");
                } else {
                    return CodeGenError.UnsupportedExpression;
                }
            },
        }
    }
    
    fn generateLValue(self: *CodeGen, lvalue: *const SirsParser.LValue) CodeGenError!void {
        switch (lvalue.*) {
            .variable => |var_name| {
                try self.write(var_name);
            },
            
            .index => |*index_lvalue| {
                try self.generateLValue(index_lvalue.array);
                try self.write("[");
                try self.generateExpression(@constCast(&index_lvalue.index));
                try self.write("]");
            },
            
            .field => |*field_lvalue| {
                try self.generateLValue(field_lvalue.object);
                try self.write(".");
                try self.write(field_lvalue.field);
            },
        }
    }
    
    fn generateCustomTypes(self: *CodeGen, program: *Program) CodeGenError!void {
        var type_iter = program.types.iterator();
        while (type_iter.next()) |entry| {
            const type_name = entry.key_ptr.*;
            const type_def = entry.value_ptr;
            
            switch (type_def.*) {
                .@"enum" => |enum_def| {
                    try self.write("const ");
                    try self.write(type_name);
                    try self.writeLine(" = enum {");
                    self.indent_level += 1;
                    
                    // Generate enum variants
                    var variant_iter = enum_def.variants.iterator();
                    while (variant_iter.next()) |variant_entry| {
                        const variant_name = variant_entry.key_ptr.*;
                        const variant_type = variant_entry.value_ptr.*;
                        
                        try self.writeIndent();
                        try self.write(variant_name);
                        
                        // If variant has associated type, we'd need to handle it differently
                        // For now, we're generating simple enums without associated values
                        if (variant_type != null) {
                            // In a full implementation, we'd generate tagged unions for enums with associated values
                            // For now, we'll just generate a comment
                            try self.write(" // TODO: associated value support");
                        }
                        
                        try self.writeLine(",");
                    }
                    
                    self.indent_level -= 1;
                    try self.writeLine("};");
                    try self.writeLine("");
                },
                .@"error" => |error_def| {
                    try self.write("const ");
                    try self.write(type_name);
                    try self.write(" = error{");
                    try self.write(error_def.name);
                    try self.writeLine("};");
                    try self.writeLine("");
                },
                .record => |record_def| {
                    try self.write("const ");
                    try self.write(type_name);
                    try self.writeLine(" = struct {");
                    self.indent_level += 1;
                    
                    // Generate record fields
                    var field_iter = record_def.fields.iterator();
                    while (field_iter.next()) |field_entry| {
                        const field_name = field_entry.key_ptr.*;
                        const field_type = field_entry.value_ptr.*;
                        
                        try self.writeIndent();
                        try self.write(field_name);
                        try self.write(": ");
                        try self.generateType(field_type.*);
                        try self.writeLine(",");
                    }
                    
                    self.indent_level -= 1;
                    try self.writeLine("};");
                    try self.writeLine("");
                },
                .discriminated_union => |union_def| {
                    try self.write("const ");
                    try self.write(type_name);
                    try self.writeLine(" = union(enum) {");
                    self.indent_level += 1;
                    
                    // Generate union variants
                    for (union_def.variants.items, 0..) |variant_type, i| {
                        try self.writeIndent();
                        try self.write("variant");
                        const variant_index_str = std.fmt.allocPrint(self.allocator, "{d}", .{i}) catch return CodeGenError.OutOfMemory;
                        defer self.allocator.free(variant_index_str);
                        try self.write(variant_index_str);
                        try self.write(": ");
                        try self.generateType(variant_type.*);
                        try self.writeLine(",");
                    }
                    
                    self.indent_level -= 1;
                    try self.writeLine("};");
                    try self.writeLine("");
                },
                else => {
                    // Handle other type definitions if needed
                },
            }
        }
        
        // Generate generic type definitions
        var generic_iter = program.generic_types.iterator();
        while (generic_iter.next()) |entry| {
            const type_name = entry.key_ptr.*;
            const generic_type = entry.value_ptr;
            
            // Generate generic type as a Zig function that returns a type
            try self.write("fn ");
            try self.write(type_name);
            try self.write("(comptime ");
            
            // Generate type parameters
            for (generic_type.type_params.items, 0..) |param_name, i| {
                if (i > 0) try self.write(", comptime ");
                try self.write(param_name);
                try self.write(": type");
            }
            
            try self.write(") type {\n");
            self.indent_level += 1;
            
            // Add parameter usage to avoid unused parameter warnings
            for (generic_type.type_params.items) |param_name| {
                try self.writeIndent();
                try self.write("_ = ");
                try self.write(param_name);
                try self.writeLine(";");
            }
            
            try self.writeIndent();
            try self.write("return ");
            
            // Generate the type definition with parameters substituted
            try self.generateType(generic_type.definition);
            try self.writeLine(";");
            
            self.indent_level -= 1;
            try self.writeLine("}");
            try self.writeLine("");
        }
        
        // Generate interface vtables
        var interface_iter = program.interfaces.iterator();
        while (interface_iter.next()) |entry| {
            const interface_name = entry.key_ptr.*;
            const interface_def = entry.value_ptr;
            
            // Generate vtable struct
            try self.write("const ");
            try self.write(interface_name);
            try self.writeLine("VTable = struct {");
            self.indent_level += 1;
            
            var method_iter = interface_def.methods.iterator();
            while (method_iter.next()) |method_entry| {
                const method_name = method_entry.key_ptr.*;
                const signature = method_entry.value_ptr;
                
                try self.writeIndent();
                try self.write(method_name);
                try self.write(": *const fn(");
                
                // Add self parameter as first argument
                try self.write("self: *anyopaque");
                
                for (signature.args.items, 0..) |arg_type, i| {
                    _ = i;
                    try self.write(", ");
                    try self.generateType(arg_type);
                }
                
                try self.write(") ");
                try self.generateType(signature.@"return");
                try self.writeLine(",");
            }
            
            self.indent_level -= 1;
            try self.writeLine("};");
            try self.writeLine("");
        }
    }
    
    fn generateType(self: *CodeGen, t: Type) CodeGenError!void {
        switch (t) {
            .void => try self.write("void"),
            .bool => try self.write("bool"),
            .i8 => try self.write("i8"),
            .i16 => try self.write("i16"),
            .i32 => try self.write("i32"),
            .i64 => try self.write("i64"),
            .u8 => try self.write("u8"),
            .u16 => try self.write("u16"),
            .u32 => try self.write("u32"),
            .u64 => try self.write("u64"),
            .f32 => try self.write("f32"),
            .f64 => try self.write("f64"),
            .str => try self.write("[]const u8"),
            
            .array => |arr| {
                try self.write("[");
                const size_str = std.fmt.allocPrint(self.allocator, "{d}", .{arr.size}) catch return CodeGenError.OutOfMemory;
                defer self.allocator.free(size_str);
                try self.write(size_str);
                try self.write("]");
                try self.generateType(arr.element.*);
            },
            
            .slice => |slice| {
                try self.write("[]");
                try self.generateType(slice.element.*);
            },
            
            .optional => |opt| {
                try self.write("?");
                try self.generateType(opt.*);
            },
            
            .@"enum" => |enum_def| {
                try self.write(enum_def.name);
            },
            
            .@"error" => |error_def| {
                try self.write(error_def.name);
            },
            
            .hashmap => |hashmap_def| {
                // Use StringHashMap for string keys, HashMap for others
                switch (hashmap_def.key.*) {
                    .str => {
                        try self.write("std.StringHashMap(");
                        try self.generateType(hashmap_def.value.*);
                        try self.write(")");
                    },
                    else => {
                        try self.write("std.HashMap(");
                        try self.generateType(hashmap_def.key.*);
                        try self.write(", ");
                        try self.generateType(hashmap_def.value.*);
                        try self.write(", std.hash_map.AutoContext(");
                        try self.generateType(hashmap_def.key.*);
                        try self.write("), std.hash_map.default_max_load_percentage)");
                    },
                }
            },
            
            .set => |set_def| {
                try self.write("std.HashMap(");
                try self.generateType(set_def.element.*);
                try self.write(", void, std.hash_map.AutoContext(");
                try self.generateType(set_def.element.*);
                try self.write("), std.hash_map.default_max_load_percentage)");
            },
            
            .tuple => |tuple_types| {
                try self.write("struct { ");
                for (tuple_types.items, 0..) |type_ptr, i| {
                    if (i > 0) try self.write(", ");
                    const field_name = std.fmt.allocPrint(self.allocator, "_{d}", .{i}) catch return CodeGenError.OutOfMemory;
                    defer self.allocator.free(field_name);
                    try self.write(field_name);
                    try self.write(": ");
                    try self.generateType(type_ptr.*);
                }
                try self.write(" }");
            },
            
            .record => |record_def| {
                try self.write(record_def.name);
            },
            
            .type_parameter => |param_name| {
                // In a monomorphized context, type parameters should be substituted
                // For now, just generate the parameter name as a placeholder
                try self.write(param_name);
            },
            
            .generic_instance => |generic_inst| {
                // Generate instantiated generic type
                try self.write(generic_inst.base_type);
                try self.write("(");
                for (generic_inst.type_args.items, 0..) |type_arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateType(type_arg.*);
                }
                try self.write(")");
            },
            
            .@"interface" => |interface_def| {
                // Interfaces generate as pointers to vtables in Zig
                try self.write("*const ");
                try self.write(interface_def.name);
                try self.write("VTable");
            },
            
            .trait_object => |trait_obj| {
                // Trait objects generate as struct with vtable and data pointer
                try self.write("struct { vtable: *const ");
                try self.write(trait_obj.trait_name);
                try self.write("VTable, data: *anyopaque }");
            },
            
            .discriminated_union => |union_def| {
                // Discriminated unions generate as tagged unions in Zig
                try self.write(union_def.name);
            },
            
            else => {
                return CodeGenError.UnsupportedType;
            },
        }
    }
    
    fn getOperatorSymbol(_: *CodeGen, op: SirsParser.OpKind) ![]const u8 {
        return switch (op) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .mod => "%",
            .eq => "==",
            .ne => "!=",
            .lt => "<",
            .le => "<=",
            .gt => ">",
            .ge => ">=",
            .@"and" => "and",
            .@"or" => "or",
            .bitand => "&",
            .bitor => "|",
            .bitxor => "^",
            .shl => "<<",
            .shr => ">>",
            else => return CodeGenError.UnsupportedExpression,
        };
    }
    
    fn compileZigFile(self: *CodeGen, zig_file: []const u8, output_file: []const u8) CodeGenError!void {
        // Extract just the basename for the package name  
        const basename = std.fs.path.basename(output_file);
        
        // Use the full output_file path which already includes dist/
        const cmd = std.fmt.allocPrint(self.allocator, "zig build-exe {s} -O ReleaseFast --name {s} -femit-bin={s}", .{ zig_file, basename, output_file }) catch return CodeGenError.OutOfMemory;
        defer self.allocator.free(cmd);
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "sh", "-c", cmd },
        }) catch return CodeGenError.IoError;
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            print("Compilation failed:\n{s}\n", .{result.stderr});
            return CodeGenError.CompilationError;
        }
    }
    
    fn generateMatchStatement(self: *CodeGen, match_stmt: anytype) CodeGenError!void {
        // Generate a match expression using if-else chain
        try self.writeIndent();
        try self.writeLine("{");
        self.indent_level += 1;
        
        // Store the match value in a temporary variable
        try self.writeIndent();
        try self.write("const _match_value = ");
        try self.generateExpression(&match_stmt.value);
        try self.writeLine(";");
        
        // Generate if-else chain for pattern matching
        for (match_stmt.cases.items, 0..) |*case, i| {
            if (i == 0) {
                try self.writeIndent();
                try self.write("if (");
            } else {
                try self.write(" else if (");
            }
            
            // Generate pattern matching condition
            try self.generatePatternCondition(&case.pattern, "_match_value");
            try self.writeLine(") {");
            
            self.indent_level += 1;
            
            // Generate variable bindings for the pattern
            try self.generatePatternBindings(&case.pattern, "_match_value");
            
            // Generate case body
            for (case.body.items) |*stmt| {
                try self.generateStatement(stmt);
            }
            
            self.indent_level -= 1;
            try self.writeIndent();
            try self.write("}");
        }
        
        // Close the final else
        if (match_stmt.cases.items.len > 0) {
            try self.writeLine("");
        }
        
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeLine("}");
    }
    
    fn generateTryStatement(self: *CodeGen, try_stmt: anytype) CodeGenError!void {
        // In Zig, we'll generate try-catch using error unions and if-else chains
        // For now, we'll generate a simplified version that catches any error
        
        try self.writeIndent();
        try self.writeLine("{");
        self.indent_level += 1;
        
        // Generate try body with error handling
        if (try_stmt.catch_clauses.items.len > 0) {
            // If there are catch clauses, wrap in error handling
            try self.writeIndent();
            try self.writeLine("if (true) {"); // Simple wrapper for now
            self.indent_level += 1;
            
            // Generate try body
            for (try_stmt.body.items) |*stmt| {
                try self.generateStatement(stmt);
            }
            
            self.indent_level -= 1;
            try self.writeIndent();
            try self.write("}");
            
            // Generate catch blocks
            for (try_stmt.catch_clauses.items) |*catch_clause| {
                try self.write(" else {");
                try self.writeLine("");
                self.indent_level += 1;
                
                // If there's a variable binding, create it (for now, skip to avoid unused variable)
                if (catch_clause.variable_name) |var_name| {
                    // Skip variable generation for now to avoid unused variable warnings
                    _ = var_name;
                    // try self.writeIndent();
                    // try self.write("const ");
                    // // Add prefix to avoid Zig reserved keywords
                    // try self.write("sever_");
                    // try self.write(var_name);
                    // try self.writeLine(" = \"Exception occurred\";"); // Simplified
                }
                
                // Generate catch body
                for (catch_clause.body.items) |*stmt| {
                    try self.generateStatement(stmt);
                }
                
                self.indent_level -= 1;
                try self.writeIndent();
                try self.write("}");
            }
            
            try self.writeLine("");
        } else {
            // No catch clauses, just generate try body
            for (try_stmt.body.items) |*stmt| {
                try self.generateStatement(stmt);
            }
        }
        
        // Generate finally block if present
        if (try_stmt.finally_body) |*finally_stmts| {
            try self.writeIndent();
            try self.writeLine("// Finally block");
            for (finally_stmts.items) |*stmt| {
                try self.generateStatement(stmt);
            }
        }
        
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeLine("}");
    }
    
    fn generatePatternCondition(self: *CodeGen, pattern: *SirsParser.Pattern, match_var: []const u8) CodeGenError!void {
        switch (pattern.*) {
            .literal => |literal| {
                try self.write(match_var);
                try self.write(" == ");
                try self.generateLiteral(literal);
            },
            
            .variable => |_| {
                // Variable patterns always match
                try self.write("true");
            },
            
            .wildcard => {
                // Wildcard patterns always match
                try self.write("true");
            },
            
            .@"struct" => |*struct_patterns| {
                // For struct patterns, we need to check each field
                // This is simplified - a full implementation would handle this properly
                try self.write("true"); // Simplified for now
                
                // In a full implementation, we would generate:
                // match_var.field1 == pattern.field1 && match_var.field2 == pattern.field2 && ...
                _ = struct_patterns; // Avoid unused warning
            },
            
            .@"enum" => |*enum_pattern| {
                // For enum patterns, check the tag matches
                // This is simplified - a full implementation would handle associated values properly
                try self.write("@intFromEnum(");
                try self.write(match_var);
                try self.write(") == @intFromEnum(");
                try self.write(enum_pattern.enum_type);
                try self.write(".");
                try self.write(enum_pattern.variant);
                try self.write(")");
            },
        }
    }
    
    fn generatePatternBindings(self: *CodeGen, pattern: *SirsParser.Pattern, match_var: []const u8) CodeGenError!void {
        switch (pattern.*) {
            .variable => |var_name| {
                // Bind the variable to the matched value
                try self.writeIndent();
                try self.write("const ");
                try self.write(var_name);
                try self.write(" = ");
                try self.write(match_var);
                try self.writeLine(";");
            },
            
            .@"struct" => |*struct_patterns| {
                // For struct patterns, bind each field
                var iter = struct_patterns.iterator();
                while (iter.next()) |entry| {
                    const field_name = entry.key_ptr.*;
                    const field_pattern = entry.value_ptr;
                    
                    // Create field access expression
                    const field_access = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ match_var, field_name });
                    defer self.allocator.free(field_access);
                    
                    // Recursively generate bindings for the field pattern
                    try self.generatePatternBindings(field_pattern, field_access);
                }
            },
            
            .@"enum" => |*enum_pattern| {
                // For enum patterns, bind any associated values
                if (enum_pattern.value_pattern) |value_pattern| {
                    // In a full implementation, we'd extract the associated value
                    // For now, just recursively handle the value pattern
                    try self.generatePatternBindings(value_pattern, match_var); // Simplified
                }
            },
            
            .literal, .wildcard => {
                // These patterns don't create bindings
            },
        }
    }
    
    fn generateLiteral(self: *CodeGen, literal: SirsParser.Literal) CodeGenError!void {
        switch (literal) {
            .integer => |i| {
                const str = std.fmt.allocPrint(self.allocator, "{d}", .{i}) catch return CodeGenError.OutOfMemory;
                defer self.allocator.free(str);
                try self.write(str);
            },
            .float => |f| {
                const str = std.fmt.allocPrint(self.allocator, "{d}", .{f}) catch return CodeGenError.OutOfMemory;
                defer self.allocator.free(str);
                try self.write(str);
            },
            .string => |s| {
                try self.write("\"");
                try self.write(s);
                try self.write("\"");
            },
            .boolean => |b| {
                if (b) {
                    try self.write("true");
                } else {
                    try self.write("false");
                }
            },
            .null => {
                try self.write("null");
            },
        }
    }
    
    fn write(self: *CodeGen, text: []const u8) CodeGenError!void {
        self.output.appendSlice(text) catch return CodeGenError.OutOfMemory;
    }
    
    fn writeLine(self: *CodeGen, text: []const u8) CodeGenError!void {
        self.output.appendSlice(text) catch return CodeGenError.OutOfMemory;
        self.output.append('\n') catch return CodeGenError.OutOfMemory;
    }
    
    fn writeIndent(self: *CodeGen) CodeGenError!void {
        var i: u32 = 0;
        while (i < self.indent_level) : (i += 1) {
            self.output.appendSlice("    ") catch return CodeGenError.OutOfMemory;
        }
    }
};