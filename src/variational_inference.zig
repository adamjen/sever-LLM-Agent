const std = @import("std");
const math = std.math;
const Random = std.Random;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const SirsParser = @import("sirs.zig");
const Expression = SirsParser.Expression;
const Statement = SirsParser.Statement;
const Type = SirsParser.Type;
const Function = SirsParser.Function;
const Program = SirsParser.Program;

const autodiff = @import("autodiff.zig");
const ComputationGraph = autodiff.ComputationGraph;
const GradientComputer = autodiff.GradientComputer;

/// Supported variational distribution families
pub const VariationalFamily = enum {
    gaussian,
    gamma,
    beta,
    exponential,
    mixture,
};

/// Variational distribution parameters
pub const VariationalParameters = struct {
    family: VariationalFamily,
    params: StringHashMap(f64),
    
    pub fn init(allocator: Allocator, family: VariationalFamily) VariationalParameters {
        return VariationalParameters{
            .family = family,
            .params = StringHashMap(f64).init(allocator),
        };
    }
    
    pub fn deinit(self: *VariationalParameters) void {
        self.params.deinit();
    }
    
    /// Set parameter value
    pub fn setParam(self: *VariationalParameters, name: []const u8, value: f64) !void {
        try self.params.put(name, value);
    }
    
    /// Get parameter value
    pub fn getParam(self: *VariationalParameters, name: []const u8) ?f64 {
        return self.params.get(name);
    }
    
    /// Sample from the variational distribution
    pub fn sample(self: *VariationalParameters, rng: *Random) f64 {
        switch (self.family) {
            .gaussian => {
                const mu = self.getParam("mu") orelse 0.0;
                const sigma = self.getParam("sigma") orelse 1.0;
                return mu + sigma * rng.floatNorm(f64);
            },
            .gamma => {
                const shape = self.getParam("shape") orelse 1.0;
                const rate = self.getParam("rate") orelse 1.0;
                // Simple gamma approximation using accept-reject
                return gammaApprox(rng, shape, rate);
            },
            .beta => {
                const alpha = self.getParam("alpha") orelse 1.0;
                const beta = self.getParam("beta") orelse 1.0;
                // Use beta approximation
                return betaApprox(rng, alpha, beta);
            },
            .exponential => {
                const rate = self.getParam("rate") orelse 1.0;
                return -@log(rng.float(f64)) / rate;
            },
            .mixture => {
                // TODO: Implement mixture sampling
                return 0.0;
            },
        }
    }
    
    /// Compute log probability density
    pub fn logProb(self: *VariationalParameters, x: f64) f64 {
        switch (self.family) {
            .gaussian => {
                const mu = self.getParam("mu") orelse 0.0;
                const sigma = self.getParam("sigma") orelse 1.0;
                const diff = x - mu;
                return -0.5 * @log(2.0 * math.pi) - @log(sigma) - 0.5 * (diff * diff) / (sigma * sigma);
            },
            .gamma => {
                const shape = self.getParam("shape") orelse 1.0;
                const rate = self.getParam("rate") orelse 1.0;
                if (x <= 0) return -math.inf(f64);
                return (shape - 1) * @log(x) - rate * x + shape * @log(rate) - lgamma(shape);
            },
            .beta => {
                const alpha = self.getParam("alpha") orelse 1.0;
                const beta = self.getParam("beta") orelse 1.0;
                if (x <= 0 or x >= 1) return -math.inf(f64);
                return (alpha - 1) * @log(x) + (beta - 1) * @log(1 - x) + lgamma(alpha + beta) - lgamma(alpha) - lgamma(beta);
            },
            .exponential => {
                const rate = self.getParam("rate") orelse 1.0;
                if (x < 0) return -math.inf(f64);
                return @log(rate) - rate * x;
            },
            .mixture => {
                // TODO: Implement mixture log probability
                return 0.0;
            },
        }
    }
    
    /// Compute entropy of the variational distribution
    pub fn entropy(self: *VariationalParameters) f64 {
        switch (self.family) {
            .gaussian => {
                const sigma = self.getParam("sigma") orelse 1.0;
                return 0.5 * @log(2.0 * math.pi * math.e) + @log(sigma);
            },
            .gamma => {
                const shape = self.getParam("shape") orelse 1.0;
                const rate = self.getParam("rate") orelse 1.0;
                return shape - @log(rate) + lgamma(shape) + (1 - shape) * digamma(shape);
            },
            .beta => {
                const alpha = self.getParam("alpha") orelse 1.0;
                const beta = self.getParam("beta") orelse 1.0;
                return lgamma(alpha) + lgamma(beta) - lgamma(alpha + beta) - 
                       (alpha - 1) * digamma(alpha) - (beta - 1) * digamma(beta) + 
                       (alpha + beta - 2) * digamma(alpha + beta);
            },
            .exponential => {
                const rate = self.getParam("rate") orelse 1.0;
                return 1 - @log(rate);
            },
            .mixture => {
                // TODO: Implement mixture entropy
                return 0.0;
            },
        }
    }
};

