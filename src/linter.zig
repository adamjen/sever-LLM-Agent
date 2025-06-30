const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const SirsParser = @import("sirs.zig");
const Program = SirsParser.Program;
const Function = SirsParser.Function;
const Statement = SirsParser.Statement;
const Expression = SirsParser.Expression;
const Type = SirsParser.Type;

/// Severity levels for lint issues
pub const LintSeverity = enum {
    @"error",
    warning,
    info,
    suggestion,
};

/// Categories of lint rules
pub const LintCategory = enum {
    style,
    performance,
    correctness,
    maintainability,
    security,
    complexity,
};

/// A single lint issue found in the code
pub const LintIssue = struct {
    rule_id: []const u8,
    severity: LintSeverity,
    category: LintCategory,
    message: []const u8,
    file: []const u8,
    line: u32,
    column: u32,
    suggestion: ?[]const u8, // Optional fix suggestion
};

/// Configuration for the linter
pub const LintConfig = struct {
    max_function_length: u32 = 50,
    max_parameter_count: u32 = 5,
    max_nesting_depth: u32 = 4,
    max_cyclomatic_complexity: u32 = 10,
    enforce_naming_conventions: bool = true,
    check_unused_variables: bool = true,
    check_dead_code: bool = true,
    check_performance_issues: bool = true,
    check_security_issues: bool = true,
};

/// Linter error types
pub const LintError = error{
    OutOfMemory,
    InvalidConfig,
    ParseError,
};

