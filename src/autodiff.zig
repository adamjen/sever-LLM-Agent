const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const SirsParser = @import("sirs.zig");
const Expression = SirsParser.Expression;
const Literal = SirsParser.Literal;
const OpKind = SirsParser.OpKind;

/// Automatic Differentiation Engine for Sever
/// Supports both forward-mode and reverse-mode automatic differentiation

pub const ADError = error{
    InvalidVariable,
    InvalidOperation,
    DimensionMismatch,
    OutOfMemory,
    CircularDependency,
};

/// Dual number for forward-mode automatic differentiation
pub const DualNumber = struct {
    value: f64,
    derivative: f64,
    
    pub fn init(value: f64, derivative: f64) DualNumber {
        return DualNumber{
            .value = value,
            .derivative = derivative,
        };
    }
    
    pub fn constant(value: f64) DualNumber {
        return DualNumber.init(value, 0.0);
    }
    
    pub fn variable(value: f64) DualNumber {
        return DualNumber.init(value, 1.0);
    }
    
    /// Addition
    pub fn add(self: DualNumber, other: DualNumber) DualNumber {
        return DualNumber.init(
            self.value + other.value,
            self.derivative + other.derivative
        );
    }
    
    /// Subtraction
    pub fn sub(self: DualNumber, other: DualNumber) DualNumber {
        return DualNumber.init(
            self.value - other.value,
            self.derivative - other.derivative
        );
    }
    
    /// Multiplication
    pub fn mul(self: DualNumber, other: DualNumber) DualNumber {
        return DualNumber.init(
            self.value * other.value,
            self.derivative * other.value + self.value * other.derivative
        );
    }
    
    /// Division
    pub fn div(self: DualNumber, other: DualNumber) DualNumber {
        const denom = other.value * other.value;
        return DualNumber.init(
            self.value / other.value,
            (self.derivative * other.value - self.value * other.derivative) / denom
        );
    }
    
    /// Power
    pub fn pow(self: DualNumber, exponent: f64) DualNumber {
        const val_pow = math.pow(f64, self.value, exponent);
        return DualNumber.init(
            val_pow,
            exponent * math.pow(f64, self.value, exponent - 1.0) * self.derivative
        );
    }
    
    /// Natural logarithm
    pub fn log(self: DualNumber) DualNumber {
        return DualNumber.init(
            @log(self.value),
            self.derivative / self.value
        );
    }
    
    /// Exponential
    pub fn exp(self: DualNumber) DualNumber {
        const exp_val = @exp(self.value);
        return DualNumber.init(exp_val, exp_val * self.derivative);
    }
    
    /// Sine
    pub fn sin(self: DualNumber) DualNumber {
        return DualNumber.init(
            @sin(self.value),
            @cos(self.value) * self.derivative
        );
    }
    
    /// Cosine
    pub fn cos(self: DualNumber) DualNumber {
        return DualNumber.init(
            @cos(self.value),
            -@sin(self.value) * self.derivative
        );
    }
    
    /// Square root
    pub fn sqrt(self: DualNumber) DualNumber {
        const sqrt_val = @sqrt(self.value);
        return DualNumber.init(
            sqrt_val,
            self.derivative / (2.0 * sqrt_val)
        );
    }
};

/// Computational graph node for reverse-mode AD
pub const ComputationNode = struct {
    /// Unique identifier for this node
    id: usize,
    /// Forward value
    value: f64,
    /// Gradient (adjoint) - computed during backward pass
    gradient: f64,
    /// Operation that created this node
    operation: Operation,
    /// Parent nodes that this node depends on
    parents: ArrayList(usize),
    /// Whether this node has been visited during backward pass
    visited: bool,
    
    pub fn init(allocator: Allocator, id: usize, operation: Operation) ComputationNode {
        return ComputationNode{
            .id = id,
            .value = 0.0,
            .gradient = 0.0,
            .operation = operation,
            .parents = ArrayList(usize).init(allocator),
            .visited = false,
        };
    }
    
    pub fn deinit(self: *ComputationNode) void {
        self.parents.deinit();
    }
};

