const std = @import("std");
const testing = std.testing;
const json = std.json;
const Allocator = std.mem.Allocator;

const CustomDistribution = @import("custom_distributions.zig").CustomDistribution;
const DistributionRegistry = @import("custom_distributions.zig").DistributionRegistry;
const DistributionBuilder = @import("custom_distributions.zig").DistributionBuilder;
const DistributionParameter = @import("custom_distributions.zig").DistributionParameter;
const ParameterConstraints = @import("custom_distributions.zig").ParameterConstraints;
const DistributionSupport = @import("custom_distributions.zig").DistributionSupport;
const DistributionCompiler = @import("distribution_compiler.zig").DistributionCompiler;
const SirsParser = @import("sirs.zig");
const Type = SirsParser.Type;

test "CustomDistribution creation and basic operations" {
    const allocator = testing.allocator;
    
    var distribution = CustomDistribution.init(allocator, try allocator.dupe(u8, "TestDistribution"));
    defer distribution.deinit(allocator);
    
    // Test basic properties
    try testing.expect(std.mem.eql(u8, distribution.name, "TestDistribution"));
    try testing.expect(distribution.parameters.items.len == 0);
    try testing.expect(distribution.support.support_type == .real_line);
    try testing.expect(!distribution.is_discrete);
    try testing.expect(!distribution.is_exponential_family);
    
    // Add a parameter
    const param = DistributionParameter{
        .name = try allocator.dupe(u8, "mu"),
        .param_type = .f64,
        .constraints = null,
        .default_value = null,
        .description = try allocator.dupe(u8, "Mean parameter"),
    };
    try distribution.parameters.append(param);
    
    try testing.expect(distribution.parameters.items.len == 1);
    try testing.expect(std.mem.eql(u8, distribution.parameters.items[0].name, "mu"));
}

test "DistributionBuilder fluent API" {
    const allocator = testing.allocator;
    
    var builder = DistributionBuilder.init(allocator, try allocator.dupe(u8, "MyDistribution"));
    
    const distribution = builder
        .addParameter("alpha", .f64)
        .addParameter("beta", .f64)
        .withConstraints("alpha", ParameterConstraints{
            .min_value = 0,
            .max_value = null,
            .positive_only = true,
            .integer_only = false,
            .vector_constraints = null,
            .custom_validator = null,
        })
        .withSupport(DistributionSupport{
            .support_type = .positive_real,
            .lower_bound = null,
            .upper_bound = null,
            .discrete_values = null,
        })
        .withLogProb("myDistributionLogProb")
        .withSampler("myDistributionSample")
        .withDescription("Test distribution built with fluent API")
        .build();
    
    defer {
        var mut_dist = distribution;
        mut_dist.deinit(allocator);
    }
    
    try testing.expect(std.mem.eql(u8, distribution.name, "MyDistribution"));
    try testing.expect(distribution.parameters.items.len == 2);
    try testing.expect(distribution.support.support_type == .positive_real);
    try testing.expect(std.mem.eql(u8, distribution.log_prob_function, "myDistributionLogProb"));
    try testing.expect(std.mem.eql(u8, distribution.sample_function.?, "myDistributionSample"));
    
    // Check parameter constraints
    const alpha_param = distribution.parameters.items[0];
    try testing.expect(alpha_param.constraints != null);
    try testing.expect(alpha_param.constraints.?.positive_only);
    try testing.expect(alpha_param.constraints.?.min_value.? == 0);
}

test "DistributionRegistry operations" {
    const allocator = testing.allocator;
    
    var registry = DistributionRegistry.init(allocator);
    defer registry.deinit();
    
    // Test built-in distributions are registered
    try testing.expect(registry.hasDistribution("Normal"));
    try testing.expect(registry.hasDistribution("Bernoulli"));
    try testing.expect(registry.hasDistribution("Exponential"));
    
    // Create and register a custom distribution
    var custom_dist = CustomDistribution.init(allocator, try allocator.dupe(u8, "CustomTest"));
    custom_dist.log_prob_function = try allocator.dupe(u8, "customLogProb");
    
    try registry.registerDistribution(custom_dist);
    
    // Test retrieval
    try testing.expect(registry.hasDistribution("CustomTest"));
    const retrieved = registry.getDistribution("CustomTest");
    try testing.expect(retrieved != null);
    try testing.expect(std.mem.eql(u8, retrieved.?.name, "CustomTest"));
}