/// Main linter implementation
pub const Linter = struct {
    allocator: Allocator,
    config: LintConfig,
    issues: ArrayList(LintIssue),
    current_file: []const u8,
    variable_usage: StringHashMap(u32), // Track variable usage counts
    function_calls: StringHashMap(u32), // Track function call counts
    
    pub fn init(allocator: Allocator, config: LintConfig) Linter {
        return Linter{
            .allocator = allocator,
            .config = config,
            .issues = ArrayList(LintIssue).init(allocator),
            .current_file = "",
            .variable_usage = StringHashMap(u32).init(allocator),
            .function_calls = StringHashMap(u32).init(allocator),
        };
    }
    
    pub fn deinit(self: *Linter) void {
        self.issues.deinit();
        self.variable_usage.deinit();
        self.function_calls.deinit();
    }
    
    /// Run linting on a program
    pub fn lint(self: *Linter, program: *Program, source_file: []const u8) LintError!void {
        self.current_file = source_file;
        self.issues.clearRetainingCapacity();
        self.variable_usage.clearRetainingCapacity();
        self.function_calls.clearRetainingCapacity();
        
        // Check program-level issues
        try self.checkProgramStructure(program);
        
        // Check each function
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            try self.lintFunction(func_name, function);
        }
        
        // Check for unused functions
        try self.checkUnusedFunctions(program);
        
        // Check for dead code patterns
        if (self.config.check_dead_code) {
            try self.checkDeadCode(program);
        }
    }
    
    /// Get all lint issues found
    pub fn getIssues(self: *Linter) []const LintIssue {
        return self.issues.items;
    }
    
    /// Print all issues to stdout
    pub fn printIssues(self: *Linter) void {
        if (self.issues.items.len == 0) {
            print("✅ No lint issues found!\n", .{});
            return;
        }
        
        print("🔍 Found {d} lint issues:\n\n", .{self.issues.items.len});
        
        for (self.issues.items, 0..) |issue, i| {
            const severity_symbol = switch (issue.severity) {
                .@"error" => "❌",
                .warning => "⚠️",
                .info => "ℹ️",
                .suggestion => "💡",
            };
            
            const category_str = switch (issue.category) {
                .style => "style",
                .performance => "performance", 
                .correctness => "correctness",
                .maintainability => "maintainability",
                .security => "security",
                .complexity => "complexity",
            };
            
            print("{s} [{s}] {s}:{d}:{d} - {s}\n", .{
                severity_symbol,
                category_str,
                issue.file,
                issue.line,
                issue.column,
                issue.message,
            });
            
            print("    Rule: {s}\n", .{issue.rule_id});
            
            if (issue.suggestion) |suggestion| {
                print("    💡 Suggestion: {s}\n", .{suggestion});
            }
            
            if (i < self.issues.items.len - 1) {
                print("\n", .{});
            }
        }
        
        // Summary by severity
        var error_count: u32 = 0;
        var warning_count: u32 = 0;
        var info_count: u32 = 0;
        var suggestion_count: u32 = 0;
        
        for (self.issues.items) |issue| {
            switch (issue.severity) {
                .@"error" => error_count += 1,
                .warning => warning_count += 1,
                .info => info_count += 1,
                .suggestion => suggestion_count += 1,
            }
        }
        
        print("\n📊 Summary: {d} errors, {d} warnings, {d} info, {d} suggestions\n", .{
            error_count, warning_count, info_count, suggestion_count
        });
    }
    
    /// Check program-level structure issues
    fn checkProgramStructure(self: *Linter, program: *Program) LintError!void {
        // Check if entry function exists
        if (!program.functions.contains(program.entry)) {
            try self.addIssue(.{
                .rule_id = "missing-entry-function",
                .severity = .@"error",
                .category = .correctness,
                .message = "Entry function not found",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Define the entry function specified in the program",
            });
        }
        
        // Check for empty program
        if (program.functions.count() == 0) {
            try self.addIssue(.{
                .rule_id = "empty-program",
                .severity = .warning,
                .category = .maintainability,
                .message = "Program contains no functions",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Add at least one function to the program",
            });
        }
        
        // Check for too many top-level functions
        if (program.functions.count() > 20) {
            try self.addIssue(.{
                .rule_id = "too-many-functions",
                .severity = .warning,
                .category = .maintainability,
                .message = "Program has too many functions (consider organizing into modules)",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Consider breaking the program into smaller modules",
            });
        }
    }
    
    /// Lint a single function
    fn lintFunction(self: *Linter, func_name: []const u8, function: *Function) LintError!void {
        // Check function naming conventions
        if (self.config.enforce_naming_conventions) {
            try self.checkNamingConventions(func_name, function);
        }
        
        // Check function length
        if (function.body.items.len > self.config.max_function_length) {
            try self.addIssue(.{
                .rule_id = "function-too-long",
                .severity = .warning,
                .category = .maintainability,
                .message = "Function is too long",
                .file = self.current_file,
                .line = 1, // Would need proper source mapping
                .column = 1,
                .suggestion = "Consider breaking this function into smaller functions",
            });
        }
        
        // Check parameter count
        if (function.args.items.len > self.config.max_parameter_count) {
            try self.addIssue(.{
                .rule_id = "too-many-parameters",
                .severity = .warning,
                .category = .maintainability,
                .message = "Function has too many parameters",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Consider using a struct to group related parameters",
            });
        }
        
        // Check for empty functions
        if (function.body.items.len == 0) {
            try self.addIssue(.{
                .rule_id = "empty-function",
                .severity = .info,
                .category = .maintainability,
                .message = "Function is empty",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Add implementation or remove unused function",
            });
        }
        
        // Analyze function body
        var analyzer = FunctionAnalyzer.init(self.allocator, self.config);
        defer analyzer.deinit();
        
        try analyzer.analyze(function);
        
        // Check cyclomatic complexity
        if (analyzer.complexity > self.config.max_cyclomatic_complexity) {
            try self.addIssue(.{
                .rule_id = "high-complexity",
                .severity = .warning,
                .category = .complexity,
                .message = "Function has high cyclomatic complexity",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Consider simplifying the function logic",
            });
        }
        
        // Check nesting depth
        if (analyzer.max_nesting_depth > self.config.max_nesting_depth) {
            try self.addIssue(.{
                .rule_id = "deep-nesting",
                .severity = .warning,
                .category = .maintainability,
                .message = "Function has deeply nested code",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Consider using early returns or extracting nested logic",
            });
        }
        
        // Check for unused parameters
        if (self.config.check_unused_variables) {
            for (function.args.items) |param| {
                if (!analyzer.used_variables.contains(param.name)) {
                    try self.addIssue(.{
                        .rule_id = "unused-parameter",
                        .severity = .warning,
                        .category = .maintainability,
                        .message = "Parameter is never used",
                        .file = self.current_file,
                        .line = 1,
                        .column = 1,
                        .suggestion = "Remove the parameter or use it in the function",
                    });
                }
            }
        }
        
        // Check for performance issues
        if (self.config.check_performance_issues) {
            try self.checkPerformanceIssues(function, &analyzer);
        }
        
        // Check for security issues
        if (self.config.check_security_issues) {
            try self.checkSecurityIssues(function, &analyzer);
        }
    }
    
    /// Check naming conventions
    fn checkNamingConventions(self: *Linter, func_name: []const u8, function: *Function) LintError!void {
        // Check function naming (should be snake_case)
        if (!isSnakeCase(func_name)) {
            try self.addIssue(.{
                .rule_id = "function-naming",
                .severity = .suggestion,
                .category = .style,
                .message = "Function name should use snake_case",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Use snake_case for function names (e.g., my_function)",
            });
        }
        
        // Check parameter naming
        for (function.args.items) |param| {
            if (!isSnakeCase(param.name)) {
                try self.addIssue(.{
                    .rule_id = "parameter-naming",
                    .severity = .suggestion,
                    .category = .style,
                    .message = "Parameter name should use snake_case",
                    .file = self.current_file,
                    .line = 1,
                    .column = 1,
                    .suggestion = "Use snake_case for parameter names",
                });
            }
        }
    }
    
    /// Check for performance issues
    fn checkPerformanceIssues(self: *Linter, function: *Function, analyzer: *FunctionAnalyzer) LintError!void {
        _ = function;
        
        // Check for excessive string concatenations
        if (analyzer.string_concatenations > 5) {
            try self.addIssue(.{
                .rule_id = "excessive-string-concat",
                .severity = .warning,
                .category = .performance,
                .message = "Excessive string concatenations detected",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Consider using a StringBuilder or format function",
            });
        }
        
        // Check for nested loops
        if (analyzer.nested_loops > 0) {
            try self.addIssue(.{
                .rule_id = "nested-loops",
                .severity = .info,
                .category = .performance,
                .message = "Nested loops detected - consider optimization",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Consider algorithm optimization or caching",
            });
        }
    }
    
    /// Check for security issues
    fn checkSecurityIssues(self: *Linter, function: *Function, analyzer: *FunctionAnalyzer) LintError!void {
        _ = function;
        
        // Check for direct file operations without validation
        if (analyzer.file_operations > 0) {
            try self.addIssue(.{
                .rule_id = "unsafe-file-ops",
                .severity = .warning,
                .category = .security,
                .message = "Direct file operations detected",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Validate file paths and handle errors properly",
            });
        }
        
        // Check for HTTP operations without validation
        if (analyzer.http_operations > 0) {
            try self.addIssue(.{
                .rule_id = "unsafe-http-ops",
                .severity = .warning,
                .category = .security,
                .message = "HTTP operations detected",
                .file = self.current_file,
                .line = 1,
                .column = 1,
                .suggestion = "Validate URLs and sanitize inputs",
            });
        }
    }
    
    /// Check for unused functions
    fn checkUnusedFunctions(self: *Linter, program: *Program) LintError!void {
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            
            // Skip entry function
            if (std.mem.eql(u8, func_name, program.entry)) {
                continue;
            }
            
            // Check if function is called
            if (!self.function_calls.contains(func_name)) {
                try self.addIssue(.{
                    .rule_id = "unused-function",
                    .severity = .warning,
                    .category = .maintainability,
                    .message = "Function is never called",
                    .file = self.current_file,
                    .line = 1,
                    .column = 1,
                    .suggestion = "Remove unused function or export it if it's meant to be public",
                });
            }
        }
    }
    
    /// Check for dead code patterns
    fn checkDeadCode(self: *Linter, program: *Program) LintError!void {
        _ = self;
        _ = program;
        // This would analyze the control flow to find unreachable code
        // For now, we'll implement basic patterns
        
        // Check for unreachable code after return statements
        // This would require more sophisticated AST analysis
    }
    
    /// Add a lint issue
    fn addIssue(self: *Linter, issue: LintIssue) LintError!void {
        try self.issues.append(issue);
    }
};

