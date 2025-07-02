const std = @import("std");
const testing = std.testing;
const math = std.math;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const autodiff = @import("autodiff.zig");
const DualNumber = autodiff.DualNumber;
const ComputationGraph = autodiff.ComputationGraph;
const ForwardModeAD = autodiff.ForwardModeAD;
const GradientComputer = autodiff.GradientComputer;

const SirsParser = @import("sirs.zig");
const Expression = SirsParser.Expression;
const Literal = SirsParser.Literal;
const OpKind = SirsParser.OpKind;

// Test dual numbers for forward-mode AD

test "DualNumber basic operations" {
    // Test addition
    const a = DualNumber.init(3.0, 1.0); // x = 3, dx = 1
    const b = DualNumber.init(2.0, 0.0); // y = 2, dy = 0
    const sum = a.add(b);
    
    try testing.expectApproxEqAbs(sum.value, 5.0, 1e-10);
    try testing.expectApproxEqAbs(sum.derivative, 1.0, 1e-10);
    
    // Test multiplication
    const product = a.mul(b);
    try testing.expectApproxEqAbs(product.value, 6.0, 1e-10);
    try testing.expectApproxEqAbs(product.derivative, 2.0, 1e-10); // d(xy)/dx = y = 2
    
    // Test division
    const quotient = a.div(b);
    try testing.expectApproxEqAbs(quotient.value, 1.5, 1e-10);
    try testing.expectApproxEqAbs(quotient.derivative, 0.5, 1e-10); // d(x/y)/dx = 1/y = 0.5
}

test "DualNumber transcendental functions" {
    const x = DualNumber.init(2.0, 1.0);
    
    // Test exponential
    const exp_x = x.exp();
    try testing.expectApproxEqAbs(exp_x.value, @exp(2.0), 1e-10);
    try testing.expectApproxEqAbs(exp_x.derivative, @exp(2.0), 1e-10); // d(e^x)/dx = e^x
    
    // Test natural logarithm
    const log_x = x.log();
    try testing.expectApproxEqAbs(log_x.value, @log(2.0), 1e-10);
    try testing.expectApproxEqAbs(log_x.derivative, 0.5, 1e-10); // d(ln(x))/dx = 1/x = 0.5
    
    // Test sine
    const sin_x = x.sin();
    try testing.expectApproxEqAbs(sin_x.value, @sin(2.0), 1e-10);
    try testing.expectApproxEqAbs(sin_x.derivative, @cos(2.0), 1e-10); // d(sin(x))/dx = cos(x)
    
    // Test square root
    const sqrt_x = x.sqrt();
    try testing.expectApproxEqAbs(sqrt_x.value, @sqrt(2.0), 1e-10);
    try testing.expectApproxEqAbs(sqrt_x.derivative, 1.0 / (2.0 * @sqrt(2.0)), 1e-10); // d(√x)/dx = 1/(2√x)
}

test "DualNumber chain rule" {
    // Test f(x) = e^(x^2) at x = 1
    // f'(x) = e^(x^2) * 2x = e^1 * 2 = 2e
    const x = DualNumber.variable(1.0);
    const x_squared = x.mul(x);
    const result = x_squared.exp();
    
    try testing.expectApproxEqAbs(result.value, @exp(1.0), 1e-10);
    try testing.expectApproxEqAbs(result.derivative, 2.0 * @exp(1.0), 1e-10);
}

// Test computation graph for reverse-mode AD

test "ComputationGraph basic operations" {
    const allocator = testing.allocator;
    var graph = ComputationGraph.init(allocator);
    defer graph.deinit();
    
    // Create variables: x = 3, y = 2
    const x_id = try graph.variable("x", 3.0);
    const y_id = try graph.variable("y", 2.0);
    
    // Compute z = x + y
    const z_id = try graph.add(x_id, y_id);
    
    // Forward pass should give z = 5
    try testing.expectApproxEqAbs(graph.nodes.items[z_id].value, 5.0, 1e-10);
    
    // Backward pass
    try graph.backward(z_id);
    
    // Check gradients: dz/dx = 1, dz/dy = 1
    try testing.expectApproxEqAbs(graph.nodes.items[x_id].gradient, 1.0, 1e-10);
    try testing.expectApproxEqAbs(graph.nodes.items[y_id].gradient, 1.0, 1e-10);
}