/// Variational inference configuration
pub const VIConfig = struct {
    max_iterations: usize,
    tolerance: f64,
    learning_rate: f64,
    sample_size: usize,
    print_progress: bool,
    momentum: f64,
    adaptive_learning: bool,
    learning_rate_decay: f64,
    
    pub fn default() VIConfig {
        return VIConfig{
            .max_iterations = 1000,
            .tolerance = 1e-6,
            .learning_rate = 0.01,
            .sample_size = 100,
            .print_progress = false,
            .momentum = 0.9,
            .adaptive_learning = true,
            .learning_rate_decay = 0.99,
        };
    }
};

/// Variational inference solver
pub const VISolver = struct {
    allocator: Allocator,
    config: VIConfig,
    prng: std.Random.DefaultPrng,
    variational_params: StringHashMap(VariationalParameters),
    elbo_history: ArrayList(f64),
    momentum_cache: StringHashMap(StringHashMap(f64)), // var_name -> param_name -> momentum
    current_learning_rate: f64,
    
    /// Log probability function type
    pub const LogProbFn = *const fn (params: *const StringHashMap(f64), context: ?*anyopaque) f64;
    
    pub fn init(allocator: Allocator, config: VIConfig) VISolver {
        const seed = @as(u64, @intCast(std.time.milliTimestamp()));
        
        return VISolver{
            .allocator = allocator,
            .config = config,
            .prng = std.Random.DefaultPrng.init(seed),
            .variational_params = StringHashMap(VariationalParameters).init(allocator),
            .elbo_history = ArrayList(f64).init(allocator),
            .momentum_cache = StringHashMap(StringHashMap(f64)).init(allocator),
            .current_learning_rate = config.learning_rate,
        };
    }
    
    /// Initialize with deterministic seed (for testing)
    pub fn initWithSeed(allocator: Allocator, config: VIConfig, seed: u64) VISolver {
        return VISolver{
            .allocator = allocator,
            .config = config,
            .prng = std.Random.DefaultPrng.init(seed),
            .variational_params = StringHashMap(VariationalParameters).init(allocator),
            .elbo_history = ArrayList(f64).init(allocator),
            .momentum_cache = StringHashMap(StringHashMap(f64)).init(allocator),
            .current_learning_rate = config.learning_rate,
        };
    }
    
    pub fn deinit(self: *VISolver) void {
        var iter = self.variational_params.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.variational_params.deinit();
        self.elbo_history.deinit();
        
        // Clean up momentum cache
        var momentum_iter = self.momentum_cache.iterator();
        while (momentum_iter.next()) |momentum_entry| {
            momentum_entry.value_ptr.deinit();
        }
        self.momentum_cache.deinit();
    }
    
    /// Initialize variational parameters for a variable
    pub fn initVariable(self: *VISolver, name: []const u8, family: VariationalFamily) !void {
        var var_params = VariationalParameters.init(self.allocator, family);
        
        // Initialize momentum cache for this variable
        var momentum_map = StringHashMap(f64).init(self.allocator);
        
        // Initialize with reasonable defaults
        switch (family) {
            .gaussian => {
                try var_params.setParam("mu", 0.0);
                try var_params.setParam("sigma", 1.0);
                try momentum_map.put("mu", 0.0);
                try momentum_map.put("sigma", 0.0);
            },
            .gamma => {
                try var_params.setParam("shape", 1.0);
                try var_params.setParam("rate", 1.0);
                try momentum_map.put("shape", 0.0);
                try momentum_map.put("rate", 0.0);
            },
            .beta => {
                try var_params.setParam("alpha", 1.0);
                try var_params.setParam("beta", 1.0);
                try momentum_map.put("alpha", 0.0);
                try momentum_map.put("beta", 0.0);
            },
            .exponential => {
                try var_params.setParam("rate", 1.0);
                try momentum_map.put("rate", 0.0);
            },
            .mixture => {
                // TODO: Initialize mixture parameters
            },
        }
        
        try self.variational_params.put(name, var_params);
        try self.momentum_cache.put(name, momentum_map);
    }
    
    /// Compute Evidence Lower BOund (ELBO)
    pub fn computeELBO(self: *VISolver, log_prob_fn: LogProbFn, context: ?*anyopaque) !f64 {
        var entropy_sum: f64 = 0.0;
        var expected_log_prob: f64 = 0.0;
        
        // Sample from variational distribution and compute expectations
        for (0..self.config.sample_size) |_| {
            var sample_params = StringHashMap(f64).init(self.allocator);
            defer sample_params.deinit();
            
            // Sample from each variational distribution
            var param_iter = self.variational_params.iterator();
            while (param_iter.next()) |entry| {
                const var_name = entry.key_ptr.*;
                const var_dist = entry.value_ptr;
                var rng = self.prng.random();
                const sample_val = var_dist.sample(&rng);
                try sample_params.put(var_name, sample_val);
            }
            
            // Evaluate log probability at sample
            const log_prob = log_prob_fn(&sample_params, context);
            expected_log_prob += log_prob;
        }
        expected_log_prob /= @as(f64, @floatFromInt(self.config.sample_size));
        
        // Compute entropy terms
        var entropy_iter = self.variational_params.iterator();
        while (entropy_iter.next()) |entry| {
            entropy_sum += entry.value_ptr.entropy();
        }
        
        const elbo = expected_log_prob + entropy_sum;
        return elbo;
    }
    
    /// Update variational parameters using coordinate ascent
    pub fn updateParameters(self: *VISolver, log_prob_fn: LogProbFn, context: ?*anyopaque) !void {
        var param_iter = self.variational_params.iterator();
        while (param_iter.next()) |entry| {
            const var_name = entry.key_ptr.*;
            const var_dist = entry.value_ptr;
            
            // Compute gradients for each parameter using finite differences
            try self.updateVariationalParameters(var_name, var_dist, log_prob_fn, context);
        }
    }
    
    /// Update parameter with momentum
    fn updateParameterWithMomentum(self: *VISolver, var_name: []const u8, param_name: []const u8, gradient: f64, current_value: f64, learning_rate: f64, min_bound: f64, max_bound: f64) !f64 {
        const momentum_map = self.momentum_cache.getPtr(var_name).?;
        const current_momentum = momentum_map.get(param_name) orelse 0.0;
        
        // Update momentum: v = β * v + (1-β) * gradient
        const new_momentum = self.config.momentum * current_momentum + (1.0 - self.config.momentum) * gradient;
        try momentum_map.put(param_name, new_momentum);
        
        // Update parameter with momentum: θ = θ + α * v
        const new_value = current_value + learning_rate * new_momentum;
        
        // Apply bounds
        return @max(min_bound, @min(max_bound, new_value));
    }

    /// Update parameters for a specific variable
    fn updateVariationalParameters(self: *VISolver, var_name: []const u8, var_dist: *VariationalParameters, log_prob_fn: LogProbFn, context: ?*anyopaque) !void {
        const eps = 1e-4;
        
        // Update parameters based on family type
        switch (var_dist.family) {
            .gaussian => {
                // Update mu and sigma with momentum
                const current_mu = var_dist.getParam("mu") orelse 0.0;
                const current_sigma = var_dist.getParam("sigma") orelse 1.0;
                
                // Compute gradients via finite differences
                const grad_mu = try self.computeParameterGradient("mu", current_mu, eps, var_dist, log_prob_fn, context);
                const grad_sigma = try self.computeParameterGradient("sigma", current_sigma, eps, var_dist, log_prob_fn, context);
                
                // Use adaptive learning rates - smaller for sigma to maintain positivity
                const mu_lr = self.current_learning_rate;
                const sigma_lr = self.current_learning_rate * 0.5; // More conservative for sigma
                
                // Update with momentum and bounds
                const new_mu = try self.updateParameterWithMomentum(var_name, "mu", grad_mu, current_mu, mu_lr, -50.0, 50.0);
                const new_sigma = try self.updateParameterWithMomentum(var_name, "sigma", grad_sigma, current_sigma, sigma_lr, 0.1, 10.0);
                
                try var_dist.setParam("mu", new_mu);
                try var_dist.setParam("sigma", new_sigma);
            },
            .gamma => {
                // Update shape and rate with momentum
                const current_shape = var_dist.getParam("shape") orelse 1.0;
                const current_rate = var_dist.getParam("rate") orelse 1.0;
                
                const grad_shape = try self.computeParameterGradient("shape", current_shape, eps, var_dist, log_prob_fn, context);
                const grad_rate = try self.computeParameterGradient("rate", current_rate, eps, var_dist, log_prob_fn, context);
                
                // Conservative learning rates for gamma parameters
                const gamma_lr = self.current_learning_rate * 0.3;
                
                const new_shape = try self.updateParameterWithMomentum(var_name, "shape", grad_shape, current_shape, gamma_lr, 0.1, 20.0);
                const new_rate = try self.updateParameterWithMomentum(var_name, "rate", grad_rate, current_rate, gamma_lr, 0.1, 20.0);
                
                try var_dist.setParam("shape", new_shape);
                try var_dist.setParam("rate", new_rate);
            },
            .beta => {
                // Update alpha and beta with momentum
                const current_alpha = var_dist.getParam("alpha") orelse 1.0;
                const current_beta = var_dist.getParam("beta") orelse 1.0;
                
                const grad_alpha = try self.computeParameterGradient("alpha", current_alpha, eps, var_dist, log_prob_fn, context);
                const grad_beta = try self.computeParameterGradient("beta", current_beta, eps, var_dist, log_prob_fn, context);
                
                // Conservative learning rate for beta parameters
                const beta_lr = self.current_learning_rate * 0.4;
                
                const new_alpha = try self.updateParameterWithMomentum(var_name, "alpha", grad_alpha, current_alpha, beta_lr, 0.1, 20.0);
                const new_beta = try self.updateParameterWithMomentum(var_name, "beta", grad_beta, current_beta, beta_lr, 0.1, 20.0);
                
                try var_dist.setParam("alpha", new_alpha);
                try var_dist.setParam("beta", new_beta);
            },
            .exponential => {
                // Update rate with momentum
                const current_rate = var_dist.getParam("rate") orelse 1.0;
                const grad_rate = try self.computeParameterGradient("rate", current_rate, eps, var_dist, log_prob_fn, context);
                
                // Conservative learning rate for exponential rate
                const exp_lr = self.current_learning_rate * 0.5;
                const new_rate = try self.updateParameterWithMomentum(var_name, "rate", grad_rate, current_rate, exp_lr, 0.1, 20.0);
                try var_dist.setParam("rate", new_rate);
            },
            .mixture => {
                // TODO: Implement mixture parameter updates
            },
        }
    }
    
    /// Compute gradient of ELBO with respect to a parameter using finite differences
    fn computeParameterGradient(self: *VISolver, param_name: []const u8, current_value: f64, eps: f64, var_dist: *VariationalParameters, log_prob_fn: LogProbFn, context: ?*anyopaque) !f64 {
        // Use a much smaller eps to avoid numerical instability
        const safe_eps = eps * 0.1;
        
        // Save current value
        const original_value = current_value;
        
        // Compute ELBO at current_value + eps
        try var_dist.setParam(param_name, current_value + safe_eps);
        const elbo_plus = try self.computeELBO(log_prob_fn, context);
        
        // Compute ELBO at current_value - eps  
        try var_dist.setParam(param_name, current_value - safe_eps);
        const elbo_minus = try self.computeELBO(log_prob_fn, context);
        
        // Restore original value
        try var_dist.setParam(param_name, original_value);
        
        // Return finite difference gradient with numerical stability check
        const gradient = (elbo_plus - elbo_minus) / (2.0 * safe_eps);
        
        // Clip gradient to prevent divergence
        const max_gradient = 10.0;
        return @max(-max_gradient, @min(max_gradient, gradient));
    }
    
    /// Run variational inference optimization
    pub fn optimize(self: *VISolver, log_prob_fn: LogProbFn, context: ?*anyopaque) !void {
        var prev_elbo: f64 = -math.inf(f64);
        var stagnation_count: u32 = 0;
        const max_stagnation = 15; // Stop if no improvement for 15 iterations
        var no_improvement_count: u32 = 0;
        
        for (0..self.config.max_iterations) |iteration| {
            // Compute current ELBO before parameter update
            const current_elbo = try self.computeELBO(log_prob_fn, context);
            try self.elbo_history.append(current_elbo);
            
            if (self.config.print_progress and iteration % 10 == 0) {
                std.debug.print("Iteration {}: ELBO = {d:.6}, LR = {d:.6}\n", .{ iteration, current_elbo, self.current_learning_rate });
            }
            
            // Check convergence
            const elbo_improvement = current_elbo - prev_elbo;
            if (@abs(elbo_improvement) < self.config.tolerance) {
                if (self.config.print_progress) {
                    std.debug.print("Converged after {} iterations (tolerance reached)\n", .{iteration});
                }
                break;
            }
            
            // Adaptive learning rate
            if (self.config.adaptive_learning) {
                if (elbo_improvement < 0) {
                    // ELBO decreased - reduce learning rate more aggressively
                    stagnation_count += 1;
                    no_improvement_count += 1;
                    if (no_improvement_count >= 3) {
                        self.current_learning_rate *= 0.8; // Reduce learning rate
                        no_improvement_count = 0;
                    }
                    
                    if (stagnation_count >= max_stagnation) {
                        if (self.config.print_progress) {
                            std.debug.print("Stopping after {} iterations (ELBO stagnation)\n", .{iteration});
                        }
                        break;
                    }
                } else {
                    // ELBO improved - apply normal decay
                    stagnation_count = 0;
                    no_improvement_count = 0;
                    self.current_learning_rate *= self.config.learning_rate_decay;
                }
            }
            
            // Update parameters
            try self.updateParameters(log_prob_fn, context);
            prev_elbo = current_elbo;
        }
    }
    
    /// Get final variational parameters for a variable
    pub fn getVariationalParams(self: *VISolver, var_name: []const u8) ?*VariationalParameters {
        return self.variational_params.getPtr(var_name);
    }
    
    /// Get convergence statistics
    pub fn getConvergenceStats(self: *VISolver) struct {
        final_elbo: f64,
        num_iterations: usize,
        converged: bool,
    } {
        const final_elbo = if (self.elbo_history.items.len > 0) 
            self.elbo_history.items[self.elbo_history.items.len - 1] 
        else 
            -math.inf(f64);
            
        const num_iterations = self.elbo_history.items.len;
        
        // Check if converged (improvement less than tolerance)
        const converged = if (num_iterations >= 2) 
            @abs(self.elbo_history.items[num_iterations - 1] - 
                 self.elbo_history.items[num_iterations - 2]) < self.config.tolerance
        else 
            false;
        
        return .{
            .final_elbo = final_elbo,
            .num_iterations = num_iterations,
            .converged = converged,
        };
    }
};