/// Helper to check if a name follows snake_case convention
fn isSnakeCase(name: []const u8) bool {
    if (name.len == 0) return false;
    
    // Should start with lowercase letter or underscore
    if (!(std.ascii.isLower(name[0]) or name[0] == '_')) {
        return false;
    }
    
    // Should only contain lowercase letters, digits, and underscores
    for (name) |char| {
        if (!(std.ascii.isLower(char) or std.ascii.isDigit(char) or char == '_')) {
            return false;
        }
    }
    
    return true;
}

/// Function analyzer for detailed analysis
const FunctionAnalyzer = struct {
    allocator: Allocator,
    config: LintConfig,
    complexity: u32,
    max_nesting_depth: u32,
    current_nesting_depth: u32,
    used_variables: StringHashMap(bool),
    string_concatenations: u32,
    nested_loops: u32,
    file_operations: u32,
    http_operations: u32,
    
    fn init(allocator: Allocator, config: LintConfig) FunctionAnalyzer {
        return FunctionAnalyzer{
            .allocator = allocator,
            .config = config,
            .complexity = 1, // Base complexity
            .max_nesting_depth = 0,
            .current_nesting_depth = 0,
            .used_variables = StringHashMap(bool).init(allocator),
            .string_concatenations = 0,
            .nested_loops = 0,
            .file_operations = 0,
            .http_operations = 0,
        };
    }
    
    fn deinit(self: *FunctionAnalyzer) void {
        self.used_variables.deinit();
    }
    
    fn analyze(self: *FunctionAnalyzer, function: *Function) LintError!void {
        for (function.body.items) |*stmt| {
            try self.analyzeStatement(stmt);
        }
    }
    
    fn analyzeStatement(self: *FunctionAnalyzer, stmt: *Statement) LintError!void {
        switch (stmt.*) {
            .let => |let_stmt| {
                try self.analyzeExpression(@constCast(&let_stmt.value));
            },
            .@"if" => |if_stmt| {
                self.complexity += 1; // If adds complexity
                self.enterNesting();
                
                try self.analyzeExpression(@constCast(&if_stmt.condition));
                for (if_stmt.then.items) |*then_stmt| {
                    try self.analyzeStatement(@constCast(then_stmt));
                }
                
                if (if_stmt.@"else") |else_stmts| {
                    for (else_stmts.items) |*else_stmt| {
                        try self.analyzeStatement(@constCast(else_stmt));
                    }
                }
                
                self.exitNesting();
            },
            .@"while" => |while_stmt| {
                self.complexity += 1; // While adds complexity
                self.enterNesting();
                
                if (self.current_nesting_depth > 1) {
                    self.nested_loops += 1;
                }
                
                try self.analyzeExpression(@constCast(&while_stmt.condition));
                for (while_stmt.body.items) |*body_stmt| {
                    try self.analyzeStatement(@constCast(body_stmt));
                }
                
                self.exitNesting();
            },
            .expression => |expr| {
                try self.analyzeExpression(@constCast(&expr));
            },
            .@"return" => |return_expr| {
                try self.analyzeExpression(@constCast(&return_expr));
            },
            else => {},
        }
    }
    
    fn analyzeExpression(self: *FunctionAnalyzer, expr: *Expression) LintError!void {
        switch (expr.*) {
            .variable => |var_name| {
                try self.used_variables.put(var_name, true);
            },
            .call => |call_expr| {
                // Check for specific function patterns
                if (std.mem.startsWith(u8, call_expr.function, "file_")) {
                    self.file_operations += 1;
                } else if (std.mem.startsWith(u8, call_expr.function, "http_")) {
                    self.http_operations += 1;
                }
                
                // Check for string concatenation
                if (std.mem.eql(u8, call_expr.function, "string_concat")) {
                    self.string_concatenations += 1;
                }
                
                for (call_expr.args.items) |*arg| {
                    try self.analyzeExpression(@constCast(arg));
                }
            },
            .op => |op_expr| {
                // String concatenation via + operator on strings
                if (op_expr.kind == .add) {
                    // Would need type information to detect string concatenation
                    // For now, we'll be conservative
                }
                
                for (op_expr.args.items) |*arg| {
                    try self.analyzeExpression(@constCast(arg));
                }
            },
            .literal => {},
            else => {},
        }
    }
    
    fn enterNesting(self: *FunctionAnalyzer) void {
        self.current_nesting_depth += 1;
        if (self.current_nesting_depth > self.max_nesting_depth) {
            self.max_nesting_depth = self.current_nesting_depth;
        }
    }
    
    fn exitNesting(self: *FunctionAnalyzer) void {
        if (self.current_nesting_depth > 0) {
            self.current_nesting_depth -= 1;
        }
    }
};

