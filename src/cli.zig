const std = @import("std");
const print = std.debug.print;

pub fn printUsage() !void {
    print("Sever Programming Language Compiler (sev0)\n", .{});
    print("Usage: sev <command> [options]\n\n", .{});
    print("Commands:\n", .{});
    print("  build <file>              Compile program to native binary (.sirs.json or .sev)\n", .{});
    print("  test <file>               Run tests for program (.sirs.json or .sev)\n", .{});
    print("  doc <file>                Generate documentation for program (.sirs.json or .sev)\n", .{});
    print("  fmt <file>                Format program with consistent style (.sirs.json or .sev)\n", .{});
    print("  repl                      Start interactive REPL mode\n", .{});
    print("  serve                     Start MCP server for LLM integration\n", .{});
    print("  debug <file>              Start interactive debugger for program (.sirs.json or .sev)\n", .{});
    print("  lint <file>               Run linter and static analysis on program (.sirs.json or .sev)\n", .{});
    print("  convert <input> <output>  Convert between formats (.sirs.json <-> .sev)\n\n", .{});
    print("Examples:\n", .{});
    print("  sev build program.sirs.json    # or program.sev\n", .{});
    print("  sev test program.sev\n", .{});
    print("  sev doc program.sirs.json\n", .{});
    print("  sev fmt program.sev\n", .{});
    print("  sev convert program.sirs.json program.sev\n", .{});
    print("  sev repl\n", .{});
    print("  sev serve\n", .{});
    print("  sev debug program.sev\n", .{});
    print("  sev lint program.sirs.json\n", .{});
}