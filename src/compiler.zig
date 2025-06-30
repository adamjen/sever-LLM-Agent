const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const SirsParser = @import("sirs.zig");
const TypeChecker = @import("typechecker.zig").TypeChecker;
const CodeGen = @import("codegen.zig").CodeGen;
const McpServer = @import("mcp.zig").McpServer;
const ErrorReporter = @import("error_reporter.zig").ErrorReporter;
const CirLowering = @import("cir.zig").CirLowering;

pub const CompilerError = error{
    FileNotFound,
    ParseError,
    TypeCheckError,
    CirLoweringError,
    CodeGenError,
    IoError,
};

pub const SeverCompiler = struct {
    allocator: Allocator,
    parser: SirsParser.Parser,
    type_checker: TypeChecker,
    code_gen: CodeGen,
    error_reporter: ErrorReporter,
    
    pub fn init(allocator: Allocator) SeverCompiler {
        return SeverCompiler{
            .allocator = allocator,
            .parser = SirsParser.Parser.init(allocator),
            .type_checker = TypeChecker.init(allocator),
            .code_gen = CodeGen.init(allocator),
            .error_reporter = ErrorReporter.init(allocator),
        };
    }
    
    pub fn deinit(self: *SeverCompiler) void {
        self.type_checker.deinit();
        self.code_gen.deinit();
        self.error_reporter.deinit();
    }
    
    pub fn compile(self: *SeverCompiler, input_file: []const u8) !void {
        // Clear any previous errors
        self.error_reporter.clear();
        try self.error_reporter.setCurrentFile(input_file);
        
        print("Building Sever program: {s}\n", .{input_file});
        
        print("Phase 1: Reading SIRS file...\n", .{});
        const content = self.readFile(input_file) catch |err| switch (err) {
            error.FileNotFound => {
                try self.error_reporter.reportErrorWithHint(
                    null,
                    "File '{s}' not found",
                    .{input_file},
                    "Make sure the file path is correct and the file exists",
                    .{}
                );
                self.error_reporter.printAllErrors();
                return CompilerError.FileNotFound;
            },
            else => {
                try self.error_reporter.reportError(
                    null,
                    "Failed to read file '{s}': {s}",
                    .{ input_file, @errorName(err) }
                );
                self.error_reporter.printAllErrors();
                return CompilerError.IoError;
            },
        };
        defer self.allocator.free(content);
        
        print("Phase 2: Parsing SIRS...\n", .{});
        var program = self.parser.parse(content) catch |err| {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Failed to parse SIRS file: {s}",
                .{@errorName(err)},
                "Check that the JSON syntax is valid and follows the SIRS specification",
                .{}
            );
            self.error_reporter.printAllErrors();
            return CompilerError.ParseError;
        };
        defer program.deinit();
        
        print("Phase 3: Type checking...\n", .{});
        self.type_checker.check(&program) catch |err| {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Type checking failed: {s}",
                .{@errorName(err)},
                "Check variable types, function signatures, and expression compatibility",
                .{}
            );
            self.error_reporter.printAllErrors();
            return CompilerError.TypeCheckError;
        };
        
        print("Phase 4: Lowering to CIR...\n", .{});
        var cir_lowering = CirLowering.init(self.allocator, &self.error_reporter, "main");
        defer cir_lowering.deinit();
        
        const cir_module = cir_lowering.lower(&program) catch |err| {
            try self.error_reporter.reportErrorWithHint(
                null,
                "CIR lowering failed: {s}",
                .{@errorName(err)},
                "Check that all language constructs are supported in CIR",
                .{}
            );
            self.error_reporter.printAllErrors();
            return CompilerError.CirLoweringError;
        };
        _ = cir_module; // Will be used by code generator in the future
        
        print("Phase 5: Generating code...\n", .{});
        const output_file = try self.getOutputFilename(input_file);
        defer self.allocator.free(output_file);
        
        self.code_gen.generate(&program, output_file) catch |err| {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Code generation failed: {s}",
                .{@errorName(err)},
                "Check that all expressions and statements are supported",
                .{}
            );
            self.error_reporter.printAllErrors();
            return CompilerError.CodeGenError;
        };
        
        const error_count = self.error_reporter.getErrorCount();
        const warning_count = self.error_reporter.getWarningCount();
        
        if (error_count > 0) {
            print("Compilation failed with {} error(s)", .{error_count});
            if (warning_count > 0) {
                print(" and {} warning(s)", .{warning_count});
            }
            print("\n", .{});
            self.error_reporter.printAllErrors();
            return CompilerError.CodeGenError;
        }
        
        print("Compilation complete: {s}", .{output_file});
        if (warning_count > 0) {
            print(" (with {} warning(s))", .{warning_count});
        }
        print("\n", .{});
        
        if (warning_count > 0) {
            self.error_reporter.printAllErrors();
        }
    }
    
    pub fn test_program(self: *SeverCompiler, input_file: []const u8) !void {
        // Clear any previous errors
        self.error_reporter.clear();
        try self.error_reporter.setCurrentFile(input_file);
        
        print("Testing Sever program: {s}\n", .{input_file});
        
        // First compile the program
        print("Phase 1: Compiling program...\n", .{});
        self.compile(input_file) catch |err| {
            try self.error_reporter.reportError(
                null,
                "Compilation failed during testing: {s}",
                .{@errorName(err)}
            );
            self.error_reporter.printAllErrors();
            return err;
        };
        
        // Get the output executable name
        const output_file = try self.getOutputFilename(input_file);
        defer self.allocator.free(output_file);
        
        // For testing, we need just the basename in the current directory
        const basename = std.fs.path.basename(output_file);
        
        // Create the executable path for Unix systems
        const exe_path = try std.fmt.allocPrint(self.allocator, "./{s}", .{basename});
        defer self.allocator.free(exe_path);
        
        // Check if the file exists before trying to execute it
        const file_stat = std.fs.cwd().statFile(basename) catch |err| {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Compiled executable '{s}' not found: {s}",
                .{ basename, @errorName(err) },
                "Make sure the compilation succeeded and the file was created",
                .{}
            );
            self.error_reporter.printAllErrors();
            return CompilerError.CodeGenError;
        };
        _ = file_stat;
        
        // Run the compiled program and capture output
        print("Phase 2: Executing test cases...\n", .{});
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{exe_path},
        }) catch |err| {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Failed to execute compiled program: {s}",
                .{@errorName(err)},
                "Make sure the program compiled successfully and is executable",
                .{}
            );
            self.error_reporter.printAllErrors();
            return CompilerError.CodeGenError;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        // Check if the program executed successfully
        if (result.term.Exited != 0) {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Program exited with non-zero status: {}",
                .{result.term.Exited},
                "Check the program logic and ensure all assertions pass",
                .{}
            );
            
            if (result.stderr.len > 0) {
                print("Error output:\n{s}\n", .{result.stderr});
            }
            
            self.error_reporter.printAllErrors();
            return CompilerError.CodeGenError;
        }
        
        // Parse and validate test output
        try self.validateTestOutput(result.stdout);
        
        const error_count = self.error_reporter.getErrorCount();
        const warning_count = self.error_reporter.getWarningCount();
        
        if (error_count > 0) {
            print("Tests failed with {} error(s)", .{error_count});
            if (warning_count > 0) {
                print(" and {} warning(s)", .{warning_count});
            }
            print("\n", .{});
            self.error_reporter.printAllErrors();
            return CompilerError.CodeGenError;
        }
        
        print("All tests passed successfully!", .{});
        if (warning_count > 0) {
            print(" (with {} warning(s))", .{warning_count});
        }
        print("\n", .{});
        
        if (warning_count > 0) {
            self.error_reporter.printAllErrors();
        }
    }
    
    pub fn serve(self: *SeverCompiler) !void {
        print("Starting MCP server...\n", .{});
        
        var mcp_server = McpServer.init(self.allocator);
        defer mcp_server.deinit();
        
        try mcp_server.start();
    }
    
    fn readFile(self: *SeverCompiler, path: []const u8) ![]u8 {
        const file = std.fs.cwd().openFile(path, .{}) catch return error.FileNotFound;
        defer file.close();
        
        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, file_size);
        _ = try file.readAll(content);
        
        return content;
    }
    
    fn getOutputFilename(self: *SeverCompiler, input_file: []const u8) ![]u8 {
        // Convert input.sirs.json to input or input.exe
        var base_name: []const u8 = input_file;
        
        if (std.mem.endsWith(u8, input_file, ".sirs.json")) {
            base_name = input_file[0..input_file.len - 10]; // Remove .sirs.json
        }
        
        // Add platform-specific extension if needed
        if (@import("builtin").os.tag == .windows) {
            return try std.fmt.allocPrint(self.allocator, "{s}.exe", .{base_name});
        }
        
        return try self.allocator.dupe(u8, base_name);
    }
    
    pub fn generate_docs(self: *SeverCompiler, input_file: []const u8) !void {
        // Clear any previous errors
        self.error_reporter.clear();
        try self.error_reporter.setCurrentFile(input_file);
        
        print("Generating documentation for: {s}\n", .{input_file});
        
        print("Phase 1: Reading SIRS file...\n", .{});
        const content = self.readFile(input_file) catch |err| switch (err) {
            error.FileNotFound => {
                try self.error_reporter.reportErrorWithHint(
                    null,
                    "File '{s}' not found",
                    .{input_file},
                    "Make sure the file path is correct and the file exists",
                    .{}
                );
                self.error_reporter.printAllErrors();
                return CompilerError.FileNotFound;
            },
            else => return err,
        };
        defer self.allocator.free(content);
        
        print("Phase 2: Parsing SIRS...\n", .{});
        var program = self.parser.parse(content) catch |err| {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Failed to parse SIRS program: {s}",
                .{@errorName(err)},
                "Check the JSON syntax and SIRS program structure",
                .{}
            );
            self.error_reporter.printAllErrors();
            return CompilerError.ParseError;
        };
        defer program.deinit();
        
        print("Phase 3: Generating documentation...\n", .{});
        try self.generateDocumentation(&program, input_file);
        
        print("Documentation generated successfully\n", .{});
    }
    
    fn generateDocumentation(self: *SeverCompiler, program: *SirsParser.Program, input_file: []const u8) !void {
        const output_filename = try self.getDocOutputFilename(input_file);
        defer self.allocator.free(output_filename);
        
        const file = std.fs.cwd().createFile(output_filename, .{}) catch |err| {
            try self.error_reporter.reportErrorWithHint(
                null,
                "Failed to create documentation file '{s}': {s}",
                .{ output_filename, @errorName(err) },
                "Check file permissions and available disk space",
                .{}
            );
            return CompilerError.IoError;
        };
        defer file.close();
        
        var writer = file.writer();
        
        // Generate markdown documentation
        try writer.print("# Documentation for {s}\n\n", .{std.fs.path.basename(input_file)});
        try writer.print("Generated automatically by Sever compiler\n\n", .{});
        
        // Document program structure
        try writer.print("## Program Overview\n\n", .{});
        try writer.print("- **Entry point**: `{s}()`\n", .{program.entry});
        try writer.print("- **Functions**: {} defined\n", .{program.functions.count()});
        try writer.print("- **Types**: {} defined\n", .{program.types.count()});
        
        if (program.interfaces.count() > 0) {
            try writer.print("- **Interfaces**: {} defined\n", .{program.interfaces.count()});
        }
        
        if (program.trait_impls.items.len > 0) {
            try writer.print("- **Trait implementations**: {} defined\n", .{program.trait_impls.items.len});
        }
        
        if (program.constants.count() > 0) {
            try writer.print("- **Constants**: {} defined\n", .{program.constants.count()});
        }
        
        try writer.print("\n", .{});
        
        // Document functions
        try writer.print("## Functions\n\n", .{});
        var func_iter = program.functions.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const function = entry.value_ptr;
            
            try writer.print("### `{s}(", .{func_name});
            
            // Document function parameters
            for (function.args.items, 0..) |param, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{s}: {s}", .{ param.name, self.typeToString(param.type) });
            }
            
            try writer.print(") -> {s}`\n\n", .{self.typeToString(function.@"return")});
            
            // Add function type parameters if any
            if (function.type_params) |type_params| {
                if (type_params.items.len > 0) {
                    try writer.print("**Type parameters**: ", .{});
                    for (type_params.items, 0..) |param, i| {
                        if (i > 0) try writer.print(", ", .{});
                        try writer.print("`{s}`", .{param});
                    }
                    try writer.print("\n\n", .{});
                }
            }
            
            try writer.print("Function with {} statement(s)\n\n", .{function.body.items.len});
        }
        
        // Document types
        if (program.types.count() > 0) {
            try writer.print("## Types\n\n", .{});
            var type_iter = program.types.iterator();
            while (type_iter.next()) |entry| {
                const type_name = entry.key_ptr.*;
                const type_def = entry.value_ptr;
                
                try writer.print("### `{s}`\n\n", .{type_name});
                try writer.print("Type: {s}\n\n", .{self.typeToString(type_def.*)});
            }
        }
        
        // Document interfaces
        if (program.interfaces.count() > 0) {
            try writer.print("## Interfaces\n\n", .{});
            var interface_iter = program.interfaces.iterator();
            while (interface_iter.next()) |entry| {
                const interface_name = entry.key_ptr.*;
                const interface_def = entry.value_ptr;
                
                try writer.print("### `{s}`\n\n", .{interface_name});
                
                if (interface_def.type_params) |type_params| {
                    if (type_params.items.len > 0) {
                        try writer.print("**Type parameters**: ", .{});
                        for (type_params.items, 0..) |param, i| {
                            if (i > 0) try writer.print(", ", .{});
                            try writer.print("`{s}`", .{param});
                        }
                        try writer.print("\n\n", .{});
                    }
                }
                
                try writer.print("Methods:\n", .{});
                var method_iter = interface_def.methods.iterator();
                while (method_iter.next()) |method_entry| {
                    const method_name = method_entry.key_ptr.*;
                    const method_sig = method_entry.value_ptr;
                    
                    try writer.print("- `{s}(", .{method_name});
                    for (method_sig.args.items, 0..) |arg_type, i| {
                        if (i > 0) try writer.print(", ", .{});
                        try writer.print("{s}", .{self.typeToString(arg_type)});
                    }
                    try writer.print(") -> {s}`\n", .{self.typeToString(method_sig.@"return")});
                }
                try writer.print("\n", .{});
            }
        }
        
        print("Documentation written to: {s}\n", .{output_filename});
    }
    
    fn getDocOutputFilename(self: *SeverCompiler, input_file: []const u8) ![]u8 {
        const basename = std.fs.path.basename(input_file);
        const extension_start = std.mem.lastIndexOf(u8, basename, ".") orelse basename.len;
        const base_name = basename[0..extension_start];
        return try std.fmt.allocPrint(self.allocator, "{s}.md", .{base_name});
    }
    
    fn typeToString(self: *SeverCompiler, type_info: SirsParser.Type) []const u8 {
        _ = self;
        return switch (type_info) {
            .void => "void",
            .bool => "bool",
            .i8, .i16, .i32, .i64 => "int",
            .u8, .u16, .u32, .u64 => "uint",
            .f32, .f64 => "float",
            .str => "str",
            .array => "Array",
            .slice => "Slice",
            .@"struct" => "Struct",
            .@"union" => "Union",
            .discriminated_union => |d| d.name,
            .@"enum" => |e| e.name,
            .@"error" => |e| e.name,
            .hashmap => "HashMap",
            .set => "Set",
            .tuple => "Tuple",
            .record => |r| r.name,
            .optional => "Optional",
            .function => "Function",
            .distribution => "Distribution",
            .type_parameter => |tp| tp,
            .generic_instance => |g| g.base_type,
            .@"interface" => |i| i.name,
            .trait_object => |t| t.trait_name,
        };
    }

    fn validateTestOutput(self: *SeverCompiler, output: []const u8) !void {
        // For now, we'll implement a simple test validation:
        // - If the program outputs anything to stdout, we consider it a test result
        // - Empty output means the test passed silently
        // - In the future, we could implement a more sophisticated test format
        
        print("Program output ({} bytes):\n", .{output.len});
        if (output.len > 0) {
            print("{s}\n", .{output});
        } else {
            print("(no output)\n", .{});
        }
        
        // Check for common test patterns or error indicators
        if (std.mem.indexOf(u8, output, "error") != null or 
           std.mem.indexOf(u8, output, "failed") != null or
           std.mem.indexOf(u8, output, "FAIL") != null) {
            try self.error_reporter.reportWarning(
                null,
                "Program output contains potential error indicators",
                .{}
            );
        }
        
        // In a more advanced implementation, we could:
        // 1. Parse structured test output (JSON/TAP format)
        // 2. Look for specific test assertions
        // 3. Count passed/failed test cases
        // 4. Generate test reports
    }
};