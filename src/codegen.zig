const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const SirsParser = @import("sirs.zig");
const Program = SirsParser.Program;
const Function = SirsParser.Function;
const Statement = SirsParser.Statement;
const Expression = SirsParser.Expression;
const Type = SirsParser.Type;

pub const CodeGenError = error{
    UnsupportedType,
    UnsupportedExpression,
    UnsupportedStatement,
    IoError,
    CompilationError,
    OutOfMemory,
};

pub const CodeGen = struct {
    allocator: Allocator,
    output: ArrayList(u8),
    indent_level: u32,
    current_function_name: ?[]const u8,
    current_function: ?*Function,
    
    pub fn init(allocator: Allocator) CodeGen {
        return CodeGen{
            .allocator = allocator,
            .output = ArrayList(u8).init(allocator),
            .indent_level = 0,
            .current_function_name = null,
            .current_function = null,
        };
    }
    
    pub fn deinit(self: *CodeGen) void {
        self.output.deinit();
    }
    
    pub fn generate(self: *CodeGen, program: *Program, output_file: []const u8) CodeGenError!void {
        // Clear output buffer
        self.output.clearRetainingCapacity();
        self.indent_level = 0;
        
        // Generate Zig code for the program
        try self.generateProgram(program);
        
        // Write to temporary Zig file
        const temp_zig_file = std.fmt.allocPrint(self.allocator, "{s}.zig", .{output_file}) catch return CodeGenError.OutOfMemory;
        defer self.allocator.free(temp_zig_file);
        
        const file = std.fs.cwd().createFile(temp_zig_file, .{}) catch return CodeGenError.IoError;
        defer file.close();
        
        file.writeAll(self.output.items) catch return CodeGenError.IoError;
        
        // Compile the Zig file to native binary
        try self.compileZigFile(temp_zig_file, output_file);
        
        // Clean up temporary file
        std.fs.cwd().deleteFile(temp_zig_file) catch {};
    }
    
    fn generateProgram(self: *CodeGen, program: *Program) CodeGenError!void {
        // Generate standard library imports
        try self.writeLine("const std = @import(\"std\");");
        try self.writeLine("const debug_print = std.debug.print;");
        try self.writeLine("const Allocator = std.mem.Allocator;");
        try self.writeLine("const math = std.math;");
        try self.writeLine("const time = std.time;");
        try self.writeLine("");
        
        // Generate embedded runtime functions
        try self.writeLine("// Embedded Sever Runtime Functions");
        try self.writeLine("var prng = std.Random.DefaultPrng.init(0);");
        try self.writeLine("var random = prng.random();");
        try self.writeLine("");
        try self.writeLine("fn sever_runtime_init(seed: ?u64) void {");
        try self.writeLine("    const actual_seed = seed orelse @as(u64, @intCast(time.timestamp()));");
        try self.writeLine("    prng = std.Random.DefaultPrng.init(actual_seed);");
        try self.writeLine("    random = prng.random();");
        try self.writeLine("}");
        try self.writeLine("");
        try self.writeLine("fn sample(distribution: []const u8, params: []const f64) f64 {");
        try self.writeLine("    if (std.mem.eql(u8, distribution, \"uniform\")) {");
        try self.writeLine("        const min = params[0];");
        try self.writeLine("        const max = params[1];");
        try self.writeLine("        return min + random.float(f64) * (max - min);");
        try self.writeLine("    } else if (std.mem.eql(u8, distribution, \"normal\")) {");
        try self.writeLine("        const mean = params[0];");
        try self.writeLine("        const std_dev = params[1];");
        try self.writeLine("        const rand1 = random.float(f64);");
        try self.writeLine("        const rand2 = random.float(f64);");
        try self.writeLine("        const z0 = math.sqrt(-2.0 * math.ln(rand1)) * math.cos(2.0 * math.pi * rand2);");
        try self.writeLine("        return mean + std_dev * z0;");
        try self.writeLine("    }");
        try self.writeLine("    return 0.0; // Default case");
        try self.writeLine("}");
        try self.writeLine("");
        try self.writeLine("fn observe(distribution: []const u8, params: []const f64, value: f64) void {");
        try self.writeLine("    _ = distribution; _ = params; _ = value; // TODO: Implement");
        try self.writeLine("}");
        try self.writeLine("");
        try self.writeLine("fn prob_assert(condition: bool, confidence: f64) void {");
        try self.writeLine("    _ = confidence;");
        try self.writeLine("    if (!condition) @panic(\"Probabilistic assertion failed\");");
        try self.writeLine("}");
        try self.writeLine("");
        
        // Generate standard library helper functions
        try self.writeLine("fn std_print(message: []const u8) void {");
        try self.writeLine("    debug_print(\"{s}\\n\", .{message});");
        try self.writeLine("}");
        try self.writeLine("");
        try self.writeLine("fn std_print_int(value: i32) void {");
        try self.writeLine("    debug_print(\"{d}\\n\", .{value});");
        try self.writeLine("}");
        try self.writeLine("");
        try self.writeLine("fn std_print_float(value: f64) void {");
        try self.writeLine("    debug_print(\"{d}\\n\", .{value});");
        try self.writeLine("}");
        try self.writeLine("");
        
        // Generate all functions
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            
            try self.generateFunction(func_name, function);
            try self.writeLine("");
        }
        
        // Generate main function wrapper if entry point is not "main"
        if (!std.mem.eql(u8, program.entry, "main")) {
            try self.writeLine("pub fn main() !void {");
            self.indent_level += 1;
            try self.writeIndent();
            try self.writeLine("sever_runtime.init(null);");
            try self.writeIndent();
            try self.write("try ");
            try self.write(program.entry);
            try self.write("();");
            try self.writeLine("");
            self.indent_level -= 1;
            try self.writeLine("}");
        } else {
            // If main exists, add runtime initialization at the beginning
            const main_func = program.functions.get("main").?;
            if (main_func.body.items.len > 0) {
                try self.writeLine("// Runtime initialization will be added automatically");
            }
        }
    }
    
    fn generateFunction(self: *CodeGen, name: []const u8, function: *Function) CodeGenError!void {
        self.current_function_name = name;
        self.current_function = function;
        
        // Function signature
        if (std.mem.eql(u8, name, "main")) {
            try self.write("pub fn main() ");
        } else {
            try self.write("fn ");
            try self.write(name);
            try self.write("(");
            
            // Parameters
            for (function.args.items, 0..) |param, i| {
                if (i > 0) try self.write(", ");
                try self.write(param.name);
                try self.write(": ");
                try self.generateType(param.type);
            }
            
            try self.write(") ");
        }
        
        // Return type - main function should return !void and print result
        if (std.mem.eql(u8, name, "main")) {
            try self.write("!void");
        } else if (function.@"return" == .void) {
            try self.write("void");
        } else {
            try self.generateType(function.@"return");
        }
        
        try self.writeLine(" {");
        self.indent_level += 1;
        
        // Add runtime initialization for main function
        if (std.mem.eql(u8, name, "main")) {
            try self.writeIndent();
            try self.writeLine("sever_runtime_init(null);");
        }
        
        // Function body
        for (function.body.items) |*stmt| {
            try self.generateStatement(stmt);
        }
        
        self.indent_level -= 1;
        try self.writeLine("}");
    }
    
    fn generateStatement(self: *CodeGen, stmt: *Statement) CodeGenError!void {
        switch (stmt.*) {
            .let => |*let_stmt| {
                try self.writeIndent();
                if (let_stmt.mutable) {
                    try self.write("var ");
                } else {
                    try self.write("const ");
                }
                try self.write(let_stmt.name);
                
                if (let_stmt.type) |stmt_type| {
                    try self.write(": ");
                    try self.generateType(stmt_type);
                }
                
                try self.write(" = ");
                try self.generateExpression(&let_stmt.value);
                try self.writeLine(";");
            },
            
            .assign => |*assign_stmt| {
                try self.writeIndent();
                try self.generateLValue(&assign_stmt.target);
                try self.write(" = ");
                try self.generateExpression(&assign_stmt.value);
                try self.writeLine(";");
            },
            
            .@"if" => |*if_stmt| {
                try self.writeIndent();
                try self.write("if (");
                try self.generateExpression(&if_stmt.condition);
                try self.writeLine(") {");
                
                self.indent_level += 1;
                for (if_stmt.then.items) |*then_stmt| {
                    try self.generateStatement(then_stmt);
                }
                self.indent_level -= 1;
                
                if (if_stmt.@"else") |*else_stmts| {
                    try self.writeLine("} else {");
                    self.indent_level += 1;
                    for (else_stmts.items) |*else_stmt| {
                        try self.generateStatement(else_stmt);
                    }
                    self.indent_level -= 1;
                }
                
                try self.writeLine("}");
            },
            
            .@"while" => |*while_stmt| {
                try self.writeIndent();
                try self.write("while (");
                try self.generateExpression(&while_stmt.condition);
                try self.writeLine(") {");
                
                self.indent_level += 1;
                for (while_stmt.body.items) |*body_stmt| {
                    try self.generateStatement(body_stmt);
                }
                self.indent_level -= 1;
                
                try self.writeLine("}");
            },
            
            .@"return" => |*return_expr| {
                try self.writeIndent();
                // Check if we're in main function and need to print result instead of returning it
                if (self.current_function) |func| {
                    if (func.@"return" != .void and self.current_function_name != null and std.mem.eql(u8, self.current_function_name.?, "main")) {
                        // For main function, print the result and return void
                        try self.write("const result = ");
                        try self.generateExpression(return_expr);
                        try self.writeLine(";");
                        try self.writeIndent();
                        try self.writeLine("std_print_int(result);");
                        try self.writeIndent();
                        try self.writeLine("return;");
                    } else {
                        try self.write("return ");
                        try self.generateExpression(return_expr);
                        try self.writeLine(";");
                    }
                } else {
                    try self.write("return ");
                    try self.generateExpression(return_expr);
                    try self.writeLine(";");
                }
            },
            
            .@"break" => {
                try self.writeIndent();
                try self.writeLine("break;");
            },
            
            .@"continue" => {
                try self.writeIndent();
                try self.writeLine("continue;");
            },
            
            .observe => |*observe_stmt| {
                try self.writeIndent();
                try self.write("observe(\"");
                try self.write(observe_stmt.distribution);
                try self.write("\", &[_]f64{");
                
                for (observe_stmt.params.items, 0..) |*param, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateExpression(param);
                }
                
                try self.write("}, ");
                try self.generateExpression(&observe_stmt.value);
                try self.writeLine(");");
            },
            
            .prob_assert => |*assert_stmt| {
                try self.writeIndent();
                try self.write("prob_assert(");
                try self.generateExpression(&assert_stmt.condition);
                try self.write(", ");
                try self.write(std.fmt.allocPrint(self.allocator, "{d}", .{assert_stmt.confidence}) catch return CodeGenError.OutOfMemory);
                try self.writeLine(");");
            },
            
            .expression => |*expr| {
                try self.writeIndent();
                try self.generateExpression(expr);
                try self.writeLine(";");
            },
            
            else => {
                return CodeGenError.UnsupportedStatement;
            },
        }
    }
    
    fn generateExpression(self: *CodeGen, expr: *Expression) CodeGenError!void {
        switch (expr.*) {
            .literal => |literal| {
                switch (literal) {
                    .integer => |i| try self.write(std.fmt.allocPrint(self.allocator, "{d}", .{i}) catch return CodeGenError.OutOfMemory),
                    .float => |f| try self.write(std.fmt.allocPrint(self.allocator, "{d}", .{f}) catch return CodeGenError.OutOfMemory),
                    .string => |s| {
                        try self.write("\"");
                        try self.write(s);
                        try self.write("\"");
                    },
                    .boolean => |b| try self.write(if (b) "true" else "false"),
                    .null => try self.write("null"),
                }
            },
            
            .variable => |var_name| {
                try self.write(var_name);
            },
            
            .call => |*call_expr| {
                try self.write(call_expr.function);
                try self.write("(");
                
                for (call_expr.args.items, 0..) |*arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateExpression(arg);
                }
                
                try self.write(")");
            },
            
            .op => |*op_expr| {
                try self.generateOperation(op_expr);
            },
            
            .index => |*index_expr| {
                try self.generateExpression(index_expr.array);
                try self.write("[");
                try self.generateExpression(index_expr.index);
                try self.write("]");
            },
            
            .field => |*field_expr| {
                try self.generateExpression(field_expr.object);
                try self.write(".");
                try self.write(field_expr.field);
            },
            
            .array => |*array_expr| {
                try self.write("[_]");
                // Need to determine element type
                try self.write("auto{");
                
                for (array_expr.items, 0..) |*elem, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateExpression(elem);
                }
                
                try self.write("}");
            },
            
            .sample => |*sample_expr| {
                try self.write("sample(\"");
                try self.write(sample_expr.distribution);
                try self.write("\", &[_]f64{");
                
                for (sample_expr.params.items, 0..) |*param, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateExpression(param);
                }
                
                try self.write("})");
            },
            
            .cast => |*cast_expr| {
                try self.write("@as(");
                try self.generateType(cast_expr.type);
                try self.write(", ");
                try self.generateExpression(cast_expr.value);
                try self.write(")");
            },
            
            else => {
                return CodeGenError.UnsupportedExpression;
            },
        }
    }
    
    fn generateOperation(self: *CodeGen, op_expr: anytype) CodeGenError!void {
        const args = &op_expr.args;
        
        switch (op_expr.kind) {
            .not => {
                try self.write("!");
                try self.generateExpression(@constCast(&args.items[0]));
            },
            
            .bitnot => {
                try self.write("~");
                try self.generateExpression(@constCast(&args.items[0]));
            },
            
            else => {
                // Binary operations
                if (args.items.len >= 2) {
                    try self.write("(");
                    try self.generateExpression(@constCast(&args.items[0]));
                    try self.write(" ");
                    try self.write(try self.getOperatorSymbol(op_expr.kind));
                    try self.write(" ");
                    try self.generateExpression(@constCast(&args.items[1]));
                    try self.write(")");
                } else {
                    return CodeGenError.UnsupportedExpression;
                }
            },
        }
    }
    
    fn generateLValue(self: *CodeGen, lvalue: *const SirsParser.LValue) CodeGenError!void {
        switch (lvalue.*) {
            .variable => |var_name| {
                try self.write(var_name);
            },
            
            .index => |*index_lvalue| {
                try self.generateLValue(index_lvalue.array);
                try self.write("[");
                try self.generateExpression(@constCast(&index_lvalue.index));
                try self.write("]");
            },
            
            .field => |*field_lvalue| {
                try self.generateLValue(field_lvalue.object);
                try self.write(".");
                try self.write(field_lvalue.field);
            },
        }
    }
    
    fn generateType(self: *CodeGen, t: Type) CodeGenError!void {
        switch (t) {
            .void => try self.write("void"),
            .bool => try self.write("bool"),
            .i8 => try self.write("i8"),
            .i16 => try self.write("i16"),
            .i32 => try self.write("i32"),
            .i64 => try self.write("i64"),
            .u8 => try self.write("u8"),
            .u16 => try self.write("u16"),
            .u32 => try self.write("u32"),
            .u64 => try self.write("u64"),
            .f32 => try self.write("f32"),
            .f64 => try self.write("f64"),
            .str => try self.write("[]const u8"),
            
            .array => |arr| {
                try self.write("[");
                try self.write(std.fmt.allocPrint(self.allocator, "{d}", .{arr.size}) catch return CodeGenError.OutOfMemory);
                try self.write("]");
                try self.generateType(arr.element.*);
            },
            
            .slice => |slice| {
                try self.write("[]");
                try self.generateType(slice.element.*);
            },
            
            .optional => |opt| {
                try self.write("?");
                try self.generateType(opt.*);
            },
            
            else => {
                return CodeGenError.UnsupportedType;
            },
        }
    }
    
    fn getOperatorSymbol(_: *CodeGen, op: SirsParser.OpKind) ![]const u8 {
        return switch (op) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .mod => "%",
            .eq => "==",
            .ne => "!=",
            .lt => "<",
            .le => "<=",
            .gt => ">",
            .ge => ">=",
            .@"and" => "and",
            .@"or" => "or",
            .bitand => "&",
            .bitor => "|",
            .bitxor => "^",
            .shl => "<<",
            .shr => ">>",
            else => return CodeGenError.UnsupportedExpression,
        };
    }
    
    fn compileZigFile(self: *CodeGen, zig_file: []const u8, output_file: []const u8) CodeGenError!void {
        // Extract just the basename for the package name  
        const basename = std.fs.path.basename(output_file);
        
        const cmd = std.fmt.allocPrint(self.allocator, "zig build-exe {s} -O ReleaseFast --name {s}", .{ zig_file, basename }) catch return CodeGenError.OutOfMemory;
        defer self.allocator.free(cmd);
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "sh", "-c", cmd },
        }) catch return CodeGenError.IoError;
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            print("Compilation failed:\n{s}\n", .{result.stderr});
            return CodeGenError.CompilationError;
        }
    }
    
    fn write(self: *CodeGen, text: []const u8) CodeGenError!void {
        self.output.appendSlice(text) catch return CodeGenError.OutOfMemory;
    }
    
    fn writeLine(self: *CodeGen, text: []const u8) CodeGenError!void {
        self.output.appendSlice(text) catch return CodeGenError.OutOfMemory;
        self.output.append('\n') catch return CodeGenError.OutOfMemory;
    }
    
    fn writeIndent(self: *CodeGen) CodeGenError!void {
        var i: u32 = 0;
        while (i < self.indent_level) : (i += 1) {
            self.output.appendSlice("    ") catch return CodeGenError.OutOfMemory;
        }
    }
};