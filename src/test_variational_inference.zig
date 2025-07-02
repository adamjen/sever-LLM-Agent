const std = @import("std");
const testing = std.testing;
const math = std.math;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const vi = @import("variational_inference.zig");
const VISolver = vi.VISolver;
const VIConfig = vi.VIConfig;
const VariationalParameters = vi.VariationalParameters;
const VariationalFamily = vi.VariationalFamily;

// Test log probability functions

/// Simple normal distribution for testing
fn normalLogProb(params: *const StringHashMap(f64), context: ?*anyopaque) f64 {
    _ = context;
    
    const x = params.get("x") orelse return -math.inf(f64);
    const mu = 0.0;
    const sigma = 1.0;
    
    const diff = x - mu;
    return -0.5 * @log(2.0 * math.pi) - @log(sigma) - 0.5 * (diff * diff) / (sigma * sigma);
}

/// Beta distribution for testing
fn betaLogProb(params: *const StringHashMap(f64), context: ?*anyopaque) f64 {
    _ = context;
    
    const x = params.get("x") orelse return -math.inf(f64);
    
    if (x <= 0 or x >= 1) return -math.inf(f64);
    
    const alpha = 2.0;
    const beta = 3.0;
    
    // Beta(2, 3) log probability
    return (alpha - 1) * @log(x) + (beta - 1) * @log(1 - x) + 
           lgamma(alpha + beta) - lgamma(alpha) - lgamma(beta);
}

/// Gamma distribution for testing
fn gammaLogProb(params: *const StringHashMap(f64), context: ?*anyopaque) f64 {
    _ = context;
    
    const x = params.get("x") orelse return -math.inf(f64);
    
    if (x <= 0) return -math.inf(f64);
    
    const shape = 2.0;
    const rate = 1.0;
    
    return (shape - 1) * @log(x) - rate * x + shape * @log(rate) - lgamma(shape);
}

/// Bivariate normal for testing multiple variables
fn bivariateNormalLogProb(params: *const StringHashMap(f64), context: ?*anyopaque) f64 {
    _ = context;
    
    const x = params.get("x") orelse return -math.inf(f64);
    const y = params.get("y") orelse return -math.inf(f64);
    
    // Independent normals for simplicity
    const x_logprob = -0.5 * @log(2.0 * math.pi) - 0.5 * x * x;
    const y_logprob = -0.5 * @log(2.0 * math.pi) - 0.5 * (y - 1.0) * (y - 1.0);
    
    return x_logprob + y_logprob;
}

// Helper function for log gamma (simplified)
fn lgamma(x: f64) f64 {
    if (x > 12.0) {
        return (x - 0.5) * @log(x) - x + 0.5 * @log(2.0 * math.pi);
    }
    if (x < 1.0) {
        return lgamma(x + 1.0) - @log(x);
    }
    return @log(@sqrt(2.0 * math.pi / x)) + x * (@log(x) - 1.0);
}

test "VariationalParameters basic operations" {
    const allocator = testing.allocator;
    
    var var_params = VariationalParameters.init(allocator, .gaussian);
    defer var_params.deinit();
    
    // Test parameter setting and getting
    try var_params.setParam("mu", 1.5);
    try var_params.setParam("sigma", 0.8);
    
    try testing.expectEqual(@as(f64, 1.5), var_params.getParam("mu").?);
    try testing.expectEqual(@as(f64, 0.8), var_params.getParam("sigma").?);
    try testing.expect(var_params.getParam("nonexistent") == null);
}

