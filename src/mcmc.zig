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

/// MCMC sampling method
pub const SamplingMethod = enum {
    metropolis_hastings,
    gibbs,
    hamiltonian,
    nuts, // No U-Turn Sampler
    slice,
    adaptive_metropolis,
};

/// Parameter bounds for constrained sampling
pub const ParameterBounds = struct {
    lower: ?f64,
    upper: ?f64,
    
    pub fn contains(self: ParameterBounds, value: f64) bool {
        if (self.lower) |lower| {
            if (value < lower) return false;
        }
        if (self.upper) |upper| {
            if (value > upper) return false;
        }
        return true;
    }
    
    pub fn constrain(self: ParameterBounds, value: f64) f64 {
        var result = value;
        if (self.lower) |lower| {
            result = @max(result, lower);
        }
        if (self.upper) |upper| {
            result = @min(result, upper);
        }
        return result;
    }
};

/// Trace of sampled values for a parameter
pub const ParameterTrace = struct {
    name: []const u8,
    values: ArrayList(f64),
    accepted: ArrayList(bool),
    log_probs: ArrayList(f64),
    
    pub fn init(allocator: Allocator, name: []const u8) ParameterTrace {
        return ParameterTrace{
            .name = name,
            .values = ArrayList(f64).init(allocator),
            .accepted = ArrayList(bool).init(allocator),
            .log_probs = ArrayList(f64).init(allocator),
        };
    }
    
    pub fn deinit(self: *ParameterTrace) void {
        self.values.deinit();
        self.accepted.deinit();
        self.log_probs.deinit();
    }
    
    pub fn append(self: *ParameterTrace, value: f64, accepted: bool, log_prob: f64) !void {
        try self.values.append(value);
        try self.accepted.append(accepted);
        try self.log_probs.append(log_prob);
    }
    
    pub fn getAcceptanceRate(self: *const ParameterTrace) f64 {
        if (self.accepted.items.len == 0) return 0.0;
        
        var accepted_count: f64 = 0;
        for (self.accepted.items) |accepted| {
            if (accepted) accepted_count += 1;
        }
        return accepted_count / @as(f64, @floatFromInt(self.accepted.items.len));
    }
    
    pub fn getMean(self: *const ParameterTrace) f64 {
        if (self.values.items.len == 0) return 0.0;
        
        var sum: f64 = 0;
        for (self.values.items) |value| {
            sum += value;
        }
        return sum / @as(f64, @floatFromInt(self.values.items.len));
    }
    
    pub fn getVariance(self: *const ParameterTrace) f64 {
        if (self.values.items.len < 2) return 0.0;
        
        const mean = self.getMean();
        var sum_sq: f64 = 0;
        for (self.values.items) |value| {
            const diff = value - mean;
            sum_sq += diff * diff;
        }
        return sum_sq / @as(f64, @floatFromInt(self.values.items.len - 1));
    }
    
    /// Get effective sample size using autocorrelation
    pub fn getEffectiveSampleSize(self: *const ParameterTrace) f64 {
        const values = self.values.items;
        
        if (values.len < 10) return @as(f64, @floatFromInt(values.len));
        
        // Compute autocorrelation at different lags
        const mean = self.getMean();
        const variance = self.getVariance();
        
        if (variance == 0) return 1;
        
        var sum_autocorr: f64 = 1.0; // lag 0
        const max_lag = @min(values.len / 4, 100);
        
        var lag: usize = 1;
        while (lag < max_lag) : (lag += 1) {
            var autocorr: f64 = 0;
            for (0..values.len - lag) |i| {
                const dev1 = values[i] - mean;
                const dev2 = values[i + lag] - mean;
                autocorr += dev1 * dev2;
            }
            autocorr /= @as(f64, @floatFromInt(values.len - lag)) * variance;
            
            // Stop when autocorrelation becomes too small
            if (autocorr < 0.1) break;
            
            sum_autocorr += 2 * autocorr;
        }
        
        return @as(f64, @floatFromInt(values.len)) / sum_autocorr;
    }
};