/// Static analysis tools
pub const StaticAnalyzer = struct {
    allocator: Allocator,
    issues: ArrayList(LintIssue),
    
    pub fn init(allocator: Allocator) StaticAnalyzer {
        return StaticAnalyzer{
            .allocator = allocator,
            .issues = ArrayList(LintIssue).init(allocator),
        };
    }
    
    pub fn deinit(self: *StaticAnalyzer) void {
        self.issues.deinit();
    }
    
    /// Perform data flow analysis
    pub fn analyzeDataFlow(self: *StaticAnalyzer, program: *Program) LintError!void {
        _ = self;
        _ = program;
        // Would implement sophisticated data flow analysis
        // - Uninitialized variable usage
        // - Null pointer dereferences
        // - Use after free
        // - Variable shadowing
    }
    
    /// Perform control flow analysis
    pub fn analyzeControlFlow(self: *StaticAnalyzer, program: *Program) LintError!void {
        _ = self;
        _ = program;
        // Would implement control flow analysis
        // - Unreachable code detection
        // - Missing return statements
        // - Infinite loops
        // - Dead branches
    }
    
    /// Perform dependency analysis
    pub fn analyzeDependencies(self: *StaticAnalyzer, program: *Program) LintError!void {
        _ = self;
        _ = program;
        // Would implement dependency analysis
        // - Circular dependencies
        // - Unused imports
        // - Missing dependencies
        // - Dependency version conflicts
    }
};