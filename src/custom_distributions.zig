const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;
const Random = std.Random;

const SirsParser = @import("sirs.zig");
const Type = SirsParser.Type;
const Expression = SirsParser.Expression;
const Statement = SirsParser.Statement;
const Function = SirsParser.Function;

/// Parameter specification for custom distributions
pub const DistributionParameter = struct {
    name: []const u8,
    param_type: Type,
    constraints: ?ParameterConstraints,
    default_value: ?Expression,
    description: ?[]const u8,
    
    pub fn deinit(self: *DistributionParameter, allocator: Allocator) void {
        allocator.free(self.name);
        if (self.constraints) |*constraints| {
            constraints.deinit(allocator);
        }
        if (self.description) |desc| {
            allocator.free(desc);
        }
        // Free any allocated Type pointers in param_type
        freeTypeRecursive(self.param_type, allocator);
    }
    
    /// Recursively free Type pointers (only handle simple cases for now)
    fn freeTypeRecursive(t: Type, allocator: Allocator) void {
        switch (t) {
            .array => |arr| {
                // Only free if the element is a simple type we allocated
                switch (arr.element.*) {
                    .f64, .f32, .i64, .i32, .u64, .u32, .str, .bool => {
                        allocator.destroy(arr.element);
                    },
                    else => {
                        // Recursively free more complex types
                        freeTypeRecursive(arr.element.*, allocator);
                        allocator.destroy(arr.element);
                    }
                }
            },
            .slice => |slice| {
                // Only free if the element is a simple type we allocated
                switch (slice.element.*) {
                    .f64, .f32, .i64, .i32, .u64, .u32, .str, .bool => {
                        allocator.destroy(slice.element);
                    },
                    else => {
                        freeTypeRecursive(slice.element.*, allocator);
                        allocator.destroy(slice.element);
                    }
                }
            },
            .optional => |opt| {
                freeTypeRecursive(opt.*, allocator);
                allocator.destroy(opt);
            },
            // For now, skip complex types that might have ownership issues
            else => {},
        }
    }
};

/// Constraints for distribution parameters
pub const ParameterConstraints = struct {
    min_value: ?f64,
    max_value: ?f64,
    positive_only: bool,
    integer_only: bool,
    vector_constraints: ?VectorConstraints,
    custom_validator: ?[]const u8, // Function name for custom validation
    
    pub const VectorConstraints = struct {
        min_length: ?usize,
        max_length: ?usize,
        element_constraints: ?*ParameterConstraints,
    };
    
    pub fn deinit(self: *ParameterConstraints, allocator: Allocator) void {
        if (self.vector_constraints) |*vec_constraints| {
            if (vec_constraints.element_constraints) |elem_constraints| {
                elem_constraints.deinit(allocator);
                allocator.destroy(elem_constraints);
            }
        }
        if (self.custom_validator) |validator| {
            allocator.free(validator);
        }
    }
};

/// Transformation function for distribution parameters
pub const ParameterTransform = struct {
    transform_type: TransformType,
    source_param: []const u8,
    target_param: []const u8,
    transform_function: ?[]const u8, // Custom transformation function
    inverse_function: ?[]const u8,   // Inverse transformation function
    jacobian_function: ?[]const u8,  // Jacobian for change of variables
    
    pub const TransformType = enum {
        log,           // log transformation
        exp,           // exponential transformation
        logit,         // logit transformation (0,1) -> (-∞,∞)
        sigmoid,       // sigmoid transformation (-∞,∞) -> (0,1)
        softmax,       // softmax transformation for probability vectors
        cholesky,      // Cholesky decomposition for covariance matrices
        custom,        // User-defined transformation
    };
    
    pub fn deinit(self: *ParameterTransform, allocator: Allocator) void {
        allocator.free(self.source_param);
        allocator.free(self.target_param);
        if (self.transform_function) |func| {
            allocator.free(func);
        }
        if (self.inverse_function) |func| {
            allocator.free(func);
        }
        if (self.jacobian_function) |func| {
            allocator.free(func);
        }
    }
};