test "Parameter validation" {
    const allocator = testing.allocator;
    
    var registry = DistributionRegistry.init(allocator);
    defer registry.deinit();
    
    // Create distribution with constrained parameters
    var distribution = CustomDistribution.init(allocator, try allocator.dupe(u8, "TestValidation"));
    
    const param = DistributionParameter{
        .name = try allocator.dupe(u8, "scale"),
        .param_type = .f64,
        .constraints = ParameterConstraints{
            .min_value = 0,
            .max_value = 100,
            .positive_only = true,
            .integer_only = false,
            .vector_constraints = null,
            .custom_validator = null,
        },
        .default_value = null,
        .description = null,
    };
    try distribution.parameters.append(param);
    
    try registry.registerDistribution(distribution);
    
    // Test parameter validation
    var params = std.StringHashMap(f64).init(allocator);
    defer params.deinit();
    
    // Valid parameter
    try params.put("scale", 5.0);
    try testing.expect(try registry.validateParameters("TestValidation", params));
    
    // Invalid: negative value
    _ = params.remove("scale");
    try params.put("scale", -1.0);
    try testing.expect(!(try registry.validateParameters("TestValidation", params)));
    
    // Invalid: too large
    _ = params.remove("scale");
    try params.put("scale", 150.0);
    try testing.expect(!(try registry.validateParameters("TestValidation", params)));
}

test "Built-in distribution implementations" {
    
    // Test Normal distribution
    const normal_params = [_]f64{ 0.0, 1.0 }; // mu=0, sigma=1
    const normal_log_prob = @import("custom_distributions.zig").normalLogProb(&normal_params, 0.0);
    
    // At mean, log probability should be -0.5 * log(2π) ≈ -0.919
    try testing.expect(@abs(normal_log_prob - (-0.9189385332046727)) < 1e-10);
    
    // Test Bernoulli distribution
    const bernoulli_params = [_]f64{0.5}; // p=0.5
    const bernoulli_log_prob_1 = @import("custom_distributions.zig").bernoulliLogProb(&bernoulli_params, 1.0);
    const bernoulli_log_prob_0 = @import("custom_distributions.zig").bernoulliLogProb(&bernoulli_params, 0.0);
    
    // Both should be log(0.5) ≈ -0.693
    try testing.expect(@abs(bernoulli_log_prob_1 - (@log(0.5))) < 1e-10);
    try testing.expect(@abs(bernoulli_log_prob_0 - (@log(0.5))) < 1e-10);
    
    // Test Exponential distribution
    const exponential_params = [_]f64{1.0}; // rate=1
    const exponential_log_prob = @import("custom_distributions.zig").exponentialLogProb(&exponential_params, 1.0);
    
    // Should be log(1) - 1*1 = -1
    try testing.expect(@abs(exponential_log_prob - (-1.0)) < 1e-10);
}

test "Distribution sampling" {
    
    var rng = std.Random.DefaultPrng.init(42);
    var random = rng.random();
    
    // Test Normal sampling
    const normal_params = [_]f64{ 0.0, 1.0 };
    var normal_sum: f64 = 0;
    const n_samples = 1000;
    
    for (0..n_samples) |_| {
        const sample = @import("custom_distributions.zig").normalSample(&normal_params, &random);
        normal_sum += sample;
    }
    
    const normal_mean = normal_sum / @as(f64, @floatFromInt(n_samples));
    // Mean should be close to 0 (within 3 standard deviations / sqrt(n))
    try testing.expect(@abs(normal_mean) < 3.0 / @sqrt(@as(f64, @floatFromInt(n_samples))));
    
    // Test Bernoulli sampling
    const bernoulli_params = [_]f64{0.7}; // p=0.7
    var bernoulli_sum: f64 = 0;
    
    for (0..n_samples) |_| {
        const sample = @import("custom_distributions.zig").bernoulliSample(&bernoulli_params, &random);
        bernoulli_sum += sample;
    }
    
    const bernoulli_mean = bernoulli_sum / @as(f64, @floatFromInt(n_samples));
    // Mean should be close to 0.7
    try testing.expect(@abs(bernoulli_mean - 0.7) < 0.1);
}

