const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const SirsError = error{
    InvalidJson,
    MissingField,
    InvalidType,
    InvalidExpression,
    InvalidStatement,
    OutOfMemory,
};

pub const FunctionSignature = struct {
    args: ArrayList(Type), // parameter types
    @"return": Type, // return type
    type_params: ?ArrayList([]const u8), // optional generic type parameters
};

pub const Type = union(enum) {
    void,
    bool,
    i8, i16, i32, i64,
    u8, u16, u32, u64,
    f32, f64,
    str,
    array: struct {
        element: *Type,
        size: u32,
    },
    slice: struct {
        element: *Type,
    },
    @"struct": std.StringHashMap(*Type),
    @"union": std.StringHashMap(*Type),
    discriminated_union: struct {
        name: []const u8,
        variants: ArrayList(*Type), // list of possible types
    },
    @"enum": struct {
        name: []const u8,
        variants: std.StringHashMap(?*Type), // variant name -> optional associated type
    },
    @"error": struct {
        name: []const u8,
        message_type: ?*Type, // optional message data type
    },
    hashmap: struct {
        key: *Type,
        value: *Type,
    },
    set: struct {
        element: *Type,
    },
    tuple: ArrayList(*Type), // ordered list of types
    record: struct {
        name: []const u8,
        fields: std.StringHashMap(*Type), // named fields with types
    },
    optional: *Type,
    function: struct {
        args: ArrayList(Type),
        @"return": *Type,
    },
    distribution: struct {
        kind: DistributionKind,
        param_types: ArrayList(Type),
    },
    type_parameter: []const u8, // type parameter placeholder (e.g., "T", "U")
    generic_instance: struct {
        base_type: []const u8, // name of generic type (e.g., "Vec", "Option")
        type_args: ArrayList(*Type), // actual type arguments
    },
    @"interface": struct {
        name: []const u8,
        methods: std.StringHashMap(FunctionSignature), // method name -> signature
    },
    trait_object: struct {
        trait_name: []const u8, // name of the implemented trait
        type_args: ?ArrayList(*Type), // optional type arguments for generic traits
    },
};

pub const DistributionKind = enum {
    uniform,
    normal,
    categorical,
    bernoulli,
    exponential,
    gamma,
    beta,
};

pub const Literal = union(enum) {
    integer: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    null,
};

pub const Expression = union(enum) {
    literal: Literal,
    variable: []const u8,
    call: struct {
        function: []const u8,
        args: ArrayList(Expression),
    },
    op: struct {
        kind: OpKind,
        args: ArrayList(Expression),
    },
    index: struct {
        array: *Expression,
        index: *Expression,
    },
    field: struct {
        object: *Expression,
        field: []const u8,
    },
    array: ArrayList(Expression),
    @"struct": std.StringHashMap(Expression),
    sample: struct {
        distribution: []const u8,
        params: ArrayList(Expression),
    },
    infer: struct {
        model: *Expression,
        data: *Expression,
    },
    cast: struct {
        value: *Expression,
        type: Type,
    },
    enum_constructor: struct {
        enum_type: []const u8,
        variant: []const u8,
        value: ?*Expression, // optional associated value
    },
    hashmap: std.StringHashMap(Expression), // key-value pairs for literal maps
    set: ArrayList(Expression), // elements for literal sets
    tuple: ArrayList(Expression), // ordered expressions for tuple literal
    record: struct {
        type_name: []const u8, // record type name
        fields: std.StringHashMap(Expression), // field assignments
    },
};

pub const OpKind = enum {
    add, sub, mul, div, mod, pow,
    eq, ne, lt, le, gt, ge,
    @"and", @"or", not,
    bitand, bitor, bitxor, bitnot,
    shl, shr,
};

pub const LValue = union(enum) {
    variable: []const u8,
    index: struct {
        array: *LValue,
        index: Expression,
    },
    field: struct {
        object: *LValue,
        field: []const u8,
    },
};

pub const Pattern = union(enum) {
    literal: Literal,
    variable: []const u8,
    wildcard,
    @"struct": std.StringHashMap(Pattern),
    @"enum": struct {
        enum_type: []const u8,
        variant: []const u8,
        value_pattern: ?*Pattern, // optional pattern for associated value
    },
};

pub const MatchCase = struct {
    pattern: Pattern,
    body: ArrayList(Statement),
};

pub const CatchClause = struct {
    exception_type: ?Type, // null means catch all
    variable_name: ?[]const u8, // variable to bind exception to
    body: ArrayList(Statement),
};

pub const Statement = union(enum) {
    let: struct {
        name: []const u8,
        type: ?Type,
        mutable: bool,
        value: Expression,
    },
    assign: struct {
        target: LValue,
        value: Expression,
    },
    @"if": struct {
        condition: Expression,
        then: ArrayList(Statement),
        @"else": ?ArrayList(Statement),
    },
    match: struct {
        value: Expression,
        cases: ArrayList(MatchCase),
    },
    @"while": struct {
        condition: Expression,
        body: ArrayList(Statement),
    },
    @"for": struct {
        variable: []const u8,
        iterable: Expression,
        body: ArrayList(Statement),
    },
    @"try": struct {
        body: ArrayList(Statement),
        catch_clauses: ArrayList(CatchClause),
        finally_body: ?ArrayList(Statement),
    },
    @"throw": Expression,
    @"return": Expression,
    @"break",
    @"continue",
    observe: struct {
        distribution: []const u8,
        params: ArrayList(Expression),
        value: Expression,
    },
    prob_assert: struct {
        condition: Expression,
        confidence: f64,
    },
    expression: Expression,
};

pub const Parameter = struct {
    name: []const u8,
    type: Type,
};

pub const Function = struct {
    args: ArrayList(Parameter),
    @"return": Type,
    body: ArrayList(Statement),
    @"inline": bool = false,
    pure: bool = false,
    type_params: ?ArrayList([]const u8) = null, // generic type parameters
};

pub const GenericType = struct {
    name: []const u8,
    type_params: ArrayList([]const u8), // type parameter names
    definition: Type, // the actual type definition (may contain type_parameter types)
};

pub const Interface = struct {
    name: []const u8,
    type_params: ?ArrayList([]const u8), // optional generic type parameters
    methods: std.StringHashMap(FunctionSignature), // method signatures
};

pub const TraitImpl = struct {
    trait_name: []const u8, // name of the trait being implemented
    target_type: Type, // type that implements the trait
    type_args: ?ArrayList(*Type), // type arguments if trait is generic
    methods: std.StringHashMap(Function), // method implementations
};

pub const Constant = struct {
    type: Type,
    value: Expression,
};