test "ComputationGraph multiplication gradients" {
    const allocator = testing.allocator;
    var graph = ComputationGraph.init(allocator);
    defer graph.deinit();
    
    // Create variables: x = 3, y = 2
    const x_id = try graph.variable("x", 3.0);
    const y_id = try graph.variable("y", 2.0);
    
    // Compute z = x * y
    const z_id = try graph.mul(x_id, y_id);
    
    // Forward pass should give z = 6
    try testing.expectApproxEqAbs(graph.nodes.items[z_id].value, 6.0, 1e-10);
    
    // Backward pass
    try graph.backward(z_id);
    
    // Check gradients: dz/dx = y = 2, dz/dy = x = 3
    try testing.expectApproxEqAbs(graph.nodes.items[x_id].gradient, 2.0, 1e-10);
    try testing.expectApproxEqAbs(graph.nodes.items[y_id].gradient, 3.0, 1e-10);
}

test "ComputationGraph complex expression" {
    const allocator = testing.allocator;
    var graph = ComputationGraph.init(allocator);
    defer graph.deinit();
    
    // Create variables: x = 2, y = 3
    const x_id = try graph.variable("x", 2.0);
    const y_id = try graph.variable("y", 3.0);
    
    // Compute f = x^2 + xy + y^2
    // f'_x = 2x + y = 2*2 + 3 = 7
    // f'_y = x + 2y = 2 + 2*3 = 8
    
    const x_squared_id = try graph.mul(x_id, x_id);
    const xy_id = try graph.mul(x_id, y_id);
    const y_squared_id = try graph.mul(y_id, y_id);
    
    const temp_id = try graph.add(x_squared_id, xy_id);
    const f_id = try graph.add(temp_id, y_squared_id);
    
    // Forward pass: f = 4 + 6 + 9 = 19
    try testing.expectApproxEqAbs(graph.nodes.items[f_id].value, 19.0, 1e-10);
    
    // Backward pass
    try graph.backward(f_id);
    
    // Check gradients
    try testing.expectApproxEqAbs(graph.nodes.items[x_id].gradient, 7.0, 1e-10);
    try testing.expectApproxEqAbs(graph.nodes.items[y_id].gradient, 8.0, 1e-10);
}

test "ComputationGraph transcendental functions" {
    const allocator = testing.allocator;
    var graph = ComputationGraph.init(allocator);
    defer graph.deinit();
    
    // Test log function
    const x_id = try graph.variable("x", 2.0);
    const log_x_id = try graph.log(x_id);
    
    // Forward pass
    try testing.expectApproxEqAbs(graph.nodes.items[log_x_id].value, @log(2.0), 1e-10);
    
    // Backward pass
    try graph.backward(log_x_id);
    
    // Check gradient: d(ln(x))/dx = 1/x = 0.5
    try testing.expectApproxEqAbs(graph.nodes.items[x_id].gradient, 0.5, 1e-10);
    
    // Test exp function
    graph.deinit();
    graph = ComputationGraph.init(allocator);
    
    const y_id = try graph.variable("y", 1.0);
    const exp_y_id = try graph.exp(y_id);
    
    try testing.expectApproxEqAbs(graph.nodes.items[exp_y_id].value, @exp(1.0), 1e-10);
    
    try graph.backward(exp_y_id);
    
    // Check gradient: d(e^y)/dy = e^y = e
    try testing.expectApproxEqAbs(graph.nodes.items[y_id].gradient, @exp(1.0), 1e-10);
}

