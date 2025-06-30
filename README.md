# Sever Programming Language

**The first AI-first, human-agnostic programming language designed for LLMs to write complete programs.**

Sever (Severlang) is a revolutionary programming language that abandons traditional text-based syntax in favor of structured intermediate representation (SIRS), enabling Large Language Models to write, understand, and manipulate programs with unprecedented precision and capability.

## 🚀 Quick Start

```bash
# Clone and build
git clone <repository-url>
cd sever1
zig build

# Compile a Sever program
./zig-out/bin/sev build examples/simple_math.sirs.json

# Run the compiled binary
./simple_math
# Output: 230
```

## 🎯 Design Philosophy

### AI-First, Human-Agnostic
- **No text syntax parsing errors** - LLMs work with structured JSON instead of fragile text
- **Semantic clarity** - Every construct has explicit, unambiguous meaning  
- **Composable abstractions** - Programs are built from well-defined, composable units
- **Tool-native** - Designed for programmatic generation and manipulation

### Core Principles
1. **Statically compiled** to efficient native binaries
2. **Type-safe** with strong inference and memory safety
3. **Probabilistic-first** with built-in statistical primitives
4. **Bootstrappable** - first compiler in Zig, future versions in Sever itself
5. **LLM-native** via Model Context Protocol (MCP) integration

## 🏗️ Language Features

### Static Type System
- **Primitive types**: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, `u64`, `f32`, `f64`, `bool`, `str`
- **Composite types**: Arrays, slices, structs, tuples, records, hash maps, sets
- **Advanced types**: Enums with associated values, union types, optional types
- **Generics**: Parametric types with type parameters and instances
- **Interface/trait system**: Dynamic dispatch with vtables
- **Type inference** - explicit when needed, inferred when clear
- **Memory safety** - no manual memory management required

### Control Flow & Pattern Matching
- **Pattern matching**: Exhaustive pattern checking with return analysis
- **Exception handling**: try/catch/finally blocks with custom error types
- **Control structures**: If/else, while/for loops, match expressions

### Probabilistic Programming
Built-in support for statistical computing with native distributions and sampling

### Comprehensive Standard Library
- **HTTP client**: `http_get`, `http_post`, `http_put`, `http_delete`
- **File I/O**: Complete file system operations (`file_read`, `file_write`, `dir_create`, etc.)
- **JSON support**: Parsing, serialization, and data extraction
- **String manipulation**: 11 string functions (`str_length`, `str_contains`, `str_trim`, etc.)
- **Mathematical operations**: Built-in arithmetic and statistical functions

## 🏗️ Architecture

### SIRS (Sever Intermediate Representation Schema)
Instead of parsing text, Sever programs are written in structured JSON:

```json
{
  "program": {
    "entry": "main",
    "functions": {
      "main": {
        "args": [],
        "return": "i32",
        "body": [
          {
            "let": {
              "name": "result",
              "type": "i32", 
              "value": {
                "op": {
                  "kind": "add",
                  "args": [{"literal": 10}, {"literal": 20}]
                }
              }
            }
          },
          {
            "return": {"var": "result"}
          }
        ]
      }
    }
  }
}
```

### Compilation Pipeline
```
SIRS JSON → Parser → Type Checker → Code Generator → Native Binary
    ↓           ↓          ↓             ↓              ↓
   AST      Validation   Types      Zig Source     Executable
```

### Compiler Components
1. **SIRS Parser** (`sirs.zig`) - Parses JSON-based intermediate representation
2. **Type Checker** (`typechecker.zig`) - Validates program correctness and infers types  
3. **Code Generator** (`codegen.zig`) - Emits native Zig code for compilation
4. **Runtime Library** (`runtime/`) - Provides probabilistic programming primitives
5. **MCP Server** (`mcp.zig`) - Enables LLM interaction and introspection

## 🛠️ Tools

### CLI Compiler (`sev`)
```bash
# Compile SIRS to native binary
sev build program.sirs.json

# Run tests on SIRS program
sev test program.sirs.json

# Generate documentation  
sev doc program.sirs.json

# Start MCP server for LLM integration
sev serve
```

### MCP Integration
Sever includes a Model Context Protocol server that exposes tools for LLMs:
- `compile` - Compile SIRS programs to binaries
- `type_check` - Validate program types
- `infer_type` - Infer expression types

## 🚀 Building from Source

```bash
# Clone repository
git clone <repository-url>
cd sever1

# Build compiler
zig build

# Run tests
zig build test

# Install globally (optional)
zig build --prefix /usr/local install
```

## 🔬 Examples

### Simple Math
```json
{
  "program": {
    "entry": "main",
    "functions": {
      "main": {
        "args": [],
        "return": "i32",
        "body": [
          {"let": {"name": "a", "type": "i32", "value": {"literal": 10}}},
          {"let": {"name": "b", "type": "i32", "value": {"literal": 20}}},
          {"return": {"op": {"kind": "add", "args": [{"var": "a"}, {"var": "b"}]}}}
        ]
      }
    }
  }
}
```

### Probabilistic Computing
```json
{
  "let": {
    "name": "random_value",
    "value": {
      "sample": {
        "distribution": "normal", 
        "params": [{"literal": 0.0}, {"literal": 1.0}]
      }
    }
  }
}
```

### Function Calls
```json
{
  "call": {
    "function": "std_print",
    "args": [{"literal": "Hello, World!"}]
  }
}
```

## 📊 Probabilistic Programming

Built-in support for statistical computing:

