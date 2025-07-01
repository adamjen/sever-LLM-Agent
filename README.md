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
./dist/sev build examples/simple_math.sirs.json

# Run the compiled binary
./dist/simple_math
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
- **Exception handling**: try/catch/finally blocks with custom error types and Result<T,E> types
- **Control structures**: If/else, while/for loops with break/continue validation, match expressions

### Probabilistic Programming
Built-in support for statistical computing with native distributions, custom distribution definitions, and advanced sampling capabilities

### Comprehensive Standard Library
- **HTTP client**: `http_get`, `http_post`, `http_put`, `http_delete`
- **File I/O**: Complete file system operations (`file_read`, `file_write`, `dir_create`, etc.)
- **JSON support**: Parsing, serialization, and data extraction
- **String manipulation**: 11 string functions (`str_length`, `str_contains`, `str_trim`, etc.)
- **Mathematical operations**: Comprehensive 39-function math library (`math_sqrt`, `math_sin`, `math_cos`, `math_pow`, `math_log`, etc.)

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
SIRS JSON → Parser → Type Checker → CIR Lowering → Optimizer → Code Generator → Native Binary
    ↓           ↓          ↓            ↓             ↓            ↓              ↓
   AST      Validation   Types     Core IR     Optimized IR   Zig Source     Executable
```

### Phase 2 Optimizations
The compiler includes advanced optimization passes:
- **Dead Code Elimination** - Removes unreachable blocks and unused instructions
- **Constant Folding & Propagation** - Evaluates constants at compile time with iterative propagation
- **Function Inlining** - Replaces small function calls with function bodies using smart heuristics

### Compiler Components
1. **SIRS Parser** (`sirs.zig`) - Parses JSON-based intermediate representation
2. **Type Checker** (`typechecker.zig`) - Validates program correctness and infers types  
3. **CIR Lowering** (`cir.zig`) - Converts to Core Intermediate Representation
4. **Optimizer** (`optimization.zig`) - Advanced optimization passes (dead code elimination, constant folding, function inlining)
5. **Code Generator** (`codegen.zig`) - Emits native Zig code for compilation
6. **Formatter** (`formatter.zig`) - Pretty-prints SIRS JSON with consistent style
7. **Runtime Library** (`runtime/`) - Provides probabilistic programming primitives
8. **MCP Server** (`mcp.zig`) - Enables LLM interaction and introspection

## 🛠️ Tools

### CLI Compiler (`sev`)
```bash
# Compile SIRS to native binary (outputs to dist/)
./dist/sev build program.sirs.json

# Run tests on SIRS program
./dist/sev test program.sirs.json

# Generate documentation  
./dist/sev doc program.sirs.json

# Format SIRS code with consistent style
./dist/sev fmt program.sirs.json

# Start interactive REPL mode
./dist/sev repl