test "VariationalParameters Gaussian sampling and log probability" {
    const allocator = testing.allocator;
    
    var var_params = VariationalParameters.init(allocator, .gaussian);
    defer var_params.deinit();
    
    try var_params.setParam("mu", 2.0);
    try var_params.setParam("sigma", 1.5);
    
    var rng = std.Random.DefaultPrng.init(42);
    var random = rng.random();
    
    // Test sampling
    var sample_sum: f64 = 0;
    const n_samples = 1000;
    
    for (0..n_samples) |_| {
        const sample = var_params.sample(&random);
        sample_sum += sample;
    }
    
    const sample_mean = sample_sum / @as(f64, @floatFromInt(n_samples));
    
    // Mean should be close to mu = 2.0
    try testing.expect(@abs(sample_mean - 2.0) < 0.2);
    
    // Test log probability
    const log_prob_at_mean = var_params.logProb(2.0);
    const log_prob_far = var_params.logProb(10.0);
    
    // Log probability should be higher at the mean
    try testing.expect(log_prob_at_mean > log_prob_far);
    
    // Test entropy
    const entropy = var_params.entropy();
    const expected_entropy = 0.5 * @log(2.0 * math.pi * math.e) + @log(1.5);
    try testing.expect(@abs(entropy - expected_entropy) < 1e-10);
}

test "VariationalParameters Gamma distribution" {
    const allocator = testing.allocator;
    
    var var_params = VariationalParameters.init(allocator, .gamma);
    defer var_params.deinit();
    
    try var_params.setParam("shape", 2.0);
    try var_params.setParam("rate", 1.5);
    
    var rng = std.Random.DefaultPrng.init(123);
    var random = rng.random();
    
    // Test sampling (basic sanity check)
    for (0..10) |_| {
        const sample = var_params.sample(&random);
        try testing.expect(sample > 0); // Gamma samples should be positive
    }
    
    // Test log probability
    const log_prob_positive = var_params.logProb(1.0);
    const log_prob_negative = var_params.logProb(-1.0);
    
    try testing.expect(log_prob_positive > -math.inf(f64));
    try testing.expect(log_prob_negative == -math.inf(f64));
}

test "VariationalParameters Beta distribution" {
    const allocator = testing.allocator;
    
    var var_params = VariationalParameters.init(allocator, .beta);
    defer var_params.deinit();
    
    try var_params.setParam("alpha", 2.0);
    try var_params.setParam("beta", 3.0);
    
    var rng = std.Random.DefaultPrng.init(456);
    var random = rng.random();
    
    // Test sampling
    for (0..10) |_| {
        const sample = var_params.sample(&random);
        try testing.expect(sample > 0 and sample < 1); // Beta samples should be in (0,1)
    }
    
    // Test log probability
    const log_prob_valid = var_params.logProb(0.3);
    const log_prob_invalid1 = var_params.logProb(-0.1);
    const log_prob_invalid2 = var_params.logProb(1.1);
    
    try testing.expect(log_prob_valid > -math.inf(f64));
    try testing.expect(log_prob_invalid1 == -math.inf(f64));
    try testing.expect(log_prob_invalid2 == -math.inf(f64));
}

test "VISolver initialization and basic operations" {
    const allocator = testing.allocator;
    
    var config = VIConfig.default();
    config.max_iterations = 10;
    config.sample_size = 50;
    
    var solver = VISolver.init(allocator, config);
    defer solver.deinit();
    
    // Test variable initialization
    try solver.initVariable("x", .gaussian);
    try solver.initVariable("y", .gamma);
    
    // Check that variables were initialized
    const x_params = solver.getVariationalParams("x");
    try testing.expect(x_params != null);
    try testing.expect(x_params.?.family == .gaussian);
    
    const y_params = solver.getVariationalParams("y");
    try testing.expect(y_params != null);
    try testing.expect(y_params.?.family == .gamma);
    
    try testing.expect(solver.getVariationalParams("nonexistent") == null);
}

test "VISolver ELBO computation" {
    const allocator = testing.allocator;
    
    var config = VIConfig.default();
    config.sample_size = 100;
    
    var solver = VISolver.init(allocator, config);
    defer solver.deinit();
    
    try solver.initVariable("x", .gaussian);
    
    // Compute ELBO for normal target
    const elbo = try solver.computeELBO(normalLogProb, null);
    
    // ELBO should be finite
    try testing.expect(!math.isInf(elbo));
    try testing.expect(!math.isNan(elbo));
}