test "Distribution code generation" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    // Create a simple distribution manually for testing
    var distribution = CustomDistribution.init(allocator, try allocator.dupe(u8, "TestCodeGen"));
    distribution.log_prob_function = try allocator.dupe(u8, "testLogProb");
    distribution.sample_function = try allocator.dupe(u8, "testSample");
    
    const param = DistributionParameter{
        .name = try allocator.dupe(u8, "theta"),
        .param_type = .f64,
        .constraints = ParameterConstraints{
            .min_value = 0,
            .max_value = null,
            .positive_only = true,
            .integer_only = false,
            .vector_constraints = null,
            .custom_validator = null,
        },
        .default_value = null,
        .description = try allocator.dupe(u8, "Parameter theta"),
    };
    try distribution.parameters.append(param);
    
    try compiler.getRegistry().registerDistribution(distribution);
    
    // Generate code
    const generated_code = try compiler.generateDistributionCode("TestCodeGen");
    defer allocator.free(generated_code);
    
    // Check that generated code contains expected elements
    try testing.expect(std.mem.indexOf(u8, generated_code, "TestCodeGenDistribution") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "struct Parameters") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "theta: f64") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "fn log_prob") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "fn sample") != null);
    try testing.expect(std.mem.indexOf(u8, generated_code, "positive") != null); // constraint comment
}

test "Distribution validation" {
    const allocator = testing.allocator;
    
    var compiler = DistributionCompiler.init(allocator);
    defer compiler.deinit();
    
    // Create a valid distribution
    var valid_distribution = CustomDistribution.init(allocator, try allocator.dupe(u8, "ValidDist"));
    valid_distribution.log_prob_function = try allocator.dupe(u8, "validLogProb");
    
    const param = DistributionParameter{
        .name = try allocator.dupe(u8, "param1"),
        .param_type = .f64,
        .constraints = ParameterConstraints{
            .min_value = 0,
            .max_value = 10,
            .positive_only = true,
            .integer_only = false,
            .vector_constraints = null,
            .custom_validator = null,
        },
        .default_value = null,
        .description = null,
    };
    try valid_distribution.parameters.append(param);
    
    try compiler.getRegistry().registerDistribution(valid_distribution);
    
    // Valid distribution should pass validation
    try testing.expect(try compiler.validateDistribution("ValidDist"));
    
    // Create an invalid distribution (no log_prob function) in a separate scope
    {
        var local_compiler = DistributionCompiler.init(allocator);
        defer local_compiler.deinit();
        
        var invalid_distribution = CustomDistribution.init(allocator, try allocator.dupe(u8, "InvalidDistLocal"));
        invalid_distribution.log_prob_function = ""; // Empty - invalid
        
        try local_compiler.getRegistry().registerDistribution(invalid_distribution);
        
        // Invalid distribution should fail validation (silent to avoid stderr output)
        try testing.expect(!(try local_compiler.validateDistributionSilent("InvalidDistLocal", true)));
    }
}

