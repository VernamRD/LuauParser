local ParserTypes = {}

-- Print intermediate and temp values
ParserTypes.verbose_print = false

export type LuauDecl = {
    attributes_line: number, -- line number of the @luau attributes
    attributes_str: string, -- line with @luau attributes
    declaration_line: number, -- line number of the start declaration (function or field)
    declaration_str: string, -- the declaration line, function signature and field declaration include inline definition
    scope: {ScopeDecl} -- e.g. {"namespace", "class"}
}

export type ParsedArgType = "nil" | "boolean" | "number" | "string" | "userdata"
ParserTypes.ParsedArgType = table.freeze({
    Nil = "nil" :: ParsedArgType,
    Boolean = "boolean" :: ParsedArgType,
    Number = "number" :: ParsedArgType,
    String = "string" :: ParsedArgType,
    Userdata = "userdata" :: ParsedArgType
})

ParserTypes.ArgTypeMapping = table.freeze({
    ["nil"] = ParserTypes.ParsedArgType.Nil,
    ["bool"] = ParserTypes.ParsedArgType.Boolean,
    ["int"] = ParserTypes.ParsedArgType.Number,
    ["float"] = ParserTypes.ParsedArgType.Number,
    ["double"] = ParserTypes.ParsedArgType.Number,
    ["std::size_t"] = ParserTypes.ParsedArgType.Number,
    ["std::int8_t"] = ParserTypes.ParsedArgType.Number,
    ["std::int16_t"] = ParserTypes.ParsedArgType.Number,
    ["std::int32_t"] = ParserTypes.ParsedArgType.Number,
    ["std::int64_t"] = ParserTypes.ParsedArgType.Number,
    ["std::uint8_t"] = ParserTypes.ParsedArgType.Number,
    ["std::uint16_t"] = ParserTypes.ParsedArgType.Number,
    ["std::uint32_t"] = ParserTypes.ParsedArgType.Number,
    ["std::uint64_t"] = ParserTypes.ParsedArgType.Number,
    ["std::string"] = ParserTypes.ParsedArgType.String,
})

export type ParsedArg = {
    name: string,
    type: ParsedArgType,
    default: string?,
    original_type: string, -- the original C++ type as a string, e.g. "int", "float"
    is_self: boolean?
}

export type LuauAttrType = "export" | "rename" | "undefined"
ParserTypes.LuauAttrType = table.freeze({
    Export = "export" :: LuauAttrType,
    Rename = "rename" :: LuauAttrType,
    Undefined = "undefined" :: LuauAttrType,
})
export type LuauAttr = {
    type: LuauAttrType,
    value: string | boolean, -- e.g. for "export" it will be true, for "rename" it will be the new name
}

export type DeclKind = "function" | "variable" | "enum" | "class" | "struct" | "unknown"
ParserTypes.DeclKind = table.freeze({
    Function = "function" :: DeclKind,
    Variable = "variable" :: DeclKind,
    Enum = "enum" :: DeclKind,
    Class = "class" :: DeclKind,
    Struct = "struct" :: DeclKind,
    Unknown = "unknown" :: DeclKind,
})

export type ScopeKind = "block" | "namespace" | "class" | "struct" | "enum" | "inline" | "unknown"
ParserTypes.ScopeKind = table.freeze({
    Block = "block" :: ScopeKind,
    Namespace = "namespace" :: ScopeKind,
    Class = "class" :: ScopeKind,
    Struct = "struct" :: ScopeKind,
    Enum = "enum" :: ScopeKind,
    Inline = "inline" :: ScopeKind,
    Unknown = "unknown" :: ScopeKind,
})

export type ScopeDecl = {
    kind: ScopeKind,
    name: string,
}

function ParserTypes.scope_decl_to_string_arr(scope: {ScopeDecl}): {string}
    local scope_parts: {string} = {}
    for _, scope_part in scope do
        if scope_part.kind == ParserTypes.ScopeKind.Root then
            continue
        end

        table.insert(scope_parts, scope_part.name)
    end

    return scope_parts
