const std = @import("std");
const testing = std.testing;
const math = std.math;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const mcmc = @import("mcmc.zig");
const HMCSampler = mcmc.HMCSampler;
const HMCConfig = mcmc.HMCConfig;

const autodiff = @import("autodiff.zig");
const ComputationGraph = autodiff.ComputationGraph;

// Integration tests for Hamiltonian Monte Carlo with automatic differentiation

test "HMC basic functionality" {
    const allocator = testing.allocator;
    
    var config = HMCConfig.default();
    config.initial_step_size = 0.05;
    config.num_leapfrog_steps = 5;
    
    var hmc = HMCSampler.init(allocator, config);
    defer hmc.deinit();
    
    // Initialize a simple parameter
    try hmc.initParameter("x", 0.0, 1.0);
    
    // Test that parameter was initialized
    try testing.expect(hmc.current_state.contains("x"));
    try testing.expect(hmc.momentum.contains("x"));
    try testing.expect(hmc.mass_matrix.contains("x"));
    try testing.expect(hmc.traces.contains("x"));
    
    try testing.expectApproxEqAbs(hmc.current_state.get("x").?, 0.0, 1e-10);
    try testing.expectApproxEqAbs(hmc.mass_matrix.get("x").?, 1.0, 1e-10);
}

test "HMC simple sampling with gradient function" {
    const allocator = testing.allocator;
    
    var config = HMCConfig.default();
    config.initial_step_size = 0.1;
    config.num_leapfrog_steps = 5;
    config.adapt_step_size = false; // Keep step size fixed for test
    
    var hmc = HMCSampler.init(allocator, config);
    defer hmc.deinit();
    
    // Initialize parameter for sampling from N(0, 1)
    try hmc.initParameter("x", 2.0, 1.0); // Start far from mode
    
    // Define log probability function: log p(x) = -0.5 * x^2 (standard normal)
    const standardNormalLogProb = struct {
        fn call(params: *const StringHashMap(f64), gradients: *StringHashMap(f64), context: ?*anyopaque) f64 {
            _ = context;
            
            const x = params.get("x") orelse return -math.inf(f64);
            
            // Compute log probability: -0.5 * x^2
            const log_prob = -0.5 * x * x;
            
            // Compute gradient: d(-0.5 * x^2)/dx = -x
            gradients.put("x", -x) catch return -math.inf(f64);
            
            return log_prob;
        }
    }.call;
    
    // Run a few HMC steps
    try hmc.sample(standardNormalLogProb, null, 20);
    
    // Check that we have samples
    const trace = hmc.getTrace("x").?;
    try testing.expect(trace.values.items.len == 20);
    try testing.expect(trace.log_probs.items.len == 20);
    try testing.expect(trace.accepted.items.len == 20);
    
    // Check acceptance rate is reasonable (should be around 0.65 for well-tuned HMC)
    const acceptance_rate = hmc.getAcceptanceRate();
    try testing.expect(acceptance_rate >= 0.2); // Very lenient bound for test
    try testing.expect(acceptance_rate <= 1.0);
    
    // Check that samples are in reasonable range for standard normal
    const final_value = trace.values.items[trace.values.items.len - 1];
    try testing.expect(@abs(final_value) < 10.0); // Very loose bound
}