test "ComputationGraph normal log probability" {
    const allocator = testing.allocator;
    var graph = ComputationGraph.init(allocator);
    defer graph.deinit();
    
    // Test normal log probability: log p(x | μ, σ)
    const x_id = try graph.variable("x", 1.0);
    const mu_id = try graph.variable("mu", 0.0);
    const sigma_id = try graph.variable("sigma", 1.0);
    
    const log_prob_id = try graph.normalLogProb(x_id, mu_id, sigma_id);
    
    // Forward pass: log p(1 | 0, 1) = -0.5*log(2π) - 0.5
    const expected = -0.5 * @log(2.0 * math.pi) - 0.5;
    try testing.expectApproxEqAbs(graph.nodes.items[log_prob_id].value, expected, 1e-10);
    
    // Backward pass
    try graph.backward(log_prob_id);
    
    // Check gradients
    // ∂log p(x|μ,σ)/∂x = -(x-μ)/σ² = -1
    try testing.expectApproxEqAbs(graph.nodes.items[x_id].gradient, -1.0, 1e-10);
    
    // ∂log p(x|μ,σ)/∂μ = (x-μ)/σ² = 1
    try testing.expectApproxEqAbs(graph.nodes.items[mu_id].gradient, 1.0, 1e-10);
    
    // ∂log p(x|μ,σ)/∂σ = -1/σ + (x-μ)²/σ³ = -1 + 1 = 0
    try testing.expectApproxEqAbs(graph.nodes.items[sigma_id].gradient, 0.0, 1e-10);
}

test "ComputationGraph gamma log probability" {
    const allocator = testing.allocator;
    var graph = ComputationGraph.init(allocator);
    defer graph.deinit();
    
    // Test gamma log probability: log p(x | α, β)
    const x_id = try graph.variable("x", 2.0);
    const shape_id = try graph.variable("shape", 2.0);
    const rate_id = try graph.variable("rate", 1.0);
    
    const log_prob_id = try graph.gammaLogProb(x_id, shape_id, rate_id);
    
    // Backward pass to compute gradients
    try graph.backward(log_prob_id);
    
    // Check that gradients are reasonable (exact values depend on gamma function implementation)
    const x_grad = graph.nodes.items[x_id].gradient;
    const shape_grad = graph.nodes.items[shape_id].gradient;
    const rate_grad = graph.nodes.items[rate_id].gradient;
    
    // Basic sanity checks - gradients should be finite
    try testing.expect(!math.isNan(x_grad));
    try testing.expect(!math.isNan(shape_grad));
    try testing.expect(!math.isNan(rate_grad));
    try testing.expect(!math.isInf(x_grad));
    try testing.expect(!math.isInf(shape_grad));
    try testing.expect(!math.isInf(rate_grad));
}

test "ComputationGraph gradient retrieval" {
    const allocator = testing.allocator;
    var graph = ComputationGraph.init(allocator);
    defer graph.deinit();
    
    const x_id = try graph.variable("x", 3.0);
    const y_id = try graph.variable("y", 2.0);
    const z_id = try graph.mul(x_id, y_id);
    
    try graph.backward(z_id);
    
    // Test gradient retrieval by variable name
    const x_grad = graph.getGradient("x");
    const y_grad = graph.getGradient("y");
    const nonexistent_grad = graph.getGradient("nonexistent");
    
    try testing.expectApproxEqAbs(x_grad.?, 2.0, 1e-10);
    try testing.expectApproxEqAbs(y_grad.?, 3.0, 1e-10);
    try testing.expect(nonexistent_grad == null);
    
    // Test getting all gradients
    var all_gradients = try graph.getAllGradients();
    defer all_gradients.deinit();
    
    try testing.expectApproxEqAbs(all_gradients.get("x").?, 2.0, 1e-10);
    try testing.expectApproxEqAbs(all_gradients.get("y").?, 3.0, 1e-10);
}

