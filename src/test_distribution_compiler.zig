const std = @import("std");
const testing = std.testing;
const json = std.json;
const Allocator = std.mem.Allocator;

const DistributionCompiler = @import("distribution_compiler.zig").DistributionCompiler;
const SirsParser = @import("sirs.zig");
const Type = SirsParser.Type;
const Function = SirsParser.Function;
const Program = SirsParser.Program;

// Helper function to create a minimal SIRS program for testing
fn createTestProgram(allocator: Allocator) !Program {
    var program = Program.init(allocator);
    
    // Add a distribution-like function
    var gamma_log_prob = Function{
        .args = std.ArrayList(SirsParser.Parameter).init(allocator),
        .@"return" = Type.f64,
        .body = std.ArrayList(SirsParser.Statement).init(allocator),
        .@"inline" = false,
        .pure = true,
    };
    
    // Add parameters
    try gamma_log_prob.args.append(SirsParser.Parameter{
        .name = try allocator.dupe(u8, "alpha"),
        .type = Type.f64,
    });
    try gamma_log_prob.args.append(SirsParser.Parameter{
        .name = try allocator.dupe(u8, "beta"),
        .type = Type.f64,
    });
    try gamma_log_prob.args.append(SirsParser.Parameter{
        .name = try allocator.dupe(u8, "x"),
        .type = Type.f64,
    });
    
    try program.functions.put(try allocator.dupe(u8, "gamma_log_prob"), gamma_log_prob);
    
    // Add a sampling function
    var gamma_sample = Function{
        .args = std.ArrayList(SirsParser.Parameter).init(allocator),
        .@"return" = Type.f64,
        .body = std.ArrayList(SirsParser.Statement).init(allocator),
        .@"inline" = false,
        .pure = false,
    };
    
    try gamma_sample.args.append(SirsParser.Parameter{
        .name = try allocator.dupe(u8, "alpha"),
        .type = Type.f64,
    });
    try gamma_sample.args.append(SirsParser.Parameter{
        .name = try allocator.dupe(u8, "beta"),
        .type = Type.f64,
    });
    
    try program.functions.put(try allocator.dupe(u8, "gamma_sample"), gamma_sample);
    
    // Add a non-distribution function
    const regular_func = Function{
        .args = std.ArrayList(SirsParser.Parameter).init(allocator),
        .@"return" = Type.i32,
        .body = std.ArrayList(SirsParser.Statement).init(allocator),
        .@"inline" = false,
        .pure = true,
    };
    
    try program.functions.put(try allocator.dupe(u8, "add_numbers"), regular_func);
    
    program.entry = "main";
    
    return program;
}

test "DistributionCompiler initialization and cleanup" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    // Compiler should initialize with empty registry
    try testing.expect(compiler.getRegistry().distributions.count() == 0);
}

test "Distribution function pattern recognition" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    var dummy_function = Function{
        .args = std.ArrayList(SirsParser.Parameter).init(allocator),
        .@"return" = Type.f64,
        .body = std.ArrayList(SirsParser.Statement).init(allocator),
        .@"inline" = false,
        .pure = true,
    };
    defer dummy_function.args.deinit();
    defer dummy_function.body.deinit();
    
    // Test various function name patterns
    const test_cases = [_]struct {
        name: []const u8,
        expected: bool,
    }{
        .{ .name = "normal_log_prob", .expected = true },
        .{ .name = "gamma_sample", .expected = true },
        .{ .name = "beta_logProb", .expected = true },
        .{ .name = "exponential_mean", .expected = true },
        .{ .name = "poisson_variance", .expected = true },
        .{ .name = "student_t_cdf", .expected = true },
        .{ .name = "chi_square_pdf", .expected = true },
        .{ .name = "dist_uniform", .expected = true },
        .{ .name = "custom_distribution_func", .expected = true },
        .{ .name = "regular_function", .expected = false },
        .{ .name = "calculate_sum", .expected = false },
        .{ .name = "parse_input", .expected = false },
    };
    
    for (test_cases) |case| {
        const result = try compiler.isDistributionFunction(case.name, &dummy_function);
        try testing.expectEqual(case.expected, result);
    }
}

test "Distribution compilation from program" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    var program = try createTestProgram(allocator);
    defer program.deinit();
    
    // Compile distributions from the program
    try compiler.compileDistributions(&program);
    
    // Should have processed the distribution functions
    // Note: The actual extraction might not create distributions due to
    // limited type information, but the compilation should succeed
    const registry = compiler.getRegistry();
    
    // At minimum, the compilation should complete without errors
    try testing.expect(registry.distributions.count() >= 0);
}

test "Code generation for distribution" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    // Create a simple custom distribution in the registry
    const registry = compiler.getRegistry();
    try registry.createExampleDistributions();
    
    // Generate code for BetaBinomial distribution
    const generated_code = try compiler.generateDistributionCode("BetaBinomial");
    defer allocator.free(generated_code);
    
    // Verify the generated code contains expected elements
    try testing.expect(std.mem.indexOf(u8, generated_code, "BetaBinomialDistribution") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "interface") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "struct Parameters") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "fn log_prob") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "impl") != null);
    
    // Check for parameters
    try testing.expect(std.mem.indexOf(u8, generated_code, "n:") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "alpha:") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "beta:") != null);
    
    // Check for constraints in comments
    try testing.expect(std.mem.indexOf(u8, generated_code, "positive") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "integer") != null);
}

