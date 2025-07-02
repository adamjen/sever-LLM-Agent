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
const CustomDistribution = @import("custom_distributions.zig").CustomDistribution;
const DistributionRegistry = @import("custom_distributions.zig").DistributionRegistry;

/// Component in a mixture model
pub const MixtureComponent = struct {
    weight: f64,                           // Mixing weight (0 < weight < 1, sum = 1)
    distribution_name: []const u8,         // Name of the component distribution
    parameters: ArrayList(Expression),     // Parameters for this component
    label: ?[]const u8,                   // Optional label for this component
    
    pub fn init(allocator: Allocator, weight: f64, distribution_name: []const u8) MixtureComponent {
        return MixtureComponent{
            .weight = weight,
            .distribution_name = allocator.dupe(u8, distribution_name) catch unreachable,
            .parameters = ArrayList(Expression).init(allocator),
            .label = null,
        };
    }
    
    pub fn deinit(self: *MixtureComponent, allocator: Allocator) void {
        allocator.free(self.distribution_name);
        self.parameters.deinit();
        if (self.label) |label| {
            allocator.free(label);
        }
    }
    
    pub fn addParameter(self: *MixtureComponent, param: Expression) !void {
        try self.parameters.append(param);
    }
    
    pub fn setLabel(self: *MixtureComponent, allocator: Allocator, label: []const u8) !void {
        if (self.label) |old_label| {
            allocator.free(old_label);
        }
        self.label = try allocator.dupe(u8, label);
    }
};

/// Mixture model combining multiple distributions
pub const MixtureModel = struct {
    name: []const u8,
    components: ArrayList(MixtureComponent),
    mixture_type: MixtureType,
    weight_prior: ?WeightPrior,           // Prior distribution for mixture weights
    component_assignment: ?[]const u8,    // Variable name for component assignments
    description: ?[]const u8,
    
    pub const MixtureType = enum {
        finite,           // Fixed number of components
        infinite,         // Infinite mixture (Dirichlet process)
        hierarchical,     // Hierarchical mixture with group structure
    };
    
    pub const WeightPrior = struct {
        distribution: []const u8,         // e.g., "dirichlet", "stick_breaking"
        parameters: ArrayList(Expression),
        
        pub fn deinit(self: *WeightPrior, allocator: Allocator) void {
            allocator.free(self.distribution);
            self.parameters.deinit();
        }
    };
    
    pub fn init(allocator: Allocator, name: []const u8, mixture_type: MixtureType) MixtureModel {
        return MixtureModel{
            .name = allocator.dupe(u8, name) catch unreachable,
            .components = ArrayList(MixtureComponent).init(allocator),
            .mixture_type = mixture_type,
            .weight_prior = null,
            .component_assignment = null,
            .description = null,
        };
    }
    
    pub fn deinit(self: *MixtureModel, allocator: Allocator) void {
        allocator.free(self.name);
        
        for (self.components.items) |*component| {
            component.deinit(allocator);
        }
        self.components.deinit();
        
        if (self.weight_prior) |*prior| {
            prior.deinit(allocator);
        }
        
        if (self.component_assignment) |assignment| {
            allocator.free(assignment);
        }
        
        if (self.description) |desc| {
            allocator.free(desc);
        }
    }
    
    pub fn addComponent(self: *MixtureModel, component: MixtureComponent) !void {
        try self.components.append(component);
    }
    
    pub fn setWeightPrior(self: *MixtureModel, allocator: Allocator, distribution: []const u8, parameters: ArrayList(Expression)) !void {
        if (self.weight_prior) |*prior| {
            prior.deinit(allocator);
        }
        
        self.weight_prior = WeightPrior{
            .distribution = try allocator.dupe(u8, distribution),
            .parameters = parameters,
        };
    }
    
    pub fn normalizeWeights(self: *MixtureModel) void {
        var total_weight: f64 = 0.0;
        for (self.components.items) |component| {
            total_weight += component.weight;
        }
        
        if (total_weight > 0.0) {
            for (self.components.items) |*component| {
                component.weight /= total_weight;
            }
        }
    }
    
    /// Validate that mixture model is well-formed
    pub fn validate(self: *MixtureModel) !void {
        if (self.components.items.len == 0) {
            return error.EmptyMixture;
        }
        
        var total_weight: f64 = 0.0;
        for (self.components.items) |component| {
            if (component.weight <= 0.0) {
                return error.InvalidWeight;
            }
            total_weight += component.weight;
        }
        
        // Check weights sum to approximately 1.0
        if (std.math.fabs(total_weight - 1.0) > 1e-10) {
            return error.WeightsNotNormalized;
        }
    }
};

