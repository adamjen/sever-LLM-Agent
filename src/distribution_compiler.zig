const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const SirsParser = @import("sirs.zig");
const Program = SirsParser.Program;
const Function = SirsParser.Function;
const Expression = SirsParser.Expression;
const Statement = SirsParser.Statement;
const Type = SirsParser.Type;

const CustomDistribution = @import("custom_distributions.zig").CustomDistribution;
const DistributionParameter = @import("custom_distributions.zig").DistributionParameter;
const ParameterConstraints = @import("custom_distributions.zig").ParameterConstraints;
const DistributionSupport = @import("custom_distributions.zig").DistributionSupport;
const DistributionRegistry = @import("custom_distributions.zig").DistributionRegistry;

/// Compiler for custom distribution definitions
pub const DistributionCompiler = struct {
    allocator: Allocator,
    registry: DistributionRegistry,
    current_distribution: ?*CustomDistribution,
    
    pub fn init(allocator: Allocator) DistributionCompiler {
        return DistributionCompiler{
            .allocator = allocator,
            .registry = DistributionRegistry.init(allocator),
            .current_distribution = null,
        };
    }
    
    pub fn deinit(self: *DistributionCompiler) void {
        self.registry.deinit();
    }
    
    /// Compile a SIRS program containing distribution definitions
    pub fn compileDistributions(self: *DistributionCompiler, program: *Program) !void {
        // Look for distribution definitions in types
        var type_iter = program.types.iterator();
        while (type_iter.next()) |entry| {
            const type_name = entry.key_ptr.*;
            const type_def = entry.value_ptr.*;
            
            if (try self.isDistributionType(type_def)) {
                try self.compileDistributionFromType(type_name, type_def);
            }
        }
        
        // Look for distribution definitions in interfaces
        var interface_iter = program.interfaces.iterator();
        while (interface_iter.next()) |entry| {
            const interface_name = entry.key_ptr.*;
            const interface_def = entry.value_ptr.*;
            
            if (try self.isDistributionInterface(interface_def)) {
                try self.compileDistributionFromInterface(interface_name, interface_def);
            }
        }
        
        // Process distribution-related functions
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            
            if (try self.isDistributionFunction(func_name, entry.value_ptr)) {
                try self.processDistributionFunction(func_name, entry.value_ptr);
            }
        }
    }
    
    /// Check if a type definition represents a distribution
    fn isDistributionType(self: *DistributionCompiler, type_def: Type) !bool {
        _ = self;
        
        switch (type_def) {
            .@"struct" => |struct_fields| {
                // Look for distribution-like fields
                return struct_fields.contains("parameters") and
                       struct_fields.contains("log_prob") and
                       (struct_fields.contains("sample") or struct_fields.contains("support"));
            },
            .discriminated_union => |union_def| {
                // Check if union name suggests it's a distribution
                return std.mem.endsWith(u8, union_def.name, "Distribution") or
                       std.mem.endsWith(u8, union_def.name, "Dist");
            },
            else => return false,
        }
    }
    
    /// Check if an interface represents a distribution
    fn isDistributionInterface(self: *DistributionCompiler, interface_def: SirsParser.Interface) !bool {
        _ = self;
        
        // Check for distribution-like methods
        const has_log_prob = interface_def.methods.contains("log_prob") or 
                           interface_def.methods.contains("logProb") or
                           interface_def.methods.contains("log_probability");
        
        const has_sample = interface_def.methods.contains("sample") or
                         interface_def.methods.contains("random") or
                         interface_def.methods.contains("generate");
        
        return has_log_prob or has_sample;
    }
    
    /// Check if a function is distribution-related
    pub fn isDistributionFunction(self: *DistributionCompiler, func_name: []const u8, function: *Function) !bool {
        _ = self;
        _ = function;
        
        // Check function name patterns
        return std.mem.endsWith(u8, func_name, "_log_prob") or
               std.mem.endsWith(u8, func_name, "_sample") or
               std.mem.endsWith(u8, func_name, "_logProb") or
               std.mem.endsWith(u8, func_name, "_mean") or
               std.mem.endsWith(u8, func_name, "_variance") or
               std.mem.endsWith(u8, func_name, "_cdf") or
               std.mem.endsWith(u8, func_name, "_pdf") or
               std.mem.startsWith(u8, func_name, "dist_") or
               std.mem.indexOf(u8, func_name, "distribution") != null;
    }
    
    /// Compile distribution from type definition
    fn compileDistributionFromType(self: *DistributionCompiler, type_name: []const u8, type_def: Type) !void {
        switch (type_def) {
            .@"struct" => |struct_fields| {
                var distribution = CustomDistribution.init(self.allocator, try self.allocator.dupe(u8, type_name));
                self.current_distribution = &distribution;
                
                // Extract parameters from struct fields
                var field_iter = struct_fields.iterator();
                while (field_iter.next()) |entry| {
                    const field_name = entry.key_ptr.*;
                    const field_type = entry.value_ptr.*;
                    
                    if (std.mem.eql(u8, field_name, "parameters")) {
                        try self.extractParametersFromType(field_type.*);
                    } else if (std.mem.eql(u8, field_name, "support")) {
                        try self.extractSupportFromType(field_type.*);
                    }
                }
                
                // Set basic properties
                distribution.log_prob_function = try std.fmt.allocPrint(self.allocator, "{s}_log_prob", .{type_name});
                distribution.sample_function = try std.fmt.allocPrint(self.allocator, "{s}_sample", .{type_name});
                
                try self.registry.registerDistribution(distribution);
                self.current_distribution = null;
            },
            .discriminated_union => |union_def| {
                var distribution = CustomDistribution.init(self.allocator, try self.allocator.dupe(u8, union_def.name));
                self.current_distribution = &distribution;
                
                // Extract parameters from union variants
                for (union_def.variants.items) |variant_type| {
                    try self.extractParametersFromType(variant_type.*);
                }
                
                distribution.log_prob_function = try std.fmt.allocPrint(self.allocator, "{s}_log_prob", .{union_def.name});
                
                try self.registry.registerDistribution(distribution);
                self.current_distribution = null;
            },
            else => {},
        }
    }
    
    /// Compile distribution from interface definition
    fn compileDistributionFromInterface(self: *DistributionCompiler, interface_name: []const u8, interface_def: SirsParser.Interface) !void {
        var distribution = CustomDistribution.init(self.allocator, try self.allocator.dupe(u8, interface_name));
        self.current_distribution = &distribution;
        
        // Extract method signatures
        var method_iter = interface_def.methods.iterator();
        while (method_iter.next()) |entry| {
            const method_name = entry.key_ptr.*;
            const method_sig = entry.value_ptr.*;
            
            if (std.mem.indexOf(u8, method_name, "log_prob") != null or std.mem.indexOf(u8, method_name, "logProb") != null) {
                distribution.log_prob_function = try self.allocator.dupe(u8, method_name);
                
                // Extract parameters from method signature
                try self.extractParametersFromFunctionSignature(method_sig);
            } else if (std.mem.indexOf(u8, method_name, "sample") != null) {
                distribution.sample_function = try self.allocator.dupe(u8, method_name);
            }
        }
        
        try self.registry.registerDistribution(distribution);
        self.current_distribution = null;
    }
    
    /// Extract parameters from a type definition
    fn extractParametersFromType(self: *DistributionCompiler, param_type: Type) !void {
        switch (param_type) {
            .@"struct" => |struct_fields| {
                var field_iter = struct_fields.iterator();
                while (field_iter.next()) |entry| {
                    const field_name = entry.key_ptr.*;
                    const field_type = entry.value_ptr.*;
                    
                    if (self.current_distribution) |distribution| {
                        const param = DistributionParameter{
                            .name = try self.allocator.dupe(u8, field_name),
                            .param_type = field_type.*,
                            .constraints = try self.inferConstraintsFromType(field_type.*),
                            .default_value = null,
                            .description = null,
                        };
                        try distribution.parameters.append(param);
                    }
                }
            },
            .record => |record_def| {
                var field_iter = record_def.fields.iterator();
                while (field_iter.next()) |entry| {
                    const field_name = entry.key_ptr.*;
                    const field_type = entry.value_ptr.*;
                    
                    if (self.current_distribution) |distribution| {
                        const param = DistributionParameter{
                            .name = try self.allocator.dupe(u8, field_name),
                            .param_type = field_type.*,
                            .constraints = try self.inferConstraintsFromType(field_type.*),
                            .default_value = null,
                            .description = null,
                        };
                        try distribution.parameters.append(param);
                    }
                }
            },
            else => {},
        }
    }
    
    /// Extract parameters from function signature
    fn extractParametersFromFunctionSignature(self: *DistributionCompiler, signature: SirsParser.FunctionSignature) !void {
        if (self.current_distribution) |distribution| {
            for (signature.args.items) |arg_type| {
                // Generate parameter name based on type
                const param_name = try self.generateParameterName(arg_type);
                
                const param = DistributionParameter{
                    .name = param_name,
                    .param_type = arg_type,
                    .constraints = try self.inferConstraintsFromType(arg_type),
                    .default_value = null,
                    .description = null,
                };
                try distribution.parameters.append(param);
            }
        }
    }
    
    /// Extract support information from type
    fn extractSupportFromType(self: *DistributionCompiler, support_type: Type) !void {
        if (self.current_distribution) |distribution| {
            distribution.support = switch (support_type) {
                .@"enum" => |enum_def| blk: {
                    if (std.mem.eql(u8, enum_def.name, "RealLine")) {
                        break :blk DistributionSupport{
                            .support_type = .real_line,
                            .lower_bound = null,
                            .upper_bound = null,
                            .discrete_values = null,
                        };
                    } else if (std.mem.eql(u8, enum_def.name, "PositiveReal")) {
                        break :blk DistributionSupport{
                            .support_type = .positive_real,
                            .lower_bound = null,
                            .upper_bound = null,
                            .discrete_values = null,
                        };
                    } else if (std.mem.eql(u8, enum_def.name, "UnitInterval")) {
                        break :blk DistributionSupport{
                            .support_type = .unit_interval,
                            .lower_bound = null,
                            .upper_bound = null,
                            .discrete_values = null,
                        };
                    } else {
                        break :blk DistributionSupport{
                            .support_type = .discrete_set,
                            .lower_bound = null,
                            .upper_bound = null,
                            .discrete_values = null,
                        };
                    }
                },
                else => DistributionSupport{
                    .support_type = .real_line,
                    .lower_bound = null,
                    .upper_bound = null,
                    .discrete_values = null,
                },
            };
        }
    }
    
    /// Infer constraints from type information
    pub fn inferConstraintsFromType(self: *DistributionCompiler, param_type: Type) !?ParameterConstraints {
        _ = self;
        
        return switch (param_type) {
            .u8, .u16, .u32, .u64 => ParameterConstraints{
                .min_value = 0,
                .max_value = null,
                .positive_only = true,
                .integer_only = true,
                .vector_constraints = null,
                .custom_validator = null,
            },
            .i8, .i16, .i32, .i64 => ParameterConstraints{
                .min_value = null,
                .max_value = null,
                .positive_only = false,
                .integer_only = true,
                .vector_constraints = null,
                .custom_validator = null,
            },
            .f32, .f64 => null, // No constraints for general floats
            else => null,
        };
    }
    
    /// Generate parameter name from type
    pub fn generateParameterName(self: *DistributionCompiler, param_type: Type) ![]const u8 {
        return switch (param_type) {
            .f64 => try self.allocator.dupe(u8, "param"),
            .i32 => try self.allocator.dupe(u8, "count"),
            .bool => try self.allocator.dupe(u8, "flag"),
            .array => try self.allocator.dupe(u8, "vector"),
            else => try self.allocator.dupe(u8, "value"),
        };
    }
    
    /// Process distribution-related functions
    fn processDistributionFunction(self: *DistributionCompiler, func_name: []const u8, function: *Function) !void {
        _ = function;
        
        // Extract distribution name from function name
        const dist_name = try self.extractDistributionNameFromFunction(func_name);
        
        if (self.registry.getDistribution(dist_name)) |distribution| {
            if (std.mem.endsWith(u8, func_name, "_log_prob")) {
                if (distribution.log_prob_function.len == 0) {
                    distribution.log_prob_function = try self.allocator.dupe(u8, func_name);
                }
            } else if (std.mem.endsWith(u8, func_name, "_sample")) {
                if (distribution.sample_function == null) {
                    distribution.sample_function = try self.allocator.dupe(u8, func_name);
                }
            } else if (std.mem.endsWith(u8, func_name, "_mean")) {
                try distribution.moment_functions.put(try self.allocator.dupe(u8, "mean"), try self.allocator.dupe(u8, func_name));
            } else if (std.mem.endsWith(u8, func_name, "_variance")) {
                try distribution.moment_functions.put(try self.allocator.dupe(u8, "variance"), try self.allocator.dupe(u8, func_name));
            }
        }
    }
    
    /// Extract distribution name from function name
    pub fn extractDistributionNameFromFunction(self: *DistributionCompiler, func_name: []const u8) ![]const u8 {
        // Remove common suffixes
        const suffixes = [_][]const u8{ "_log_prob", "_sample", "_mean", "_variance", "_cdf", "_pdf" };
        
        for (suffixes) |suffix| {
            if (std.mem.endsWith(u8, func_name, suffix)) {
                const end_pos = func_name.len - suffix.len;
                return try self.allocator.dupe(u8, func_name[0..end_pos]);
            }
        }
        
        // Remove "dist_" prefix
        if (std.mem.startsWith(u8, func_name, "dist_")) {
            return try self.allocator.dupe(u8, func_name[5..]);
        }
        
        return try self.allocator.dupe(u8, func_name);
    }
    
    /// Generate SIRS code for a distribution
    pub fn generateDistributionCode(self: *DistributionCompiler, dist_name: []const u8) ![]const u8 {
        if (self.registry.getDistribution(dist_name)) |distribution| {
            var code = ArrayList(u8).init(self.allocator);
            defer code.deinit();
            
            const writer = code.writer();
            
            // Generate distribution interface
            try writer.print("interface {s}Distribution {{\n", .{distribution.name});
            
            // Generate parameter structure
            try writer.print("    struct Parameters {{\n", .{});
            for (distribution.parameters.items) |param| {
                try writer.print("        {s}: {s}", .{ param.name, try self.typeToString(param.param_type) });
                if (param.constraints) |constraints| {
                    try writer.print(" // ", .{});
                    if (constraints.positive_only) try writer.print("positive ", .{});
                    if (constraints.integer_only) try writer.print("integer ", .{});
                    if (constraints.min_value) |min| try writer.print("min={d} ", .{min});
                    if (constraints.max_value) |max| try writer.print("max={d} ", .{max});
                }
                try writer.print(",\n", .{});
            }
            try writer.print("    }}\n\n", .{});
            
            // Generate log probability method
            try writer.print("    fn log_prob(params: Parameters, value: f64) -> f64;\n", .{});
            
            // Generate sampling method
            if (distribution.sample_function != null) {
                try writer.print("    fn sample(params: Parameters, rng: &mut Random) -> f64;\n", .{});
            }
            
            // Generate moment methods
            var moment_iter = distribution.moment_functions.iterator();
            while (moment_iter.next()) |entry| {
                const moment_name = entry.key_ptr.*;
                try writer.print("    fn {s}(params: Parameters) -> f64;\n", .{moment_name});
            }
            
            try writer.print("}}\n\n", .{});
            
            // Generate implementation
            try writer.print("impl {s}Distribution {{\n", .{distribution.name});
            
            // Generate log probability implementation template
            try writer.print("    fn log_prob(params: Parameters, value: f64) -> f64 {{\n", .{});
            try writer.print("        // TODO: Implement log probability calculation\n", .{});
            try writer.print("        // Support: {s}\n", .{@tagName(distribution.support.support_type)});
            try writer.print("        return 0.0;\n", .{});
            try writer.print("    }}\n\n", .{});
            
            // Generate sampling implementation template
            if (distribution.sample_function != null) {
                try writer.print("    fn sample(params: Parameters, rng: &mut Random) -> f64 {{\n", .{});
                try writer.print("        // TODO: Implement sampling algorithm\n", .{});
                try writer.print("        return 0.0;\n", .{});
                try writer.print("    }}\n\n", .{});
            }
            
            try writer.print("}}\n", .{});
            
            return try self.allocator.dupe(u8, code.items);
        }
        
        return try self.allocator.dupe(u8, "// Distribution not found");
    }
    
    /// Convert type to string representation
    pub fn typeToString(self: *DistributionCompiler, param_type: Type) ![]const u8 {
        _ = self;
        
        return switch (param_type) {
            .void => "void",
            .bool => "bool",
            .i8 => "i8",
            .i16 => "i16",
            .i32 => "i32",
            .i64 => "i64",
            .u8 => "u8",
            .u16 => "u16",
            .u32 => "u32",
            .u64 => "u64",
            .f32 => "f32",
            .f64 => "f64",
            .str => "str",
            .array => "Array",
            .slice => "Slice",
            else => "unknown",
        };
    }
    
    /// Validate distribution definition
    pub fn validateDistribution(self: *DistributionCompiler, dist_name: []const u8) !bool {
        if (self.registry.getDistribution(dist_name)) |distribution| {
            // Check required components
            if (distribution.log_prob_function.len == 0) {
                print("Error: Distribution '{s}' missing log_prob function\n", .{dist_name});
                return false;
            }
            
            if (distribution.parameters.items.len == 0) {
                print("Warning: Distribution '{s}' has no parameters\n", .{dist_name});
            }
            
            // Validate parameter constraints
            for (distribution.parameters.items) |param| {
                if (param.constraints) |constraints| {
                    if (constraints.min_value != null and constraints.max_value != null) {
                        if (constraints.min_value.? >= constraints.max_value.?) {
                            print("Error: Parameter '{s}' has invalid range\n", .{param.name});
                            return false;
                        }
                    }
                }
            }
            
            return true;
        }
        
        print("Error: Distribution '{s}' not found\n", .{dist_name});
        return false;
    }
    
    /// Get registry for external access
    pub fn getRegistry(self: *DistributionCompiler) *DistributionRegistry {
        return &self.registry;
    }
};