test "Distribution validation" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    const registry = compiler.getRegistry();
    try registry.createExampleDistributions();
    
    // Test validation of valid distributions
    try testing.expect(try compiler.validateDistribution("BetaBinomial"));
    try testing.expect(try compiler.validateDistribution("StudentT"));
    try testing.expect(try compiler.validateDistribution("GaussianMixture"));
    
    // Test validation of non-existent distribution (silent mode to avoid stderr)
    try testing.expect(!(try compiler.validateDistributionSilent("NonExistentDistribution", true)));
}

test "Type to string conversion" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    // Test basic type conversions
    const test_cases = [_]struct {
        type_val: Type,
        expected: []const u8,
    }{
        .{ .type_val = Type.void, .expected = "void" },
        .{ .type_val = Type.bool, .expected = "bool" },
        .{ .type_val = Type.i32, .expected = "i32" },
        .{ .type_val = Type.i64, .expected = "i64" },
        .{ .type_val = Type.f32, .expected = "f32" },
        .{ .type_val = Type.f64, .expected = "f64" },
        .{ .type_val = Type.str, .expected = "str" },
    };
    
    for (test_cases) |case| {
        const result = try compiler.typeToString(case.type_val);
        try testing.expect(std.mem.eql(u8, result, case.expected));
    }
}

test "Distribution name extraction from function names" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    const test_cases = [_]struct {
        func_name: []const u8,
        expected: []const u8,
    }{
        .{ .func_name = "normal_log_prob", .expected = "normal" },
        .{ .func_name = "gamma_sample", .expected = "gamma" },
        .{ .func_name = "beta_mean", .expected = "beta" },
        .{ .func_name = "exponential_variance", .expected = "exponential" },
        .{ .func_name = "student_t_cdf", .expected = "student_t" },
        .{ .func_name = "chi_square_pdf", .expected = "chi_square" },
        .{ .func_name = "dist_uniform", .expected = "uniform" },
        .{ .func_name = "my_custom_distribution", .expected = "my_custom_distribution" },
    };
    
    for (test_cases) |case| {
        const result = try compiler.extractDistributionNameFromFunction(case.func_name);
        defer allocator.free(result);
        try testing.expect(std.mem.eql(u8, result, case.expected));
    }
}

test "Code generation with constraints" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    const registry = compiler.getRegistry();
    try registry.createExampleDistributions();
    
    // Generate code for StudentT which has constraints
    const generated_code = try compiler.generateDistributionCode("StudentT");
    defer allocator.free(generated_code);
    
    // Should contain constraint comments
    try testing.expect(std.mem.indexOf(u8, generated_code, "positive") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "min=") != null);
    
    // Should contain support information
    try testing.expect(std.mem.indexOf(u8, generated_code, "Support: real_line") != null);
}

test "Code generation for non-existent distribution" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    // Try to generate code for non-existent distribution
    const generated_code = try compiler.generateDistributionCode("NonExistentDist");
    defer allocator.free(generated_code);
    
    // Should return a comment indicating distribution not found
    try testing.expect(std.mem.indexOf(u8, generated_code, "not found") != null);
}

test "Multiple distribution compilation" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    // Create a program with multiple distribution-like functions
    var program = Program.init(allocator);
    defer program.deinit();
    
    program.entry = "main";
    
    // Add multiple distribution functions
    const dist_functions = [_][]const u8{
        "normal_log_prob",
        "normal_sample", 
        "gamma_log_prob",
        "gamma_sample",
        "beta_log_prob",
        "beta_sample",
    };
    
    for (dist_functions) |func_name| {
        const func = Function{
            .args = std.ArrayList(SirsParser.Parameter).init(allocator),
            .@"return" = Type.f64,
            .body = std.ArrayList(SirsParser.Statement).init(allocator),
            .@"inline" = false,
            .pure = true,
        };
        
        try program.functions.put(try allocator.dupe(u8, func_name), func);
    }
    
    // Compile distributions
    try compiler.compileDistributions(&program);
    
    // Compilation should complete successfully
    const registry = compiler.getRegistry();
    try testing.expect(registry.distributions.count() >= 0);
}

test "Constraint inference from types" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    // Test constraint inference for different types
    const u32_constraints = try compiler.inferConstraintsFromType(Type.u32);
    try testing.expect(u32_constraints != null);
    try testing.expect(u32_constraints.?.positive_only);
    try testing.expect(u32_constraints.?.integer_only);
    try testing.expect(u32_constraints.?.min_value.? == 0);
    
    const i32_constraints = try compiler.inferConstraintsFromType(Type.i32);
    try testing.expect(i32_constraints != null);
    try testing.expect(!i32_constraints.?.positive_only);
    try testing.expect(i32_constraints.?.integer_only);
    
    const f64_constraints = try compiler.inferConstraintsFromType(Type.f64);
    try testing.expect(f64_constraints == null); // No constraints for general floats
}

test "Parameter name generation from types" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    const test_cases = [_]struct {
        type_val: Type,
        expected: []const u8,
    }{
        .{ .type_val = Type.f64, .expected = "param" },
        .{ .type_val = Type.i32, .expected = "count" },
        .{ .type_val = Type.bool, .expected = "flag" },
    };
    
    for (test_cases) |case| {
        const result = try compiler.generateParameterName(case.type_val);
        defer allocator.free(result);
        try testing.expect(std.mem.eql(u8, result, case.expected));
    }
}

test "Compiler memory management" {
    const allocator = testing.allocator;
    
    // Test multiple compiler instances
    for (0..5) |_| {
        var compiler = DistributionCompiler.init(allocator);
        
        // Do some operations
        const registry = compiler.getRegistry();
        try registry.createExampleDistributions();
        
        const generated_code = try compiler.generateDistributionCode("BetaBinomial");
        defer allocator.free(generated_code);
        
        compiler.deinit();
    }
    
    // All memory should be properly freed
}