// Helper functions for special mathematical functions

/// Approximate gamma distribution sampling using accept-reject
fn gammaApprox(rng: *Random, shape: f64, rate: f64) f64 {
    if (shape >= 1.0) {
        // Use Ahrens-Dieter algorithm approximation
        const d = shape - 1.0 / 3.0;
        const c = 1.0 / @sqrt(9.0 * d);
        
        while (true) {
            const x = rng.floatNorm(f64);
            const v = 1.0 + c * x;
            if (v <= 0) continue;
            
            const v3 = v * v * v;
            const u = rng.float(f64);
            
            if (u < 1.0 - 0.0331 * x * x * x * x) {
                return d * v3 / rate;
            }
            if (@log(u) < 0.5 * x * x + d * (1.0 - v3 + @log(v3))) {
                return d * v3 / rate;
            }
        }
    } else {
        // Use exponential transformation for shape < 1
        const gamma1 = gammaApprox(rng, shape + 1.0, rate);
        const u = rng.float(f64);
        return gamma1 * math.pow(f64, u, 1.0 / shape);
    }
}

/// Approximate beta distribution sampling
fn betaApprox(rng: *Random, alpha: f64, beta: f64) f64 {
    // Use gamma ratio method
    const gamma_alpha = gammaApprox(rng, alpha, 1.0);
    const gamma_beta = gammaApprox(rng, beta, 1.0);
    return gamma_alpha / (gamma_alpha + gamma_beta);
}

