const std = @import("std");
const math = std.math;
const Random = std.Random;
const Allocator = std.mem.Allocator;

// Global random number generator
var prng = std.rand.DefaultPrng.init(0);
var random = prng.random();

// Observation storage for inference
var observations = std.ArrayList(Observation).init(std.heap.page_allocator);

const Observation = struct {
    distribution: []const u8,
    params: []const f64,
    value: f64,
};

// Initialize runtime with random seed
pub fn init(seed: ?u64) void {
    const actual_seed = seed orelse @intCast(std.time.timestamp());
    prng = std.rand.DefaultPrng.init(actual_seed);
    random = prng.random();
}

// Sampling functions for different distributions
pub fn sample(distribution: []const u8, params: []const f64) f64 {
    if (std.mem.eql(u8, distribution, "uniform")) {
        if (params.len != 2) @panic("Uniform distribution requires 2 parameters (min, max)");
        const min = params[0];
        const max = params[1];
        return min + random.float(f64) * (max - min);
    } else if (std.mem.eql(u8, distribution, "normal")) {
        if (params.len != 2) @panic("Normal distribution requires 2 parameters (mean, std)");
        const mean = params[0];
        const std_dev = params[1];
        return sampleNormal(mean, std_dev);
    } else if (std.mem.eql(u8, distribution, "exponential")) {
        if (params.len != 1) @panic("Exponential distribution requires 1 parameter (rate)");
        const rate = params[0];
        return -math.ln(1.0 - random.float(f64)) / rate;
    } else if (std.mem.eql(u8, distribution, "gamma")) {
        if (params.len != 2) @panic("Gamma distribution requires 2 parameters (shape, scale)");
        const shape = params[0];
        const scale = params[1];
        return sampleGamma(shape, scale);
    } else if (std.mem.eql(u8, distribution, "beta")) {
        if (params.len != 2) @panic("Beta distribution requires 2 parameters (alpha, beta)");
        const alpha = params[0];
        const beta = params[1];
        return sampleBeta(alpha, beta);
    } else if (std.mem.eql(u8, distribution, "bernoulli")) {
        if (params.len != 1) @panic("Bernoulli distribution requires 1 parameter (probability)");
        const p = params[0];
        return if (random.float(f64) < p) 1.0 else 0.0;
    } else if (std.mem.eql(u8, distribution, "categorical")) {
        if (params.len < 1) @panic("Categorical distribution requires at least 1 parameter");
        return sampleCategorical(params);
    } else {
        @panic("Unknown distribution");
    }
}

// Sample from normal distribution using Box-Muller transform
fn sampleNormal(mean: f64, std_dev: f64) f64 {
    const u1 = random.float(f64);
    const u2 = random.float(f64);
    
    const z0 = math.sqrt(-2.0 * math.ln(u1)) * math.cos(2.0 * math.pi * u2);
    return mean + std_dev * z0;
}

// Sample from gamma distribution using Marsaglia-Tsang method
fn sampleGamma(shape: f64, scale: f64) f64 {
    if (shape < 1.0) {
        return sampleGamma(shape + 1.0, scale) * math.pow(f64, random.float(f64), 1.0 / shape);
    }
    
    const d = shape - 1.0 / 3.0;
    const c = 1.0 / math.sqrt(9.0 * d);
    
    while (true) {
        var x = sampleNormal(0.0, 1.0);
        var v = 1.0 + c * x;
        
        if (v <= 0.0) continue;
        
        v = v * v * v;
        const u = random.float(f64);
        
        if (u < 1.0 - 0.0331 * x * x * x * x) {
            return d * v * scale;
        }
        
        if (math.ln(u) < 0.5 * x * x + d * (1.0 - v + math.ln(v))) {
            return d * v * scale;
        }
    }
}

// Sample from beta distribution
fn sampleBeta(alpha: f64, beta: f64) f64 {
    const x = sampleGamma(alpha, 1.0);
    const y = sampleGamma(beta, 1.0);
    return x / (x + y);
}

// Sample from categorical distribution
fn sampleCategorical(probs: []const f64) f64 {
    var cumsum: f64 = 0.0;
    for (probs) |p| {
        cumsum += p;
    }
    
    const u = random.float(f64) * cumsum;
    var running_sum: f64 = 0.0;
    
    for (probs, 0..) |p, i| {
        running_sum += p;
        if (u <= running_sum) {
            return @floatFromInt(i);
        }
    }
    
    return @floatFromInt(probs.len - 1);
}