/// MCMC chain state
pub const ChainState = struct {
    parameters: StringHashMap(f64),
    log_prob: f64,
    iteration: usize,
    
    pub fn init(allocator: Allocator) ChainState {
        return ChainState{
            .parameters = StringHashMap(f64).init(allocator),
            .log_prob = -math.inf(f64),
            .iteration = 0,
        };
    }
    
    pub fn deinit(self: *ChainState) void {
        // Note: We don't free the keys here because they're owned by MCMCSampler
        self.parameters.deinit();
    }
    
    pub fn clone(self: *const ChainState, allocator: Allocator) !ChainState {
        var new_state = ChainState.init(allocator);
        
        var iter = self.parameters.iterator();
        while (iter.next()) |entry| {
            try new_state.parameters.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        
        new_state.log_prob = self.log_prob;
        new_state.iteration = self.iteration;
        return new_state;
    }
};

/// MCMC sampler configuration
pub const SamplerConfig = struct {
    method: SamplingMethod,
    num_samples: usize,
    burnin: usize,
    thin: usize,
    step_size: f64,
    target_accept_rate: f64,
    adapt_step_size: bool,
    parallel_chains: usize,
    seed: ?u64,
    
    pub fn default() SamplerConfig {
        return SamplerConfig{
            .method = .metropolis_hastings,
            .num_samples = 1000,
            .burnin = 100,
            .thin = 1,
            .step_size = 0.1,
            .target_accept_rate = 0.234, // Optimal for Metropolis in high dimensions
            .adapt_step_size = true,
            .parallel_chains = 1,
            .seed = null,
        };
    }
};

/// MCMC sampler
pub const MCMCSampler = struct {
    allocator: Allocator,
    config: SamplerConfig,
    prng: std.Random.DefaultPrng,
    parameter_bounds: StringHashMap(ParameterBounds),
    traces: StringHashMap(ParameterTrace),
    current_state: ChainState,
    best_state: ChainState,
    total_iterations: usize,
    accepted_moves: usize,
    
    /// Log probability function type
    pub const LogProbFn = *const fn (params: *const StringHashMap(f64), context: ?*anyopaque) f64;
    
    pub fn init(allocator: Allocator, config: SamplerConfig) MCMCSampler {
        const seed = config.seed orelse @as(u64, @intCast(std.time.milliTimestamp()));
        
        return MCMCSampler{
            .allocator = allocator,
            .config = config,
            .prng = std.Random.DefaultPrng.init(seed),
            .parameter_bounds = StringHashMap(ParameterBounds).init(allocator),
            .traces = StringHashMap(ParameterTrace).init(allocator),
            .current_state = ChainState.init(allocator),
            .best_state = ChainState.init(allocator),
            .total_iterations = 0,
            .accepted_moves = 0,
        };
    }
    
    pub fn deinit(self: *MCMCSampler) void {
        // Free parameter bounds keys
        var bounds_iter = self.parameter_bounds.iterator();
        while (bounds_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.parameter_bounds.deinit();
        
        // Free traces and their keys
        var trace_iter = self.traces.iterator();
        while (trace_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.traces.deinit();
        
        self.current_state.deinit();
        self.best_state.deinit();
    }
    
    /// Set parameter bounds
    pub fn setParameterBounds(self: *MCMCSampler, param_name: []const u8, bounds: ParameterBounds) !void {
        // Copy parameter name since we'll store it
        const param_name_copy = try self.allocator.dupe(u8, param_name);
        try self.parameter_bounds.put(param_name_copy, bounds);
    }
    
    /// Initialize parameter with value
    pub fn initParameter(self: *MCMCSampler, param_name: []const u8, initial_value: f64) !void {
        // Copy parameter name since we'll store it
        const param_name_copy = try self.allocator.dupe(u8, param_name);
        
        try self.current_state.parameters.put(param_name_copy, initial_value);
        
        // Initialize trace
        const trace = ParameterTrace.init(self.allocator, param_name_copy);
        try self.traces.put(param_name_copy, trace);
    }
    
    /// Run MCMC sampling
    pub fn sample(self: *MCMCSampler, log_prob_fn: LogProbFn, context: ?*anyopaque) !void {
        // Evaluate initial log probability
        self.current_state.log_prob = log_prob_fn(&self.current_state.parameters, context);
        self.best_state = try self.current_state.clone(self.allocator);
        
        // Adaptive step size tracking
        var step_size = self.config.step_size;
        const adaptation_window: usize = 50;
        var recent_accepts: usize = 0;
        
        // Main sampling loop
        const total_iterations = self.config.num_samples + self.config.burnin;
        var iteration: usize = 0;
        
        while (iteration < total_iterations) : (iteration += 1) {
            const in_burnin = iteration < self.config.burnin;
            
            // Propose new state
            var proposed_state = try self.proposeState(&self.current_state, step_size);
            defer proposed_state.deinit();
            
            // Evaluate proposal
            proposed_state.log_prob = log_prob_fn(&proposed_state.parameters, context);
            
            // Accept/reject decision
            const log_ratio = proposed_state.log_prob - self.current_state.log_prob;
            const accept = log_ratio > 0 or self.prng.random().float(f64) < @exp(log_ratio);
            
            if (accept) {
                // Update current state
                self.current_state.deinit();
                self.current_state = try proposed_state.clone(self.allocator);
                self.accepted_moves += 1;
                recent_accepts += 1;
                
                // Update best state
                if (self.current_state.log_prob > self.best_state.log_prob) {
                    self.best_state.deinit();
                    self.best_state = try self.current_state.clone(self.allocator);
                }
            }
            
            // Record samples (after burnin and respecting thinning)
            if (!in_burnin and iteration % self.config.thin == 0) {
                var param_iter = self.current_state.parameters.iterator();
                while (param_iter.next()) |entry| {
                    if (self.traces.getPtr(entry.key_ptr.*)) |trace| {
                        try trace.append(entry.value_ptr.*, accept, self.current_state.log_prob);
                    }
                }
            }
            
            // Adapt step size during burnin
            if (in_burnin and self.config.adapt_step_size and iteration % adaptation_window == 0 and iteration > 0) {
                const recent_rate = @as(f64, @floatFromInt(recent_accepts)) / @as(f64, @floatFromInt(adaptation_window));
                
                // Adjust step size based on acceptance rate
                if (recent_rate < self.config.target_accept_rate - 0.05) {
                    step_size *= 0.9;
                } else if (recent_rate > self.config.target_accept_rate + 0.05) {
                    step_size *= 1.1;
                }
                
                recent_accepts = 0;
            }
            
            self.total_iterations += 1;
            self.current_state.iteration = iteration;
        }
    }
    
    /// Propose new state using current sampling method
    fn proposeState(self: *MCMCSampler, current: *const ChainState, step_size: f64) !ChainState {
        var proposed = try current.clone(self.allocator);
        
        switch (self.config.method) {
            .metropolis_hastings => {
                // Random walk Metropolis
                var param_iter = proposed.parameters.iterator();
                while (param_iter.next()) |entry| {
                    const current_value = entry.value_ptr.*;
                    const perturbation = self.prng.random().floatNorm(f64) * step_size;
                    var new_value = current_value + perturbation;
                    
                    // Apply bounds if specified
                    if (self.parameter_bounds.get(entry.key_ptr.*)) |bounds| {
                        new_value = bounds.constrain(new_value);
                    }
                    
                    entry.value_ptr.* = new_value;
                }
            },
            .adaptive_metropolis => {
                // Adaptive Metropolis with covariance estimation
                // For now, use independent proposals
                var param_iter = proposed.parameters.iterator();
                while (param_iter.next()) |entry| {
                    const param_name = entry.key_ptr.*;
                    const current_value = entry.value_ptr.*;
                    
                    // Use trace variance if available
                    var proposal_std = step_size;
                    if (self.traces.get(param_name)) |trace| {
                        if (trace.values.items.len > 10) {
                            const variance = trace.getVariance();
                            if (variance > 0) {
                                proposal_std = @sqrt(variance) * 2.38 / @sqrt(@as(f64, @floatFromInt(proposed.parameters.count())));
                            }
                        }
                    }
                    
                    const perturbation = self.prng.random().floatNorm(f64) * proposal_std;
                    var new_value = current_value + perturbation;
                    
                    // Apply bounds if specified
                    if (self.parameter_bounds.get(param_name)) |bounds| {
                        new_value = bounds.constrain(new_value);
                    }
                    
                    entry.value_ptr.* = new_value;
                }
            },
            else => {
                // TODO: Implement other sampling methods
                return error.NotImplemented;
            },
        }
        
        return proposed;
    }
    
    /// Get acceptance rate
    pub fn getAcceptanceRate(self: *MCMCSampler) f64 {
        if (self.total_iterations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.accepted_moves)) / @as(f64, @floatFromInt(self.total_iterations));
    }
    
    /// Get parameter statistics
    pub fn getParameterStats(self: *MCMCSampler, param_name: []const u8) ?struct {
        mean: f64,
        variance: f64,
        min: f64,
        max: f64,
        acceptance_rate: f64,
    } {
        const trace = self.traces.get(param_name) orelse return null;
        
        if (trace.values.items.len == 0) return null;
        
        var min = trace.values.items[0];
        var max = trace.values.items[0];
        
        for (trace.values.items) |value| {
            min = @min(min, value);
            max = @max(max, value);
        }
        
        return .{
            .mean = trace.getMean(),
            .variance = trace.getVariance(),
            .min = min,
            .max = max,
            .acceptance_rate = trace.getAcceptanceRate(),
        };
    }
    
    /// Get effective sample size using autocorrelation
    pub fn getEffectiveSampleSize(self: *MCMCSampler, param_name: []const u8) f64 {
        const trace = self.traces.get(param_name) orelse return 0;
        const values = trace.values.items;
        
        if (values.len < 10) return @as(f64, @floatFromInt(values.len));
        
        // Compute autocorrelation at different lags
        const mean = trace.getMean();
        const variance = trace.getVariance();
        
        if (variance == 0) return 1;
        
        var sum_autocorr: f64 = 1.0; // lag 0
        const max_lag = @min(values.len / 4, 100);
        
        var lag: usize = 1;
        while (lag < max_lag) : (lag += 1) {
            var autocorr: f64 = 0;
            for (0..values.len - lag) |i| {
                autocorr += (values[i] - mean) * (values[i + lag] - mean);
            }
            autocorr /= @as(f64, @floatFromInt(values.len - lag)) * variance;
            
            // Stop when autocorrelation becomes negligible
            if (@abs(autocorr) < 0.05) break;
            
            sum_autocorr += 2 * autocorr;
        }
        
        // Ensure sum_autocorr is at least 1 to avoid division issues
        const effective_autocorr = @max(sum_autocorr, 1.0);
        return @as(f64, @floatFromInt(values.len)) / effective_autocorr;
    }
    
    /// Export trace to CSV
    pub fn exportTrace(self: *MCMCSampler, writer: anytype) !void {
        // Write header
        try writer.print("iteration", .{});
        
        var param_names = ArrayList([]const u8).init(self.allocator);
        defer param_names.deinit();
        
        var param_iter = self.traces.iterator();
        while (param_iter.next()) |entry| {
            try param_names.append(entry.key_ptr.*);
            try writer.print(",{s}", .{entry.key_ptr.*});
        }
        try writer.print(",log_prob,accepted\n", .{});
        
        // Write data
        if (param_names.items.len > 0) {
            const first_trace = self.traces.get(param_names.items[0]).?;
            for (0..first_trace.values.items.len) |i| {
                try writer.print("{}", .{i});
                
                for (param_names.items) |param_name| {
                    const trace = self.traces.get(param_name).?;
                    try writer.print(",{d:.6}", .{trace.values.items[i]});
                }
                
                try writer.print(",{d:.6},{}\n", .{ 
                    first_trace.log_probs.items[i],
                    first_trace.accepted.items[i] 
                });
            }
        }
    }
};

/// Parallel tempering for better mixing
pub const ParallelTempering = struct {
    allocator: Allocator,
    chains: ArrayList(MCMCSampler),
    temperatures: ArrayList(f64),
    swap_attempts: usize,
    successful_swaps: usize,
    
    pub fn init(allocator: Allocator, num_chains: usize, base_config: SamplerConfig) !ParallelTempering {
        var pt = ParallelTempering{
            .allocator = allocator,
            .chains = ArrayList(MCMCSampler).init(allocator),
            .temperatures = ArrayList(f64).init(allocator),
            .swap_attempts = 0,
            .successful_swaps = 0,
        };
        
        // Initialize chains with different temperatures
        for (0..num_chains) |i| {
            const temp = math.pow(f64, 2.0, @as(f64, @floatFromInt(i)));
            try pt.temperatures.append(temp);
            
            var config = base_config;
            config.seed = if (base_config.seed) |seed| seed + i else null;
            
            const chain = MCMCSampler.init(allocator, config);
            try pt.chains.append(chain);
        }
        
        return pt;
    }
    
    pub fn deinit(self: *ParallelTempering) void {
        for (self.chains.items) |*chain| {
            chain.deinit();
        }
        self.chains.deinit();
        self.temperatures.deinit();
    }
    
    /// Run parallel tempering
    pub fn sample(self: *ParallelTempering, log_prob_fn: MCMCSampler.LogProbFn, context: ?*anyopaque) !void {
        // TODO: Implement parallel tempering with chain swaps
        _ = self;
        _ = log_prob_fn;
        _ = context;
        return error.NotImplemented;
    }
};

/// Convergence diagnostics
pub const ConvergenceDiagnostics = struct {
    /// Gelman-Rubin statistic (R-hat)
    pub fn gelmanRubin(chains: []const *MCMCSampler, param_name: []const u8) !f64 {
        if (chains.len < 2) return error.InsufficientChains;
        
        var chain_means = ArrayList(f64).init(chains[0].allocator);
        defer chain_means.deinit();
        
        var chain_variances = ArrayList(f64).init(chains[0].allocator);
        defer chain_variances.deinit();
        
        var total_samples: usize = 0;
        
        // Calculate per-chain statistics
        for (chains) |chain| {
            const trace = chain.traces.get(param_name) orelse continue;
            if (trace.values.items.len < 2) continue;
            
            try chain_means.append(trace.getMean());
            try chain_variances.append(trace.getVariance());
            total_samples += trace.values.items.len;
        }
        
        if (chain_means.items.len < 2) return error.InsufficientData;
        
        const n = @as(f64, @floatFromInt(total_samples / chains.len));
        const m = @as(f64, @floatFromInt(chain_means.items.len));
        
        // Between-chain variance
        var grand_mean: f64 = 0;
        for (chain_means.items) |mean| {
            grand_mean += mean;
        }
        grand_mean /= m;
        
        var b: f64 = 0;
        for (chain_means.items) |mean| {
            const diff = mean - grand_mean;
            b += diff * diff;
        }
        b *= n / (m - 1);
        
        // Within-chain variance
        var w: f64 = 0;
        for (chain_variances.items) |variance| {
            w += variance;
        }
        w /= m;
        
        // Potential scale reduction factor
        const var_plus = ((n - 1) / n) * w + (1 / n) * b;
        const r_hat = @sqrt(var_plus / w);
        
        return r_hat;
    }
    
    /// Effective sample size across chains
    pub fn multiChainESS(chains: []const *MCMCSampler, param_name: []const u8) f64 {
        var total_ess: f64 = 0;
        
        for (chains) |chain| {
            total_ess += chain.getEffectiveSampleSize(param_name);
        }
        
        return total_ess;
    }
};

/// Hamiltonian Monte Carlo (HMC) implementation using automatic differentiation
pub const HMCSampler = struct {
    allocator: Allocator,
    config: HMCConfig,
    prng: std.Random.DefaultPrng,
    current_state: StringHashMap(f64),
    momentum: StringHashMap(f64),
    traces: StringHashMap(ParameterTrace),
    mass_matrix: StringHashMap(f64), // Diagonal mass matrix
    step_size: f64,
    num_leapfrog_steps: usize,
    accepted_samples: usize,
    total_samples: usize,
    
    /// Log probability function type that supports gradients
    pub const GradientLogProbFn = *const fn (params: *const StringHashMap(f64), gradients: *StringHashMap(f64), context: ?*anyopaque) f64;
    
    pub fn init(allocator: Allocator, config: HMCConfig) HMCSampler {
        const seed = @as(u64, @intCast(std.time.milliTimestamp()));
        
        return HMCSampler{
            .allocator = allocator,
            .config = config,
            .prng = std.Random.DefaultPrng.init(seed),
            .current_state = StringHashMap(f64).init(allocator),
            .momentum = StringHashMap(f64).init(allocator),
            .traces = StringHashMap(ParameterTrace).init(allocator),
            .mass_matrix = StringHashMap(f64).init(allocator),
            .step_size = config.initial_step_size,
            .num_leapfrog_steps = config.num_leapfrog_steps,
            .accepted_samples = 0,
            .total_samples = 0,
        };
    }
    
    pub fn deinit(self: *HMCSampler) void {
        self.current_state.deinit();
        self.momentum.deinit();
        self.mass_matrix.deinit();
        
        var trace_iter = self.traces.iterator();
        while (trace_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.traces.deinit();
    }
    
    /// Initialize parameter
    pub fn initParameter(self: *HMCSampler, name: []const u8, initial_value: f64, mass: f64) !void {
        try self.current_state.put(name, initial_value);
        try self.momentum.put(name, 0.0);
        try self.mass_matrix.put(name, mass);
        
        const trace = ParameterTrace.init(self.allocator, name);
        try self.traces.put(name, trace);
    }
    
    /// Run HMC sampling
    pub fn sample(self: *HMCSampler, log_prob_fn: GradientLogProbFn, context: ?*anyopaque, num_samples: usize) !void {
        for (0..num_samples) |_| {
            try self.hmcStep(log_prob_fn, context);
        }
    }
    
    /// Single HMC step using leapfrog integration
    fn hmcStep(self: *HMCSampler, log_prob_fn: GradientLogProbFn, context: ?*anyopaque) !void {
        // Save current state
        var old_state = StringHashMap(f64).init(self.allocator);
        defer old_state.deinit();
        
        var state_iter = self.current_state.iterator();
        while (state_iter.next()) |entry| {
            try old_state.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        
        // Sample new momentum
        try self.sampleMomentum();
        
        // Save old momentum for energy calculation
        var old_momentum = StringHashMap(f64).init(self.allocator);
        defer old_momentum.deinit();
        
        var momentum_iter = self.momentum.iterator();
        while (momentum_iter.next()) |entry| {
            try old_momentum.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        
        // Compute initial energy
        var initial_gradients = StringHashMap(f64).init(self.allocator);
        defer initial_gradients.deinit();
        
        const initial_potential = log_prob_fn(&self.current_state, &initial_gradients, context);
        const initial_kinetic = self.computeKineticEnergy(&old_momentum);
        const initial_energy = -initial_potential + initial_kinetic;
        
        // Half step for momentum
        try self.leapfrogMomentumStep(&initial_gradients, 0.5 * self.step_size);
        
        // Full steps
        for (0..self.num_leapfrog_steps - 1) |_| {
            // Full position step
            try self.leapfrogPositionStep(self.step_size);
            
            // Compute gradients at new position
            var gradients = StringHashMap(f64).init(self.allocator);
            defer gradients.deinit();
            _ = log_prob_fn(&self.current_state, &gradients, context);
            
            // Full momentum step
            try self.leapfrogMomentumStep(&gradients, self.step_size);
        }
        
        // Final position step
        try self.leapfrogPositionStep(self.step_size);
        
        // Final half momentum step
        var final_gradients = StringHashMap(f64).init(self.allocator);
        defer final_gradients.deinit();
        
        const final_potential = log_prob_fn(&self.current_state, &final_gradients, context);
        try self.leapfrogMomentumStep(&final_gradients, 0.5 * self.step_size);
        
        // Compute final energy
        const final_kinetic = self.computeKineticEnergy(&self.momentum);
        const final_energy = -final_potential + final_kinetic;
        
        // Metropolis acceptance
        const energy_diff = final_energy - initial_energy;
        const accept_prob = @min(1.0, @exp(-energy_diff));
        
        var rng = self.prng.random();
        const accepted = rng.float(f64) < accept_prob;
        
        if (accepted) {
            self.accepted_samples += 1;
            // State is already updated by leapfrog steps
        } else {
            // Restore old state
            var restore_iter = old_state.iterator();
            while (restore_iter.next()) |entry| {
                try self.current_state.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        
        // Record sample
        try self.recordSample(-final_potential, accepted);
        self.total_samples += 1;
        
        // Adapt step size
        if (self.config.adapt_step_size) {
            self.adaptStepSize(accept_prob);
        }
    }
    
    fn sampleMomentum(self: *HMCSampler) !void {
        var rng = self.prng.random();
        
        var momentum_iter = self.momentum.iterator();
        while (momentum_iter.next()) |entry| {
            const param_name = entry.key_ptr.*;
            const mass = self.mass_matrix.get(param_name) orelse 1.0;
            const momentum_val = rng.floatNorm(f64) * @sqrt(mass);
            try self.momentum.put(param_name, momentum_val);
        }
    }
    
    fn computeKineticEnergy(self: *HMCSampler, momentum_map: *const StringHashMap(f64)) f64 {
        var kinetic_energy: f64 = 0.0;
        
        var momentum_iter = momentum_map.iterator();
        while (momentum_iter.next()) |entry| {
            const param_name = entry.key_ptr.*;
            const momentum_val = entry.value_ptr.*;
            const mass = self.mass_matrix.get(param_name) orelse 1.0;
            
            kinetic_energy += 0.5 * momentum_val * momentum_val / mass;
        }
        
        return kinetic_energy;
    }
    
    fn leapfrogPositionStep(self: *HMCSampler, step_size: f64) !void {
        var position_iter = self.current_state.iterator();
        while (position_iter.next()) |entry| {
            const param_name = entry.key_ptr.*;
            const current_pos = entry.value_ptr.*;
            const momentum_val = self.momentum.get(param_name) orelse 0.0;
            const mass = self.mass_matrix.get(param_name) orelse 1.0;
            
            const new_pos = current_pos + step_size * momentum_val / mass;
            try self.current_state.put(param_name, new_pos);
        }
    }
    
    fn leapfrogMomentumStep(self: *HMCSampler, gradients: *const StringHashMap(f64), step_size: f64) !void {
        var momentum_iter = self.momentum.iterator();
        while (momentum_iter.next()) |entry| {
            const param_name = entry.key_ptr.*;
            const current_momentum = entry.value_ptr.*;
            const gradient = gradients.get(param_name) orelse 0.0;
            
            const new_momentum = current_momentum + step_size * gradient;
            try self.momentum.put(param_name, new_momentum);
        }
    }
    
    fn adaptStepSize(self: *HMCSampler, accept_prob: f64) void {
        const target_accept = 0.65; // Target acceptance rate for HMC
        const adaptation_rate = 0.01;
        
        if (accept_prob > target_accept) {
            self.step_size *= (1.0 + adaptation_rate);
        } else {
            self.step_size *= (1.0 - adaptation_rate);
        }
        
        // Keep step size within reasonable bounds
        self.step_size = @max(1e-6, @min(1.0, self.step_size));
    }
    
    fn recordSample(self: *HMCSampler, log_prob: f64, accepted: bool) !void {
        var state_iter = self.current_state.iterator();
        while (state_iter.next()) |entry| {
            const param_name = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            
            var trace = self.traces.getPtr(param_name).?;
            try trace.values.append(value);
            try trace.log_probs.append(log_prob);
            try trace.accepted.append(accepted);
        }
    }
    
    /// Get trace for a parameter
    pub fn getTrace(self: *HMCSampler, param_name: []const u8) ?*ParameterTrace {
        return self.traces.getPtr(param_name);
    }
    
    /// Get acceptance rate
    pub fn getAcceptanceRate(self: *HMCSampler) f64 {
        if (self.total_samples == 0) return 0.0;
        return @as(f64, @floatFromInt(self.accepted_samples)) / @as(f64, @floatFromInt(self.total_samples));
    }
    
    /// Get effective sample size for a parameter
    pub fn getEffectiveSampleSize(self: *HMCSampler, param_name: []const u8) f64 {
        if (self.traces.get(param_name)) |trace| {
            return trace.getEffectiveSampleSize();
        }
        return 0.0;
    }
};

/// Configuration for HMC sampling
pub const HMCConfig = struct {
    initial_step_size: f64,
    num_leapfrog_steps: usize,
    adapt_step_size: bool,
    mass_adaptation: bool,
    adaptation_window: usize,
    
    pub fn default() HMCConfig {
        return HMCConfig{
            .initial_step_size = 0.1,
            .num_leapfrog_steps = 10,
            .adapt_step_size = true,
            .mass_adaptation = false,
            .adaptation_window = 500,
        };
    }
};