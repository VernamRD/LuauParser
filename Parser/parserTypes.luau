local ParserTypes = {}

-- Print intermediate and temp values
ParserTypes.verbose_print = false

export type LuauDecl = {
    attributes_line: number, -- line number of the @luau attributes
    attributes_str: string, -- line with @luau attributes
    declaration_line: number, -- line number of the start declaration (function or field)
    declaration_str: string, -- the declaration line, function signature and field declaration include inline definition
    scope: {ScopeDecl}? -- e.g. {"namespace", "class"}
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
    ["nil"] = "nil",
    ["bool"] = "boolean",
    ["int"] = "number",
    ["float"] = "number",
    ["double"] = "number",
    ["std::size_t"] = "number",
    ["std::int8_t"] = "number",
    ["std::int16_t"] = "number",
    ["std::int32_t"] = "number",
    ["std::int64_t"] = "number",
    ["std::uint8_t"] = "number",
    ["std::uint16_t"] = "number",
    ["std::uint32_t"] = "number",
    ["std::uint64_t"] = "number",
    ["std::string"] = "string",
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

export type DeclKind = "function" | "field" | "unknown"
ParserTypes.DeclKind = table.freeze({
    Function = "function" :: DeclKind,
    Field = "field" :: DeclKind,
    Unknown = "unknown" :: DeclKind,
})

export type ScopeDecl = {
    kind: ScopeKind,
    name: string,
}

export type ParsedDeclFunc = {
    kind: DeclKind,
    name: string,
    attributes: {LuauAttr}?,    -- parsed attributes from the @luau line
    ret_type: ParsedArgType?,   -- return type in luau
    ret_original_type: string?, -- return type in c++
    args: {ParsedArg}?,
    is_const: boolean,
    is_static: boolean,
    is_field: boolean,          -- is field of class/struct
    scope: {ScopeDecl}?         -- e.g. {"namespace", "class"}
}

export type ScopeKind = "root" | "block" | "namespace" | "class" | "struct" | "enum" | "inline" |"unknown"
ParserTypes.ScopeKind = table.freeze({
    Root = "root" :: ScopeKind,
    Block = "block" :: ScopeKind,
    Namespace = "namespace" :: ScopeKind,
    Class = "class" :: ScopeKind,
    Struct = "struct" :: ScopeKind,
    Enum = "enum" :: ScopeKind,
    Inline = "inline" :: ScopeKind,
    Unknown = "unknown" :: ScopeKind,
})

export type ScopeNode = {
    kind: ScopeKind,
    name: string,
    children: {ScopeNode},
    parent: ScopeNode?,
    line_start: number?, 
    line_end: number?,
}



return ParserTypes