// Observe a value from a distribution (for inference)
pub fn observe(distribution: []const u8, params: []const f64, value: f64) void {
    const obs = Observation{
        .distribution = distribution,
        .params = params,
        .value = value,
    };
    
    observations.append(obs) catch @panic("Failed to store observation");
}

// Compute log probability density/mass function
pub fn logpdf(distribution: []const u8, params: []const f64, value: f64) f64 {
    if (std.mem.eql(u8, distribution, "uniform")) {
        if (params.len != 2) @panic("Uniform distribution requires 2 parameters");
        const min = params[0];
        const max = params[1];
        if (value >= min and value <= max) {
            return -math.ln(max - min);
        } else {
            return -math.inf(f64);
        }
    } else if (std.mem.eql(u8, distribution, "normal")) {
        if (params.len != 2) @panic("Normal distribution requires 2 parameters");
        const mean = params[0];
        const std_dev = params[1];
        const diff = value - mean;
        return -0.5 * math.ln(2.0 * math.pi) - math.ln(std_dev) - 0.5 * (diff * diff) / (std_dev * std_dev);
    } else if (std.mem.eql(u8, distribution, "exponential")) {
        if (params.len != 1) @panic("Exponential distribution requires 1 parameter");
        const rate = params[0];
        if (value >= 0.0) {
            return math.ln(rate) - rate * value;
        } else {
            return -math.inf(f64);
        }
    } else if (std.mem.eql(u8, distribution, "bernoulli")) {
        if (params.len != 1) @panic("Bernoulli distribution requires 1 parameter");
        const p = params[0];
        if (value == 1.0) {
            return math.ln(p);
        } else if (value == 0.0) {
            return math.ln(1.0 - p);
        } else {
            return -math.inf(f64);
        }
    } else {
        @panic("Log PDF not implemented for this distribution");
    }
}

// Simple Monte Carlo inference
pub fn infer(model_func: *const fn () f64, num_samples: u32) f64 {
    var sum: f64 = 0.0;
    
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const sample_value = model_func();
        sum += sample_value;
    }
    
    return sum / @as(f64, @floatFromInt(num_samples));
}

// Metropolis-Hastings sampling for more sophisticated inference
pub fn mh_sample(model_func: *const fn (f64) f64, initial_value: f64, num_samples: u32, step_size: f64) []f64 {
    const allocator = std.heap.page_allocator;
    var samples = allocator.alloc(f64, num_samples) catch @panic("Failed to allocate samples");
    
    var current_value = initial_value;
    var current_log_prob = model_func(current_value);
    
    var accepted: u32 = 0;
    
    for (samples, 0..) |*sample, i| {
        // Propose new value
        const proposal = current_value + sampleNormal(0.0, step_size);
        const proposal_log_prob = model_func(proposal);
        
        // Accept/reject
        const log_alpha = proposal_log_prob - current_log_prob;
        if (log_alpha > 0.0 or math.ln(random.float(f64)) < log_alpha) {
            current_value = proposal;
            current_log_prob = proposal_log_prob;
            accepted += 1;
        }
        
        sample.* = current_value;
    }
    
    const acceptance_rate = @as(f64, @floatFromInt(accepted)) / @as(f64, @floatFromInt(num_samples));
    std.debug.print("Acceptance rate: {d:.2}\n", .{acceptance_rate});
    
    return samples;
}

// Probabilistic assertion - check that condition holds with minimum confidence
pub fn prob_assert(condition_func: *const fn () bool, confidence: f64, num_samples: u32) void {
    var successes: u32 = 0;
    
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        if (condition_func()) {
            successes += 1;
        }
    }
    
    const actual_confidence = @as(f64, @floatFromInt(successes)) / @as(f64, @floatFromInt(num_samples));
    
    if (actual_confidence < confidence) {
        std.debug.print("Probabilistic assertion failed: expected {d:.2}, got {d:.2}\n", .{ confidence, actual_confidence });
        @panic("Probabilistic assertion failed");
    }
}

// Simple version of prob_assert for boolean expressions
pub fn prob_assert_simple(condition: bool, confidence: f64) void {
    _ = confidence;
    if (!condition) {
        @panic("Probabilistic assertion failed");
    }
}

// Clear observations (for testing)
pub fn clear_observations() void {
    observations.clearRetainingCapacity();
}

// Get number of observations (for testing)
pub fn observation_count() usize {
    return observations.items.len;
}

// Compute log likelihood of all observations
pub fn log_likelihood() f64 {
    var total_log_prob: f64 = 0.0;
    
    for (observations.items) |obs| {
        total_log_prob += logpdf(obs.distribution, obs.params, obs.value);
    }
    
    return total_log_prob;
}