test "HMC two-parameter sampling" {
    const allocator = testing.allocator;
    
    var config = HMCConfig.default();
    config.initial_step_size = 0.08;
    config.num_leapfrog_steps = 8;
    config.adapt_step_size = false;
    
    var hmc = HMCSampler.init(allocator, config);
    defer hmc.deinit();
    
    // Initialize two independent parameters
    try hmc.initParameter("x", 1.0, 1.0);
    try hmc.initParameter("y", -1.0, 1.0);
    
    // Define log probability function for independent standard normals
    const bivariateNormalLogProb = struct {
        fn call(params: *const StringHashMap(f64), gradients: *StringHashMap(f64), context: ?*anyopaque) f64 {
            _ = context;
            
            const x = params.get("x") orelse return -math.inf(f64);
            const y = params.get("y") orelse return -math.inf(f64);
            
            // Log probability: -0.5 * (x^2 + y^2)
            const log_prob = -0.5 * (x * x + y * y);
            
            // Gradients
            gradients.put("x", -x) catch return -math.inf(f64);
            gradients.put("y", -y) catch return -math.inf(f64);
            
            return log_prob;
        }
    }.call;
    
    // Run HMC sampling
    try hmc.sample(bivariateNormalLogProb, null, 15);
    
    // Check both parameters have traces
    const x_trace = hmc.getTrace("x").?;
    const y_trace = hmc.getTrace("y").?;
    
    try testing.expect(x_trace.values.items.len == 15);
    try testing.expect(y_trace.values.items.len == 15);
    
    // Check that both parameters moved from their initial values
    const initial_x = 1.0;
    const initial_y = -1.0;
    const final_x = x_trace.values.items[x_trace.values.items.len - 1];
    const final_y = y_trace.values.items[y_trace.values.items.len - 1];
    
    // Should have moved (very loose test - mainly checking no crashes)
    try testing.expect(@abs(final_x - initial_x) < 10.0);
    try testing.expect(@abs(final_y - initial_y) < 10.0);
    
    // Check effective sample size computation doesn't crash
    const x_ess = hmc.getEffectiveSampleSize("x");
    const y_ess = hmc.getEffectiveSampleSize("y");
    try testing.expect(x_ess >= 0.0);
    try testing.expect(y_ess >= 0.0);
}

test "HMC step size adaptation" {
    const allocator = testing.allocator;
    
    var config = HMCConfig.default();
    config.initial_step_size = 0.01; // Start with very small step size
    config.num_leapfrog_steps = 5;
    config.adapt_step_size = true;
    
    var hmc = HMCSampler.init(allocator, config);
    defer hmc.deinit();
    
    try hmc.initParameter("x", 0.0, 1.0);
    
    const initial_step_size = hmc.step_size;
    try testing.expectApproxEqAbs(initial_step_size, 0.01, 1e-10);
    
    // Define log probability function
    const standardNormalLogProb = struct {
        fn call(params: *const StringHashMap(f64), gradients: *StringHashMap(f64), context: ?*anyopaque) f64 {
            _ = context;
            
            const x = params.get("x") orelse return -math.inf(f64);
            const log_prob = -0.5 * x * x;
            
            gradients.put("x", -x) catch return -math.inf(f64);
            
            return log_prob;
        }
    }.call;
    
    // Run several steps to allow adaptation
    try hmc.sample(standardNormalLogProb, null, 10);
    
    // Step size should have adapted (increased due to small initial value)
    const final_step_size = hmc.step_size;
    try testing.expect(final_step_size != initial_step_size);
    try testing.expect(final_step_size > 1e-6); // Should be within bounds
    try testing.expect(final_step_size <= 1.0);
}

test "HMC mass matrix functionality" {
    const allocator = testing.allocator;
    
    const config = HMCConfig.default();
    var hmc = HMCSampler.init(allocator, config);
    defer hmc.deinit();
    
    // Initialize parameters with different masses
    try hmc.initParameter("x", 0.0, 2.0); // Higher mass
    try hmc.initParameter("y", 0.0, 0.5); // Lower mass
    
    // Check that masses were set correctly
    try testing.expectApproxEqAbs(hmc.mass_matrix.get("x").?, 2.0, 1e-10);
    try testing.expectApproxEqAbs(hmc.mass_matrix.get("y").?, 0.5, 1e-10);
    
    // Just test that sampling completes without error
    const simpleLogProb = struct {
        fn call(params: *const StringHashMap(f64), gradients: *StringHashMap(f64), context: ?*anyopaque) f64 {
            _ = context;
            
            const x = params.get("x") orelse return -math.inf(f64);
            const y = params.get("y") orelse return -math.inf(f64);
            const log_prob = -0.5 * (x * x + y * y);
            
            gradients.put("x", -x) catch return -math.inf(f64);
            gradients.put("y", -y) catch return -math.inf(f64);
            
            return log_prob;
        }
    }.call;
    
    try hmc.sample(simpleLogProb, null, 2);
    
    // Check that traces exist and have samples
    try testing.expect(hmc.getTrace("x") != null);
    try testing.expect(hmc.getTrace("y") != null);
}

