const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const SeverCompiler = @import("compiler.zig").SeverCompiler;
const SirsParser = @import("sirs.zig");
const CLI = @import("cli.zig");
const SirsFormatter = @import("formatter.zig").SirsFormatter;
const Debugger = @import("debugger.zig").Debugger;
const DebugInfoGenerator = @import("debugger.zig").DebugInfoGenerator;
const Linter = @import("linter.zig").Linter;
const LintConfig = @import("linter.zig").LintConfig;
const LintSeverity = @import("linter.zig").LintSeverity;
const SevConverter = @import("sev_converter.zig").Converter;
const benchmarkTokenUsage = @import("sev_converter.zig").benchmarkTokenUsage;

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
    } else if (std.mem.eql(u8, command, "fmt")) {
        if (args.len < 3) {
            print("Error: fmt command requires input file\n", .{});
            return;
        }
        try fmtCommand(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "repl")) {
        try replCommand(allocator);
    } else if (std.mem.eql(u8, command, "serve")) {
        try serveCommand(allocator);
    } else if (std.mem.eql(u8, command, "debug")) {
        if (args.len < 3) {
            print("Error: debug command requires input file\n", .{});
            return;
        }
        try debugCommand(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "lint")) {
        if (args.len < 3) {
            print("Error: lint command requires input file\n", .{});
            return;
        }
        try lintCommand(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "convert")) {
        if (args.len < 4) {
            print("Error: convert command requires input and output files\n", .{});
            return;
        }
        try convertCommand(allocator, args[2], args[3]);
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

fn fmtCommand(allocator: Allocator, input_file: []const u8) !void {
    print("Formatting Sever program: {s}\n", .{input_file});
    
    var formatter = SirsFormatter.init(allocator);
    defer formatter.deinit();
    
    try formatter.formatFile(input_file, null); // Format in place
    print("Formatting complete\n", .{});
}

fn replCommand(allocator: Allocator) !void {
    print("Starting Sever REPL (Read-Eval-Print Loop)\n", .{});
    print("Type expressions in SIRS JSON format, or 'exit' to quit.\n", .{});
    print("Example: {{\"op\": {{\"kind\": \"add\", \"args\": [{{\"literal\": 10}}, {{\"literal\": 20}}]}}}}\n\n", .{});
    
    var compiler = SeverCompiler.init(allocator);
    defer compiler.deinit();
    
    try compiler.repl();
}

fn serveCommand(allocator: Allocator) !void {
    print("Starting Sever MCP server...\n", .{});
    
    var compiler = SeverCompiler.init(allocator);
    defer compiler.deinit();
    
    try compiler.serve();
}

fn debugCommand(allocator: Allocator, input_file: []const u8) !void {
    print("Starting Sever debugger for: {s}\n", .{input_file});
    print("Type 'help' for available commands, 'exit' to quit.\n\n", .{});
    
    // Initialize debugger
    var debugger = Debugger.init(allocator);
    defer debugger.deinit();
    
    debugger.setDebugMode(true);
    
    // Parse the input file to generate debug info
    const file_content = std.fs.cwd().readFileAlloc(allocator, input_file, 1024 * 1024) catch |err| {
        print("Error reading file {s}: {}\n", .{ input_file, err });
        return;
    };
    defer allocator.free(file_content);
    
    var sirs_parser = SirsParser.Parser.init(allocator);
    
    var program = sirs_parser.parse(file_content) catch |err| {
        print("Error parsing file {s}: {}\n", .{ input_file, err });
        return;
    };
    
    // Generate debug information
    var debug_info_gen = DebugInfoGenerator.init(allocator, &debugger);
    debug_info_gen.generateDebugInfo(&program, input_file) catch |err| {
        print("Error generating debug info: {}\n", .{err});
        return;
    };
    
    print("Debug symbols loaded for {d} functions\n", .{program.functions.count()});
    
    // Interactive debugging loop
    const stdin = std.io.getStdIn().reader();
    var input_buffer: [256]u8 = undefined;
    
    while (true) {
        print("sever-debug> ", .{});
        
        if (try stdin.readUntilDelimiterOrEof(input_buffer[0..], '\n')) |input| {
            const trimmed_input = std.mem.trim(u8, input, " \t\r\n");
            
            if (std.mem.eql(u8, trimmed_input, "exit") or std.mem.eql(u8, trimmed_input, "quit")) {
                print("Goodbye!\n", .{});
                break;
            }
            
            if (trimmed_input.len == 0) continue;
            
            debugger.processDebugCommand(trimmed_input);
        } else {
            break;
        }
    }
}

fn lintCommand(allocator: Allocator, input_file: []const u8) !void {
    print("Linting Sever program: {s}\n", .{input_file});
    
    // Parse the input file
    const file_content = std.fs.cwd().readFileAlloc(allocator, input_file, 1024 * 1024) catch |err| {
        print("Error reading file {s}: {}\n", .{ input_file, err });
        return;
    };
    defer allocator.free(file_content);
    
    var sirs_parser = SirsParser.Parser.init(allocator);
    
    var program = sirs_parser.parse(file_content) catch |err| {
        print("Error parsing file {s}: {}\n", .{ input_file, err });
        return;
    };
    
    // Initialize linter with default config
    const config = LintConfig{};
    var linter = Linter.init(allocator, config);
    defer linter.deinit();
    
    // Run linting
    linter.lint(&program, input_file) catch |err| {
        print("Error during linting: {}\n", .{err});
        return;
    };
    
    // Print results
    print("\n", .{});
    linter.printIssues();
    
    // Return non-zero exit code if there are errors
    const issues = linter.getIssues();
    var has_errors = false;
    for (issues) |issue| {
        if (issue.severity == .@"error") {
            has_errors = true;
            break;
        }
    }
    
    if (has_errors) {
        std.process.exit(1);
    }
}

fn convertCommand(allocator: Allocator, input_file: []const u8, output_file: []const u8) !void {
    print("Converting {s} to {s}\n", .{ input_file, output_file });
    
    // Read input file
    const input_content = std.fs.cwd().readFileAlloc(allocator, input_file, 1024 * 1024) catch |err| {
        print("Error reading input file {s}: {}\n", .{ input_file, err });
        return;
    };
    defer allocator.free(input_content);
    
    // Detect input and output formats
    const input_format = detectFormat(input_file);
    const output_format = detectFormat(output_file);
    
    if (input_format == output_format) {
        print("Error: Input and output formats are the same\n", .{});
        return;
    }
    
    var converter = SevConverter.init(allocator);
    
    const output_content = switch (input_format) {
        .json => switch (output_format) {
            .sev => try converter.jsonToSev(input_content),
            .json => unreachable,
        },
        .sev => switch (output_format) {
            .json => try converter.sevToJson(input_content),
            .sev => unreachable,
        },
    };
    defer allocator.free(output_content);
    
    // Write output file
    std.fs.cwd().writeFile(.{ .sub_path = output_file, .data = output_content }) catch |err| {
        print("Error writing output file {s}: {}\n", .{ output_file, err });
        return;
    };
    
    // Show compression stats if converting to SEV
    if (output_format == .sev) {
        const benchmark = try benchmarkTokenUsage(allocator, input_content);
        print("\nConversion complete! Token efficiency:\n", .{});
        print("{}\n", .{benchmark});
    } else {
        print("Conversion complete\n", .{});
    }
}

const FileFormat = enum { json, sev };

fn detectFormat(filename: []const u8) FileFormat {
    if (std.mem.endsWith(u8, filename, ".sev")) {
        return .sev;
    } else if (std.mem.endsWith(u8, filename, ".sirs.json") or std.mem.endsWith(u8, filename, ".json")) {
        return .json;
    } else {
        // Default to JSON for unknown extensions
        return .json;
    }
}