Supported distributions:
- `uniform(min, max)` - Uniform distribution
- `normal(mean, std)` - Normal/Gaussian distribution  
- `bernoulli(p)` - Bernoulli distribution
- `categorical(probs)` - Categorical distribution
- `exponential(rate)` - Exponential distribution
- `gamma(shape, scale)` - Gamma distribution
- `beta(alpha, beta)` - Beta distribution

Built-in functions:
- `std_print(message: str)` - Print string
- `std_print_int(value: i32)` - Print integer
- `std_print_float(value: f64)` - Print float

### HTTP Client
- `http_get(url: str) -> str` - HTTP GET request
- `http_post(url: str, body: str) -> str` - HTTP POST request
- `http_put(url: str, body: str) -> str` - HTTP PUT request
- `http_delete(url: str) -> str` - HTTP DELETE request

### File I/O Operations
- `file_read(path: str) -> str` - Read file contents
- `file_write(path: str, content: str) -> bool` - Write file
- `file_append(path: str, content: str) -> bool` - Append to file
- `file_exists(path: str) -> bool` - Check file existence
- `file_delete(path: str) -> bool` - Delete file
- `file_size(path: str) -> i64` - Get file size
- `dir_create(path: str) -> bool` - Create directory
- `dir_exists(path: str) -> bool` - Check directory existence
- `dir_list(path: str) -> str` - List directory contents

### JSON Processing
- `json_parse(json: str) -> str` - Parse and format JSON
- `json_get_string(json: str, key: str) -> str` - Extract string value
- `json_get_number(json: str, key: str) -> f64` - Extract number value
- `json_get_bool(json: str, key: str) -> bool` - Extract boolean value
- `json_has_key(json: str, key: str) -> bool` - Check key existence

### String Manipulation
- `str_length(s: str) -> i32` - Get string length
- `str_substring(s: str, start: i64, end: i64) -> str` - Extract substring
- `str_contains(s: str, needle: str) -> bool` - Check substring
- `str_starts_with(s: str, prefix: str) -> bool` - Check prefix
- `str_ends_with(s: str, suffix: str) -> bool` - Check suffix
- `str_index_of(s: str, needle: str) -> i64` - Find substring position
- `str_replace(s: str, needle: str, replacement: str) -> str` - Replace all occurrences
- `str_to_upper(s: str) -> str` - Convert to uppercase
- `str_to_lower(s: str) -> str` - Convert to lowercase
- `str_trim(s: str) -> str` - Remove whitespace
- `str_equals(a: str, b: str) -> bool` - Compare strings

## 📁 Project Structure

```
sever1/
├── src/
│   ├── main.zig          # CLI entry point
│   ├── sirs.zig          # SIRS parser and AST
│   ├── typechecker.zig   # Type system
│   ├── codegen.zig       # Code generation
│   ├── compiler.zig      # Compilation coordinator
│   └── mcp.zig           # MCP server
├── runtime/
│   └── sever_runtime.zig # Probabilistic runtime
├── examples/
│   ├── simple_math.sirs.json
│   ├── hello_world.sirs.json
│   ├── fibonacci.sirs.json
│   ├── monte_carlo_pi.sirs.json
│   ├── pattern_matching_test.sirs.json
│   ├── enum_test.sirs.json
│   ├── exception_test.sirs.json
│   ├── collections_test.sirs.json
│   ├── tuples_records_test.sirs.json
│   ├── generics_test.sirs.json
│   ├── interfaces_test.sirs.json
│   ├── http_test.sirs.json
│   ├── file_io_test.sirs.json
│   ├── json_test.sirs.json
│   ├── json_http_test.sirs.json
│   └── string_test.sirs.json
├── sirs-spec.json        # Complete SIRS schema
├── build.zig            # Zig build configuration
├── README.md            # This file
└── ROADMAP.md           # Development roadmap
```

## 🎯 Why Sever?

### For LLMs
- **Elimination of syntax errors** - No more malformed code generation
- **Semantic precision** - Every construct has explicit, unambiguous meaning
- **Composable generation** - Build programs incrementally with confidence
- **Built-in tooling** - Native integration via MCP protocol

### For Developers  
- **Native performance** - Compiles to efficient machine code
- **Type safety** - Catch errors at compile time
- **Modern features** - Memory safety, type inference, probabilistic primitives
- **Tool ecosystem** - Designed for programmatic manipulation

### For Research
- **Novel paradigm** - Explore structured programming beyond text
- **AI-native design** - Study how languages can be optimized for LLM use
- **Probabilistic computing** - Built-in support for statistical programming
- **Bootstrapping studies** - Self-hosting compiler development

## 🔧 Requirements

- **Zig 0.14.1+** - Primary implementation language
- **Modern OS** - macOS, Linux, or Windows with Zig support
- **Git** - For source code management

## 🤝 Contributing

Sever is an experimental language exploring the intersection of AI and programming languages. Contributions are welcome in areas including:

- **Language design** - New features and syntax proposals
- **Runtime optimization** - Performance improvements
- **Tooling** - IDE support, debugging tools, linting
- **Documentation** - Examples, tutorials, specification improvements
- **Testing** - Test cases, benchmarks, validation

## 📄 License

[Insert chosen license - e.g., MIT, Apache 2.0, etc.]

## 🙏 Acknowledgments

- **Zig language** - Foundation for the compiler implementation
- **Model Context Protocol** - Framework for LLM tool integration
- **Statistical computing community** - Inspiration for probabilistic primitives

---

*Sever represents a fundamental rethinking of how programming languages can be designed for the age of AI. By abandoning text-based syntax in favor of structured representation, we unlock new possibilities for both human and artificial intelligence to create software.*