/// Operations in the computational graph
pub const Operation = union(enum) {
    constant: f64,
    variable: []const u8,
    add: struct { left: usize, right: usize },
    sub: struct { left: usize, right: usize },
    mul: struct { left: usize, right: usize },
    div: struct { left: usize, right: usize },
    pow: struct { base: usize, exponent: f64 },
    log: usize,
    exp: usize,
    sin: usize,
    cos: usize,
    sqrt: usize,
    // Probability distributions
    normal_log_prob: struct { value: usize, mu: usize, sigma: usize },
    gamma_log_prob: struct { value: usize, shape: usize, rate: usize },
    beta_log_prob: struct { value: usize, alpha: usize, beta: usize },
};

/// Computational graph for reverse-mode automatic differentiation
pub const ComputationGraph = struct {
    allocator: Allocator,
    nodes: ArrayList(ComputationNode),
    variables: StringHashMap(usize), // variable name -> node id
    next_id: usize,
    
    pub fn init(allocator: Allocator) ComputationGraph {
        return ComputationGraph{
            .allocator = allocator,
            .nodes = ArrayList(ComputationNode).init(allocator),
            .variables = StringHashMap(usize).init(allocator),
            .next_id = 0,
        };
    }
    
    pub fn deinit(self: *ComputationGraph) void {
        for (self.nodes.items) |*node| {
            node.deinit();
        }
        self.nodes.deinit();
        self.variables.deinit();
    }
    
    /// Create a constant node
    pub fn constant(self: *ComputationGraph, value: f64) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .constant = value });
        node.value = value;
        try self.nodes.append(node);
        
        return id;
    }
    
    /// Create a variable node
    pub fn variable(self: *ComputationGraph, name: []const u8, value: f64) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .variable = name });
        node.value = value;
        try self.nodes.append(node);
        try self.variables.put(name, id);
        
        return id;
    }
    
    /// Binary operations
    pub fn add(self: *ComputationGraph, left_id: usize, right_id: usize) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .add = .{ .left = left_id, .right = right_id } });
        try node.parents.append(left_id);
        try node.parents.append(right_id);
        
        // Forward pass
        node.value = self.nodes.items[left_id].value + self.nodes.items[right_id].value;
        
        try self.nodes.append(node);
        return id;
    }
    
    pub fn sub(self: *ComputationGraph, left_id: usize, right_id: usize) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .sub = .{ .left = left_id, .right = right_id } });
        try node.parents.append(left_id);
        try node.parents.append(right_id);
        
        // Forward pass
        node.value = self.nodes.items[left_id].value - self.nodes.items[right_id].value;
        
        try self.nodes.append(node);
        return id;
    }
    
    pub fn mul(self: *ComputationGraph, left_id: usize, right_id: usize) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .mul = .{ .left = left_id, .right = right_id } });
        try node.parents.append(left_id);
        try node.parents.append(right_id);
        
        // Forward pass
        node.value = self.nodes.items[left_id].value * self.nodes.items[right_id].value;
        
        try self.nodes.append(node);
        return id;
    }
    
    pub fn div(self: *ComputationGraph, left_id: usize, right_id: usize) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .div = .{ .left = left_id, .right = right_id } });
        try node.parents.append(left_id);
        try node.parents.append(right_id);
        
        // Forward pass
        node.value = self.nodes.items[left_id].value / self.nodes.items[right_id].value;
        
        try self.nodes.append(node);
        return id;
    }
    
    /// Unary operations
    pub fn log(self: *ComputationGraph, operand_id: usize) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .log = operand_id });
        try node.parents.append(operand_id);
        
        // Forward pass
        node.value = @log(self.nodes.items[operand_id].value);
        
        try self.nodes.append(node);
        return id;
    }
    
    pub fn exp(self: *ComputationGraph, operand_id: usize) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .exp = operand_id });
        try node.parents.append(operand_id);
        
        // Forward pass
        node.value = @exp(self.nodes.items[operand_id].value);
        
        try self.nodes.append(node);
        return id;
    }
    
    pub fn sin(self: *ComputationGraph, operand_id: usize) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .sin = operand_id });
        try node.parents.append(operand_id);
        
        // Forward pass
        node.value = @sin(self.nodes.items[operand_id].value);
        
        try self.nodes.append(node);
        return id;
    }
    
    pub fn sqrt(self: *ComputationGraph, operand_id: usize) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .sqrt = operand_id });
        try node.parents.append(operand_id);
        
        // Forward pass
        node.value = @sqrt(self.nodes.items[operand_id].value);
        
        try self.nodes.append(node);
        return id;
    }
    
    /// Probability distribution operations
    pub fn normalLogProb(self: *ComputationGraph, value_id: usize, mu_id: usize, sigma_id: usize) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .normal_log_prob = .{ .value = value_id, .mu = mu_id, .sigma = sigma_id } });
        try node.parents.append(value_id);
        try node.parents.append(mu_id);
        try node.parents.append(sigma_id);
        
        // Forward pass: log(1/√(2πσ²)) - (x-μ)²/(2σ²)
        const value = self.nodes.items[value_id].value;
        const mu = self.nodes.items[mu_id].value;
        const sigma = self.nodes.items[sigma_id].value;
        
        const diff = value - mu;
        const sigma_sq = sigma * sigma;
        node.value = -0.5 * @log(2.0 * math.pi) - @log(sigma) - (diff * diff) / (2.0 * sigma_sq);
        
        try self.nodes.append(node);
        return id;
    }
    
    pub fn gammaLogProb(self: *ComputationGraph, value_id: usize, shape_id: usize, rate_id: usize) !usize {
        const id = self.next_id;
        self.next_id += 1;
        
        var node = ComputationNode.init(self.allocator, id, Operation{ .gamma_log_prob = .{ .value = value_id, .shape = shape_id, .rate = rate_id } });
        try node.parents.append(value_id);
        try node.parents.append(shape_id);
        try node.parents.append(rate_id);
        
        // Forward pass: (α-1)log(x) - βx + αlog(β) - log(Γ(α))
        const value = self.nodes.items[value_id].value;
        const shape = self.nodes.items[shape_id].value;
        const rate = self.nodes.items[rate_id].value;
        
        if (value <= 0) {
            node.value = -math.inf(f64);
        } else {
            node.value = (shape - 1.0) * @log(value) - rate * value + shape * @log(rate) - lgamma(shape);
        }
        
        try self.nodes.append(node);
        return id;
    }
    
    /// Compute gradients using reverse-mode automatic differentiation
    pub fn backward(self: *ComputationGraph, output_id: usize) !void {
        // Reset gradients
        for (self.nodes.items) |*node| {
            node.gradient = 0.0;
            node.visited = false;
        }
        
        // Set gradient of output to 1.0
        self.nodes.items[output_id].gradient = 1.0;
        
        // Backward pass in reverse topological order
        var i = self.nodes.items.len;
        while (i > 0) {
            i -= 1;
            const node = &self.nodes.items[i];
            
            if (node.gradient == 0.0) continue;
            
            try self.propagateGradients(i);
        }
    }
    
    /// Propagate gradients for a specific node
    fn propagateGradients(self: *ComputationGraph, node_id: usize) !void {
        const node = &self.nodes.items[node_id];
        
        switch (node.operation) {
            .constant, .variable => {
                // No gradients to propagate
            },
            
            .add => |add_op| {
                // ∂f/∂x = ∂f/∂z * ∂z/∂x = ∂f/∂z * 1
                self.nodes.items[add_op.left].gradient += node.gradient;
                self.nodes.items[add_op.right].gradient += node.gradient;
            },
            
            .sub => |sub_op| {
                // ∂f/∂x = ∂f/∂z * ∂z/∂x = ∂f/∂z * 1 for left, -1 for right
                self.nodes.items[sub_op.left].gradient += node.gradient;
                self.nodes.items[sub_op.right].gradient -= node.gradient;
            },
            
            .mul => |mul_op| {
                // ∂f/∂x = ∂f/∂z * ∂z/∂x = ∂f/∂z * y for left, ∂f/∂z * x for right
                const left_val = self.nodes.items[mul_op.left].value;
                const right_val = self.nodes.items[mul_op.right].value;
                
                self.nodes.items[mul_op.left].gradient += node.gradient * right_val;
                self.nodes.items[mul_op.right].gradient += node.gradient * left_val;
            },
            
            .div => |div_op| {
                // ∂f/∂x = ∂f/∂z * ∂z/∂x = ∂f/∂z * (1/y) for left, ∂f/∂z * (-x/y²) for right
                const left_val = self.nodes.items[div_op.left].value;
                const right_val = self.nodes.items[div_op.right].value;
                
                self.nodes.items[div_op.left].gradient += node.gradient / right_val;
                self.nodes.items[div_op.right].gradient -= node.gradient * left_val / (right_val * right_val);
            },
            
            .log => |operand_id| {
                // ∂f/∂x = ∂f/∂z * ∂z/∂x = ∂f/∂z * (1/x)
                const operand_val = self.nodes.items[operand_id].value;
                self.nodes.items[operand_id].gradient += node.gradient / operand_val;
            },
            
            .exp => |operand_id| {
                // ∂f/∂x = ∂f/∂z * ∂z/∂x = ∂f/∂z * exp(x)
                const operand_val = self.nodes.items[operand_id].value;
                self.nodes.items[operand_id].gradient += node.gradient * @exp(operand_val);
            },
            
            .sin => |operand_id| {
                // ∂f/∂x = ∂f/∂z * ∂z/∂x = ∂f/∂z * cos(x)
                const operand_val = self.nodes.items[operand_id].value;
                self.nodes.items[operand_id].gradient += node.gradient * @cos(operand_val);
            },
            
            .sqrt => |operand_id| {
                // ∂f/∂x = ∂f/∂z * ∂z/∂x = ∂f/∂z * (1/(2√x))
                const operand_val = self.nodes.items[operand_id].value;
                self.nodes.items[operand_id].gradient += node.gradient / (2.0 * @sqrt(operand_val));
            },
            
            .normal_log_prob => |normal_op| {
                // Gradients for normal log probability
                const value = self.nodes.items[normal_op.value].value;
                const mu = self.nodes.items[normal_op.mu].value;
                const sigma = self.nodes.items[normal_op.sigma].value;
                
                const diff = value - mu;
                const sigma_sq = sigma * sigma;
                
                // ∂log p(x|μ,σ)/∂x = -(x-μ)/σ²
                self.nodes.items[normal_op.value].gradient += node.gradient * (-diff / sigma_sq);
                
                // ∂log p(x|μ,σ)/∂μ = (x-μ)/σ²
                self.nodes.items[normal_op.mu].gradient += node.gradient * (diff / sigma_sq);
                
                // ∂log p(x|μ,σ)/∂σ = -1/σ + (x-μ)²/σ³
                self.nodes.items[normal_op.sigma].gradient += node.gradient * (-1.0/sigma + (diff * diff)/(sigma_sq * sigma));
            },
            
            .gamma_log_prob => |gamma_op| {
                // Gradients for gamma log probability
                const value = self.nodes.items[gamma_op.value].value;
                const shape = self.nodes.items[gamma_op.shape].value;
                const rate = self.nodes.items[gamma_op.rate].value;
                
                if (value > 0) {
                    // ∂log p(x|α,β)/∂x = (α-1)/x - β
                    self.nodes.items[gamma_op.value].gradient += node.gradient * ((shape - 1.0) / value - rate);
                    
                    // ∂log p(x|α,β)/∂α = log(x) + log(β) - digamma(α)
                    self.nodes.items[gamma_op.shape].gradient += node.gradient * (@log(value) + @log(rate) - digamma(shape));
                    
                    // ∂log p(x|α,β)/∂β = α/β - x
                    self.nodes.items[gamma_op.rate].gradient += node.gradient * (shape / rate - value);
                }
            },
            
            else => {
                // Handle other operations as needed
            },
        }
    }
    
    /// Get gradient with respect to a variable
    pub fn getGradient(self: *ComputationGraph, var_name: []const u8) ?f64 {
        if (self.variables.get(var_name)) |node_id| {
            return self.nodes.items[node_id].gradient;
        }
        return null;
    }
    
    /// Get all gradients as a map
    pub fn getAllGradients(self: *ComputationGraph) !StringHashMap(f64) {
        var gradients = StringHashMap(f64).init(self.allocator);
        
        var var_iter = self.variables.iterator();
        while (var_iter.next()) |entry| {
            const var_name = entry.key_ptr.*;
            const node_id = entry.value_ptr.*;
            try gradients.put(var_name, self.nodes.items[node_id].gradient);
        }
        
        return gradients;
    }
    
    /// Update variable values
    pub fn updateVariable(self: *ComputationGraph, var_name: []const u8, new_value: f64) !void {
        if (self.variables.get(var_name)) |node_id| {
            self.nodes.items[node_id].value = new_value;
        } else {
            return ADError.InvalidVariable;
        }
    }
    
    /// Get current value of a variable
    pub fn getValue(self: *ComputationGraph, var_name: []const u8) ?f64 {
        if (self.variables.get(var_name)) |node_id| {
            return self.nodes.items[node_id].value;
        }
        return null;
    }
};

