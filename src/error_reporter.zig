const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const SourceLocation = struct {
    file: []const u8,
    line: u32,
    column: u32,
};

pub const ErrorLevel = enum {
    @"error",
    warning,
    info,
};

pub const CompilerError = struct {
    level: ErrorLevel,
    location: ?SourceLocation,
    message: []const u8,
    hint: ?[]const u8,
    code: []const u8,
};

pub const ErrorReporter = struct {
    allocator: Allocator,
    errors: ArrayList(CompilerError),
    current_file: ?[]u8,
    
    pub fn init(allocator: Allocator) ErrorReporter {
        return ErrorReporter{
            .allocator = allocator,
            .errors = ArrayList(CompilerError).init(allocator),
            .current_file = null,
        };
    }
    
    pub fn deinit(self: *ErrorReporter) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
            if (err.hint) |hint| {
                self.allocator.free(hint);
            }
            if (err.location) |loc| {
                self.allocator.free(loc.file);
            }
        }
        self.errors.deinit();
        
        if (self.current_file) |file| {
            self.allocator.free(file);
        }
    }
    
    pub fn setCurrentFile(self: *ErrorReporter, file: []const u8) !void {
        if (self.current_file) |old_file| {
            self.allocator.free(old_file);
        }
        self.current_file = try self.allocator.dupe(u8, file);
    }
    
    pub fn reportError(self: *ErrorReporter, location: ?SourceLocation, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.errors.append(CompilerError{
            .level = .@"error",
            .location = if (location) |loc| SourceLocation{
                .file = try self.allocator.dupe(u8, loc.file),
                .line = loc.line,
                .column = loc.column,
            } else null,
            .message = message,
            .hint = null,
            .code = "",
        });
    }
    
    pub fn reportErrorWithHint(self: *ErrorReporter, location: ?SourceLocation, comptime fmt: []const u8, args: anytype, comptime hint_fmt: []const u8, hint_args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        const hint = try std.fmt.allocPrint(self.allocator, hint_fmt, hint_args);
        try self.errors.append(CompilerError{
            .level = .@"error",
            .location = if (location) |loc| SourceLocation{
                .file = try self.allocator.dupe(u8, loc.file),
                .line = loc.line,
                .column = loc.column,
            } else null,
            .message = message,
            .hint = hint,
            .code = "",
        });
    }
    
    pub fn reportWarning(self: *ErrorReporter, location: ?SourceLocation, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.errors.append(CompilerError{
            .level = .warning,
            .location = if (location) |loc| SourceLocation{
                .file = try self.allocator.dupe(u8, loc.file),
                .line = loc.line,
                .column = loc.column,
            } else null,
            .message = message,
            .hint = null,
            .code = "",
        });
    }
    
    pub fn printAllErrors(self: *ErrorReporter) void {
        for (self.errors.items) |err| {
            self.printError(err);
        }
    }
    
    pub fn hasErrors(self: *ErrorReporter) bool {
        for (self.errors.items) |err| {
            if (err.level == .@"error") return true;
        }
        return false;
    }
    
    pub fn getErrorCount(self: *ErrorReporter) u32 {
        var count: u32 = 0;
        for (self.errors.items) |err| {
            if (err.level == .@"error") count += 1;
        }
        return count;
    }
    
    pub fn getWarningCount(self: *ErrorReporter) u32 {
        var count: u32 = 0;
        for (self.errors.items) |err| {
            if (err.level == .warning) count += 1;
        }
        return count;
    }
    
    fn printError(self: *ErrorReporter, err: CompilerError) void {
        _ = self;
        
        // Print error level and location
        switch (err.level) {
            .@"error" => print("\x1b[31merror\x1b[0m", .{}),
            .warning => print("\x1b[33mwarning\x1b[0m", .{}),
            .info => print("\x1b[36minfo\x1b[0m", .{}),
        }
        
        if (err.location) |loc| {
            print(": {s}:{}:{}: ", .{ loc.file, loc.line, loc.column });
        } else {
            print(": ", .{});
        }
        
        // Print message
        print("{s}\n", .{err.message});
        
        // Print hint if available
        if (err.hint) |hint| {
            print("  \x1b[36mhint\x1b[0m: {s}\n", .{hint});
        }
        
        print("\n", .{});
    }
    
    pub fn clear(self: *ErrorReporter) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
            if (err.hint) |hint| {
                self.allocator.free(hint);
            }
            if (err.location) |loc| {
                self.allocator.free(loc.file);
            }
        }
        self.errors.clearRetainingCapacity();
        
        if (self.current_file) |file| {
            self.allocator.free(file);
            self.current_file = null;
        }
    }
};