# Start MCP server for LLM integration
./dist/sev serve
```

### MCP Integration
Sever includes a comprehensive Model Context Protocol server that exposes advanced tools for LLMs:

**Core Compilation Tools:**
- `compile` - Compile SIRS programs with detailed analysis
- `type_check` - Comprehensive type checking with error reporting
- `infer_type` - Infer types of SIRS expressions
- `analyze_program` - Comprehensive program analysis with complexity metrics
- `optimize_analysis` - Analyze optimization opportunities with estimated benefits
- `function_info` - Detailed function parameter and signature analysis

**AST Analysis and Manipulation Tools:**
- `query_functions` - Find functions matching patterns with detailed metadata
- `query_variables` - Locate and analyze variable usage throughout code
- `query_function_calls` - Track function call relationships and dependencies
- `get_function_info` - Extract comprehensive function signatures and properties
- `rename_function` - Safely rename functions across the entire codebase
- `add_function` - Insert new functions with proper signature validation
- `remove_function` - Delete functions while checking for dependencies
- `analyze_complexity` - Calculate cyclomatic complexity and maintainability metrics

**Dependency Analysis Tools:**
- `analyze_dependencies` - Comprehensive dependency mapping with health metrics
- `find_circular_dependencies` - Detect and analyze circular references with break suggestions
- `find_unused_functions` - Identify dead code and optimization opportunities
- `get_dependency_graph` - Generate visual dependency graphs (JSON, DOT, Mermaid formats)
- `analyze_function_dependencies` - Deep-dive into specific function relationships
- `check_dependency_health` - Overall codebase health scoring and recommendations
- `get_reachability_analysis` - Analyze code reachability from entry points

**Custom Distribution Tools (Probabilistic Programming):**
- `create_custom_distribution` - Define new probability distributions with parameters and constraints
- `compile_distributions_from_sirs` - Extract distribution definitions from existing SIRS code
- `list_distributions` - Browse all available built-in and custom distributions
- `get_distribution_info` - Detailed distribution properties, parameters, and usage examples
- `validate_distribution_parameters` - Check parameter validity against distribution constraints
- `generate_distribution_code` - Generate SIRS implementation code for distributions
- `create_mixture_distribution` - Compose mixture models from existing distributions
- `validate_distribution_definition` - Verify distribution mathematical correctness

### Interactive Development
- **REPL Mode** - Interactive evaluation of SIRS expressions with JSON syntax
- **Code Formatter** - Consistent, deterministic formatting with proper indentation
- **Rich Analysis** - Complexity scoring, optimization recommendations, and performance insights

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

**Built-in Distributions:**
- `uniform(min, max)` - Uniform distribution
- `normal(mean, std)` - Normal/Gaussian distribution  
- `bernoulli(p)` - Bernoulli distribution
- `categorical(probs)` - Categorical distribution
- `exponential(rate)` - Exponential distribution
- `gamma(shape, scale)` - Gamma distribution
- `beta(alpha, beta)` - Beta distribution

**Custom Distribution System:**
- **Distribution Builder** - Fluent API for defining custom probability distributions
- **Parameter Constraints** - Type-safe parameter validation with bounds, positivity, and custom validators
- **Support Specification** - Define mathematical domains (real line, positive real, unit interval, discrete sets, etc.)
- **Parameter Transformations** - Built-in transformations (log, exp, logit, sigmoid, softmax, Cholesky)
- **Exponential Family Support** - Sufficient statistics and natural parameter specifications
- **Mixture Models** - Compose distributions with weighted components
- **Example Distributions** - Pre-built: Beta-Binomial, Gaussian Mixture, Student's t, Dirichlet
- **Code Generation** - Automatic SIRS code generation from distribution definitions
- **Validation Framework** - Mathematical correctness checking and constraint verification

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

### Mathematical Functions
Comprehensive mathematical library with 39 functions covering all major mathematical operations:

**Basic Operations:**
- `math_abs(x: f64) -> f64` - Absolute value
- `math_sqrt(x: f64) -> f64` - Square root
- `math_pow(base: f64, exp: f64) -> f64` - Power function
- `math_exp(x: f64) -> f64` - Exponential function
- `math_min(x: f64, y: f64) -> f64` - Minimum value
- `math_max(x: f64, y: f64) -> f64` - Maximum value

**Trigonometric Functions:**
- `math_sin(x: f64) -> f64` - Sine
- `math_cos(x: f64) -> f64` - Cosine
- `math_tan(x: f64) -> f64` - Tangent
- `math_asin(x: f64) -> f64` - Arcsine
- `math_acos(x: f64) -> f64` - Arccosine
- `math_atan(x: f64) -> f64` - Arctangent
- `math_atan2(y: f64, x: f64) -> f64` - Two-argument arctangent

**Hyperbolic Functions:**
- `math_sinh(x: f64) -> f64` - Hyperbolic sine
- `math_cosh(x: f64) -> f64` - Hyperbolic cosine
- `math_tanh(x: f64) -> f64` - Hyperbolic tangent

**Logarithmic Functions:**
- `math_log(x: f64) -> f64` - Natural logarithm
- `math_log10(x: f64) -> f64` - Base-10 logarithm
- `math_log2(x: f64) -> f64` - Base-2 logarithm

**Rounding Functions:**
- `math_floor(x: f64) -> f64` - Floor function
- `math_ceil(x: f64) -> f64` - Ceiling function
- `math_round(x: f64) -> f64` - Round to nearest integer
- `math_trunc(x: f64) -> f64` - Truncate towards zero

**Advanced Operations:**
- `math_fmod(x: f64, y: f64) -> f64` - Floating-point remainder
- `math_remainder(x: f64, y: f64) -> f64` - IEEE remainder
- `math_clamp(value: f64, min: f64, max: f64) -> f64` - Clamp value to range
- `math_lerp(a: f64, b: f64, t: f64) -> f64` - Linear interpolation
- `math_copysign(magnitude: f64, sign: f64) -> f64` - Copy sign
- `math_sign(x: f64) -> f64` - Sign function

**Constants and Utilities:**
- `math_pi() -> f64` - π constant
- `math_e() -> f64` - Euler's number
- `math_inf() -> f64` - Positive infinity
- `math_nan() -> f64` - Not-a-Number
- `math_degrees(radians: f64) -> f64` - Convert radians to degrees
- `math_radians(degrees: f64) -> f64` - Convert degrees to radians

**Predicates:**
- `math_is_finite(x: f64) -> bool` - Check if finite
- `math_is_infinite(x: f64) -> bool` - Check if infinite
- `math_is_nan(x: f64) -> bool` - Check if NaN

## 📁 Project Structure

```
sever1/
├── src/
│   ├── main.zig          # CLI entry point
│   ├── sirs.zig          # SIRS parser and AST
│   ├── typechecker.zig   # Type system
│   ├── cir.zig           # Core Intermediate Representation
│   ├── optimization.zig  # Optimization passes (DCE, constant folding, inlining)
│   ├── codegen.zig       # Code generation
│   ├── formatter.zig     # SIRS code formatter
│   ├── compiler.zig      # Compilation coordinator
│   ├── cli.zig           # Command-line interface
│   ├── error_reporter.zig # Error reporting and diagnostics
│   ├── mcp.zig           # MCP server with advanced introspection
│   ├── ast_query.zig     # AST querying and manipulation engine
│   ├── mcp_ast_tools.zig # MCP tools for AST operations
│   ├── dependency_analyzer.zig # Code dependency analysis engine
│   ├── mcp_dependency_tools.zig # MCP tools for dependency analysis
│   ├── custom_distributions.zig # Custom distribution framework
│   ├── distribution_compiler.zig # Distribution code compiler
│   ├── mcp_distribution_tools.zig # MCP tools for probabilistic programming
│   ├── test_custom_distributions.zig # Distribution system tests
│   ├── test_mcp_distribution_tools.zig # MCP distribution tool tests
│   └── test_distribution_compiler.zig # Distribution compiler tests
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