pub const Program = struct {
    entry: []const u8,
    functions: std.StringHashMap(Function),
    types: std.StringHashMap(Type),
    generic_types: std.StringHashMap(GenericType), // generic type definitions
    interfaces: std.StringHashMap(Interface), // interface/trait definitions
    trait_impls: ArrayList(TraitImpl), // trait implementations
    constants: std.StringHashMap(Constant),
    
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) Program {
        return Program{
            .entry = "",
            .functions = std.StringHashMap(Function).init(allocator),
            .types = std.StringHashMap(Type).init(allocator),
            .generic_types = std.StringHashMap(GenericType).init(allocator),
            .interfaces = std.StringHashMap(Interface).init(allocator),
            .trait_impls = ArrayList(TraitImpl).init(allocator),
            .constants = std.StringHashMap(Constant).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Program) void {
        // Free the entry string
        if (self.entry.len > 0) {
            self.allocator.free(self.entry);
        }
        
        // Free all function names and their contents
        var func_iter = self.functions.iterator();
        while (func_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.deallocateFunction(entry.value_ptr);
        }
        self.functions.deinit();
        
        // Free all type names and their contents
        var type_iter = self.types.iterator();
        while (type_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.deallocateType(entry.value_ptr);
        }
        self.types.deinit();
        
        // Free all generic type names and their contents
        var generic_iter = self.generic_types.iterator();
        while (generic_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.deallocateGenericType(entry.value_ptr);
        }
        self.generic_types.deinit();
        
        // Free all interface names and their contents
        var interface_iter = self.interfaces.iterator();
        while (interface_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.deallocateInterface(entry.value_ptr);
        }
        self.interfaces.deinit();
        
        // Free all trait implementations
        for (self.trait_impls.items) |*trait_impl| {
            self.deallocateTraitImpl(trait_impl);
        }
        self.trait_impls.deinit();
        
        // Free all constant names and their contents
        var const_iter = self.constants.iterator();
        while (const_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.deallocateConstant(entry.value_ptr);
        }
        self.constants.deinit();
    }
    
    fn deallocateFunction(self: *Program, function: *Function) void {
        // Free parameter names
        for (function.args.items) |param| {
            self.allocator.free(param.name);
        }
        function.args.deinit();
        
        // Free type parameters if present
        if (function.type_params) |*type_params| {
            for (type_params.items) |param_name| {
                self.allocator.free(param_name);
            }
            type_params.deinit();
        }
        
        // Free statements
        for (function.body.items) |*stmt| {
            self.deallocateStatement(stmt);
        }
        function.body.deinit();
    }
    
    fn deallocateType(self: *Program, type_val: *Type) void {
        switch (type_val.*) {
            .@"enum" => |*enum_def| {
                // Free the enum name
                self.allocator.free(enum_def.name);
                
                // Free all variant names and associated types
                var variant_iter = enum_def.variants.iterator();
                while (variant_iter.next()) |entry| {
                    // Free variant name
                    self.allocator.free(entry.key_ptr.*);
                    
                    // Free associated type if present
                    if (entry.value_ptr.*) |variant_type| {
                        self.deallocateType(variant_type);
                        self.allocator.destroy(variant_type);
                    }
                }
                
                // Free the variants map
                enum_def.variants.deinit();
            },
            .discriminated_union => |*union_def| {
                // Free the union name
                self.allocator.free(union_def.name);
                
                // Free all variant types
                for (union_def.variants.items) |variant_type| {
                    self.deallocateType(variant_type);
                    self.allocator.destroy(variant_type);
                }
                
                // Free the variants list
                union_def.variants.deinit();
            },
            .@"error" => |*error_def| {
                // Free the error name
                self.allocator.free(error_def.name);
                
                // Free message type if present
                if (error_def.message_type) |msg_type| {
                    self.deallocateType(msg_type);
                    self.allocator.destroy(msg_type);
                }
            },
            .hashmap => |hashmap_def| {
                self.deallocateType(hashmap_def.key);
                self.allocator.destroy(hashmap_def.key);
                self.deallocateType(hashmap_def.value);
                self.allocator.destroy(hashmap_def.value);
            },
            .set => |set_def| {
                self.deallocateType(set_def.element);
                self.allocator.destroy(set_def.element);
            },
            .tuple => |*tuple_types| {
                for (tuple_types.items) |type_ptr| {
                    self.deallocateType(type_ptr);
                    self.allocator.destroy(type_ptr);
                }
                tuple_types.deinit();
            },
            .record => |*record_def| {
                // Free the record name
                self.allocator.free(record_def.name);
                
                // Free all field names and types
                var field_iter = record_def.fields.iterator();
                while (field_iter.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.deallocateType(entry.value_ptr.*);
                    self.allocator.destroy(entry.value_ptr.*);
                }
                record_def.fields.deinit();
            },
            .array => |array_def| {
                self.deallocateType(array_def.element);
                self.allocator.destroy(array_def.element);
            },
            .slice => |slice_def| {
                self.deallocateType(slice_def.element);
                self.allocator.destroy(slice_def.element);
            },
            .optional => |opt_type| {
                self.deallocateType(opt_type);
                self.allocator.destroy(opt_type);
            },
            .@"struct" => |*struct_fields| {
                var field_iter = struct_fields.iterator();
                while (field_iter.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.deallocateType(entry.value_ptr.*);
                    self.allocator.destroy(entry.value_ptr.*);
                }
                struct_fields.deinit();
            },
            .@"union" => |*union_fields| {
                var field_iter = union_fields.iterator();
                while (field_iter.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.deallocateType(entry.value_ptr.*);
                    self.allocator.destroy(entry.value_ptr.*);
                }
                union_fields.deinit();
            },
            .function => |*func_type| {
                func_type.args.deinit();
                self.deallocateType(func_type.@"return");
                self.allocator.destroy(func_type.@"return");
            },
            .distribution => |*dist_type| {
                dist_type.param_types.deinit();
            },
            .type_parameter => |param_name| {
                self.allocator.free(param_name);
            },
            .generic_instance => |*generic_inst| {
                self.allocator.free(generic_inst.base_type);
                for (generic_inst.type_args.items) |type_ptr| {
                    self.deallocateType(type_ptr);
                    self.allocator.destroy(type_ptr);
                }
                generic_inst.type_args.deinit();
            },
            .@"interface" => |*interface_def| {
                self.allocator.free(interface_def.name);
                var method_iter = interface_def.methods.iterator();
                while (method_iter.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.deallocateFunctionSignature(entry.value_ptr);
                }
                interface_def.methods.deinit();
            },
            .trait_object => |*trait_obj| {
                self.allocator.free(trait_obj.trait_name);
                if (trait_obj.type_args) |*type_args| {
                    for (type_args.items) |type_ptr| {
                        self.deallocateType(type_ptr);
                        self.allocator.destroy(type_ptr);
                    }
                    type_args.deinit();
                }
            },
            else => {
                // Basic types don't need cleanup
            },
        }
    }
    
    fn deallocateGenericType(self: *Program, generic_type: *GenericType) void {
        // Free the generic type name
        self.allocator.free(generic_type.name);
        
        // Free type parameter names
        for (generic_type.type_params.items) |param_name| {
            self.allocator.free(param_name);
        }
        generic_type.type_params.deinit();
        
        // Free the type definition
        self.deallocateType(&generic_type.definition);
    }
    
    fn deallocateFunctionSignature(self: *Program, signature: *FunctionSignature) void {
        signature.args.deinit();
        
        if (signature.type_params) |*type_params| {
            for (type_params.items) |param_name| {
                self.allocator.free(param_name);
            }
            type_params.deinit();
        }
    }
    
    fn deallocateInterface(self: *Program, interface: *Interface) void {
        self.allocator.free(interface.name);
        
        if (interface.type_params) |*type_params| {
            for (type_params.items) |param_name| {
                self.allocator.free(param_name);
            }
            type_params.deinit();
        }
        
        var method_iter = interface.methods.iterator();
        while (method_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.deallocateFunctionSignature(entry.value_ptr);
        }
        interface.methods.deinit();
    }
    
    fn deallocateTraitImpl(self: *Program, trait_impl: *TraitImpl) void {
        self.allocator.free(trait_impl.trait_name);
        self.deallocateType(&trait_impl.target_type);
        
        if (trait_impl.type_args) |*type_args| {
            for (type_args.items) |type_ptr| {
                self.deallocateType(type_ptr);
                self.allocator.destroy(type_ptr);
            }
            type_args.deinit();
        }
        
        var method_iter = trait_impl.methods.iterator();
        while (method_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.deallocateFunction(entry.value_ptr);
        }
        trait_impl.methods.deinit();
    }
    
    fn deallocateConstant(self: *Program, constant: *Constant) void {
        self.deallocateExpression(&constant.value);
    }
    
    fn deallocateStatement(self: *Program, stmt: *Statement) void {
        switch (stmt.*) {
            .let => |*let_stmt| {
                self.allocator.free(let_stmt.name);
                self.deallocateExpression(&let_stmt.value);
            },
            .assign => |*assign_stmt| {
                self.deallocateLValue(&assign_stmt.target);
                self.deallocateExpression(&assign_stmt.value);
            },
            .@"if" => |*if_stmt| {
                self.deallocateExpression(&if_stmt.condition);
                for (if_stmt.then.items) |*then_stmt| {
                    self.deallocateStatement(then_stmt);
                }
                if_stmt.then.deinit();
                if (if_stmt.@"else") |*else_stmts| {
                    for (else_stmts.items) |*else_stmt| {
                        self.deallocateStatement(else_stmt);
                    }
                    else_stmts.deinit();
                }
            },
            .@"while" => |*while_stmt| {
                self.deallocateExpression(&while_stmt.condition);
                for (while_stmt.body.items) |*body_stmt| {
                    self.deallocateStatement(body_stmt);
                }
                while_stmt.body.deinit();
            },
            .@"return" => |*return_expr| {
                self.deallocateExpression(return_expr);
            },
            .observe => |*observe_stmt| {
                self.allocator.free(observe_stmt.distribution);
                for (observe_stmt.params.items) |*param| {
                    self.deallocateExpression(param);
                }
                observe_stmt.params.deinit();
                self.deallocateExpression(&observe_stmt.value);
            },
            .match => |*match_stmt| {
                self.deallocateExpression(&match_stmt.value);
                for (match_stmt.cases.items) |*case| {
                    self.deallocatePattern(&case.pattern);
                    for (case.body.items) |*body_stmt| {
                        self.deallocateStatement(body_stmt);
                    }
                    case.body.deinit();
                }
                match_stmt.cases.deinit();
            },
            .@"try" => |*try_stmt| {
                // Deallocate try body
                for (try_stmt.body.items) |*body_stmt| {
                    self.deallocateStatement(body_stmt);
                }
                try_stmt.body.deinit();
                
                // Deallocate catch clauses
                for (try_stmt.catch_clauses.items) |*catch_clause| {
                    if (catch_clause.variable_name) |var_name| {
                        self.allocator.free(var_name);
                    }
                    for (catch_clause.body.items) |*catch_stmt| {
                        self.deallocateStatement(catch_stmt);
                    }
                    catch_clause.body.deinit();
                }
                try_stmt.catch_clauses.deinit();
                
                // Deallocate finally body
                if (try_stmt.finally_body) |*finally_stmts| {
                    for (finally_stmts.items) |*finally_stmt| {
                        self.deallocateStatement(finally_stmt);
                    }
                    finally_stmts.deinit();
                }
            },
            .@"throw" => |*throw_expr| {
                self.deallocateExpression(throw_expr);
            },
            .expression => |*expr| {
                self.deallocateExpression(expr);
            },
            else => {},
        }
    }
    
    fn deallocateExpression(self: *Program, expr: *Expression) void {
        switch (expr.*) {
            .literal => |literal| {
                switch (literal) {
                    .string => |s| self.allocator.free(s),
                    else => {},
                }
            },
            .variable => |var_name| {
                self.allocator.free(var_name);
            },
            .call => |*call_expr| {
                self.allocator.free(call_expr.function);
                for (call_expr.args.items) |*arg| {
                    self.deallocateExpression(arg);
                }
                call_expr.args.deinit();
            },
            .op => |*op_expr| {
                for (op_expr.args.items) |*arg| {
                    self.deallocateExpression(arg);
                }
                op_expr.args.deinit();
            },
            .index => |*index_expr| {
                self.deallocateExpression(index_expr.array);
                self.allocator.destroy(index_expr.array);
                self.deallocateExpression(index_expr.index);
                self.allocator.destroy(index_expr.index);
            },
            .field => |*field_expr| {
                self.deallocateExpression(field_expr.object);
                self.allocator.destroy(field_expr.object);
                self.allocator.free(field_expr.field);
            },
            .array => |*array_expr| {
                for (array_expr.items) |*elem| {
                    self.deallocateExpression(elem);
                }
                array_expr.deinit();
            },
            .@"struct" => |*struct_expr| {
                var field_iter = struct_expr.iterator();
                while (field_iter.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.deallocateExpression(entry.value_ptr);
                }
                struct_expr.deinit();
            },
            .sample => |*sample_expr| {
                self.allocator.free(sample_expr.distribution);
                for (sample_expr.params.items) |*param| {
                    self.deallocateExpression(param);
                }
                sample_expr.params.deinit();
            },
            .cast => |*cast_expr| {
                self.deallocateExpression(cast_expr.value);
                self.allocator.destroy(cast_expr.value);
            },
            .enum_constructor => |*enum_expr| {
                self.allocator.free(enum_expr.enum_type);
                self.allocator.free(enum_expr.variant);
                if (enum_expr.value) |value| {
                    self.deallocateExpression(value);
                    self.allocator.destroy(value);
                }
            },
            .hashmap => |*hashmap_expr| {
                var map_iter = hashmap_expr.iterator();
                while (map_iter.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.deallocateExpression(entry.value_ptr);
                }
                hashmap_expr.deinit();
            },
            .set => |*set_expr| {
                for (set_expr.items) |*elem| {
                    self.deallocateExpression(elem);
                }
                set_expr.deinit();
            },
            .tuple => |*tuple_expr| {
                for (tuple_expr.items) |*elem| {
                    self.deallocateExpression(elem);
                }
                tuple_expr.deinit();
            },
            .record => |*record_expr| {
                self.allocator.free(record_expr.type_name);
                var field_iter = record_expr.fields.iterator();
                while (field_iter.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.deallocateExpression(entry.value_ptr);
                }
                record_expr.fields.deinit();
            },
            else => {},
        }
    }
    
    fn deallocateLValue(self: *Program, lvalue: *LValue) void {
        switch (lvalue.*) {
            .variable => |var_name| {
                self.allocator.free(var_name);
            },
            .index => |*index_lvalue| {
                self.deallocateLValue(index_lvalue.array);
                self.allocator.destroy(index_lvalue.array);
                self.deallocateExpression(&index_lvalue.index);
            },
            .field => |*field_lvalue| {
                self.deallocateLValue(field_lvalue.object);
                self.allocator.destroy(field_lvalue.object);
                self.allocator.free(field_lvalue.field);
            },
        }
    }
    
    fn deallocatePattern(self: *Program, pattern: *Pattern) void {
        switch (pattern.*) {
            .literal => |literal| {
                switch (literal) {
                    .string => |s| self.allocator.free(s),
                    else => {},
                }
            },
            .variable => |var_name| {
                self.allocator.free(var_name);
            },
            .@"struct" => |*struct_patterns| {
                var iter = struct_patterns.iterator();
                while (iter.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.deallocatePattern(entry.value_ptr);
                }
                struct_patterns.deinit();
            },
            .@"enum" => |*enum_pattern| {
                self.allocator.free(enum_pattern.enum_type);
                self.allocator.free(enum_pattern.variant);
                if (enum_pattern.value_pattern) |value_pattern| {
                    self.deallocatePattern(value_pattern);
                    self.allocator.destroy(value_pattern);
                }
            },
            .wildcard => {},
        }
    }
};

