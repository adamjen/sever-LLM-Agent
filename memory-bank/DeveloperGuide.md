# Developer Guide

## Getting Started
1. Install dependencies using `npm install`
2. Configure environment variables in `.env` file
3. Build the project by running `zig build`

## Code Structure Overview
- **src/**: Contains the core compiler, MCMC engine, AST tools, and other modules.
  - `ast_query.zig`: AST querying and manipulation.
  - `autodiff.zig`: Automatic differentiation for gradient computations.
  - `cir.zig`: Common Intermediate Representation lowering.
  - `cli.zig`: Command-line interface utilities.
  - `codegen.zig`: Code generation from SIRS to target languages (e.g., Zig).
  - `compiler.zig`: Main compiler orchestration.
  - `custom_distributions.zig`: Definition and management of custom probability distributions.
  - `debugger.zig`: Debugging functionalities.
  - `dependency_analyzer.zig`: Analysis of code dependencies.
  - `distribution_compiler.zig`: Compilation of custom distributions.
  - `error_reporter.zig`: Centralized error reporting.
  - `formatter.zig`: SIRS code formatter.
  - `graphical_model.zig`: Graphical model representation and compilation.
  - `linter.zig`: Code linting and static analysis.
  - `main.zig`: Entry point for the SIRS compiler CLI.
  - `mcmc.zig`: Markov Chain Monte Carlo sampling algorithms.
  - `mcp_ast_tools.zig`: MCP tools for AST interaction.
  - `mcp_dependency_tools.zig`: MCP tools for dependency analysis.
  - `mcp_distribution_tools.zig`: MCP tools for distribution management.
  - `mcp.zig`: Model Context Protocol server implementation.
  - `mixture_models.zig`: Mixture and hierarchical model definitions.
  - `optimization.zig`: Compiler optimization passes.
  - `sev_converter.zig`: Conversion between SIRS and SEV formats.
  - `sev_generator.zig`: Generation of SEV code.
  - `sev_simple.zig`: Simple SEV parser.
  - `sev.zig`: SEV parser.
  - `sirs_converter.zig`: Conversion between SIRS and SIRS-L formats.
  - `sirs.zig`: SIRS language parser (JSON representation).
  - `test_*.zig`: Various test files for different modules.
  - `typechecker.zig`: Static type checking.
  - `variational_inference.zig`: Variational Inference algorithms.
- **examples/**: Contains sample SIRS programs and test cases.
- **data/**: Stores project-related data files (e.g., `workflow.db`).
- **runtime/**: Contains runtime support files for the compiled SIRS programs.

## Development Workflow
1. Analyze codebase using `list_code_definition_names`
2. Make changes to source files using `apply_diff` or `write_to_file`
3. Test changes locally with the active development server

## Contribution Guidelines
- Follow coding standards and best practices outlined in `memory-bank/systemPatterns.md`.
- Document any significant architectural or implementation decisions in `memory-bank/decisionLog.md`.
- Keep `memory-bank/activeContext.md` updated with current focus, recent changes, and open questions.
- Ensure all contributions are compatible with the existing codebase architecture.