test "ComputationGraph variable updates" {
    const allocator = testing.allocator;
    var graph = ComputationGraph.init(allocator);
    defer graph.deinit();
    
    _ = try graph.variable("x", 1.0);
    _ = try graph.variable("y", 2.0);
    
    // Test getting current values
    try testing.expectApproxEqAbs(graph.getValue("x").?, 1.0, 1e-10);
    try testing.expectApproxEqAbs(graph.getValue("y").?, 2.0, 1e-10);
    try testing.expect(graph.getValue("nonexistent") == null);
    
    // Test updating variables
    try graph.updateVariable("x", 5.0);
    try graph.updateVariable("y", 3.0);
    
    try testing.expectApproxEqAbs(graph.getValue("x").?, 5.0, 1e-10);
    try testing.expectApproxEqAbs(graph.getValue("y").?, 3.0, 1e-10);
    
    // Test error for nonexistent variable
    const result = graph.updateVariable("nonexistent", 1.0);
    try testing.expectError(autodiff.ADError.InvalidVariable, result);
}

// Test forward-mode AD

test "ForwardModeAD basic functionality" {
    const allocator = testing.allocator;
    var forward_ad = ForwardModeAD.init(allocator);
    defer forward_ad.deinit();
    
    // Set variables
    try forward_ad.setVariable("x", 2.0, true);  // differentiating w.r.t. x
    try forward_ad.setVariable("y", 3.0, false); // not differentiating w.r.t. y
    
    // Test simple expression: x + y
    var args = std.ArrayList(Expression).init(allocator);
    defer args.deinit();
    
    try args.append(Expression{ .variable = "x" });
    try args.append(Expression{ .variable = "y" });
    
    const add_expr = Expression{
        .op = .{
            .kind = .add,
            .args = args,
        }
    };
    
    const result = try forward_ad.evaluate(&add_expr);
    
    try testing.expectApproxEqAbs(result.value, 5.0, 1e-10);
    try testing.expectApproxEqAbs(result.derivative, 1.0, 1e-10); // d(x+y)/dx = 1
}

test "ForwardModeAD literal expressions" {
    const allocator = testing.allocator;
    var forward_ad = ForwardModeAD.init(allocator);
    defer forward_ad.deinit();
    
    // Test float literal
    const float_expr = Expression{ .literal = Literal{ .float = 3.14 } };
    const float_result = try forward_ad.evaluate(&float_expr);
    
    try testing.expectApproxEqAbs(float_result.value, 3.14, 1e-10);
    try testing.expectApproxEqAbs(float_result.derivative, 0.0, 1e-10);
    
    // Test integer literal
    const int_expr = Expression{ .literal = Literal{ .integer = 42 } };
    const int_result = try forward_ad.evaluate(&int_expr);
    
    try testing.expectApproxEqAbs(int_result.value, 42.0, 1e-10);
    try testing.expectApproxEqAbs(int_result.derivative, 0.0, 1e-10);
}

test "ForwardModeAD complex expression" {
    const allocator = testing.allocator;
    var forward_ad = ForwardModeAD.init(allocator);
    defer forward_ad.deinit();
    
    try forward_ad.setVariable("x", 2.0, true);
    
    // Build expression: x * x (using the op structure)
    var args = std.ArrayList(Expression).init(allocator);
    defer args.deinit();
    
    try args.append(Expression{ .variable = "x" });
    try args.append(Expression{ .variable = "x" });
    
    const mul_expr = Expression{
        .op = .{
            .kind = .mul,
            .args = args,
        }
    };
    
    const result = try forward_ad.evaluate(&mul_expr);
    
    try testing.expectApproxEqAbs(result.value, 4.0, 1e-10);
    try testing.expectApproxEqAbs(result.derivative, 4.0, 1e-10); // d(x²)/dx = 2x = 4
}

