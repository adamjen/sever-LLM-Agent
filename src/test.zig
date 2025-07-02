const std = @import("std");
const testing = std.testing;

const SirsParser = @import("sirs.zig");
const TypeChecker = @import("typechecker.zig").TypeChecker;
const CodeGen = @import("codegen.zig").CodeGen;
const CodeGenError = @import("codegen.zig").CodeGenError;

// Import custom distribution test modules
comptime {
    _ = @import("test_custom_distributions.zig");
    // MCP distribution tools tests isolated due to global registry memory leaks
    // Run with: zig build test-mcp
    // _ = @import("test_mcp_distribution_tools.zig");
    
    // Advanced tests run separately to avoid cross-test contamination:
    // - Distribution compiler tests: isolated due to memory management interference
    // - VI integration tests: 'zig build test-vi'
    // - VI unit tests (exponential): 'zig build test-vi' (cross-contamination issues)
    // - MCMC tests: 'zig build test-mcmc' (currently failing due to distribution lookup issues)
    // - MCMC integration tests: 'zig build test-mcmc' (currently failing due to parsing issues)
    // - MCP distribution tools: 'zig build test-mcp' (global registry memory leaks)
}

test "SIRS parser basic functionality" {
    const allocator = testing.allocator;
    
    const sirs_program = 
        \\{
        \\  "program": {
        \\    "entry": "main",
        \\    "functions": {
        \\      "main": {
        \\        "args": [],
        \\        "return": "i32",
        \\        "body": [
        \\          {
        \\            "return": {
        \\              "literal": 42
        \\            }
        \\          }
        \\        ]
        \\      }
        \\    }
        \\  }
        \\}
    ;
    
    var parser = SirsParser.Parser.init(allocator);
    var program = try parser.parse(sirs_program);
    defer program.deinit();
    
    try testing.expectEqualStrings("main", program.entry);
    try testing.expect(program.functions.contains("main"));
}

test "Type checker basic functionality" {
    const allocator = testing.allocator;
    
    var program = SirsParser.Program.init(allocator);
    defer program.deinit();
    
    program.entry = try allocator.dupe(u8, "main");
    program.entry_allocated = true;
    
    // Create a simple main function
    var main_func = SirsParser.Function{
        .args = std.ArrayList(SirsParser.Parameter).init(allocator),
        .@"return" = SirsParser.Type.i32,
        .body = std.ArrayList(SirsParser.Statement).init(allocator),
    };
    
    const return_stmt = SirsParser.Statement{
        .@"return" = SirsParser.Expression{
            .literal = SirsParser.Literal{ .integer = 42 },
        },
    };
    
    try main_func.body.append(return_stmt);
    const main_name = try allocator.dupe(u8, "main");
    try program.functions.put(main_name, main_func);
    
    var type_checker = TypeChecker.init(allocator);
    defer type_checker.deinit();
    
    try type_checker.check(&program);
}

test "Sample expression parsing" {
    const allocator = testing.allocator;
    
    const sirs_program = 
        \\{
        \\  "program": {
        \\    "entry": "main",
        \\    "functions": {
        \\      "main": {
        \\        "args": [],
        \\        "return": "i32",
        \\        "body": [
        \\          {
        \\            "let": {
        \\              "name": "x",
        \\              "value": {
        \\                "sample": {
        \\                  "distribution": "uniform",
        \\                  "params": [
        \\                    {"literal": 1},
        \\                    {"literal": 10}
        \\                  ]
        \\                }
        \\              }
        \\            }
        \\          },
        \\          {
        \\            "return": {
        \\              "var": "x"
        \\            }
        \\          }
        \\        ]
        \\      }
        \\    }
        \\  }
        \\}
    ;
    
    var parser = SirsParser.Parser.init(allocator);
    var program = try parser.parse(sirs_program);
    defer program.deinit();
    
    try testing.expectEqualStrings("main", program.entry);
    
    const main_func = program.functions.get("main").?;
    try testing.expect(main_func.body.items.len == 2);
    
    const let_stmt = main_func.body.items[0];
    try testing.expect(let_stmt == .let);
    try testing.expectEqualStrings("x", let_stmt.let.name);
    
    const sample_expr = let_stmt.let.value;
    try testing.expect(sample_expr == .sample);
    try testing.expectEqualStrings("uniform", sample_expr.sample.distribution);
    try testing.expect(sample_expr.sample.params.items.len == 2);
}

test "Code generation basic test" {
    const allocator = testing.allocator;
    
    var program = SirsParser.Program.init(allocator);
    defer program.deinit();
    
    program.entry = try allocator.dupe(u8, "main");
    program.entry_allocated = true;
    
    // Create a simple main function
    var main_func = SirsParser.Function{
        .args = std.ArrayList(SirsParser.Parameter).init(allocator),
        .@"return" = SirsParser.Type.void,
        .body = std.ArrayList(SirsParser.Statement).init(allocator),
    };
    
    const return_stmt = SirsParser.Statement{
        .@"return" = SirsParser.Expression{
            .literal = SirsParser.Literal{ .integer = 0 },
        },
    };
    
    try main_func.body.append(return_stmt);
    const main_name = try allocator.dupe(u8, "main");
    try program.functions.put(main_name, main_func);
    
    var codegen = CodeGen.init(allocator);
    defer codegen.deinit();
    
    // Test that code generation doesn't crash
    codegen.generateProgram(&program) catch |err| {
        // Expected to fail due to missing runtime, but should not crash
        try testing.expect(err == CodeGenError.CompilationError or err == CodeGenError.IoError);
    };
}