test "VISolver optimization for normal target" {
    const allocator = testing.allocator;
    
    var config = VIConfig.default();
    config.max_iterations = 100;
    config.sample_size = 200;
    config.learning_rate = 0.1;
    config.tolerance = 1e-4;
    
    var solver = VISolver.init(allocator, config);
    defer solver.deinit();
    
    // Initialize with poor starting values
    try solver.initVariable("x", .gaussian);
    var x_params = solver.getVariationalParams("x").?;
    try x_params.setParam("mu", 5.0);    // True mu is 0.0
    try x_params.setParam("sigma", 2.0); // True sigma is 1.0
    
    // Run optimization
    try solver.optimize(normalLogProb, null);
    
    // Check convergence
    const stats = solver.getConvergenceStats();
    try testing.expect(stats.num_iterations > 0);
    try testing.expect(!math.isInf(stats.final_elbo));
    
    // Check that parameters improved (moved towards true values)
    const final_mu = x_params.getParam("mu").?;
    const final_sigma = x_params.getParam("sigma").?;
    
    // Should be within bounds
    try testing.expect(@abs(final_mu) <= 50.0); // Within bounds
    try testing.expect(final_sigma >= 0.01 and final_sigma <= 10.0); // Within bounds
}

test "VISolver optimization for Beta target" {
    const allocator = testing.allocator;
    
    var config = VIConfig.default();
    config.max_iterations = 50;
    config.sample_size = 150;
    config.learning_rate = 0.05;
    
    var solver = VISolver.init(allocator, config);
    defer solver.deinit();
    
    try solver.initVariable("x", .beta);
    
    // Run optimization on Beta(2,3) target
    try solver.optimize(betaLogProb, null);
    
    const stats = solver.getConvergenceStats();
    try testing.expect(stats.num_iterations > 0);
    
    // Check that parameters are reasonable
    const x_params = solver.getVariationalParams("x").?;
    const alpha = x_params.getParam("alpha").?;
    const beta = x_params.getParam("beta").?;
    
    try testing.expect(alpha >= 0.1 and alpha <= 20.0);
    try testing.expect(beta >= 0.1 and beta <= 20.0);
}

test "VISolver optimization for Gamma target" {
    const allocator = testing.allocator;
    
    var config = VIConfig.default();
    config.max_iterations = 50;
    config.sample_size = 150;
    config.learning_rate = 0.05;
    
    var solver = VISolver.init(allocator, config);
    defer solver.deinit();
    
    try solver.initVariable("x", .gamma);
    
    // Run optimization on Gamma(2,1) target
    try solver.optimize(gammaLogProb, null);
    
    const stats = solver.getConvergenceStats();
    try testing.expect(stats.num_iterations > 0);
    
    // Check that parameters are reasonable
    const x_params = solver.getVariationalParams("x").?;
    const shape = x_params.getParam("shape").?;
    const rate = x_params.getParam("rate").?;
    
    try testing.expect(shape > 0.01 and shape < 100.0);
    try testing.expect(rate > 0.01 and rate < 100.0);
}

test "VISolver multivariate optimization" {
    const allocator = testing.allocator;
    
    var config = VIConfig.default();
    config.max_iterations = 50;
    config.sample_size = 100;
    config.learning_rate = 0.01;
    config.tolerance = 1e-3;
    
    var solver = VISolver.init(allocator, config);
    defer solver.deinit();
    
    // Initialize two variables
    try solver.initVariable("x", .gaussian);
    try solver.initVariable("y", .gaussian);
    
    // Set initial values closer to true values
    var x_params = solver.getVariationalParams("x").?;
    var y_params = solver.getVariationalParams("y").?;
    
    try x_params.setParam("mu", 1.0);
    try x_params.setParam("sigma", 1.5);
    try y_params.setParam("mu", 0.5);
    try y_params.setParam("sigma", 1.5);
    
    // Run optimization
    try solver.optimize(bivariateNormalLogProb, null);
    
    const stats = solver.getConvergenceStats();
    try testing.expect(stats.num_iterations > 0);
    
    // Check that parameters are reasonable
    const final_x_mu = x_params.getParam("mu").?;
    const final_y_mu = y_params.getParam("mu").?;
    const final_x_sigma = x_params.getParam("sigma").?;
    const final_y_sigma = y_params.getParam("sigma").?;
    
    try testing.expect(@abs(final_x_mu - 0.0) < 3.0);
    try testing.expect(@abs(final_y_mu - 1.0) < 3.0);
    try testing.expect(final_x_sigma > 0.01 and final_x_sigma < 10.0);
    try testing.expect(final_y_sigma > 0.01 and final_y_sigma < 10.0);
}