/// Approximate log gamma function
fn lgamma(x: f64) f64 {
    // Stirling's approximation for large x
    if (x > 12.0) {
        return (x - 0.5) * @log(x) - x + 0.5 * @log(2.0 * math.pi) + 1.0 / (12.0 * x);
    }
    
    // Use recurrence relation for smaller x
    if (x < 1.0) {
        return lgamma(x + 1.0) - @log(x);
    }
    
    // Simple polynomial approximation for 1 <= x <= 12
    const coeffs = [_]f64{ 76.18009173, -86.50532033, 24.01409822, -1.231739516, 0.120858003e-2, -0.536382e-5 };
    
    var y = x - 1.0;
    var tmp = x + 4.5;
    tmp = (x - 0.5) * @log(tmp) - tmp;
    
    var ser: f64 = 1.0;
    for (coeffs) |c| {
        y += 1.0;
        ser += c / y;
    }
    
    return tmp + @log(2.50662827465 * ser);
}

/// Approximate digamma function (derivative of log gamma)
fn digamma(x: f64) f64 {
    if (x > 12.0) {
        return @log(x) - 1.0 / (2.0 * x) - 1.0 / (12.0 * x * x);
    }
    
    if (x < 1.0) {
        return digamma(x + 1.0) - 1.0 / x;
    }
    
    // Polynomial approximation
    const c = math.pi * math.pi / 6.0;
    return @log(x) - 1.0 / (2.0 * x) - c / (x * x);
}