/// Forward-mode automatic differentiation engine
pub const ForwardModeAD = struct {
    allocator: Allocator,
    variables: StringHashMap(DualNumber),
    
    pub fn init(allocator: Allocator) ForwardModeAD {
        return ForwardModeAD{
            .allocator = allocator,
            .variables = StringHashMap(DualNumber).init(allocator),
        };
    }
    
    pub fn deinit(self: *ForwardModeAD) void {
        self.variables.deinit();
    }
    
    /// Set variable with its value and indicate if we're differentiating w.r.t. it
    pub fn setVariable(self: *ForwardModeAD, name: []const u8, value: f64, is_diff_var: bool) !void {
        const dual = if (is_diff_var) DualNumber.variable(value) else DualNumber.constant(value);
        try self.variables.put(name, dual);
    }
    
    /// Evaluate an expression and return both value and derivative
    pub fn evaluate(self: *ForwardModeAD, expr: *const Expression) ADError!DualNumber {
        switch (expr.*) {
            .literal => |literal| {
                switch (literal) {
                    .float => |f| return DualNumber.constant(f),
                    .integer => |i| return DualNumber.constant(@floatFromInt(i)),
                    else => return ADError.InvalidOperation,
                }
            },
            
            .variable => |var_name| {
                if (self.variables.get(var_name)) |dual| {
                    return dual;
                } else {
                    return ADError.InvalidVariable;
                }
            },
            
            .op => |op_expr| {
                return try self.evaluateOperation(op_expr);
            },
            
            else => return ADError.InvalidOperation,
        }
    }
    
    fn evaluateOperation(self: *ForwardModeAD, op_expr: anytype) ADError!DualNumber {
        switch (op_expr.kind) {
            .add => {
                const left = try self.evaluate(&op_expr.args.items[0]);
                const right = try self.evaluate(&op_expr.args.items[1]);
                return left.add(right);
            },
            
            .sub => {
                const left = try self.evaluate(&op_expr.args.items[0]);
                const right = try self.evaluate(&op_expr.args.items[1]);
                return left.sub(right);
            },
            
            .mul => {
                const left = try self.evaluate(&op_expr.args.items[0]);
                const right = try self.evaluate(&op_expr.args.items[1]);
                return left.mul(right);
            },
            
            .div => {
                const left = try self.evaluate(&op_expr.args.items[0]);
                const right = try self.evaluate(&op_expr.args.items[1]);
                return left.div(right);
            },
            
            else => return ADError.InvalidOperation,
        }
    }
};