test "ComputationGraph chain rule verification" {
    const allocator = testing.allocator;
    var graph = ComputationGraph.init(allocator);
    defer graph.deinit();
    
    // Test f(x) = (x + 1)² at x = 2
    // f'(x) = 2(x + 1) = 2(2 + 1) = 6
    
    const x_id = try graph.variable("x", 2.0);
    const one_id = try graph.constant(1.0);
    const x_plus_1_id = try graph.add(x_id, one_id);
    const result_id = try graph.mul(x_plus_1_id, x_plus_1_id);
    
    // Forward pass: f(2) = (2 + 1)² = 9
    try testing.expectApproxEqAbs(graph.nodes.items[result_id].value, 9.0, 1e-10);
    
    // Backward pass
    try graph.backward(result_id);
    
    // Check gradient: f'(2) = 6
    try testing.expectApproxEqAbs(graph.nodes.items[x_id].gradient, 6.0, 1e-10);
}

test "ComputationGraph numerical gradient verification" {
    const allocator = testing.allocator;
    
    // Test numerical vs analytical gradients for f(x,y) = x²y + xy²
    // ∂f/∂x = 2xy + y² 
    // ∂f/∂y = x² + 2xy
    // At (x=2, y=3): ∂f/∂x = 2*2*3 + 3² = 12 + 9 = 21
    //                ∂f/∂y = 2² + 2*2*3 = 4 + 12 = 16
    
    var graph = ComputationGraph.init(allocator);
    defer graph.deinit();
    
    const x_id = try graph.variable("x", 2.0);
    const y_id = try graph.variable("y", 3.0);
    
    // f = x²y + xy²
    const x_sq_id = try graph.mul(x_id, x_id);
    const y_sq_id = try graph.mul(y_id, y_id);
    const x_sq_y_id = try graph.mul(x_sq_id, y_id);
    const x_y_sq_id = try graph.mul(x_id, y_sq_id);
    const f_id = try graph.add(x_sq_y_id, x_y_sq_id);
    
    // Backward pass
    try graph.backward(f_id);
    
    // Check analytical gradients
    try testing.expectApproxEqAbs(graph.nodes.items[x_id].gradient, 21.0, 1e-10);
    try testing.expectApproxEqAbs(graph.nodes.items[y_id].gradient, 16.0, 1e-10);
    
    // Verify with numerical differentiation
    const eps = 1e-8;
    
    // Numerical gradient w.r.t. x
    const f_base = graph.nodes.items[f_id].value; // f(2,3)
    try graph.updateVariable("x", 2.0 + eps);
    
    // Recompute forward pass manually for x+eps
    graph.nodes.items[x_sq_id].value = (2.0 + eps) * (2.0 + eps);
    graph.nodes.items[x_sq_y_id].value = graph.nodes.items[x_sq_id].value * 3.0;
    graph.nodes.items[x_y_sq_id].value = (2.0 + eps) * 9.0;
    graph.nodes.items[f_id].value = graph.nodes.items[x_sq_y_id].value + graph.nodes.items[x_y_sq_id].value;
    
    const f_plus_eps = graph.nodes.items[f_id].value;
    const numerical_grad_x = (f_plus_eps - f_base) / eps;
    
    try testing.expectApproxEqAbs(numerical_grad_x, 21.0, 1e-5);
}

test "ForwardModeAD error handling" {
    const allocator = testing.allocator;
    var forward_ad = ForwardModeAD.init(allocator);
    defer forward_ad.deinit();
    
    // Test undefined variable
    const var_expr = Expression{ .variable = "undefined_var" };
    const result = forward_ad.evaluate(&var_expr);
    try testing.expectError(autodiff.ADError.InvalidVariable, result);
    
    // Test invalid literal
    const bool_expr = Expression{ .literal = Literal{ .boolean = true } };
    const bool_result = forward_ad.evaluate(&bool_expr);
    try testing.expectError(autodiff.ADError.InvalidOperation, bool_result);
}

test "GradientComputer initialization" {
    const allocator = testing.allocator;
    var grad_computer = GradientComputer.init(allocator);
    defer grad_computer.deinit();
    
    // Just test that it initializes and deinitializes without error
    // The full functionality would require more complex integration
}