/// Support information for a distribution
pub const DistributionSupport = struct {
    support_type: SupportType,
    lower_bound: ?Expression,
    upper_bound: ?Expression,
    discrete_values: ?ArrayList(Expression),
    
    pub const SupportType = enum {
        real_line,        // (-∞, ∞)
        positive_real,    // (0, ∞)
        unit_interval,    // [0, 1]
        positive_integer, // {1, 2, 3, ...}
        non_negative_integer, // {0, 1, 2, ...}
        bounded_interval, // [a, b]
        discrete_set,     // {x₁, x₂, ..., xₙ}
        simplex,          // Probability simplex
        positive_definite_matrix, // Positive definite matrices
    };
    
    pub fn deinit(self: *DistributionSupport, allocator: Allocator) void {
        _ = allocator;
        if (self.discrete_values) |*values| {
            values.deinit();
        }
    }
};

/// Sufficient statistics for exponential family distributions
pub const SufficientStatistics = struct {
    statistics: ArrayList(StatisticFunction),
    natural_parameters: ArrayList([]const u8), // Parameter names
    log_partition_function: ?[]const u8,       // Function name
    
    pub const StatisticFunction = struct {
        name: []const u8,
        function_body: []const u8,
        description: ?[]const u8,
        
        pub fn deinit(self: *StatisticFunction, allocator: Allocator) void {
            allocator.free(self.name);
            allocator.free(self.function_body);
            if (self.description) |desc| {
                allocator.free(desc);
            }
        }
    };
    
    pub fn deinit(self: *SufficientStatistics, allocator: Allocator) void {
        for (self.statistics.items) |*stat| {
            stat.deinit(allocator);
        }
        self.statistics.deinit();
        
        for (self.natural_parameters.items) |param| {
            allocator.free(param);
        }
        self.natural_parameters.deinit();
        
        if (self.log_partition_function) |func| {
            allocator.free(func);
        }
    }
};