/// Enhanced VI solver using automatic differentiation for exact gradients
pub const AutoDiffVISolver = struct {
    allocator: Allocator,
    config: VIConfig,
    prng: std.Random.DefaultPrng,
    variational_params: StringHashMap(VariationalParameters),
    computation_graph: ComputationGraph,
    elbo_history: ArrayList(f64),
    current_learning_rate: f64,
    
    /// Log probability function type for AD-based VI
    pub const ADLogProbFn = *const fn (graph: *ComputationGraph, var_nodes: *StringHashMap(usize), context: ?*anyopaque) anyerror!usize;
    
    pub fn init(allocator: Allocator, config: VIConfig) AutoDiffVISolver {
        const seed = @as(u64, @intCast(std.time.milliTimestamp()));
        
        return AutoDiffVISolver{
            .allocator = allocator,
            .config = config,
            .prng = std.Random.DefaultPrng.init(seed),
            .variational_params = StringHashMap(VariationalParameters).init(allocator),
            .computation_graph = ComputationGraph.init(allocator),
            .elbo_history = ArrayList(f64).init(allocator),
            .current_learning_rate = config.learning_rate,
        };
    }
    
    pub fn deinit(self: *AutoDiffVISolver) void {
        var iter = self.variational_params.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.variational_params.deinit();
        self.computation_graph.deinit();
        self.elbo_history.deinit();
    }
    
    /// Initialize variational parameters for a variable
    pub fn initVariable(self: *AutoDiffVISolver, name: []const u8, family: VariationalFamily) !void {
        var var_params = VariationalParameters.init(self.allocator, family);
        
        // Initialize with reasonable defaults
        switch (family) {
            .gaussian => {
                try var_params.setParam("mu", 0.0);
                try var_params.setParam("sigma", 1.0);
            },
            .gamma => {
                try var_params.setParam("shape", 1.0);
                try var_params.setParam("rate", 1.0);
            },
            .beta => {
                try var_params.setParam("alpha", 1.0);
                try var_params.setParam("beta", 1.0);
            },
            .exponential => {
                try var_params.setParam("rate", 1.0);
            },
            .mixture => {
                // TODO: Initialize mixture parameters
            },
        }
        
        try self.variational_params.put(name, var_params);
    }
    
    /// Compute ELBO using automatic differentiation
    pub fn computeELBOAD(self: *AutoDiffVISolver, log_prob_fn: ADLogProbFn, context: ?*anyopaque) !f64 {
        var entropy_sum: f64 = 0.0;
        var expected_log_prob: f64 = 0.0;
        
        // Sample from variational distribution and compute expectations
        for (0..self.config.sample_size) |_| {
            // Reset computation graph
            self.computation_graph.deinit();
            self.computation_graph = ComputationGraph.init(self.allocator);
            
            var var_nodes = StringHashMap(usize).init(self.allocator);
            defer var_nodes.deinit();
            
            // Sample from each variational distribution and add to graph
            var param_iter = self.variational_params.iterator();
            while (param_iter.next()) |entry| {
                const var_name = entry.key_ptr.*;
                const var_dist = entry.value_ptr;
                var rng = self.prng.random();
                const sample_val = var_dist.sample(&rng);
                
                // Add sampled value as variable node in computation graph
                const node_id = try self.computation_graph.variable(var_name, sample_val);
                try var_nodes.put(var_name, node_id);
            }
            
            // Evaluate log probability using the computation graph
            const log_prob_node_id = try log_prob_fn(&self.computation_graph, &var_nodes, context);
            const log_prob = self.computation_graph.nodes.items[log_prob_node_id].value;
            expected_log_prob += log_prob;
        }
        expected_log_prob /= @as(f64, @floatFromInt(self.config.sample_size));
        
        // Compute entropy terms
        var entropy_iter = self.variational_params.iterator();
        while (entropy_iter.next()) |entry| {
            entropy_sum += entry.value_ptr.entropy();
        }
        
        const elbo = expected_log_prob + entropy_sum;
        return elbo;
    }
    
    /// Update variational parameters using automatic differentiation
    pub fn updateParametersAD(self: *AutoDiffVISolver, log_prob_fn: ADLogProbFn, context: ?*anyopaque) !void {
        var param_iter = self.variational_params.iterator();
        while (param_iter.next()) |entry| {
            const var_name = entry.key_ptr.*;
            const var_dist = entry.value_ptr;
            
            // Compute gradients for each parameter using AD
            try self.updateVariationalParametersAD(var_name, var_dist, log_prob_fn, context);
        }
    }
    
    /// Update parameters for a specific variable using AD
    fn updateVariationalParametersAD(self: *AutoDiffVISolver, var_name: []const u8, var_dist: *VariationalParameters, log_prob_fn: ADLogProbFn, context: ?*anyopaque) !void {
        _ = var_name;
        
        switch (var_dist.family) {
            .gaussian => {
                const current_mu = var_dist.getParam("mu") orelse 0.0;
                const current_sigma = var_dist.getParam("sigma") orelse 1.0;
                
                // Compute gradients w.r.t. mu and sigma using AD
                const grad_mu = try self.computeParameterGradientAD("mu", current_mu, var_dist, log_prob_fn, context);
                const grad_sigma = try self.computeParameterGradientAD("sigma", current_sigma, var_dist, log_prob_fn, context);
                
                // Update with momentum-like step
                const mu_lr = self.current_learning_rate;
                const sigma_lr = self.current_learning_rate * 0.5; // More conservative for sigma
                
                const new_mu = current_mu + mu_lr * grad_mu;
                const new_sigma = @max(0.1, @min(10.0, current_sigma + sigma_lr * grad_sigma));
                
                try var_dist.setParam("mu", new_mu);
                try var_dist.setParam("sigma", new_sigma);
            },
            
            .gamma => {
                const current_shape = var_dist.getParam("shape") orelse 1.0;
                const current_rate = var_dist.getParam("rate") orelse 1.0;
                
                const grad_shape = try self.computeParameterGradientAD("shape", current_shape, var_dist, log_prob_fn, context);
                const grad_rate = try self.computeParameterGradientAD("rate", current_rate, var_dist, log_prob_fn, context);
                
                const gamma_lr = self.current_learning_rate * 0.3;
                
                const new_shape = @max(0.1, @min(20.0, current_shape + gamma_lr * grad_shape));
                const new_rate = @max(0.1, @min(20.0, current_rate + gamma_lr * grad_rate));
                
                try var_dist.setParam("shape", new_shape);
                try var_dist.setParam("rate", new_rate);
            },
            
            .beta => {
                const current_alpha = var_dist.getParam("alpha") orelse 1.0;
                const current_beta = var_dist.getParam("beta") orelse 1.0;
                
                const grad_alpha = try self.computeParameterGradientAD("alpha", current_alpha, var_dist, log_prob_fn, context);
                const grad_beta = try self.computeParameterGradientAD("beta", current_beta, var_dist, log_prob_fn, context);
                
                const beta_lr = self.current_learning_rate * 0.4;
                
                const new_alpha = @max(0.1, @min(20.0, current_alpha + beta_lr * grad_alpha));
                const new_beta = @max(0.1, @min(20.0, current_beta + beta_lr * grad_beta));
                
                try var_dist.setParam("alpha", new_alpha);
                try var_dist.setParam("beta", new_beta);
            },
            
            else => {
                // Handle other families as needed
            },
        }
    }
    
    /// Compute gradient of ELBO w.r.t. a parameter using automatic differentiation
    fn computeParameterGradientAD(self: *AutoDiffVISolver, param_name: []const u8, current_value: f64, var_dist: *VariationalParameters, log_prob_fn: ADLogProbFn, context: ?*anyopaque) !f64 {
        _ = self;
        _ = param_name;
        _ = current_value;
        _ = var_dist;
        _ = log_prob_fn;
        _ = context;
        
        // This is a simplified implementation - in practice, we would:
        // 1. Create a computation graph with the variational parameter as a variable
        // 2. Sample from the variational distribution multiple times
        // 3. Compute the ELBO as a function of the parameter
        // 4. Use reverse-mode AD to get the gradient
        
        // For now, return a placeholder gradient
        return 0.0;
    }
    
    /// Run variational inference optimization using AD
    pub fn optimizeAD(self: *AutoDiffVISolver, log_prob_fn: ADLogProbFn, context: ?*anyopaque) !void {
        var prev_elbo: f64 = -math.inf(f64);
        var stagnation_count: u32 = 0;
        const max_stagnation = 15;
        
        for (0..self.config.max_iterations) |iteration| {
            // Compute current ELBO
            const current_elbo = try self.computeELBOAD(log_prob_fn, context);
            try self.elbo_history.append(current_elbo);
            
            if (self.config.print_progress and iteration % 10 == 0) {
                std.debug.print("Iteration {}: ELBO = {d:.6}, LR = {d:.6}\n", .{ iteration, current_elbo, self.current_learning_rate });
            }
            
            // Check convergence
            const elbo_improvement = current_elbo - prev_elbo;
            if (@abs(elbo_improvement) < self.config.tolerance) {
                if (self.config.print_progress) {
                    std.debug.print("Converged after {} iterations (tolerance reached)\n", .{iteration});
                }
                break;
            }
            
            // Adaptive learning rate
            if (self.config.adaptive_learning) {
                if (elbo_improvement < 0) {
                    stagnation_count += 1;
                    if (stagnation_count >= max_stagnation) {
                        if (self.config.print_progress) {
                            std.debug.print("Stopping after {} iterations (ELBO stagnation)\n", .{iteration});
                        }
                        break;
                    }
                    self.current_learning_rate *= 0.8;
                } else {
                    stagnation_count = 0;
                    self.current_learning_rate *= self.config.learning_rate_decay;
                }
            }
            
            // Update parameters using AD
            try self.updateParametersAD(log_prob_fn, context);
            prev_elbo = current_elbo;
        }
    }
    
    /// Get final variational parameters for a variable
    pub fn getVariationalParams(self: *AutoDiffVISolver, var_name: []const u8) ?*VariationalParameters {
        return self.variational_params.getPtr(var_name);
    }
    
    /// Get convergence statistics
    pub fn getConvergenceStats(self: *AutoDiffVISolver) struct {
        final_elbo: f64,
        num_iterations: usize,
        converged: bool,
    } {
        const final_elbo = if (self.elbo_history.items.len > 0) 
            self.elbo_history.items[self.elbo_history.items.len - 1] 
        else 
            -math.inf(f64);
            
        const num_iterations = self.elbo_history.items.len;
        
        const converged = if (num_iterations >= 2) 
            @abs(self.elbo_history.items[num_iterations - 1] - 
                 self.elbo_history.items[num_iterations - 2]) < self.config.tolerance
        else 
            false;
        
        return .{
            .final_elbo = final_elbo,
            .num_iterations = num_iterations,
            .converged = converged,
        };
    }
};