end

function ParserTypes.concat_scope(scope: {ScopeDecl}): string
    return table.concat(ParserTypes.scope_decl_to_string_arr(scope), "::")
end

export type FunctionDecl = {
    ret_type: ParsedArgType?,      -- return type in luau
    ret_original_type: string?,    -- return type in c++
    args: {ParsedArg}?,            -- arguments (includes synthetic `self` for instance methods)
    is_const: boolean,             -- is const method
    is_static: boolean,            -- is static method / free function
    is_field: boolean,             -- is this a method of a class/struct (vs. free/namespace function)
}

export type VariableDecl = {
    var_type: ParsedArgType,       -- variable type in luau
    var_original_type: string,     -- variable type in c++
    is_const: boolean,
    is_static: boolean,
    is_field: boolean,             -- is this a class/struct field (vs. free/namespace variable)
    default: string?,              -- default value/initializer, if any
}

export type ClassDecl = {
    is_struct: boolean,            -- `class` vs `struct` keyword
    base: string?,                 -- fully-qualified base class name, if any (single inheritance only)
}

export type EnumValueDecl = {
    name: string,
    value: number?,                -- explicit numeric value, if given (e.g. `FOO = 5`)
}

export type EnumDecl = {
    underlying_type: string?,      -- e.g. "uint32_t" for `enum class Foo : uint32_t`
    is_enum_class: boolean,        -- `enum class` vs. plain `enum`
    values: {EnumValueDecl},
}

export type ParsedDecl = {
    kind: DeclKind,
    name: string,
    scope: {ScopeDecl},           -- e.g. {"Namespace", "Class"}
    attributes: {LuauAttr}?,      -- parsed attributes from the @luau line

    -- Exactly one of these is set, matching `kind`:
    ["function"]: FunctionDecl?,
    variable: VariableDecl?,
    ["class"]: ClassDecl?,        -- used for both Class and Struct kinds
    ["enum"]: EnumDecl?,
}

-- Class Registry
--
-- Populated whenever a class/struct declaration carries `@luau export`.
-- Lets a builder resolving some other declaration's argument/return type
-- of "MyClass" find where MyClass actually lives (scope + header to
-- #include). One entry per exported class/struct, per header parsed;
-- merging entries across headers into one target-wide registry is a
-- separate aggregation step, not the parser's concern.
-- ============================================================

export type TypeRegistryEntry = {
    name: string,              -- unqualified class name, e.g. "MyClass"
    scope: {ScopeDecl},        -- full scope path INCLUDING the class itself, e.g. {"core", "math", "MyClass"}
    header: string,            -- header path (relative to project root) that declares it
    kind: DeclKind,
    base: string?,             -- fully-qualified base class name, if any
}
export type TypeRegistry = { TypeRegistryEntry }

-- ============================================================
-- ParseContext
--
-- Shared input handed to every per-kind sub-parser (ParserFunction,
-- ParserVariable, ParserClass, ParserEnum). Each sub-parser's
-- `try_parse(context)` reads only what it needs and returns a
-- ParsedDecl, or nil if the declaration text doesn't match its shape.
-- ============================================================

export type ParseContext = {
    decl_str: string,            -- declaration text, modifiers/qualifiers already stripped
    is_static: boolean,
    is_const: boolean,
    is_field: boolean,           -- true if the innermost enclosing scope is a class/struct
    scope: {ScopeDecl},           -- scope this declaration lives IN (not including itself)
    file_lines: {string},         -- full source file, for sub-parsers needing extra context
    declaration_line: number,     -- line where the declaration starts
    header_path: string,          -- path of the header being parsed (for class registry entries)
    registry: TypeRegistry,      -- shared registry, read/write
}

ParserTypes.parsed_function_prefix = "luau_parsed_func_"


return ParserTypes