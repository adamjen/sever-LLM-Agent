const std = @import("std");
const Allocator = std.mem.Allocator;
const sirs = @import("sirs.zig");
const sev_simple = @import("sev_simple.zig");
const sev_gen = @import("sev_generator.zig");

/// Convert between SIRS JSON and SEV formats
pub const Converter = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Converter {
        return Converter{ .allocator = allocator };
    }

    /// Convert SIRS JSON to SEV format
    pub fn jsonToSev(self: *Converter, json_input: []const u8) ![]const u8 {
        // Parse JSON to AST
        var parser = sirs.Parser.init(self.allocator);
        const program = try parser.parse(json_input);
        
        // Generate SEV from AST
        return try sev_gen.generateSev(self.allocator, program);
    }

    /// Convert SEV to SIRS JSON format
    pub fn sevToJson(self: *Converter, sev_input: []const u8) ![]const u8 {
        // For now, just create a simple JSON representation
        // TODO: Proper AST to JSON conversion when needed
        const json_template = 
            \\{{
            \\  "program": {{
            \\    "entry": "main",
            \\    "functions": {{
            \\      "main": {{
            \\        "args": [],
            \\        "return": "i32",
            \\        "body": [
            \\          {{"comment": "Converted from SEV: {s}"}}
            \\        ]
            \\      }}
            \\    }}
            \\  }}
            \\}}
        ;
        
        return try std.fmt.allocPrint(self.allocator, json_template, .{sev_input});
    }
};

/// Benchmark token usage between formats
pub const TokenBenchmark = struct {
    json_tokens: usize,
    sev_tokens: usize,
    json_bytes: usize,
    sev_bytes: usize,
    token_reduction_percent: f64,
    size_reduction_percent: f64,
    
    pub fn format(self: TokenBenchmark, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        
        try writer.print(
            \\Token Usage Benchmark:
            \\======================
            \\JSON Format:
            \\  Tokens: {}
            \\  Bytes: {}
            \\
            \\SEV Format:
            \\  Tokens: {}
            \\  Bytes: {}
            \\
            \\Improvements:
            \\  Token reduction: {d:.1}%
            \\  Size reduction: {d:.1}%
            \\  Compression ratio: {d:.1}x smaller
            \\
        , .{
            self.json_tokens,
            self.json_bytes,
            self.sev_tokens,
            self.sev_bytes,
            self.token_reduction_percent,
            self.size_reduction_percent,
            @as(f64, @floatFromInt(self.json_bytes)) / @as(f64, @floatFromInt(self.sev_bytes)),
        });
    }
};

/// Compare token usage between JSON and SEV
pub fn benchmarkTokenUsage(allocator: Allocator, json_source: []const u8) !TokenBenchmark {
    var converter = Converter.init(allocator);
    
    // Convert to SEV
    const sev_source = try converter.jsonToSev(json_source);
    defer allocator.free(sev_source);
    
    // Estimate token counts
    const json_tokens = estimateJsonTokens(json_source);
    const sev_tokens = estimateSevTokens(sev_source);
    
    const token_reduction = if (json_tokens > 0) blk: {
        if (sev_tokens > json_tokens) {
            // SEV is somehow larger, show negative reduction
            const increase = sev_tokens - json_tokens;
            break :blk -@as(f64, @floatFromInt(increase)) / @as(f64, @floatFromInt(json_tokens)) * 100.0;
        } else {
            break :blk @as(f64, @floatFromInt(json_tokens - sev_tokens)) / @as(f64, @floatFromInt(json_tokens)) * 100.0;
        }
    } else 0.0;
        
    const size_reduction = if (json_source.len > 0)
        @as(f64, @floatFromInt(json_source.len - sev_source.len)) / @as(f64, @floatFromInt(json_source.len)) * 100.0
    else
        0.0;
    
    return TokenBenchmark{
        .json_tokens = json_tokens,
        .sev_tokens = sev_tokens,
        .json_bytes = json_source.len,
        .sev_bytes = sev_source.len,
        .token_reduction_percent = token_reduction,
        .size_reduction_percent = size_reduction,
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

/// Estimate token count for SEV format
fn estimateSevTokens(sev_source: []const u8) usize {
    var tokens: usize = 0;
    var i: usize = 0;
    
    while (i < sev_source.len) {
        const ch = sev_source[i];
        
        // Single character operators/delimiters = 1 token each
        if (ch == '+' or ch == '-' or ch == '*' or ch == '/' or 
            ch == '=' or ch == '<' or ch == '>' or ch == '(' or ch == ')' or
            ch == '[' or ch == ']' or ch == '|' or ch == ';' or ch == ',' or
            ch == ':' or ch == '?' or ch == 'P' or ch == 'D' or ch == 'L' or
            ch == 'R' or ch == 'I' or ch == 'F' or ch == 'B' or ch == 'S' or
            ch == 'C' or ch == 'W') {
            tokens += 1;
            i += 1;
        } else if (std.ascii.isAlphanumeric(ch) or ch == '_') {
            // Identifiers and numbers count as single tokens
            tokens += 1;
            while (i < sev_source.len and (std.ascii.isAlphanumeric(sev_source[i]) or sev_source[i] == '_' or sev_source[i] == '.')) {
                i += 1;
            }
        } else {
            i += 1;
        }
    }
    
    return tokens;
}