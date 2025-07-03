# Technical Architecture

## System Components
- **Compiler**: Handles source code compilation for SIRS language
- **MCMC Engine**: Implements Markov Chain Monte Carlo algorithms
- **Dependency Analyzer**: Manages package dependencies
- **AST Query Tool**: Provides access to abstract syntax trees
- **Code Generator**: Translates high-level constructs to target formats

## Architecture Diagram
[Insert architecture diagram here]

## Module Relationships
- Compiler interacts with MCMC Engine for probabilistic inference
- Dependency Analyzer integrates with AST Query Tool for semantic analysis
- Code Generator uses compiler output for format translation

## Detailed Component Descriptions
- **Compiler (`compiler.zig`)**: Converts SIRS language source code into executable binaries. It orchestrates parsing, CIR lowering, and code generation.
- **MCMC Engine (`mcmc.zig`)**: Implements Markov Chain Monte Carlo algorithms for probabilistic inference. Includes `MCMCSampler` and `HMCSampler` for different sampling methods, and `ConvergenceDiagnostics`.
- **Dependency Analyzer (`dependency_analyzer.zig`)**: Identifies and manages package dependencies within the SIRS program, including detection of circular dependencies and unused functions.
- **AST Query Tool (`ast_query.zig`)**: Provides functionalities to query and manipulate Abstract Syntax Trees (AST), including finding functions, variables, and function calls, and performing AST transformations.
- **Code Generator (`codegen.zig`)**: Translates high-level SIRS constructs into target formats (currently Zig code).
- **CIR Lowering (`cir.zig`)**: Lowers the SIRS AST into a Common Intermediate Representation (CIR) for further optimization and code generation.
- **Custom Distributions (`custom_distributions.zig`)**: Manages and registers custom probability distributions, allowing for their definition and use within the SIRS language.
- **Debugger (`debugger.zig`)**: Provides debugging functionalities such as setting breakpoints, managing symbols, and inspecting call stacks.
- **Distribution Compiler (`distribution_compiler.zig`)**: Compiles custom distributions defined in SIRS into executable code.
- **Error Reporter (`error_reporter.zig`)**: Centralized system for reporting compilation and runtime errors with source location information.
- **Formatter (`formatter.zig`)**: Formats SIRS code (JSON representation) for improved readability.
- **Graphical Model (`graphical_model.zig`)**: Defines structures and tools for building and compiling graphical models, including nodes, plates, and factors.
- **Linter (`linter.zig`)**: Analyzes SIRS code for potential issues, including naming conventions, performance, security, and dead code.
- **Mixture Models (`mixture_models.zig`)**: Provides functionalities for defining and managing mixture models and hierarchical models.
- **Optimization (`optimization.zig`)**: Contains various compiler optimization passes such as Dead Code Elimination, Constant Folding, Function Inlining, Loop Invariant Code Motion, Loop Unrolling, and Loop Strength Reduction.
- **SIRS Parser (`sirs.zig`)**: Parses SIRS language source code (JSON representation) into an Abstract Syntax Tree (AST).
- **Type Checker (`typechecker.zig`)**: Performs static type checking on the SIRS AST to ensure type consistency and correctness.
- **Variational Inference (`variational_inference.zig`)**: Implements Variational Inference algorithms for approximate probabilistic inference, including `VISolver` and `AutoDiffVISolver`.