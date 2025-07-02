const std = @import("std");
const Allocator = std.mem.Allocator;

const sirs = @import("sirs.zig");
const sirs_l = @import("sirs_l.zig");
const sirs_l_gen = @import("sirs_l_generator.zig");

/// Convert between SIRS JSON and SIRS-L formats
pub const Converter = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) Converter {
        return Converter{
            .allocator = allocator,
        };
    }
    
    /// Convert JSON to SIRS-L
    pub fn jsonToSirsL(self: *Converter, json_source: []const u8) ![]const u8 {
        // Parse JSON to AST
        var parser = sirs.Parser.init(self.allocator, json_source);
        const program = try parser.parse(json_source);
        defer parser.deinit();
        
        // Generate SIRS-L from AST
        return try sirs_l_gen.generate(self.allocator, &program);
    }
    
    /// Convert SIRS-L to JSON
    pub fn sirsLToJson(self: *Converter, sirs_l_source: []const u8) ![]const u8 {
        // Parse SIRS-L to AST
        const program = try sirs_l.parse(self.allocator, sirs_l_source);
        
        // Generate JSON from AST
        var json_buffer = std.ArrayList(u8).init(self.allocator);
        defer json_buffer.deinit();
        
        // Use the existing JSON serialization
        try std.json.stringify(program, .{ .whitespace = .{ .indent = .{.space = 2} } }, json_buffer.writer());
        
        return json_buffer.toOwnedSlice();
    }
};

/// Benchmark token usage between formats
pub const TokenBenchmark = struct {
    json_tokens: usize,
    sirs_l_tokens: usize,
    json_bytes: usize,
    sirs_l_bytes: usize,
    reduction_percentage: f64,
    
    pub fn format(self: TokenBenchmark, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        
        try writer.print(
            \\Token Usage Benchmark:
            \\----------------------
            \\JSON Format:
            \\  Tokens: {}
            \\  Bytes: {}
            \\
            \\SIRS-L Format:
            \\  Tokens: {}
            \\  Bytes: {}
            \\
            \\Reduction: {d:.1}% fewer tokens
            \\Space savings: {d:.1}% smaller
            \\
        , .{
            self.json_tokens,
            self.json_bytes,
            self.sirs_l_tokens,
            self.sirs_l_bytes,
            self.reduction_percentage,
            @as(f64, @floatFromInt(self.json_bytes - self.sirs_l_bytes)) / @as(f64, @floatFromInt(self.json_bytes)) * 100,
        });
    }
};

/// Compare token usage between JSON and SIRS-L
pub fn benchmarkTokenUsage(allocator: Allocator, json_source: []const u8) !TokenBenchmark {
    var converter = Converter.init(allocator);
    
    // Convert to SIRS-L
    const sirs_l_source = try converter.jsonToSirsL(json_source);
    defer allocator.free(sirs_l_source);
    
    // Estimate token counts
    const json_tokens = estimateJsonTokens(json_source);
    const sirs_l_tokens = sirs_l_gen.estimateTokenCount(sirs_l_source);
    
    const reduction = @as(f64, @floatFromInt(json_tokens - sirs_l_tokens)) / @as(f64, @floatFromInt(json_tokens)) * 100;
    
    return TokenBenchmark{
        .json_tokens = json_tokens,
        .sirs_l_tokens = sirs_l_tokens,
        .json_bytes = json_source.len,
        .sirs_l_bytes = sirs_l_source.len,
        .reduction_percentage = reduction,
    };
}

/// Estimate token count for JSON (rough approximation)
fn estimateJsonTokens(json_source: []const u8) usize {
    var count: usize = 0;
    var in_string = false;
    var i: usize = 0;
    
    while (i < json_source.len) {
        if (json_source[i] == '"' and (i == 0 or json_source[i-1] != '\\')) {
            in_string = !in_string;
            count += 1; // Count quotes as tokens
        }
        
        if (!in_string) {
            switch (json_source[i]) {
                ' ', '\n', '\r', '\t' => {
                    // Whitespace doesn't count
                },
                '{', '}', '[', ']', ':', ',' => {
                    count += 1; // JSON structural tokens
                },
                else => {
                    // Start of a value/key
                    if (i == 0 or std.ascii.isWhitespace(json_source[i-1]) or
                        json_source[i-1] == ':' or json_source[i-1] == ',' or
                        json_source[i-1] == '{' or json_source[i-1] == '[') {
                        count += 1;
                        
                        // Skip to end of token
                        while (i < json_source.len and !std.ascii.isWhitespace(json_source[i]) and
                               json_source[i] != ':' and json_source[i] != ',' and
                               json_source[i] != '}' and json_source[i] != ']' and
                               json_source[i] != '"') {
                            i += 1;
                        }
                        i -= 1;
                    }
                },
            }
        } else {
            // Inside string - count the whole string as one token
            while (i < json_source.len - 1 and json_source[i] != '"') {
                if (json_source[i] == '\\') i += 1; // Skip escaped char
                i += 1;
            }
        }
        
        i += 1;
    }
    
    return count;
}