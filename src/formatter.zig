const std = @import("std");
const json = std.json;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const SirsParser = @import("sirs.zig");
const ErrorReporter = @import("error_reporter.zig").ErrorReporter;

/// SIRS Code Formatter
/// Formats SIRS JSON files with consistent indentation and style
pub const SirsFormatter = struct {
    allocator: Allocator,
    error_reporter: ErrorReporter,
    indent_size: u32,
    
    pub fn init(allocator: Allocator) SirsFormatter {
        return SirsFormatter{
            .allocator = allocator,
            .error_reporter = ErrorReporter.init(allocator),
            .indent_size = 2, // Default 2-space indentation
        };
    }
    
    pub fn deinit(self: *SirsFormatter) void {
        self.error_reporter.deinit();
    }
    
    /// Format a SIRS file and write the result to output_file
    pub fn formatFile(self: *SirsFormatter, input_file: []const u8, output_file: ?[]const u8) !void {
        // Clear any previous errors
        self.error_reporter.clear();
        try self.error_reporter.setCurrentFile(input_file);
        
        print("Formatting SIRS file: {s}\n", .{input_file});
        
        // Read the input file
        const content = self.readFile(input_file) catch |err| switch (err) {
            error.FileNotFound => {
                try self.error_reporter.reportErrorWithHint(
                    null,
                    "File '{s}' not found",
                    .{input_file},
                    "Make sure the file path is correct and the file exists",
                    .{}
                );
                self.error_reporter.printAllErrors();
                return;
            },
            else => {
                try self.error_reporter.reportError(
                    null,
                    "Failed to read file '{s}': {s}",
                    .{ input_file, @errorName(err) }
                );
                self.error_reporter.printAllErrors();
                return;
            },
        };
        defer self.allocator.free(content);
        
        // Parse JSON to validate and reformat
        var parsed = json.parseFromSlice(json.Value, self.allocator, content, .{}) catch |err| {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Failed to parse JSON: {s}",
                .{@errorName(err)},
                "Check that the file contains valid JSON syntax",
                .{}
            );
            self.error_reporter.printAllErrors();
            return;
        };
        defer parsed.deinit();
        
        // Validate that it's a proper SIRS program
        if (!self.validateSirsStructure(parsed.value)) {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Invalid SIRS program structure",
                .{},
                "The file should contain a SIRS program with the correct schema",
                .{}
            );
            self.error_reporter.printAllErrors();
            return;
        }
        
        // Format the JSON with proper indentation
        var formatted = ArrayList(u8).init(self.allocator);
        defer formatted.deinit();
        
        try self.formatJsonValue(parsed.value, formatted.writer(), 0);
        
        // Determine output destination
        const output_path = output_file orelse input_file;
        
        // Write formatted content to output file
        const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Failed to create output file '{s}': {s}",
                .{ output_path, @errorName(err) },
                "Check file permissions and available disk space",
                .{}
            );
            self.error_reporter.printAllErrors();
            return;
        };
        defer file.close();
        
        try file.writeAll(formatted.items);
        try file.writeAll("\n"); // Ensure file ends with newline
        
        if (output_file != null) {
            print("Formatted code written to: {s}\n", .{output_path});
        } else {
            print("File formatted in place: {s}\n", .{output_path});
        }
    }
    
    /// Format JSON content from string and return formatted string
    pub fn formatString(self: *SirsFormatter, content: []const u8) ![]u8 {
        var parsed = json.parseFromSlice(json.Value, self.allocator, content, .{}) catch |err| {
            try self.error_reporter.reportError(
                null,
                "Failed to parse JSON: {s}",
                .{@errorName(err)}
            );
            return err;
        };
        defer parsed.deinit();
        
        var formatted = ArrayList(u8).init(self.allocator);
        try self.formatJsonValue(parsed.value, formatted.writer(), 0);
        
        return formatted.toOwnedSlice();
    }
    
    /// Recursively format a JSON value with proper indentation
    fn formatJsonValue(self: *SirsFormatter, value: json.Value, writer: anytype, indent_level: u32) !void {
        switch (value) {
            .null => try writer.writeAll("null"),
            .bool => |b| try writer.writeAll(if (b) "true" else "false"),
            .integer => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .number_string => |s| try writer.writeAll(s),
            .string => |s| {
                try writer.writeAll("\"");
                try self.writeEscapedString(writer, s);
                try writer.writeAll("\"");
            },
            .array => |arr| {
                if (arr.items.len == 0) {
                    try writer.writeAll("[]");
                    return;
                }
                
                try writer.writeAll("[\n");
                for (arr.items, 0..) |item, i| {
                    try self.writeIndent(writer, indent_level + 1);
                    try self.formatJsonValue(item, writer, indent_level + 1);
                    if (i < arr.items.len - 1) {
                        try writer.writeAll(",");
                    }
                    try writer.writeAll("\n");
                }
                try self.writeIndent(writer, indent_level);
                try writer.writeAll("]");
            },
            .object => |obj| {
                if (obj.count() == 0) {
                    try writer.writeAll("{}");
                    return;
                }
                
                try writer.writeAll("{\n");
                
                // Get sorted keys for consistent formatting
                var keys = ArrayList([]const u8).init(self.allocator);
                defer keys.deinit();
                
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    try keys.append(entry.key_ptr.*);
                }
                
                // Sort keys for consistent output
                std.mem.sort([]const u8, keys.items, {}, struct {
                    fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                        return std.mem.order(u8, a, b).compare(std.math.CompareOperator.lt);
                    }
                }.lessThan);
                
                for (keys.items, 0..) |key, i| {
                    const obj_value = obj.get(key).?;
                    
                    try self.writeIndent(writer, indent_level + 1);
                    try writer.writeAll("\"");
                    try self.writeEscapedString(writer, key);
                    try writer.writeAll("\": ");
                    try self.formatJsonValue(obj_value, writer, indent_level + 1);
                    
                    if (i < keys.items.len - 1) {
                        try writer.writeAll(",");
                    }
                    try writer.writeAll("\n");
                }
                
                try self.writeIndent(writer, indent_level);
                try writer.writeAll("}");
            },
        }
    }
    
    /// Write proper indentation
    fn writeIndent(self: *SirsFormatter, writer: anytype, level: u32) !void {
        const total_spaces = level * self.indent_size;
        var i: u32 = 0;
        while (i < total_spaces) : (i += 1) {
            try writer.writeAll(" ");
        }
    }
    
    /// Write escaped string content
    fn writeEscapedString(self: *SirsFormatter, writer: anytype, str: []const u8) !void {
        _ = self;
        
        for (str) |char| {
            switch (char) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                '\u{08}' => try writer.writeAll("\\b"),
                '\u{0C}' => try writer.writeAll("\\f"),
                else => try writer.writeByte(char),
            }
        }
    }
    
    /// Validate that the JSON represents a valid SIRS program structure
    fn validateSirsStructure(self: *SirsFormatter, value: json.Value) bool {
        _ = self;
        
        if (value != .object) return false;
        
        const root_obj = value.object;
        
        // Check for "program" key at root level
        const program = root_obj.get("program") orelse return false;
        if (program != .object) return false;
        
        const program_obj = program.object;
        
        // Check for required top-level fields
        const entry = program_obj.get("entry");
        const functions = program_obj.get("functions");
        
        if (entry == null or entry.? != .string) return false;
        if (functions == null or functions.? != .object) return false;
        
        // Basic validation passed
        return true;
    }
    
    fn readFile(self: *SirsFormatter, path: []const u8) ![]u8 {
        const file = std.fs.cwd().openFile(path, .{}) catch return error.FileNotFound;
        defer file.close();
        
        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, file_size);
        _ = try file.readAll(content);
        
        return content;
    }
};