/// Hierarchical model structure
pub const HierarchicalLevel = struct {
    level_name: []const u8,               // Name of this hierarchical level
    group_variable: []const u8,           // Variable that defines groups at this level
    parameters: StringHashMap(ParameterSpec), // Parameters that vary by group
    hyperpriors: StringHashMap(Expression),   // Hyperprior distributions
    group_size_distribution: ?Expression,     // Distribution for number of groups
    
    pub const ParameterSpec = struct {
        parameter_name: []const u8,
        distribution: []const u8,         // Distribution family for this parameter
        hyperparameters: ArrayList([]const u8), // Names of hyperparameters
        
        pub fn deinit(self: *ParameterSpec, allocator: Allocator) void {
            allocator.free(self.parameter_name);
            allocator.free(self.distribution);
            for (self.hyperparameters.items) |hyperparam| {
                allocator.free(hyperparam);
            }
            self.hyperparameters.deinit();
        }
    };
    
    pub fn init(allocator: Allocator, level_name: []const u8, group_variable: []const u8) HierarchicalLevel {
        return HierarchicalLevel{
            .level_name = allocator.dupe(u8, level_name) catch unreachable,
            .group_variable = allocator.dupe(u8, group_variable) catch unreachable,
            .parameters = StringHashMap(ParameterSpec).init(allocator),
            .hyperpriors = StringHashMap(Expression).init(allocator),
            .group_size_distribution = null,
        };
    }
    
    pub fn deinit(self: *HierarchicalLevel, allocator: Allocator) void {
        allocator.free(self.level_name);
        allocator.free(self.group_variable);
        
        var param_iter = self.parameters.iterator();
        while (param_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.parameters.deinit();
        
        var prior_iter = self.hyperpriors.iterator();
        while (prior_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            // Note: Expression cleanup would need to be handled by caller
        }
        self.hyperpriors.deinit();
    }
    
    pub fn addParameter(self: *HierarchicalLevel, allocator: Allocator, param_name: []const u8, distribution: []const u8, hyperparams: []const []const u8) !void {
        var hyperparam_list = ArrayList([]const u8).init(allocator);
        for (hyperparams) |hyperparam| {
            try hyperparam_list.append(try allocator.dupe(u8, hyperparam));
        }
        
        const param_spec = ParameterSpec{
            .parameter_name = try allocator.dupe(u8, param_name),
            .distribution = try allocator.dupe(u8, distribution),
            .hyperparameters = hyperparam_list,
        };
        
        try self.parameters.put(try allocator.dupe(u8, param_name), param_spec);
    }
    
    pub fn addHyperprior(self: *HierarchicalLevel, allocator: Allocator, hyperparam_name: []const u8, prior: Expression) !void {
        try self.hyperpriors.put(try allocator.dupe(u8, hyperparam_name), prior);
    }
};

/// Complete hierarchical model
pub const HierarchicalModel = struct {
    name: []const u8,
    levels: ArrayList(HierarchicalLevel),
    observation_model: ObservationModel,
    missing_data_model: ?MissingDataModel,
    description: ?[]const u8,
    
    pub const ObservationModel = struct {
        likelihood: []const u8,           // Likelihood distribution
        parameters: ArrayList([]const u8), // Parameter names from hierarchical levels
        link_functions: StringHashMap([]const u8), // Link functions for parameters
        
        pub fn deinit(self: *ObservationModel, allocator: Allocator) void {
            allocator.free(self.likelihood);
            for (self.parameters.items) |param| {
                allocator.free(param);
            }
            self.parameters.deinit();
            
            var link_iter = self.link_functions.iterator();
            while (link_iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            self.link_functions.deinit();
        }
    };
    
    pub const MissingDataModel = struct {
        missing_mechanism: MissingMechanism,
        imputation_model: ?[]const u8,     // Model for imputing missing values
        
        pub const MissingMechanism = enum {
            mcar,     // Missing Completely At Random
            mar,      // Missing At Random
            mnar,     // Missing Not At Random
        };
    };
    
    pub fn init(allocator: Allocator, name: []const u8) HierarchicalModel {
        return HierarchicalModel{
            .name = allocator.dupe(u8, name) catch unreachable,
            .levels = ArrayList(HierarchicalLevel).init(allocator),
            .observation_model = ObservationModel{
                .likelihood = allocator.dupe(u8, "normal") catch unreachable,
                .parameters = ArrayList([]const u8).init(allocator),
                .link_functions = StringHashMap([]const u8).init(allocator),
            },
            .missing_data_model = null,
            .description = null,
        };
    }
    
    pub fn deinit(self: *HierarchicalModel, allocator: Allocator) void {
        allocator.free(self.name);
        
        for (self.levels.items) |*level| {
            level.deinit(allocator);
        }
        self.levels.deinit();
        
        self.observation_model.deinit(allocator);
        
        if (self.description) |desc| {
            allocator.free(desc);
        }
    }
    
    pub fn addLevel(self: *HierarchicalModel, level: HierarchicalLevel) !void {
        try self.levels.append(level);
    }
    
    pub fn setObservationModel(self: *HierarchicalModel, allocator: Allocator, likelihood: []const u8, parameters: []const []const u8) !void {
        self.observation_model.deinit(allocator);
        
        self.observation_model = ObservationModel{
            .likelihood = try allocator.dupe(u8, likelihood),
            .parameters = ArrayList([]const u8).init(allocator),
            .link_functions = StringHashMap([]const u8).init(allocator),
        };
        
        for (parameters) |param| {
            try self.observation_model.parameters.append(try allocator.dupe(u8, param));
        }
    }
    
    /// Validate hierarchical model structure
    pub fn validate(self: *HierarchicalModel) !void {
        if (self.levels.items.len == 0) {
            return error.NoHierarchicalLevels;
        }
        
        // Check that observation model parameters exist in hierarchical levels
        for (self.observation_model.parameters.items) |param_name| {
            var found = false;
            for (self.levels.items) |level| {
                if (level.parameters.contains(param_name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                print("Parameter '{}' in observation model not found in hierarchical levels\n", .{param_name});
                return error.InvalidObservationParameter;
            }
        }
    }
};

/// Manager for mixture and hierarchical models
pub const MixtureHierarchicalManager = struct {
    allocator: Allocator,
    mixture_models: StringHashMap(MixtureModel),
    hierarchical_models: StringHashMap(HierarchicalModel),
    distribution_registry: *DistributionRegistry,
    
    pub fn init(allocator: Allocator, distribution_registry: *DistributionRegistry) MixtureHierarchicalManager {
        return MixtureHierarchicalManager{
            .allocator = allocator,
            .mixture_models = StringHashMap(MixtureModel).init(allocator),
            .hierarchical_models = StringHashMap(HierarchicalModel).init(allocator),
            .distribution_registry = distribution_registry,
        };
    }
    
    pub fn deinit(self: *MixtureHierarchicalManager) void {
        var mixture_iter = self.mixture_models.iterator();
        while (mixture_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.mixture_models.deinit();
        
        var hierarchical_iter = self.hierarchical_models.iterator();
        while (hierarchical_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.hierarchical_models.deinit();
    }
    
    /// Register a new mixture model
    pub fn registerMixtureModel(self: *MixtureHierarchicalManager, model: MixtureModel) !void {
        try model.validate();
        const name_copy = try self.allocator.dupe(u8, model.name);
        try self.mixture_models.put(name_copy, model);
    }
    
    /// Register a new hierarchical model
    pub fn registerHierarchicalModel(self: *MixtureHierarchicalManager, model: HierarchicalModel) !void {
        try model.validate();
        const name_copy = try self.allocator.dupe(u8, model.name);
        try self.hierarchical_models.put(name_copy, model);
    }
    
    /// Get a mixture model by name
    pub fn getMixtureModel(self: *MixtureHierarchicalManager, name: []const u8) ?*MixtureModel {
        return self.mixture_models.getPtr(name);
    }
    
    /// Get a hierarchical model by name
    pub fn getHierarchicalModel(self: *MixtureHierarchicalManager, name: []const u8) ?*HierarchicalModel {
        return self.hierarchical_models.getPtr(name);
    }
    
    /// List all available mixture models
    pub fn listMixtureModels(self: *MixtureHierarchicalManager, allocator: Allocator) !ArrayList([]const u8) {
        var model_names = ArrayList([]const u8).init(allocator);
        
        var iter = self.mixture_models.iterator();
        while (iter.next()) |entry| {
            try model_names.append(try allocator.dupe(u8, entry.key_ptr.*));
        }
        
        return model_names;
    }
    
    /// List all available hierarchical models
    pub fn listHierarchicalModels(self: *MixtureHierarchicalManager, allocator: Allocator) !ArrayList([]const u8) {
        var model_names = ArrayList([]const u8).init(allocator);
        
        var iter = self.hierarchical_models.iterator();
        while (iter.next()) |entry| {
            try model_names.append(try allocator.dupe(u8, entry.key_ptr.*));
        }
        
        return model_names;
    }
    
    /// Create a Gaussian mixture model
    pub fn createGaussianMixture(self: *MixtureHierarchicalManager, name: []const u8, num_components: usize) !MixtureModel {
        var mixture = MixtureModel.init(self.allocator, name, .finite);
        
        const weight = 1.0 / @as(f64, @floatFromInt(num_components));
        
        for (0..num_components) |i| {
            var component = MixtureComponent.init(self.allocator, weight, "normal");
            
            // Add mean parameter (will be learned)
            try component.addParameter(Expression{ .literal = .{ .float = 0.0 } });
            // Add std parameter (will be learned)  
            try component.addParameter(Expression{ .literal = .{ .float = 1.0 } });
            
            const label = try std.fmt.allocPrint(self.allocator, "component_{}", .{i});
            try component.setLabel(self.allocator, label);
            self.allocator.free(label);
            
            try mixture.addComponent(component);
        }
        
        // Set Dirichlet prior for mixture weights
        var dirichlet_params = ArrayList(Expression).init(self.allocator);
        for (0..num_components) |_| {
            try dirichlet_params.append(Expression{ .literal = .{ .float = 1.0 } });
        }
        try mixture.setWeightPrior(self.allocator, "dirichlet", dirichlet_params);
        
        return mixture;
    }
    
    /// Create a simple hierarchical linear model
    pub fn createHierarchicalLinearModel(self: *MixtureHierarchicalManager, name: []const u8, group_variable: []const u8) !HierarchicalModel {
        var model = HierarchicalModel.init(self.allocator, name);
        
        // Create group level
        var group_level = HierarchicalLevel.init(self.allocator, "group", group_variable);
        
        // Add intercept parameter that varies by group
        try group_level.addParameter(self.allocator, "intercept", "normal", &[_][]const u8{ "mu_intercept", "sigma_intercept" });
        
        // Add slope parameter that varies by group  
        try group_level.addParameter(self.allocator, "slope", "normal", &[_][]const u8{ "mu_slope", "sigma_slope" });
        
        // Add hyperpriors
        try group_level.addHyperprior(self.allocator, "mu_intercept", Expression{ .literal = .{ .float = 0.0 } });
        try group_level.addHyperprior(self.allocator, "sigma_intercept", Expression{ .literal = .{ .float = 1.0 } });
        try group_level.addHyperprior(self.allocator, "mu_slope", Expression{ .literal = .{ .float = 0.0 } });
        try group_level.addHyperprior(self.allocator, "sigma_slope", Expression{ .literal = .{ .float = 1.0 } });
        
        try model.addLevel(group_level);
        
        // Set observation model
        try model.setObservationModel(self.allocator, "normal", &[_][]const u8{ "intercept", "slope" });
        
        return model;
    }
};

/// Test functions for mixture and hierarchical models
pub fn testMixtureModels() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var registry = DistributionRegistry.init(allocator);
    defer registry.deinit();
    
    var manager = MixtureHierarchicalManager.init(allocator, &registry);
    defer manager.deinit();
    
    // Test Gaussian mixture model
    const gaussian_mixture = try manager.createGaussianMixture("gaussian_mixture_3", 3);
    try manager.registerMixtureModel(gaussian_mixture);
    
    print("Created Gaussian mixture model with {} components\n", .{gaussian_mixture.components.items.len});
    
    // Test hierarchical model
    const hierarchical_model = try manager.createHierarchicalLinearModel("hierarchical_linear", "group_id");
    try manager.registerHierarchicalModel(hierarchical_model);
    
    print("Created hierarchical linear model with {} levels\n", .{hierarchical_model.levels.items.len});
    
    // List all models
    const mixture_names = try manager.listMixtureModels(allocator);
    defer {
        for (mixture_names.items) |name| {
            allocator.free(name);
        }
        mixture_names.deinit();
    }
    
    print("Registered mixture models:\n");
    for (mixture_names.items) |name| {
        print("  - {s}\n", .{name});
    }
}