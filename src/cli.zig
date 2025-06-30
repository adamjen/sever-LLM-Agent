const std = @import("std");
const print = std.debug.print;

pub fn printUsage() !void {
    print("Sever Programming Language Compiler (sev0)\n", .{});
    print("Usage: sev <command> [options]\n\n", .{});
    print("Commands:\n", .{});
    print("  build <file.sirs.json>    Compile SIRS program to native binary\n", .{});
    print("  test <file.sirs.json>     Run tests for SIRS program\n", .{});
    print("  doc <file.sirs.json>      Generate documentation for SIRS program\n", .{});
    print("  serve                     Start MCP server for LLM integration\n\n", .{});
    print("Examples:\n", .{});
    print("  sev build program.sirs.json\n", .{});
    print("  sev test program.sirs.json\n", .{});
    print("  sev doc program.sirs.json\n", .{});
    print("  sev serve\n", .{});
}