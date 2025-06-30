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
- **Composite types**: Arrays, slices, structs, optionals
- **Type inference** - explicit when needed, inferred when clear
- **Memory safety** - no manual memory management required

### Probabilistic Programming
Built-in support for statistical computing with native distributions and sampling

### Standard Library
Essential functions for I/O, mathematical operations, and system interaction

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

# Type check without compilation  
sev check program.sirs.json

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
│   └── monte_carlo_pi.sirs.json
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