test "Example distributions creation" {
    const allocator = testing.allocator;
    
    var registry = DistributionRegistry.init(allocator);
    defer registry.deinit();
    
    // Create example distributions
    try registry.createExampleDistributions();
    
    // Check that example distributions were created
    try testing.expect(registry.hasDistribution("BetaBinomial"));
    try testing.expect(registry.hasDistribution("GaussianMixture"));
    try testing.expect(registry.hasDistribution("StudentT"));
    try testing.expect(registry.hasDistribution("Dirichlet"));
    
    // Check BetaBinomial parameters
    const beta_binomial = registry.getDistribution("BetaBinomial").?;
    try testing.expect(beta_binomial.parameters.items.len == 3); // n, alpha, beta
    try testing.expect(beta_binomial.is_discrete);
    try testing.expect(beta_binomial.support.support_type == .non_negative_integer);
    
    // Check StudentT parameters
    const student_t = registry.getDistribution("StudentT").?;
    try testing.expect(student_t.parameters.items.len == 3); // df, loc, scale
    try testing.expect(!student_t.is_discrete);
    try testing.expect(student_t.is_location_scale);
}

test "Parameter constraints validation edge cases" {
    const allocator = testing.allocator;
    
    var registry = DistributionRegistry.init(allocator);
    defer registry.deinit();
    
    // Create distribution with integer constraints
    var distribution = CustomDistribution.init(allocator, try allocator.dupe(u8, "IntegerTest"));
    
    const int_param = DistributionParameter{
        .name = try allocator.dupe(u8, "count"),
        .param_type = .i32,
        .constraints = ParameterConstraints{
            .min_value = 1,
            .max_value = 100,
            .positive_only = true,
            .integer_only = true,
            .vector_constraints = null,
            .custom_validator = null,
        },
        .default_value = null,
        .description = null,
    };
    try distribution.parameters.append(int_param);
    
    try registry.registerDistribution(distribution);
    
    var params = std.StringHashMap(f64).init(allocator);
    defer params.deinit();
    
    // Valid integer
    try params.put("count", 5.0);
    try testing.expect(try registry.validateParameters("IntegerTest", params));
    
    // Invalid: not an integer
    _ = params.remove("count");
    try params.put("count", 5.5);
    try testing.expect(!(try registry.validateParameters("IntegerTest", params)));
    
    // Invalid: below minimum
    _ = params.remove("count");
    try params.put("count", 0.0);
    try testing.expect(!(try registry.validateParameters("IntegerTest", params)));
    
    // Invalid: above maximum
    _ = params.remove("count");
    try params.put("count", 101.0);
    try testing.expect(!(try registry.validateParameters("IntegerTest", params)));
}

test "Distribution support types" {
    const allocator = testing.allocator;
    
    // Test all support types
    const support_types = [_]DistributionSupport.SupportType{
        .real_line,
        .positive_real,
        .unit_interval,
        .positive_integer,
        .non_negative_integer,
        .bounded_interval,
        .discrete_set,
        .simplex,
        .positive_definite_matrix,
    };
    
    for (support_types) |support_type| {
        var distribution = CustomDistribution.init(allocator, try allocator.dupe(u8, "SupportTest"));
        defer distribution.deinit(allocator);
        
        distribution.support = DistributionSupport{
            .support_type = support_type,
            .lower_bound = null,
            .upper_bound = null,
            .discrete_values = null,
        };
        
        try testing.expect(distribution.support.support_type == support_type);
    }
}

test "Memory management and cleanup" {
    const allocator = testing.allocator;
    
    // Test that all memory is properly freed
    {
        var registry = DistributionRegistry.init(allocator);
        defer registry.deinit();
        
        // Create and register multiple distributions
        for (0..10) |i| {
            const name = try std.fmt.allocPrint(allocator, "TestDist{d}", .{i});
            defer allocator.free(name);
            
            var distribution = CustomDistribution.init(allocator, try allocator.dupe(u8, name));
            distribution.log_prob_function = try allocator.dupe(u8, "testLogProb");
            
            const param = DistributionParameter{
                .name = try allocator.dupe(u8, "param"),
                .param_type = .f64,
                .constraints = null,
                .default_value = null,
                .description = try allocator.dupe(u8, "Test parameter"),
            };
            try distribution.parameters.append(param);
            
            try registry.registerDistribution(distribution);
        }
        
        // Registry should contain all distributions
        try testing.expect(registry.distributions.count() >= 10);
    }
    // All memory should be freed when registry goes out of scope
}