const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const SeverCompiler = @import("compiler.zig").SeverCompiler;
const SirsParser = @import("sirs.zig");
const CLI = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try CLI.printUsage();
        return;
    }

    const command = args[1];
    
    if (std.mem.eql(u8, command, "build")) {
        if (args.len < 3) {
            print("Error: build command requires input file\n", .{});
            return;
        }
        try buildCommand(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "test")) {
        if (args.len < 3) {
            print("Error: test command requires input file\n", .{});
            return;
        }
        try testCommand(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "doc")) {
        if (args.len < 3) {
            print("Error: doc command requires input file\n", .{});
            return;
        }
        try docCommand(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "serve")) {
        try serveCommand(allocator);
    } else {
        print("Error: Unknown command '{s}'\n", .{command});
        try CLI.printUsage();
    }
}

fn buildCommand(allocator: Allocator, input_file: []const u8) !void {
    print("Building Sever program: {s}\n", .{input_file});
    
    var compiler = SeverCompiler.init(allocator);
    defer compiler.deinit();
    
    try compiler.compile(input_file);
    print("Build successful\n", .{});
}

fn testCommand(allocator: Allocator, input_file: []const u8) !void {
    print("Testing Sever program: {s}\n", .{input_file});
    
    var compiler = SeverCompiler.init(allocator);
    defer compiler.deinit();
    
    try compiler.test_program(input_file);
    print("Tests passed\n", .{});
}

fn docCommand(allocator: Allocator, input_file: []const u8) !void {
    print("Generating documentation for: {s}\n", .{input_file});
    
    var compiler = SeverCompiler.init(allocator);
    defer compiler.deinit();
    
    try compiler.generate_docs(input_file);
    print("Documentation generated\n", .{});
}

fn serveCommand(allocator: Allocator) !void {
    print("Starting Sever MCP server...\n", .{});
    
    var compiler = SeverCompiler.init(allocator);
    defer compiler.deinit();
    
    try compiler.serve();
}