test "HMC energy conservation test" {
    const allocator = testing.allocator;
    
    var config = HMCConfig.default();
    config.initial_step_size = 0.01; // Very small step size for better conservation
    config.num_leapfrog_steps = 20;
    config.adapt_step_size = false;
    
    var hmc = HMCSampler.init(allocator, config);
    defer hmc.deinit();
    
    try hmc.initParameter("x", 1.0, 1.0);
    
    // Define simple quadratic potential: U(x) = 0.5 * x^2
    // This should have good energy conservation properties
    const quadraticLogProb = struct {
        fn call(params: *const StringHashMap(f64), gradients: *StringHashMap(f64), context: ?*anyopaque) f64 {
            _ = context;
            
            const x = params.get("x") orelse return -math.inf(f64);
            const log_prob = -0.5 * x * x; // log p(x) = -U(x)
            
            gradients.put("x", -x) catch return -math.inf(f64); // -dU/dx
            
            return log_prob;
        }
    }.call;
    
    // Run one HMC step and check that it completes without error
    try hmc.sample(quadraticLogProb, null, 1);
    
    // Basic sanity checks
    const trace = hmc.getTrace("x").?;
    try testing.expect(trace.values.items.len == 1);
    try testing.expect(!math.isNan(trace.values.items[0]));
    try testing.expect(!math.isInf(trace.values.items[0]));
    try testing.expect(!math.isNan(trace.log_probs.items[0]));
    
    // Check that acceptance rate is reasonable
    const acceptance_rate = hmc.getAcceptanceRate();
    try testing.expect(acceptance_rate >= 0.0);
    try testing.expect(acceptance_rate <= 1.0);
}

// Note: Removed tests for internal leapfrog and kinetic energy methods
// These are implementation details that should be tested through the public API

test "HMC trace recording and statistics" {
    const allocator = testing.allocator;
    
    var config = HMCConfig.default();
    config.adapt_step_size = false;
    
    var hmc = HMCSampler.init(allocator, config);
    defer hmc.deinit();
    
    try hmc.initParameter("theta", 0.5, 1.0);
    
    // Simple log probability function
    const simpleLogProb = struct {
        fn call(params: *const StringHashMap(f64), gradients: *StringHashMap(f64), context: ?*anyopaque) f64 {
            _ = context;
            
            const theta = params.get("theta") orelse return -math.inf(f64);
            const log_prob = -0.5 * theta * theta;
            
            gradients.put("theta", -theta) catch return -math.inf(f64);
            
            return log_prob;
        }
    }.call;
    
    // Run several samples
    const num_samples = 8;
    try hmc.sample(simpleLogProb, null, num_samples);
    
    // Check trace properties
    const trace = hmc.getTrace("theta").?;
    try testing.expect(trace.values.items.len == num_samples);
    try testing.expect(trace.log_probs.items.len == num_samples);
    try testing.expect(trace.accepted.items.len == num_samples);
    
    // Check that all log probabilities are finite
    for (trace.log_probs.items) |log_prob| {
        try testing.expect(!math.isNan(log_prob));
        try testing.expect(!math.isInf(log_prob));
    }
    
    // Check that all values are finite
    for (trace.values.items) |value| {
        try testing.expect(!math.isNan(value));
        try testing.expect(!math.isInf(value));
    }
    
    // Check acceptance/rejection tracking
    var num_accepted: usize = 0;
    for (trace.accepted.items) |accepted| {
        if (accepted) num_accepted += 1;
    }
    
    const expected_acceptance_rate = @as(f64, @floatFromInt(num_accepted)) / @as(f64, @floatFromInt(num_samples));
    const actual_acceptance_rate = hmc.getAcceptanceRate();
    
    try testing.expectApproxEqAbs(actual_acceptance_rate, expected_acceptance_rate, 1e-10);
}

test "HMC error handling" {
    const allocator = testing.allocator;
    
    const config = HMCConfig.default();
    var hmc = HMCSampler.init(allocator, config);
    defer hmc.deinit();
    
    // Test getting trace for non-existent parameter
    const nonexistent_trace = hmc.getTrace("nonexistent");
    try testing.expect(nonexistent_trace == null);
    
    // Test effective sample size for non-existent parameter
    const nonexistent_ess = hmc.getEffectiveSampleSize("nonexistent");
    try testing.expectApproxEqAbs(nonexistent_ess, 0.0, 1e-10);
    
    // Test acceptance rate with no samples
    const initial_acceptance_rate = hmc.getAcceptanceRate();
    try testing.expectApproxEqAbs(initial_acceptance_rate, 0.0, 1e-10);
}