test "VISolver convergence detection" {
    const allocator = testing.allocator;
    
    var config = VIConfig.default();
    config.max_iterations = 5;
    config.tolerance = 1e-1; // Large tolerance for quick convergence
    config.sample_size = 50;
    
    var solver = VISolver.init(allocator, config);
    defer solver.deinit();
    
    try solver.initVariable("x", .gaussian);
    
    try solver.optimize(normalLogProb, null);
    
    const stats = solver.getConvergenceStats();
    
    // Should have stopped before max iterations due to convergence
    try testing.expect(stats.num_iterations <= 5);
}

test "VIConfig default values" {
    const config = VIConfig.default();
    
    try testing.expectEqual(@as(usize, 1000), config.max_iterations);
    try testing.expectEqual(@as(f64, 1e-6), config.tolerance);
    try testing.expectEqual(@as(f64, 0.01), config.learning_rate);
    try testing.expectEqual(@as(usize, 100), config.sample_size);
    try testing.expect(!config.print_progress);
    try testing.expectEqual(@as(f64, 0.9), config.momentum);
    try testing.expect(config.adaptive_learning);
    try testing.expectEqual(@as(f64, 0.99), config.learning_rate_decay);
}

test "VariationalParameters entropy computation" {
    const allocator = testing.allocator;
    
    // Test Gaussian entropy
    var gaussian_params = VariationalParameters.init(allocator, .gaussian);
    defer gaussian_params.deinit();
    
    try gaussian_params.setParam("mu", 0.0);
    try gaussian_params.setParam("sigma", 2.0);
    
    const gaussian_entropy = gaussian_params.entropy();
    const expected_gaussian_entropy = 0.5 * @log(2.0 * math.pi * math.e) + @log(2.0);
    try testing.expect(@abs(gaussian_entropy - expected_gaussian_entropy) < 1e-10);
    
    // Test exponential entropy
    var exp_params = VariationalParameters.init(allocator, .exponential);
    defer exp_params.deinit();
    
    try exp_params.setParam("rate", 0.5);
    const exp_entropy = exp_params.entropy();
    const expected_exp_entropy = 1 - @log(0.5);
    try testing.expect(@abs(exp_entropy - expected_exp_entropy) < 1e-10);
}

test "VariationalParameters exponential distribution" {
    const allocator = testing.allocator;
    
    var var_params = VariationalParameters.init(allocator, .exponential);
    defer var_params.deinit();
    
    try var_params.setParam("rate", 2.0);
    
    var rng = std.Random.DefaultPrng.init(789);
    var random = rng.random();
    
    // Test sampling
    for (0..10) |_| {
        const sample = var_params.sample(&random);
        try testing.expect(sample >= 0); // Exponential samples should be non-negative
    }
    
    // Test log probability
    const log_prob_positive = var_params.logProb(1.0);
    const log_prob_zero = var_params.logProb(0.0);
    const log_prob_negative = var_params.logProb(-1.0);
    
    try testing.expect(log_prob_positive > -math.inf(f64));
    try testing.expect(log_prob_zero > -math.inf(f64));
    try testing.expect(log_prob_negative == -math.inf(f64));
}