pub const Parser = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) Parser {
        return Parser{
            .allocator = allocator,
        };
    }
    
    pub fn parse(self: *Parser, json_content: []const u8) SirsError!Program {
        var parsed = json.parseFromSlice(json.Value, self.allocator, json_content, .{}) catch return SirsError.InvalidJson;
        defer parsed.deinit();
        
        const root = parsed.value;
        if (root != .object) return SirsError.InvalidJson;
        
        const program_obj = root.object.get("program") orelse return SirsError.MissingField;
        if (program_obj != .object) return SirsError.InvalidJson;
        
        var program = Program.init(self.allocator);
        
        // Parse entry point
        const entry = program_obj.object.get("entry") orelse return SirsError.MissingField;
        if (entry != .string) return SirsError.InvalidType;
        program.entry = self.allocator.dupe(u8, entry.string) catch return SirsError.OutOfMemory;
        
        // Parse functions
        if (program_obj.object.get("functions")) |functions_obj| {
            if (functions_obj != .object) return SirsError.InvalidType;
            
            var func_iter = functions_obj.object.iterator();
            while (func_iter.next()) |entry_kv| {
                const func_name = entry_kv.key_ptr.*;
                const func_obj = entry_kv.value_ptr.*;
                
                const function = try self.parseFunction(func_obj);
                const func_name_copy = self.allocator.dupe(u8, func_name) catch return SirsError.OutOfMemory;
                program.functions.put(func_name_copy, function) catch return SirsError.OutOfMemory;
            }
        }
        
        // Parse types
        if (program_obj.object.get("types")) |types_obj| {
            if (types_obj != .object) return SirsError.InvalidType;
            
            var type_iter = types_obj.object.iterator();
            while (type_iter.next()) |entry_kv| {
                const type_name = entry_kv.key_ptr.*;
                const type_obj = entry_kv.value_ptr.*;
                
                // Check if this is a generic type definition
                if (type_obj.object.get("generic_def")) |generic_obj| {
                    const generic_type = try self.parseGenericTypeDefinition(generic_obj);
                    const type_name_copy = self.allocator.dupe(u8, type_name) catch return SirsError.OutOfMemory;
                    program.generic_types.put(type_name_copy, generic_type) catch return SirsError.OutOfMemory;
                } else {
                    const parsed_type = try self.parseComplexType(type_obj);
                    const type_name_copy = self.allocator.dupe(u8, type_name) catch return SirsError.OutOfMemory;
                    program.types.put(type_name_copy, parsed_type) catch return SirsError.OutOfMemory;
                }
            }
        }
        
        // Parse interfaces
        if (program_obj.object.get("interfaces")) |interfaces_obj| {
            if (interfaces_obj != .object) return SirsError.InvalidType;
            
            var interface_iter = interfaces_obj.object.iterator();
            while (interface_iter.next()) |entry_kv| {
                const interface_name = entry_kv.key_ptr.*;
                const interface_obj = entry_kv.value_ptr.*;
                
                const interface_def = try self.parseInterface(interface_obj);
                const interface_name_copy = self.allocator.dupe(u8, interface_name) catch return SirsError.OutOfMemory;
                program.interfaces.put(interface_name_copy, interface_def) catch return SirsError.OutOfMemory;
            }
        }
        
        // Parse trait implementations
        if (program_obj.object.get("trait_impls")) |trait_impls_obj| {
            if (trait_impls_obj != .array) return SirsError.InvalidType;
            
            for (trait_impls_obj.array.items) |trait_impl_obj| {
                const trait_impl = try self.parseTraitImpl(trait_impl_obj);
                program.trait_impls.append(trait_impl) catch return SirsError.OutOfMemory;
            }
        }
        
        return program;
    }
    
    fn parseFunction(self: *Parser, func_obj: json.Value) SirsError!Function {
        if (func_obj != .object) return SirsError.InvalidType;
        
        var function = Function{
            .args = ArrayList(Parameter).init(self.allocator),
            .@"return" = Type.void,
            .body = ArrayList(Statement).init(self.allocator),
        };
        
        // Parse arguments
        if (func_obj.object.get("args")) |args_obj| {
            if (args_obj != .array) return SirsError.InvalidType;
            
            for (args_obj.array.items) |arg_obj| {
                const param = try self.parseParameter(arg_obj);
                function.args.append(param) catch return SirsError.OutOfMemory;
            }
        }
        
        // Parse return type
        if (func_obj.object.get("return")) |return_obj| {
            function.@"return" = try self.parseType(return_obj);
        }
        
        // Parse body
        if (func_obj.object.get("body")) |body_obj| {
            if (body_obj != .array) return SirsError.InvalidType;
            
            for (body_obj.array.items) |stmt_obj| {
                const stmt = try self.parseStatement(stmt_obj);
                function.body.append(stmt) catch return SirsError.OutOfMemory;
            }
        }
        
        // Parse optional fields
        if (func_obj.object.get("inline")) |inline_obj| {
            if (inline_obj == .bool) function.@"inline" = inline_obj.bool;
        }
        
        if (func_obj.object.get("pure")) |pure_obj| {
            if (pure_obj == .bool) function.pure = pure_obj.bool;
        }
        
        return function;
    }
    
    fn parseParameter(self: *Parser, param_obj: json.Value) SirsError!Parameter {
        if (param_obj != .object) return SirsError.InvalidType;
        
        const name = param_obj.object.get("name") orelse return SirsError.MissingField;
        if (name != .string) return SirsError.InvalidType;
        
        const type_obj = param_obj.object.get("type") orelse return SirsError.MissingField;
        const param_type = try self.parseType(type_obj);
        
        return Parameter{
            .name = self.allocator.dupe(u8, name.string) catch return SirsError.OutOfMemory,
            .type = param_type,
        };
    }
    
    fn parseType(self: *Parser, type_obj: json.Value) SirsError!Type {
        if (type_obj == .string) {
            const type_str = type_obj.string;
            if (std.mem.eql(u8, type_str, "void")) return Type.void;
            if (std.mem.eql(u8, type_str, "bool")) return Type.bool;
            if (std.mem.eql(u8, type_str, "i8")) return Type.i8;
            if (std.mem.eql(u8, type_str, "i16")) return Type.i16;
            if (std.mem.eql(u8, type_str, "i32")) return Type.i32;
            if (std.mem.eql(u8, type_str, "i64")) return Type.i64;
            if (std.mem.eql(u8, type_str, "u8")) return Type.u8;
            if (std.mem.eql(u8, type_str, "u16")) return Type.u16;
            if (std.mem.eql(u8, type_str, "u32")) return Type.u32;
            if (std.mem.eql(u8, type_str, "u64")) return Type.u64;
            if (std.mem.eql(u8, type_str, "f32")) return Type.f32;
            if (std.mem.eql(u8, type_str, "f64")) return Type.f64;
            if (std.mem.eql(u8, type_str, "str")) return Type.str;
            
            // Check if it's a type parameter (single uppercase letter or T, U, V pattern)
            if (type_str.len == 1 and type_str[0] >= 'A' and type_str[0] <= 'Z') {
                const param_name = try self.allocator.dupe(u8, type_str);
                return Type{ .type_parameter = param_name };
            }
            
            // For other names, assume they might be type references (handled elsewhere)
            return SirsError.InvalidType;
        }
        
        // Handle complex types
        if (type_obj == .object) {
            // Handle hashmap types: {"hashmap": {"key": "str", "value": "i32"}}
            if (type_obj.object.get("hashmap")) |hashmap_obj| {
                if (hashmap_obj != .object) return SirsError.InvalidType;
                
                const key_obj = hashmap_obj.object.get("key") orelse return SirsError.MissingField;
                const value_obj = hashmap_obj.object.get("value") orelse return SirsError.MissingField;
                
                const key_type = try self.allocator.create(Type);
                key_type.* = try self.parseType(key_obj);
                
                const value_type = try self.allocator.create(Type);
                value_type.* = try self.parseType(value_obj);
                
                return Type{ .hashmap = .{ .key = key_type, .value = value_type } };
            }
            
            // Handle set types: {"set": {"element": "str"}}
            if (type_obj.object.get("set")) |set_obj| {
                if (set_obj != .object) return SirsError.InvalidType;
                
                const element_obj = set_obj.object.get("element") orelse return SirsError.MissingField;
                
                const element_type = try self.allocator.create(Type);
                element_type.* = try self.parseType(element_obj);
                
                return Type{ .set = .{ .element = element_type } };
            }
            
            // Handle generic type instantiation: {"generic": {"type": "Vec", "args": ["i32"]}}
            if (type_obj.object.get("generic")) |generic_obj| {
                if (generic_obj != .object) return SirsError.InvalidType;
                
                const type_name = generic_obj.object.get("type") orelse return SirsError.MissingField;
                if (type_name != .string) return SirsError.InvalidType;
                
                const args_obj = generic_obj.object.get("args") orelse return SirsError.MissingField;
                if (args_obj != .array) return SirsError.InvalidType;
                
                const base_type = try self.allocator.dupe(u8, type_name.string);
                var type_args = ArrayList(*Type).init(self.allocator);
                
                for (args_obj.array.items) |arg_obj| {
                    const arg_type = try self.parseType(arg_obj);
                    const arg_type_ptr = try self.allocator.create(Type);
                    arg_type_ptr.* = arg_type;
                    try type_args.append(arg_type_ptr);
                }
                
                return Type{ 
                    .generic_instance = .{
                        .base_type = base_type,
                        .type_args = type_args,
                    }
                };
            }
            
            // Handle trait object: {"trait": {"name": "Display", "args": ["T"]}}
            if (type_obj.object.get("trait")) |trait_obj| {
                if (trait_obj != .object) return SirsError.InvalidType;
                
                const trait_name = trait_obj.object.get("name") orelse return SirsError.MissingField;
                if (trait_name != .string) return SirsError.InvalidType;
                
                const trait_name_copy = try self.allocator.dupe(u8, trait_name.string);
                var type_args: ?ArrayList(*Type) = null;
                
                // Handle optional type arguments
                if (trait_obj.object.get("args")) |args_obj| {
                    if (args_obj != .array) return SirsError.InvalidType;
                    
                    var args_list = ArrayList(*Type).init(self.allocator);
                    for (args_obj.array.items) |arg_obj| {
                        const arg_type = try self.parseType(arg_obj);
                        const arg_type_ptr = try self.allocator.create(Type);
                        arg_type_ptr.* = arg_type;
                        try args_list.append(arg_type_ptr);
                    }
                    type_args = args_list;
                }
                
                return Type{ 
                    .trait_object = .{
                        .trait_name = trait_name_copy,
                        .type_args = type_args,
                    }
                };
            }
            
            // Handle other complex types that might be added later
            return try self.parseComplexType(type_obj);
        }
        
        return SirsError.InvalidType;
    }
    
    fn parseStatement(self: *Parser, stmt_obj: json.Value) SirsError!Statement {
        if (stmt_obj != .object) return SirsError.InvalidStatement;
        
        // Handle different statement types
        if (stmt_obj.object.get("let")) |let_obj| {
            return try self.parseLetStatement(let_obj);
        }
        
        if (stmt_obj.object.get("return")) |return_obj| {
            const expr = try self.parseExpression(return_obj);
            return Statement{ .@"return" = expr };
        }
        
        if (stmt_obj.object.get("expression")) |expr_obj| {
            const expr = try self.parseExpression(expr_obj);
            return Statement{ .expression = expr };
        }
        
        if (stmt_obj.object.get("assign")) |assign_obj| {
            return try self.parseAssignStatement(assign_obj);
        }
        
        if (stmt_obj.object.get("while")) |while_obj| {
            return try self.parseWhileStatement(while_obj);
        }
        
        if (stmt_obj.object.get("if")) |if_obj| {
            return try self.parseIfStatement(if_obj);
        }
        
        if (stmt_obj.object.get("match")) |match_obj| {
            return try self.parseMatchStatement(match_obj);
        }
        
        if (stmt_obj.object.get("try")) |try_obj| {
            return try self.parseTryStatement(try_obj);
        }
        
        if (stmt_obj.object.get("throw")) |throw_obj| {
            const expr = try self.parseExpression(throw_obj);
            return Statement{ .@"throw" = expr };
        }
        
        return SirsError.InvalidStatement;
    }
    
    fn parseLetStatement(self: *Parser, let_obj: json.Value) SirsError!Statement {
        if (let_obj != .object) return SirsError.InvalidStatement;
        
        const name = let_obj.object.get("name") orelse return SirsError.MissingField;
        if (name != .string) return SirsError.InvalidType;
        
        const value_obj = let_obj.object.get("value") orelse return SirsError.MissingField;
        const value = try self.parseExpression(value_obj);
        
        const mutable = if (let_obj.object.get("mutable")) |mut_obj| 
            if (mut_obj == .bool) mut_obj.bool else false
        else false;
        
        const type_opt = if (let_obj.object.get("type")) |type_obj|
            try self.parseType(type_obj)
        else null;
        
        return Statement{
            .let = .{
                .name = self.allocator.dupe(u8, name.string) catch return SirsError.OutOfMemory,
                .type = type_opt,
                .mutable = mutable,
                .value = value,
            },
        };
    }
    
    fn parseAssignStatement(self: *Parser, assign_obj: json.Value) SirsError!Statement {
        if (assign_obj != .object) return SirsError.InvalidStatement;
        
        const target_obj = assign_obj.object.get("target") orelse return SirsError.MissingField;
        const value_obj = assign_obj.object.get("value") orelse return SirsError.MissingField;
        
        const target = try self.parseLValue(target_obj);
        const value = try self.parseExpression(value_obj);
        
        return Statement{
            .assign = .{
                .target = target,
                .value = value,
            },
        };
    }
    
    fn parseWhileStatement(self: *Parser, while_obj: json.Value) SirsError!Statement {
        if (while_obj != .object) return SirsError.InvalidStatement;
        
        const condition_obj = while_obj.object.get("condition") orelse return SirsError.MissingField;
        const body_obj = while_obj.object.get("body") orelse return SirsError.MissingField;
        
        if (body_obj != .array) return SirsError.InvalidStatement;
        
        const condition = try self.parseExpression(condition_obj);
        
        var body = ArrayList(Statement).init(self.allocator);
        for (body_obj.array.items) |stmt_obj| {
            const stmt = try self.parseStatement(stmt_obj);
            body.append(stmt) catch return SirsError.OutOfMemory;
        }
        
        return Statement{
            .@"while" = .{
                .condition = condition,
                .body = body,
            },
        };
    }
    
    fn parseIfStatement(self: *Parser, if_obj: json.Value) SirsError!Statement {
        if (if_obj != .object) return SirsError.InvalidStatement;
        
        const condition_obj = if_obj.object.get("condition") orelse return SirsError.MissingField;
        const then_obj = if_obj.object.get("then") orelse return SirsError.MissingField;
        
        if (then_obj != .array) return SirsError.InvalidStatement;
        
        const condition = try self.parseExpression(condition_obj);
        
        var then_body = ArrayList(Statement).init(self.allocator);
        for (then_obj.array.items) |stmt_obj| {
            const stmt = try self.parseStatement(stmt_obj);
            then_body.append(stmt) catch return SirsError.OutOfMemory;
        }
        
        // Parse optional else clause
        var else_body: ?ArrayList(Statement) = null;
        if (if_obj.object.get("else")) |else_obj| {
            if (else_obj != .array) return SirsError.InvalidStatement;
            
            var else_statements = ArrayList(Statement).init(self.allocator);
            for (else_obj.array.items) |stmt_obj| {
                const stmt = try self.parseStatement(stmt_obj);
                else_statements.append(stmt) catch return SirsError.OutOfMemory;
            }
            else_body = else_statements;
        }
        
        return Statement{
            .@"if" = .{
                .condition = condition,
                .then = then_body,
                .@"else" = else_body,
            },
        };
    }
    
    fn parseMatchStatement(self: *Parser, match_obj: json.Value) SirsError!Statement {
        if (match_obj != .object) return SirsError.InvalidStatement;
        
        const value_obj = match_obj.object.get("value") orelse return SirsError.MissingField;
        const cases_obj = match_obj.object.get("cases") orelse return SirsError.MissingField;
        
        if (cases_obj != .array) return SirsError.InvalidStatement;
        
        const value = try self.parseExpression(value_obj);
        var cases = ArrayList(MatchCase).init(self.allocator);
        
        for (cases_obj.array.items) |case_obj| {
            if (case_obj != .object) return SirsError.InvalidStatement;
            
            const pattern_obj = case_obj.object.get("pattern") orelse return SirsError.MissingField;
            const body_obj = case_obj.object.get("body") orelse return SirsError.MissingField;
            
            if (body_obj != .array) return SirsError.InvalidStatement;
            
            const pattern = try self.parsePattern(pattern_obj);
            var body = ArrayList(Statement).init(self.allocator);
            
            for (body_obj.array.items) |stmt_obj| {
                const stmt = try self.parseStatement(stmt_obj);
                try body.append(stmt);
            }
            
            try cases.append(.{ .pattern = pattern, .body = body });
        }
        
        return Statement{
            .match = .{
                .value = value,
                .cases = cases,
            },
        };
    }
    
    fn parseTryStatement(self: *Parser, try_obj: json.Value) SirsError!Statement {
        if (try_obj != .object) return SirsError.InvalidStatement;
        
        // Parse try body
        const body_obj = try_obj.object.get("body") orelse return SirsError.MissingField;
        if (body_obj != .array) return SirsError.InvalidStatement;
        
        var body = ArrayList(Statement).init(self.allocator);
        for (body_obj.array.items) |stmt_obj| {
            const stmt = try self.parseStatement(stmt_obj);
            try body.append(stmt);
        }
        
        // Parse catch clauses
        var catch_clauses = ArrayList(CatchClause).init(self.allocator);
        if (try_obj.object.get("catch")) |catch_obj| {
            if (catch_obj == .array) {
                // Multiple catch clauses
                for (catch_obj.array.items) |clause_obj| {
                    const clause = try self.parseCatchClause(clause_obj);
                    try catch_clauses.append(clause);
                }
            } else {
                // Single catch clause
                const clause = try self.parseCatchClause(catch_obj);
                try catch_clauses.append(clause);
            }
        }
        
        // Parse finally body (optional)
        var finally_body: ?ArrayList(Statement) = null;
        if (try_obj.object.get("finally")) |finally_obj| {
            if (finally_obj != .array) return SirsError.InvalidStatement;
            
            var finally_stmts = ArrayList(Statement).init(self.allocator);
            for (finally_obj.array.items) |stmt_obj| {
                const stmt = try self.parseStatement(stmt_obj);
                try finally_stmts.append(stmt);
            }
            finally_body = finally_stmts;
        }
        
        return Statement{
            .@"try" = .{
                .body = body,
                .catch_clauses = catch_clauses,
                .finally_body = finally_body,
            },
        };
    }
    
    fn parseCatchClause(self: *Parser, catch_obj: json.Value) SirsError!CatchClause {
        if (catch_obj != .object) return SirsError.InvalidStatement;
        
        // Parse exception type (optional)
        var exception_type: ?Type = null;
        if (catch_obj.object.get("type")) |type_obj| {
            exception_type = try self.parseType(type_obj);
        }
        
        // Parse variable name to bind exception (optional)
        var variable_name: ?[]const u8 = null;
        if (catch_obj.object.get("variable")) |var_obj| {
            if (var_obj != .string) return SirsError.InvalidStatement;
            variable_name = try self.allocator.dupe(u8, var_obj.string);
        }
        
        // Parse catch body
        const body_obj = catch_obj.object.get("body") orelse return SirsError.MissingField;
        if (body_obj != .array) return SirsError.InvalidStatement;
        
        var body = ArrayList(Statement).init(self.allocator);
        for (body_obj.array.items) |stmt_obj| {
            const stmt = try self.parseStatement(stmt_obj);
            try body.append(stmt);
        }
        
        return CatchClause{
            .exception_type = exception_type,
            .variable_name = variable_name,
            .body = body,
        };
    }
    
    fn parsePattern(self: *Parser, pattern_obj: json.Value) SirsError!Pattern {
        if (pattern_obj != .object) return SirsError.InvalidStatement;
        
        // Handle literal patterns
        if (pattern_obj.object.get("literal")) |literal_obj| {
            const literal = try self.parseLiteral(literal_obj);
            return Pattern{ .literal = literal.literal };
        }
        
        // Handle variable patterns  
        if (pattern_obj.object.get("var")) |var_obj| {
            if (var_obj != .string) return SirsError.InvalidExpression;
            return Pattern{
                .variable = self.allocator.dupe(u8, var_obj.string) catch return SirsError.OutOfMemory,
            };
        }
        
        // Handle wildcard patterns
        if (pattern_obj.object.get("_")) |_| {
            return Pattern.wildcard;
        }
        
        // Handle struct patterns
        if (pattern_obj.object.get("struct")) |struct_obj| {
            if (struct_obj != .object) return SirsError.InvalidExpression;
            
            var patterns = std.StringHashMap(Pattern).init(self.allocator);
            
            var iter = struct_obj.object.iterator();
            while (iter.next()) |entry| {
                const field_name = try self.allocator.dupe(u8, entry.key_ptr.*);
                const field_pattern = try self.parsePattern(entry.value_ptr.*);
                try patterns.put(field_name, field_pattern);
            }
            
            return Pattern{ .@"struct" = patterns };
        }
        
        // Handle enum patterns
        if (pattern_obj.object.get("enum")) |enum_obj| {
            if (enum_obj != .object) return SirsError.InvalidExpression;
            
            const enum_type = enum_obj.object.get("type") orelse return SirsError.MissingField;
            if (enum_type != .string) return SirsError.InvalidExpression;
            
            const variant = enum_obj.object.get("variant") orelse return SirsError.MissingField;
            if (variant != .string) return SirsError.InvalidExpression;
            
            const enum_type_copy = self.allocator.dupe(u8, enum_type.string) catch return SirsError.OutOfMemory;
            const variant_copy = self.allocator.dupe(u8, variant.string) catch return SirsError.OutOfMemory;
            
            var value_pattern: ?*Pattern = null;
            if (enum_obj.object.get("value")) |value_obj| {
                const pattern = try self.parsePattern(value_obj);
                value_pattern = self.allocator.create(Pattern) catch return SirsError.OutOfMemory;
                value_pattern.?.* = pattern;
            }
            
            return Pattern{ 
                .@"enum" = .{
                    .enum_type = enum_type_copy,
                    .variant = variant_copy,
                    .value_pattern = value_pattern,
                },
            };
        }
        
        return SirsError.InvalidStatement;
    }
    
    fn parseLValue(self: *Parser, lvalue_obj: json.Value) SirsError!LValue {
        if (lvalue_obj != .object) return SirsError.InvalidStatement;
        
        // Handle variable lvalue
        if (lvalue_obj.object.get("var")) |var_obj| {
            if (var_obj != .string) return SirsError.InvalidExpression;
            return LValue{
                .variable = self.allocator.dupe(u8, var_obj.string) catch return SirsError.OutOfMemory,
            };
        }
        
        // Handle field access lvalue  
        if (lvalue_obj.object.get("field")) |field_obj| {
            if (field_obj != .object) return SirsError.InvalidStatement;
            
            const object_obj = field_obj.object.get("object") orelse return SirsError.MissingField;
            const field_name = field_obj.object.get("field") orelse return SirsError.MissingField;
            
            if (field_name != .string) return SirsError.InvalidExpression;
            
            const object_lvalue = try self.parseLValue(object_obj);
            const object_ptr = self.allocator.create(LValue) catch return SirsError.OutOfMemory;
            object_ptr.* = object_lvalue;
            
            return LValue{
                .field = .{
                    .object = object_ptr,
                    .field = self.allocator.dupe(u8, field_name.string) catch return SirsError.OutOfMemory,
                },
            };
        }
        
        // Handle index access lvalue
        if (lvalue_obj.object.get("index")) |index_obj| {
            if (index_obj != .object) return SirsError.InvalidStatement;
            
            const array_obj = index_obj.object.get("array") orelse return SirsError.MissingField;
            const index_expr_obj = index_obj.object.get("index") orelse return SirsError.MissingField;
            
            const array_lvalue = try self.parseLValue(array_obj);
            const index_expr = try self.parseExpression(index_expr_obj);
            
            const array_ptr = self.allocator.create(LValue) catch return SirsError.OutOfMemory;
            array_ptr.* = array_lvalue;
            
            return LValue{
                .index = .{
                    .array = array_ptr,
                    .index = index_expr,
                },
            };
        }
        
        return SirsError.InvalidStatement;
    }
    
    fn parseExpression(self: *Parser, expr_obj: json.Value) SirsError!Expression {
        if (expr_obj != .object) return SirsError.InvalidExpression;
        
        // Handle literal expressions
        if (expr_obj.object.get("literal")) |literal_obj| {
            return try self.parseLiteral(literal_obj);
        }
        
        // Handle variable expressions
        if (expr_obj.object.get("var")) |var_obj| {
            if (var_obj != .string) return SirsError.InvalidExpression;
            return Expression{
                .variable = self.allocator.dupe(u8, var_obj.string) catch return SirsError.OutOfMemory,
            };
        }
        
        // Handle sample expressions
        if (expr_obj.object.get("sample")) |sample_obj| {
            return try self.parseSampleExpression(sample_obj);
        }
        
        // Handle operation expressions
        if (expr_obj.object.get("op")) |op_obj| {
            return try self.parseOpExpression(op_obj);
        }
        
        // Handle call expressions
        if (expr_obj.object.get("call")) |call_obj| {
            return try self.parseCallExpression(call_obj);
        }
        
        // Handle struct literal expressions
        if (expr_obj.object.get("struct")) |struct_obj| {
            return try self.parseStructExpression(struct_obj);
        }
        
        // Handle field access expressions
        if (expr_obj.object.get("field")) |field_obj| {
            return try self.parseFieldExpression(field_obj);
        }
        
        // Handle array literal expressions
        if (expr_obj.object.get("array")) |array_obj| {
            return try self.parseArrayExpression(array_obj);
        }
        
        // Handle array index expressions
        if (expr_obj.object.get("index")) |index_obj| {
            return try self.parseIndexExpression(index_obj);
        }
        
        // Handle enum constructor expressions
        if (expr_obj.object.get("enum")) |enum_obj| {
            return try self.parseEnumConstructorExpression(enum_obj);
        }
        
        // Handle hashmap expressions
        if (expr_obj.object.get("hashmap")) |hashmap_obj| {
            return try self.parseHashMapExpression(hashmap_obj);
        }
        
        // Handle set expressions
        if (expr_obj.object.get("set")) |set_obj| {
            return try self.parseSetExpression(set_obj);
        }
        
        // Handle tuple expressions
        if (expr_obj.object.get("tuple")) |tuple_obj| {
            return try self.parseTupleExpression(tuple_obj);
        }
        
        // Handle record expressions
        if (expr_obj.object.get("record")) |record_obj| {
            return try self.parseRecordExpression(record_obj);
        }
        
        return SirsError.InvalidExpression;
    }
    
    fn parseCallExpression(self: *Parser, call_obj: json.Value) SirsError!Expression {
        if (call_obj != .object) return SirsError.InvalidExpression;
        
        const function_name = call_obj.object.get("function") orelse return SirsError.MissingField;
        if (function_name != .string) return SirsError.InvalidExpression;
        
        const args_obj = call_obj.object.get("args") orelse return SirsError.MissingField;
        if (args_obj != .array) return SirsError.InvalidExpression;
        
        var args = ArrayList(Expression).init(self.allocator);
        for (args_obj.array.items) |arg_obj| {
            const arg = try self.parseExpression(arg_obj);
            args.append(arg) catch return SirsError.OutOfMemory;
        }
        
        return Expression{
            .call = .{
                .function = self.allocator.dupe(u8, function_name.string) catch return SirsError.OutOfMemory,
                .args = args,
            },
        };
    }
    
    fn parseStructExpression(self: *Parser, struct_obj: json.Value) SirsError!Expression {
        if (struct_obj != .object) return SirsError.InvalidExpression;
        
        var fields = std.StringHashMap(Expression).init(self.allocator);
        
        var field_iter = struct_obj.object.iterator();
        while (field_iter.next()) |entry| {
            const field_name = entry.key_ptr.*;
            const field_value_obj = entry.value_ptr.*;
            
            const field_value = try self.parseExpression(field_value_obj);
            const field_name_copy = self.allocator.dupe(u8, field_name) catch return SirsError.OutOfMemory;
            
            fields.put(field_name_copy, field_value) catch return SirsError.OutOfMemory;
        }
        
        return Expression{
            .@"struct" = fields,
        };
    }
    
    fn parseFieldExpression(self: *Parser, field_obj: json.Value) SirsError!Expression {
        if (field_obj != .object) return SirsError.InvalidExpression;
        
        const object_obj = field_obj.object.get("object") orelse return SirsError.MissingField;
        const field_name_obj = field_obj.object.get("field") orelse return SirsError.MissingField;
        
        if (field_name_obj != .string) return SirsError.InvalidExpression;
        
        const object_expr = try self.parseExpression(object_obj);
        const object_ptr = self.allocator.create(Expression) catch return SirsError.OutOfMemory;
        object_ptr.* = object_expr;
        
        return Expression{
            .field = .{
                .object = object_ptr,
                .field = self.allocator.dupe(u8, field_name_obj.string) catch return SirsError.OutOfMemory,
            },
        };
    }
    
    fn parseArrayExpression(self: *Parser, array_obj: json.Value) SirsError!Expression {
        if (array_obj != .array) return SirsError.InvalidExpression;
        
        var elements = ArrayList(Expression).init(self.allocator);
        
        for (array_obj.array.items) |elem_obj| {
            const elem_expr = try self.parseExpression(elem_obj);
            elements.append(elem_expr) catch return SirsError.OutOfMemory;
        }
        
        return Expression{
            .array = elements,
        };
    }
    
    fn parseIndexExpression(self: *Parser, index_obj: json.Value) SirsError!Expression {
        if (index_obj != .object) return SirsError.InvalidExpression;
        
        const array_obj = index_obj.object.get("array") orelse return SirsError.MissingField;
        const index_expr_obj = index_obj.object.get("index") orelse return SirsError.MissingField;
        
        const array_expr = try self.parseExpression(array_obj);
        const index_expr = try self.parseExpression(index_expr_obj);
        
        const array_ptr = self.allocator.create(Expression) catch return SirsError.OutOfMemory;
        const index_ptr = self.allocator.create(Expression) catch return SirsError.OutOfMemory;
        array_ptr.* = array_expr;
        index_ptr.* = index_expr;
        
        return Expression{
            .index = .{
                .array = array_ptr,
                .index = index_ptr,
            },
        };
    }
    
    fn parseLiteral(self: *Parser, literal_obj: json.Value) SirsError!Expression {
        switch (literal_obj) {
            .integer => |i| return Expression{ .literal = Literal{ .integer = i } },
            .float => |f| return Expression{ .literal = Literal{ .float = f } },
            .string => |s| return Expression{ .literal = Literal{ .string = self.allocator.dupe(u8, s) catch return SirsError.OutOfMemory } },
            .bool => |b| return Expression{ .literal = Literal{ .boolean = b } },
            .null => return Expression{ .literal = Literal.null },
            else => return SirsError.InvalidExpression,
        }
    }
    
    fn parseSampleExpression(self: *Parser, sample_obj: json.Value) SirsError!Expression {
        if (sample_obj != .object) return SirsError.InvalidExpression;
        
        const distribution = sample_obj.object.get("distribution") orelse return SirsError.MissingField;
        if (distribution != .string) return SirsError.InvalidType;
        
        var params = ArrayList(Expression).init(self.allocator);
        
        if (sample_obj.object.get("params")) |params_obj| {
            if (params_obj != .array) return SirsError.InvalidType;
            
            for (params_obj.array.items) |param_obj| {
                const param_expr = try self.parseExpression(param_obj);
                params.append(param_expr) catch return SirsError.OutOfMemory;
            }
        }
        
        return Expression{
            .sample = .{
                .distribution = self.allocator.dupe(u8, distribution.string) catch return SirsError.OutOfMemory,
                .params = params,
            },
        };
    }
    
    fn parseOpExpression(self: *Parser, op_obj: json.Value) SirsError!Expression {
        if (op_obj != .object) return SirsError.InvalidExpression;
        
        const kind_obj = op_obj.object.get("kind") orelse return SirsError.MissingField;
        if (kind_obj != .string) return SirsError.InvalidType;
        
        const op_kind = try self.parseOpKind(kind_obj.string);
        
        const args_obj = op_obj.object.get("args") orelse return SirsError.MissingField;
        if (args_obj != .array) return SirsError.InvalidType;
        
        var args = ArrayList(Expression).init(self.allocator);
        for (args_obj.array.items) |arg_obj| {
            const arg_expr = try self.parseExpression(arg_obj);
            args.append(arg_expr) catch return SirsError.OutOfMemory;
        }
        
        return Expression{
            .op = .{
                .kind = op_kind,
                .args = args,
            },
        };
    }
    
    fn parseOpKind(_: *Parser, op_str: []const u8) SirsError!OpKind {
        if (std.mem.eql(u8, op_str, "add")) return OpKind.add;
        if (std.mem.eql(u8, op_str, "sub")) return OpKind.sub;
        if (std.mem.eql(u8, op_str, "mul")) return OpKind.mul;
        if (std.mem.eql(u8, op_str, "div")) return OpKind.div;
        if (std.mem.eql(u8, op_str, "mod")) return OpKind.mod;
        if (std.mem.eql(u8, op_str, "pow")) return OpKind.pow;
        if (std.mem.eql(u8, op_str, "eq")) return OpKind.eq;
        if (std.mem.eql(u8, op_str, "ne")) return OpKind.ne;
        if (std.mem.eql(u8, op_str, "lt")) return OpKind.lt;
        if (std.mem.eql(u8, op_str, "le")) return OpKind.le;
        if (std.mem.eql(u8, op_str, "gt")) return OpKind.gt;
        if (std.mem.eql(u8, op_str, "ge")) return OpKind.ge;
        if (std.mem.eql(u8, op_str, "and")) return OpKind.@"and";
        if (std.mem.eql(u8, op_str, "or")) return OpKind.@"or";
        if (std.mem.eql(u8, op_str, "not")) return OpKind.not;
        if (std.mem.eql(u8, op_str, "bitand")) return OpKind.bitand;
        if (std.mem.eql(u8, op_str, "bitor")) return OpKind.bitor;
        if (std.mem.eql(u8, op_str, "bitxor")) return OpKind.bitxor;
        if (std.mem.eql(u8, op_str, "bitnot")) return OpKind.bitnot;
        if (std.mem.eql(u8, op_str, "shl")) return OpKind.shl;
        if (std.mem.eql(u8, op_str, "shr")) return OpKind.shr;
        
        return SirsError.InvalidExpression;
    }
    
    fn parseEnumConstructorExpression(self: *Parser, enum_obj: json.Value) SirsError!Expression {
        if (enum_obj != .object) return SirsError.InvalidExpression;
        
        const enum_type = enum_obj.object.get("type") orelse return SirsError.MissingField;
        if (enum_type != .string) return SirsError.InvalidExpression;
        
        const variant = enum_obj.object.get("variant") orelse return SirsError.MissingField;
        if (variant != .string) return SirsError.InvalidExpression;
        
        const enum_type_copy = self.allocator.dupe(u8, enum_type.string) catch return SirsError.OutOfMemory;
        const variant_copy = self.allocator.dupe(u8, variant.string) catch return SirsError.OutOfMemory;
        
        var value_expr: ?*Expression = null;
        if (enum_obj.object.get("value")) |value_obj| {
            const expr = try self.parseExpression(value_obj);
            value_expr = self.allocator.create(Expression) catch return SirsError.OutOfMemory;
            value_expr.?.* = expr;
        }
        
        return Expression{
            .enum_constructor = .{
                .enum_type = enum_type_copy,
                .variant = variant_copy,
                .value = value_expr,
            },
        };
    }
    
    fn parseHashMapExpression(self: *Parser, hashmap_obj: json.Value) SirsError!Expression {
        if (hashmap_obj != .object) return SirsError.InvalidExpression;
        
        var map = std.StringHashMap(Expression).init(self.allocator);
        
        var map_iter = hashmap_obj.object.iterator();
        while (map_iter.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const value_expr = try self.parseExpression(entry.value_ptr.*);
            
            try map.put(key, value_expr);
        }
        
        return Expression{ .hashmap = map };
    }
    
    fn parseSetExpression(self: *Parser, set_obj: json.Value) SirsError!Expression {
        if (set_obj != .array) return SirsError.InvalidExpression;
        
        var elements = ArrayList(Expression).init(self.allocator);
        
        for (set_obj.array.items) |elem_obj| {
            const elem_expr = try self.parseExpression(elem_obj);
            try elements.append(elem_expr);
        }
        
        return Expression{ .set = elements };
    }
    
    fn parseTupleExpression(self: *Parser, tuple_obj: json.Value) SirsError!Expression {
        if (tuple_obj != .array) return SirsError.InvalidExpression;
        
        var elements = ArrayList(Expression).init(self.allocator);
        
        for (tuple_obj.array.items) |elem_obj| {
            const elem_expr = try self.parseExpression(elem_obj);
            try elements.append(elem_expr);
        }
        
        return Expression{ .tuple = elements };
    }
    
    fn parseRecordExpression(self: *Parser, record_obj: json.Value) SirsError!Expression {
        if (record_obj != .object) return SirsError.InvalidExpression;
        
        const type_name = record_obj.object.get("type") orelse return SirsError.MissingField;
        if (type_name != .string) return SirsError.InvalidExpression;
        
        const fields_obj = record_obj.object.get("fields") orelse return SirsError.MissingField;
        if (fields_obj != .object) return SirsError.InvalidExpression;
        
        const type_name_copy = try self.allocator.dupe(u8, type_name.string);
        var fields = std.StringHashMap(Expression).init(self.allocator);
        
        var field_iter = fields_obj.object.iterator();
        while (field_iter.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const value_expr = try self.parseExpression(entry.value_ptr.*);
            
            try fields.put(key, value_expr);
        }
        
        return Expression{ 
            .record = .{
                .type_name = type_name_copy,
                .fields = fields,
            }
        };
    }
    
    fn parseComplexType(self: *Parser, type_obj: json.Value) SirsError!Type {
        if (type_obj != .object) return SirsError.InvalidType;
        
        // Handle enum type definitions
        if (type_obj.object.get("enum")) |enum_obj| {
            if (enum_obj != .object) return SirsError.InvalidType;
            
            const name = enum_obj.object.get("name") orelse return SirsError.MissingField;
            if (name != .string) return SirsError.InvalidType;
            
            const variants_obj = enum_obj.object.get("variants") orelse return SirsError.MissingField;
            if (variants_obj != .object) return SirsError.InvalidType;
            
            var variants = std.StringHashMap(?*Type).init(self.allocator);
            
            var variant_iter = variants_obj.object.iterator();
            while (variant_iter.next()) |entry| {
                const variant_name = try self.allocator.dupe(u8, entry.key_ptr.*);
                
                var variant_type: ?*Type = null;
                if (entry.value_ptr.* != .null) {
                    // Parse associated type if present
                    const associated_type = try self.parseType(entry.value_ptr.*);
                    variant_type = try self.allocator.create(Type);
                    variant_type.?.* = associated_type;
                }
                
                try variants.put(variant_name, variant_type);
            }
            
            return Type{
                .@"enum" = .{
                    .name = try self.allocator.dupe(u8, name.string),
                    .variants = variants,
                },
            };
        }
        
        // Handle discriminated union type definitions
        if (type_obj.object.get("discriminated_union")) |union_obj| {
            if (union_obj != .object) return SirsError.InvalidType;
            
            const name = union_obj.object.get("name") orelse return SirsError.MissingField;
            if (name != .string) return SirsError.InvalidType;
            
            const variants_obj = union_obj.object.get("variants") orelse return SirsError.MissingField;
            if (variants_obj != .array) return SirsError.InvalidType;
            
            var variants = ArrayList(*Type).init(self.allocator);
            
            for (variants_obj.array.items) |variant_obj| {
                const variant_type = try self.allocator.create(Type);
                variant_type.* = try self.parseType(variant_obj);
                try variants.append(variant_type);
            }
            
            return Type{
                .discriminated_union = .{
                    .name = try self.allocator.dupe(u8, name.string),
                    .variants = variants,
                },
            };
        }
        
        // Handle error type definitions
        if (type_obj.object.get("error")) |error_obj| {
            if (error_obj != .object) return SirsError.InvalidType;
            
            const name = error_obj.object.get("name") orelse return SirsError.MissingField;
            if (name != .string) return SirsError.InvalidType;
            
            var message_type: ?*Type = null;
            if (error_obj.object.get("message_type")) |msg_type_obj| {
                const parsed_type = try self.parseType(msg_type_obj);
                message_type = try self.allocator.create(Type);
                message_type.?.* = parsed_type;
            }
            
            return Type{
                .@"error" = .{
                    .name = try self.allocator.dupe(u8, name.string),
                    .message_type = message_type,
                },
            };
        }
        
        // Handle tuple type definitions
        if (type_obj.object.get("tuple")) |tuple_obj| {
            if (tuple_obj != .array) return SirsError.InvalidType;
            
            var element_types = ArrayList(*Type).init(self.allocator);
            
            for (tuple_obj.array.items) |elem_type_obj| {
                const elem_type = try self.parseType(elem_type_obj);
                const elem_type_ptr = try self.allocator.create(Type);
                elem_type_ptr.* = elem_type;
                try element_types.append(elem_type_ptr);
            }
            
            return Type{ .tuple = element_types };
        }
        
        // Handle record type definitions
        if (type_obj.object.get("record")) |record_obj| {
            if (record_obj != .object) return SirsError.InvalidType;
            
            const name = record_obj.object.get("name") orelse return SirsError.MissingField;
            if (name != .string) return SirsError.InvalidType;
            
            const fields_obj = record_obj.object.get("fields") orelse return SirsError.MissingField;
            if (fields_obj != .object) return SirsError.InvalidType;
            
            var fields = std.StringHashMap(*Type).init(self.allocator);
            var field_iter = fields_obj.object.iterator();
            while (field_iter.next()) |entry| {
                const field_name = try self.allocator.dupe(u8, entry.key_ptr.*);
                const field_type = try self.parseType(entry.value_ptr.*);
                const field_type_ptr = try self.allocator.create(Type);
                field_type_ptr.* = field_type;
                try fields.put(field_name, field_type_ptr);
            }
            
            return Type{
                .record = .{
                    .name = try self.allocator.dupe(u8, name.string),
                    .fields = fields,
                },
            };
        }
        
        // Handle generic type definitions: {"generic": {"name": "Vec", "params": ["T"], "definition": ...}}
        if (type_obj.object.get("generic_def")) |generic_obj| {
            if (generic_obj != .object) return SirsError.InvalidType;
            
            const name = generic_obj.object.get("name") orelse return SirsError.MissingField;
            if (name != .string) return SirsError.InvalidType;
            
            const params_obj = generic_obj.object.get("params") orelse return SirsError.MissingField;
            if (params_obj != .array) return SirsError.InvalidType;
            
            const definition_obj = generic_obj.object.get("definition") orelse return SirsError.MissingField;
            
            var type_params = ArrayList([]const u8).init(self.allocator);
            for (params_obj.array.items) |param_obj| {
                if (param_obj != .string) return SirsError.InvalidType;
                const param_name = try self.allocator.dupe(u8, param_obj.string);
                try type_params.append(param_name);
            }
            
            _ = try self.parseType(definition_obj);
            
            // This is a generic type definition, not a concrete type
            // We'll handle this differently in the parsing context
            return SirsError.InvalidType; // Temporary - should be handled by program parsing
        }
        
        // Handle interface definition: {"interface": {"name": "Display", "params": ["T"], "methods": {...}}}
        if (type_obj.object.get("interface")) |interface_obj| {
            if (interface_obj != .object) return SirsError.InvalidType;
            
            const name = interface_obj.object.get("name") orelse return SirsError.MissingField;
            if (name != .string) return SirsError.InvalidType;
            
            const methods_obj = interface_obj.object.get("methods") orelse return SirsError.MissingField;
            if (methods_obj != .object) return SirsError.InvalidType;
            
            var type_params: ?ArrayList([]const u8) = null;
            if (interface_obj.object.get("params")) |params_obj| {
                if (params_obj != .array) return SirsError.InvalidType;
                
                var params_list = ArrayList([]const u8).init(self.allocator);
                for (params_obj.array.items) |param_obj| {
                    if (param_obj != .string) return SirsError.InvalidType;
                    const param_name = try self.allocator.dupe(u8, param_obj.string);
                    try params_list.append(param_name);
                }
                type_params = params_list;
            }
            
            var methods = std.StringHashMap(FunctionSignature).init(self.allocator);
            var method_iter = methods_obj.object.iterator();
            while (method_iter.next()) |entry| {
                const method_name = try self.allocator.dupe(u8, entry.key_ptr.*);
                const signature = try self.parseFunctionSignature(entry.value_ptr.*);
                try methods.put(method_name, signature);
            }
            
            return Type{
                .@"interface" = .{
                    .name = try self.allocator.dupe(u8, name.string),
                    .methods = methods,
                },
            };
        }
        
        // Handle other complex types here (structs, unions, etc.)
        return SirsError.InvalidType;
    }
    
    fn parseGenericTypeDefinition(self: *Parser, generic_obj: json.Value) SirsError!GenericType {
        if (generic_obj != .object) return SirsError.InvalidType;
        
        const name = generic_obj.object.get("name") orelse return SirsError.MissingField;
        if (name != .string) return SirsError.InvalidType;
        
        const params_obj = generic_obj.object.get("params") orelse return SirsError.MissingField;
        if (params_obj != .array) return SirsError.InvalidType;
        
        const definition_obj = generic_obj.object.get("definition") orelse return SirsError.MissingField;
        
        var type_params = ArrayList([]const u8).init(self.allocator);
        for (params_obj.array.items) |param_obj| {
            if (param_obj != .string) return SirsError.InvalidType;
            const param_name = try self.allocator.dupe(u8, param_obj.string);
            try type_params.append(param_name);
        }
        
        const definition = try self.parseType(definition_obj);
        
        return GenericType{
            .name = try self.allocator.dupe(u8, name.string),
            .type_params = type_params,
            .definition = definition,
        };
    }
    
    fn parseFunctionSignature(self: *Parser, sig_obj: json.Value) SirsError!FunctionSignature {
        if (sig_obj != .object) return SirsError.InvalidType;
        
        const args_obj = sig_obj.object.get("args") orelse return SirsError.MissingField;
        if (args_obj != .array) return SirsError.InvalidType;
        
        const return_obj = sig_obj.object.get("return") orelse return SirsError.MissingField;
        
        var args = ArrayList(Type).init(self.allocator);
        for (args_obj.array.items) |arg_obj| {
            const arg_type = try self.parseType(arg_obj);
            try args.append(arg_type);
        }
        
        const return_type = try self.parseType(return_obj);
        
        var type_params: ?ArrayList([]const u8) = null;
        if (sig_obj.object.get("type_params")) |params_obj| {
            if (params_obj != .array) return SirsError.InvalidType;
            
            var params_list = ArrayList([]const u8).init(self.allocator);
            for (params_obj.array.items) |param_obj| {
                if (param_obj != .string) return SirsError.InvalidType;
                const param_name = try self.allocator.dupe(u8, param_obj.string);
                try params_list.append(param_name);
            }
            type_params = params_list;
        }
        
        return FunctionSignature{
            .args = args,
            .@"return" = return_type,
            .type_params = type_params,
        };
    }
    
    fn parseInterface(self: *Parser, interface_obj: json.Value) SirsError!Interface {
        if (interface_obj != .object) return SirsError.InvalidType;
        
        const name = interface_obj.object.get("name") orelse return SirsError.MissingField;
        if (name != .string) return SirsError.InvalidType;
        
        var type_params: ?ArrayList([]const u8) = null;
        if (interface_obj.object.get("type_params")) |params_obj| {
            if (params_obj != .array) return SirsError.InvalidType;
            
            var params_list = ArrayList([]const u8).init(self.allocator);
            for (params_obj.array.items) |param_obj| {
                if (param_obj != .string) return SirsError.InvalidType;
                const param_name = try self.allocator.dupe(u8, param_obj.string);
                try params_list.append(param_name);
            }
            type_params = params_list;
        }
        
        const methods_obj = interface_obj.object.get("methods") orelse return SirsError.MissingField;
        if (methods_obj != .object) return SirsError.InvalidType;
        
        var methods = std.StringHashMap(FunctionSignature).init(self.allocator);
        var method_iter = methods_obj.object.iterator();
        while (method_iter.next()) |entry| {
            const method_name = try self.allocator.dupe(u8, entry.key_ptr.*);
            const signature = try self.parseFunctionSignature(entry.value_ptr.*);
            try methods.put(method_name, signature);
        }
        
        return Interface{
            .name = try self.allocator.dupe(u8, name.string),
            .type_params = type_params,
            .methods = methods,
        };
    }
    
    fn parseTraitImpl(self: *Parser, trait_impl_obj: json.Value) SirsError!TraitImpl {
        if (trait_impl_obj != .object) return SirsError.InvalidType;
        
        const trait_name = trait_impl_obj.object.get("trait_name") orelse return SirsError.MissingField;
        if (trait_name != .string) return SirsError.InvalidType;
        
        const target_type_obj = trait_impl_obj.object.get("target_type") orelse return SirsError.MissingField;
        const target_type = try self.parseType(target_type_obj);
        
        var type_args: ?ArrayList(*Type) = null;
        if (trait_impl_obj.object.get("type_args")) |args_obj| {
            if (args_obj != .array) return SirsError.InvalidType;
            
            var args_list = ArrayList(*Type).init(self.allocator);
            for (args_obj.array.items) |arg_obj| {
                const arg_type = try self.allocator.create(Type);
                arg_type.* = try self.parseType(arg_obj);
                try args_list.append(arg_type);
            }
            type_args = args_list;
        }
        
        const methods_obj = trait_impl_obj.object.get("methods") orelse return SirsError.MissingField;
        if (methods_obj != .object) return SirsError.InvalidType;
        
        var methods = std.StringHashMap(Function).init(self.allocator);
        var method_iter = methods_obj.object.iterator();
        while (method_iter.next()) |entry| {
            const method_name = try self.allocator.dupe(u8, entry.key_ptr.*);
            const function = try self.parseFunction(entry.value_ptr.*);
            try methods.put(method_name, function);
        }
        
        return TraitImpl{
            .trait_name = try self.allocator.dupe(u8, trait_name.string),
            .target_type = target_type,
            .type_args = type_args,
            .methods = methods,
        };
    }
};