/// Utility functions

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

/// High-level gradient computation interface
pub const GradientComputer = struct {
    allocator: Allocator,
    computation_graph: ComputationGraph,
    
    pub fn init(allocator: Allocator) GradientComputer {
        return GradientComputer{
            .allocator = allocator,
            .computation_graph = ComputationGraph.init(allocator),
        };
    }
    
    pub fn deinit(self: *GradientComputer) void {
        self.computation_graph.deinit();
    }
    
    /// Compute gradient of a log probability function
    pub fn computeLogProbGradient(
        self: *GradientComputer, 
        log_prob_fn: *const fn(*StringHashMap(f64), ?*anyopaque) f64,
        variables: *StringHashMap(f64),
        context: ?*anyopaque
    ) !StringHashMap(f64) {
        // Reset computation graph
        self.computation_graph.deinit();
        self.computation_graph = ComputationGraph.init(self.allocator);
        
        // Add variables to computation graph
        var var_iter = variables.iterator();
        while (var_iter.next()) |entry| {
            const var_name = entry.key_ptr.*;
            const var_value = entry.value_ptr.*;
            _ = try self.computation_graph.variable(var_name, var_value);
        }
        
        // This is a simplified approach - in practice, we'd need to parse
        // the log_prob_fn or build the computation graph programmatically
        _ = log_prob_fn;
        _ = context;
        
        // For now, return empty gradients
        return StringHashMap(f64).init(self.allocator);
    }
};