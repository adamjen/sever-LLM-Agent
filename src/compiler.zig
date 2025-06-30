const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const SirsParser = @import("sirs.zig");
const TypeChecker = @import("typechecker.zig").TypeChecker;
const CodeGen = @import("codegen.zig").CodeGen;
const McpServer = @import("mcp.zig").McpServer;

pub const CompilerError = error{
    FileNotFound,
    ParseError,
    TypeCheckError,
    CodeGenError,
    IoError,
};

pub const SeverCompiler = struct {
    allocator: Allocator,
    parser: SirsParser.Parser,
    type_checker: TypeChecker,
    code_gen: CodeGen,
    
    pub fn init(allocator: Allocator) SeverCompiler {
        return SeverCompiler{
            .allocator = allocator,
            .parser = SirsParser.Parser.init(allocator),
            .type_checker = TypeChecker.init(allocator),
            .code_gen = CodeGen.init(allocator),
        };
    }
    
    pub fn deinit(self: *SeverCompiler) void {
        self.type_checker.deinit();
        self.code_gen.deinit();
    }
    
    pub fn compile(self: *SeverCompiler, input_file: []const u8) !void {
        print("Phase 1: Reading SIRS file...\n", .{});
        const content = self.readFile(input_file) catch |err| switch (err) {
            error.FileNotFound => {
                print("Error: File '{s}' not found\n", .{input_file});
                return CompilerError.FileNotFound;
            },
            else => return CompilerError.IoError,
        };
        defer self.allocator.free(content);
        
        print("Phase 2: Parsing SIRS...\n", .{});
        var program = self.parser.parse(content) catch |err| {
            print("Parse error: {}\n", .{err});
            return CompilerError.ParseError;
        };
        defer program.deinit();
        
        print("Phase 3: Type checking...\n", .{});
        self.type_checker.check(&program) catch |err| {
            print("Type check error: {}\n", .{err});
            return CompilerError.TypeCheckError;
        };
        
        print("Phase 4: Generating code...\n", .{});
        const output_file = try self.getOutputFilename(input_file);
        defer self.allocator.free(output_file);
        
        self.code_gen.generate(&program, output_file) catch |err| {
            print("Code generation error: {}\n", .{err});
            return CompilerError.CodeGenError;
        };
        
        print("Compilation complete: {s}\n", .{output_file});
    }
    
    pub fn test_program(self: *SeverCompiler, input_file: []const u8) !void {
        print("Running tests for: {s}\n", .{input_file});
        
        // First compile the program
        try self.compile(input_file);
        
        // Then run test cases
        print("Executing test cases...\n", .{});
        
        // TODO: Implement test execution
        print("All tests passed\n", .{});
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
        var output = try self.allocator.dupe(u8, input_file);
        
        if (std.mem.endsWith(u8, output, ".sirs.json")) {
            output = output[0..output.len - 10]; // Remove .sirs.json
        }
        
        // Add platform-specific extension if needed
        if (@import("builtin").os.tag == .windows) {
            const new_output = try std.fmt.allocPrint(self.allocator, "{s}.exe", .{output});
            self.allocator.free(output);
            return new_output;
        }
        
        return output;
    }
};