/// Custom distribution definition
pub const CustomDistribution = struct {
    name: []const u8,
    parameters: ArrayList(DistributionParameter),
    support: DistributionSupport,
    log_prob_function: []const u8,      // Function name for log probability
    sample_function: ?[]const u8,       // Function name for sampling
    moment_functions: StringHashMap([]const u8), // Moment name -> function name
    parameter_transforms: ArrayList(ParameterTransform),
    sufficient_statistics: ?SufficientStatistics,
    conjugate_priors: StringHashMap([]const u8), // Parameter -> prior distribution
    is_exponential_family: bool,
    is_location_scale: bool,
    is_discrete: bool,
    description: ?[]const u8,
    examples: ArrayList(DistributionExample),
    
    pub const DistributionExample = struct {
        name: []const u8,
        parameters: StringHashMap(Expression),
        description: []const u8,
        
        pub fn deinit(self: *DistributionExample, allocator: Allocator) void {
            allocator.free(self.name);
            allocator.free(self.description);
            
            // Free the keys that were allocated with dupe()
            var param_iter = self.parameters.iterator();
            while (param_iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            self.parameters.deinit();
        }
    };
    
    pub fn init(allocator: Allocator, name: []const u8) CustomDistribution {
        return CustomDistribution{
            .name = name,
            .parameters = ArrayList(DistributionParameter).init(allocator),
            .support = DistributionSupport{
                .support_type = .real_line,
                .lower_bound = null,
                .upper_bound = null,
                .discrete_values = null,
            },
            .log_prob_function = "",
            .sample_function = null,
            .moment_functions = StringHashMap([]const u8).init(allocator),
            .parameter_transforms = ArrayList(ParameterTransform).init(allocator),
            .sufficient_statistics = null,
            .conjugate_priors = StringHashMap([]const u8).init(allocator),
            .is_exponential_family = false,
            .is_location_scale = false,
            .is_discrete = false,
            .description = null,
            .examples = ArrayList(DistributionExample).init(allocator),
        };
    }
    
    pub fn deinit(self: *CustomDistribution, allocator: Allocator) void {
        allocator.free(self.name);
        
        for (self.parameters.items) |*param| {
            param.deinit(allocator);
        }
        self.parameters.deinit();
        
        self.support.deinit(allocator);
        
        allocator.free(self.log_prob_function);
        if (self.sample_function) |func| {
            allocator.free(func);
        }
        
        var moment_iter = self.moment_functions.iterator();
        while (moment_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.moment_functions.deinit();
        
        for (self.parameter_transforms.items) |*transform| {
            transform.deinit(allocator);
        }
        self.parameter_transforms.deinit();
        
        if (self.sufficient_statistics) |*stats| {
            stats.deinit(allocator);
        }
        
        var prior_iter = self.conjugate_priors.iterator();
        while (prior_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.conjugate_priors.deinit();
        
        if (self.description) |desc| {
            allocator.free(desc);
        }
        
        for (self.examples.items) |*example| {
            example.deinit(allocator);
        }
        self.examples.deinit();
    }
};

/// Registry for custom distributions
pub const DistributionRegistry = struct {
    allocator: Allocator,
    distributions: StringHashMap(CustomDistribution),
    built_in_distributions: StringHashMap(BuiltInDistribution),
    
    pub const BuiltInDistribution = struct {
        name: []const u8,
        parameter_names: []const []const u8,
        support_type: DistributionSupport.SupportType,
        is_discrete: bool,
        log_prob_impl: *const fn (params: []const f64, value: f64) f64,
        sample_impl: *const fn (params: []const f64, rng: *Random) f64,
    };
    
    pub fn init(allocator: Allocator) DistributionRegistry {
        var registry = DistributionRegistry{
            .allocator = allocator,
            .distributions = StringHashMap(CustomDistribution).init(allocator),
            .built_in_distributions = StringHashMap(BuiltInDistribution).init(allocator),
        };
        
        // Register built-in distributions
        registry.registerBuiltInDistributions() catch |err| {
            print("Error registering built-in distributions: {}\n", .{err});
        };
        
        return registry;
    }
    
    pub fn deinit(self: *DistributionRegistry) void {
        var dist_iter = self.distributions.iterator();
        while (dist_iter.next()) |entry| {
            // Free the duplicated key
            self.allocator.free(entry.key_ptr.*);
            // Free the distribution value
            entry.value_ptr.deinit(self.allocator);
        }
        self.distributions.deinit();
        
        var builtin_iter = self.built_in_distributions.iterator();
        while (builtin_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.built_in_distributions.deinit();
    }
    
    /// Register a custom distribution
    pub fn registerDistribution(self: *DistributionRegistry, distribution: CustomDistribution) !void {
        const name_copy = try self.allocator.dupe(u8, distribution.name);
        try self.distributions.put(name_copy, distribution);
    }
    
    /// Get a distribution by name
    pub fn getDistribution(self: *DistributionRegistry, name: []const u8) ?*CustomDistribution {
        return self.distributions.getPtr(name);
    }
    
    /// Check if a distribution exists
    pub fn hasDistribution(self: *DistributionRegistry, name: []const u8) bool {
        return self.distributions.contains(name) or self.built_in_distributions.contains(name);
    }
    
    /// Validate distribution parameters
    pub fn validateParameters(self: *DistributionRegistry, dist_name: []const u8, params: StringHashMap(f64)) !bool {
        if (self.getDistribution(dist_name)) |distribution| {
            for (distribution.parameters.items) |param| {
                if (params.get(param.name)) |value| {
                    if (param.constraints) |constraints| {
                        if (!try self.validateParameterValue(value, constraints)) {
                            return false;
                        }
                    }
                } else {
                    // Check if parameter has default value
                    if (param.default_value == null) {
                        print("Missing required parameter: {s}\n", .{param.name});
                        return false;
                    }
                }
            }
            return true;
        }
        return false;
    }
    
    /// Validate a single parameter value against constraints
    fn validateParameterValue(self: *DistributionRegistry, value: f64, constraints: ParameterConstraints) !bool {
        _ = self;
        
        if (constraints.positive_only and value <= 0) {
            return false;
        }
        
        if (constraints.integer_only and value != @floor(value)) {
            return false;
        }
        
        if (constraints.min_value) |min| {
            if (value < min) return false;
        }
        
        if (constraints.max_value) |max| {
            if (value > max) return false;
        }
        
        return true;
    }
    
    /// Generate code for a distribution instance
    pub fn generateDistributionCode(self: *DistributionRegistry, dist_name: []const u8, params: StringHashMap(Expression)) ![]const u8 {
        var code = ArrayList(u8).init(self.allocator);
        defer code.deinit();
        
        const writer = code.writer();
        
        if (self.getDistribution(dist_name)) |distribution| {
            try writer.print("// Custom distribution: {s}\n", .{distribution.name});
            
            if (distribution.description) |desc| {
                try writer.print("// Description: {s}\n", .{desc});
            }
            
            try writer.print("const {s}_dist = Distribution.{{\n", .{dist_name});
            try writer.print("    .name = \"{s}\",\n", .{distribution.name});
            try writer.print("    .parameters = .{{\n");
            
            var param_iter = params.iterator();
            while (param_iter.next()) |entry| {
                try writer.print("        .{s} = ", .{entry.key_ptr.*});
                try self.generateExpressionCode(writer, entry.value_ptr.*);
                try writer.print(",\n");
            }
            
            try writer.print("    }},\n");
            try writer.print("    .log_prob = {s},\n", .{distribution.log_prob_function});
            
            if (distribution.sample_function) |sample_func| {
                try writer.print("    .sample = {s},\n", .{sample_func});
            }
            
            try writer.print("}};\n");
        }
        
        return try self.allocator.dupe(u8, code.items);
    }
    
    /// Generate expression code
    fn generateExpressionCode(self: *DistributionRegistry, writer: anytype, expr: Expression) !void {
        
        switch (expr) {
            .literal => |literal| {
                switch (literal) {
                    .integer => |i| try writer.print("{d}", .{i}),
                    .float => |f| try writer.print("{d}", .{f}),
                    .boolean => |b| try writer.print("{}", .{b}),
                    .string => |s| try writer.print("\"{s}\"", .{s}),
                    .null => try writer.print("null"),
                }
            },
            .variable => |var_name| {
                try writer.print("{s}", .{var_name});
            },
            .call => |call| {
                try writer.print("{s}(", .{call.function});
                for (call.args.items, 0..) |arg, i| {
                    if (i > 0) try writer.print(", ");
                    try self.generateExpressionCode(writer, arg);
                }
                try writer.print(")");
            },
            else => try writer.print("/* complex expression */"),
        }
    }
    
    /// Register built-in distributions
    fn registerBuiltInDistributions(self: *DistributionRegistry) !void {
        // Normal distribution
        try self.built_in_distributions.put(try self.allocator.dupe(u8, "Normal"), BuiltInDistribution{
            .name = "Normal",
            .parameter_names = &[_][]const u8{ "mu", "sigma" },
            .support_type = .real_line,
            .is_discrete = false,
            .log_prob_impl = normalLogProb,
            .sample_impl = normalSample,
        });
        
        // Bernoulli distribution
        try self.built_in_distributions.put(try self.allocator.dupe(u8, "Bernoulli"), BuiltInDistribution{
            .name = "Bernoulli",
            .parameter_names = &[_][]const u8{"p"},
            .support_type = .discrete_set,
            .is_discrete = true,
            .log_prob_impl = bernoulliLogProb,
            .sample_impl = bernoulliSample,
        });
        
        // Exponential distribution
        try self.built_in_distributions.put(try self.allocator.dupe(u8, "Exponential"), BuiltInDistribution{
            .name = "Exponential",
            .parameter_names = &[_][]const u8{"rate"},
            .support_type = .positive_real,
            .is_discrete = false,
            .log_prob_impl = exponentialLogProb,
            .sample_impl = exponentialSample,
        });
    }
    
    /// Create examples of common custom distributions
    pub fn createExampleDistributions(self: *DistributionRegistry) !void {
        // Beta-Binomial distribution
        try self.createBetaBinomialDistribution();
        
        // Mixture of Gaussians
        try self.createGaussianMixtureDistribution();
        
        // Student's t-distribution
        try self.createStudentTDistribution();
        
        // Dirichlet distribution
        try self.createDirichletDistribution();
    }
    
    /// Create Beta-Binomial distribution
    fn createBetaBinomialDistribution(self: *DistributionRegistry) !void {
        var distribution = CustomDistribution.init(self.allocator, try self.allocator.dupe(u8, "BetaBinomial"));
        
        // Parameters
        try distribution.parameters.append(DistributionParameter{
            .name = try self.allocator.dupe(u8, "n"),
            .param_type = .i32,
            .constraints = ParameterConstraints{
                .min_value = 1,
                .max_value = null,
                .positive_only = true,
                .integer_only = true,
                .vector_constraints = null,
                .custom_validator = null,
            },
            .default_value = null,
            .description = try self.allocator.dupe(u8, "Number of trials"),
        });
        
        try distribution.parameters.append(DistributionParameter{
            .name = try self.allocator.dupe(u8, "alpha"),
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
            .description = try self.allocator.dupe(u8, "Beta distribution alpha parameter"),
        });
        
        try distribution.parameters.append(DistributionParameter{
            .name = try self.allocator.dupe(u8, "beta"),
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
            .description = try self.allocator.dupe(u8, "Beta distribution beta parameter"),
        });
        
        // Support
        distribution.support = DistributionSupport{
            .support_type = .non_negative_integer,
            .lower_bound = null,
            .upper_bound = null,
            .discrete_values = null,
        };
        
        // Functions
        distribution.log_prob_function = try self.allocator.dupe(u8, "betaBinomialLogProb");
        distribution.sample_function = try self.allocator.dupe(u8, "betaBinomialSample");
        
        // Moments
        try distribution.moment_functions.put(try self.allocator.dupe(u8, "mean"), try self.allocator.dupe(u8, "betaBinomialMean"));
        try distribution.moment_functions.put(try self.allocator.dupe(u8, "variance"), try self.allocator.dupe(u8, "betaBinomialVariance"));
        
        distribution.is_discrete = true;
        distribution.description = try self.allocator.dupe(u8, "Beta-Binomial distribution for overdispersed count data");
        
        // Example
        var example = CustomDistribution.DistributionExample{
            .name = try self.allocator.dupe(u8, "Coin flipping with uncertainty"),
            .parameters = StringHashMap(Expression).init(self.allocator),
            .description = try self.allocator.dupe(u8, "Modeling coin flips where the bias is uncertain"),
        };
        
        try example.parameters.put(try self.allocator.dupe(u8, "n"), Expression{ .literal = .{ .integer = 10 } });
        try example.parameters.put(try self.allocator.dupe(u8, "alpha"), Expression{ .literal = .{ .float = 2.0 } });
        try example.parameters.put(try self.allocator.dupe(u8, "beta"), Expression{ .literal = .{ .float = 2.0 } });
        
        try distribution.examples.append(example);
        
        try self.registerDistribution(distribution);
    }
    
    /// Create Gaussian Mixture distribution
    fn createGaussianMixtureDistribution(self: *DistributionRegistry) !void {
        var distribution = CustomDistribution.init(self.allocator, try self.allocator.dupe(u8, "GaussianMixture"));
        
        // Parameters
        const f64_type = try self.allocator.create(Type);
        f64_type.* = Type.f64;
        
        try distribution.parameters.append(DistributionParameter{
            .name = try self.allocator.dupe(u8, "weights"),
            .param_type = Type{ .array = .{ .element = f64_type, .size = 0 } }, // Dynamic array
            .constraints = ParameterConstraints{
                .min_value = 0,
                .max_value = 1,
                .positive_only = false,
                .integer_only = false,
                .vector_constraints = ParameterConstraints.VectorConstraints{
                    .min_length = 2,
                    .max_length = null,
                    .element_constraints = null,
                },
                .custom_validator = try self.allocator.dupe(u8, "validateSimplex"),
            },
            .default_value = null,
            .description = try self.allocator.dupe(u8, "Mixture weights (must sum to 1)"),
        });
        
        const f64_type_2 = try self.allocator.create(Type);
        f64_type_2.* = Type.f64;
        
        try distribution.parameters.append(DistributionParameter{
            .name = try self.allocator.dupe(u8, "means"),
            .param_type = Type{ .array = .{ .element = f64_type_2, .size = 0 } },
            .constraints = null,
            .default_value = null,
            .description = try self.allocator.dupe(u8, "Component means"),
        });
        
        const f64_type_3 = try self.allocator.create(Type);
        f64_type_3.* = Type.f64;
        
        try distribution.parameters.append(DistributionParameter{
            .name = try self.allocator.dupe(u8, "variances"),
            .param_type = Type{ .array = .{ .element = f64_type_3, .size = 0 } },
            .constraints = ParameterConstraints{
                .min_value = 0,
                .max_value = null,
                .positive_only = true,
                .integer_only = false,
                .vector_constraints = null,
                .custom_validator = null,
            },
            .default_value = null,
            .description = try self.allocator.dupe(u8, "Component variances"),
        });
        
        distribution.support = DistributionSupport{
            .support_type = .real_line,
            .lower_bound = null,
            .upper_bound = null,
            .discrete_values = null,
        };
        
        distribution.log_prob_function = try self.allocator.dupe(u8, "gaussianMixtureLogProb");
        distribution.sample_function = try self.allocator.dupe(u8, "gaussianMixtureSample");
        distribution.description = try self.allocator.dupe(u8, "Mixture of Gaussian distributions");
        
        try self.registerDistribution(distribution);
    }
    
    /// Create Student's t-distribution
    fn createStudentTDistribution(self: *DistributionRegistry) !void {
        var distribution = CustomDistribution.init(self.allocator, try self.allocator.dupe(u8, "StudentT"));
        
        try distribution.parameters.append(DistributionParameter{
            .name = try self.allocator.dupe(u8, "df"),
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
            .description = try self.allocator.dupe(u8, "Degrees of freedom"),
        });
        
        try distribution.parameters.append(DistributionParameter{
            .name = try self.allocator.dupe(u8, "loc"),
            .param_type = .f64,
            .constraints = null,
            .default_value = Expression{ .literal = .{ .float = 0.0 } },
            .description = try self.allocator.dupe(u8, "Location parameter"),
        });
        
        try distribution.parameters.append(DistributionParameter{
            .name = try self.allocator.dupe(u8, "scale"),
            .param_type = .f64,
            .constraints = ParameterConstraints{
                .min_value = 0,
                .max_value = null,
                .positive_only = true,
                .integer_only = false,
                .vector_constraints = null,
                .custom_validator = null,
            },
            .default_value = Expression{ .literal = .{ .float = 1.0 } },
            .description = try self.allocator.dupe(u8, "Scale parameter"),
        });
        
        distribution.support = DistributionSupport{
            .support_type = .real_line,
            .lower_bound = null,
            .upper_bound = null,
            .discrete_values = null,
        };
        
        distribution.log_prob_function = try self.allocator.dupe(u8, "studentTLogProb");
        distribution.sample_function = try self.allocator.dupe(u8, "studentTSample");
        distribution.is_location_scale = true;
        distribution.description = try self.allocator.dupe(u8, "Student's t-distribution with location and scale");
        
        try self.registerDistribution(distribution);
    }
    
    /// Create Dirichlet distribution
    fn createDirichletDistribution(self: *DistributionRegistry) !void {
        var distribution = CustomDistribution.init(self.allocator, try self.allocator.dupe(u8, "Dirichlet"));
        
        const f64_type_4 = try self.allocator.create(Type);
        f64_type_4.* = Type.f64;
        
        try distribution.parameters.append(DistributionParameter{
            .name = try self.allocator.dupe(u8, "alpha"),
            .param_type = Type{ .array = .{ .element = f64_type_4, .size = 0 } },
            .constraints = ParameterConstraints{
                .min_value = 0,
                .max_value = null,
                .positive_only = true,
                .integer_only = false,
                .vector_constraints = ParameterConstraints.VectorConstraints{
                    .min_length = 2,
                    .max_length = null,
                    .element_constraints = null,
                },
                .custom_validator = null,
            },
            .default_value = null,
            .description = try self.allocator.dupe(u8, "Concentration parameters"),
        });
        
        distribution.support = DistributionSupport{
            .support_type = .simplex,
            .lower_bound = null,
            .upper_bound = null,
            .discrete_values = null,
        };
        
        distribution.log_prob_function = try self.allocator.dupe(u8, "dirichletLogProb");
        distribution.sample_function = try self.allocator.dupe(u8, "dirichletSample");
        distribution.description = try self.allocator.dupe(u8, "Dirichlet distribution for probability vectors");
        
        try self.registerDistribution(distribution);
    }
};

// Built-in distribution implementations
pub fn normalLogProb(params: []const f64, value: f64) f64 {
    const mu = params[0];
    const sigma = params[1];
    const diff = value - mu;
    return -0.5 * @log(2.0 * std.math.pi) - @log(sigma) - 0.5 * (diff * diff) / (sigma * sigma);
}

pub fn normalSample(params: []const f64, rng: *Random) f64 {
    const mu = params[0];
    const sigma = params[1];
    const u_1 = rng.float(f64);
    const u_2 = rng.float(f64);
    const z = std.math.sqrt(-2.0 * @log(u_1)) * std.math.cos(2.0 * std.math.pi * u_2);
    return mu + sigma * z;
}

pub fn bernoulliLogProb(params: []const f64, value: f64) f64 {
    const p = params[0];
    if (value == 1.0) {
        return @log(p);
    } else if (value == 0.0) {
        return @log(1.0 - p);
    } else {
        return -std.math.inf(f64);
    }
}

pub fn bernoulliSample(params: []const f64, rng: *Random) f64 {
    const p = params[0];
    return if (rng.float(f64) < p) 1.0 else 0.0;
}

pub fn exponentialLogProb(params: []const f64, value: f64) f64 {
    const rate = params[0];
    if (value >= 0.0) {
        return @log(rate) - rate * value;
    } else {
        return -std.math.inf(f64);
    }
}

fn exponentialSample(params: []const f64, rng: *Random) f64 {
    const rate = params[0];
    return -@log(rng.float(f64)) / rate;
}

/// Distribution builder for fluent API
pub const DistributionBuilder = struct {
    allocator: Allocator,
    distribution: CustomDistribution,
    
    pub fn init(allocator: Allocator, name: []const u8) DistributionBuilder {
        return DistributionBuilder{
            .allocator = allocator,
            .distribution = CustomDistribution.init(allocator, name),
        };
    }
    
    pub fn addParameter(self: *DistributionBuilder, name: []const u8, param_type: Type) *DistributionBuilder {
        const param = DistributionParameter{
            .name = self.allocator.dupe(u8, name) catch return self,
            .param_type = param_type,
            .constraints = null,
            .default_value = null,
            .description = null,
        };
        self.distribution.parameters.append(param) catch return self;
        return self;
    }
    
    pub fn withConstraints(self: *DistributionBuilder, param_name: []const u8, constraints: ParameterConstraints) *DistributionBuilder {
        for (self.distribution.parameters.items) |*param| {
            if (std.mem.eql(u8, param.name, param_name)) {
                param.constraints = constraints;
                break;
            }
        }
        return self;
    }
    
    pub fn withSupport(self: *DistributionBuilder, support: DistributionSupport) *DistributionBuilder {
        self.distribution.support = support;
        return self;
    }
    
    pub fn withLogProb(self: *DistributionBuilder, function_name: []const u8) *DistributionBuilder {
        self.distribution.log_prob_function = self.allocator.dupe(u8, function_name) catch return self;
        return self;
    }
    
    pub fn withSampler(self: *DistributionBuilder, function_name: []const u8) *DistributionBuilder {
        self.distribution.sample_function = self.allocator.dupe(u8, function_name) catch return self;
        return self;
    }
    
    pub fn withDescription(self: *DistributionBuilder, description: []const u8) *DistributionBuilder {
        self.distribution.description = self.allocator.dupe(u8, description) catch return self;
        return self;
    }
    
    pub fn build(self: *DistributionBuilder) CustomDistribution {
        return self.distribution;
    }
};