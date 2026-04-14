local ParserTypes = {}

export type LuauDecl = {
    attributes_line: number, -- line number of the @luau attributes
    attributes_str: string, -- line with @luau attributes
    declaration_line: number, -- line number of the start declaration (function or field)
    declaration_str: string, -- the declaration line, function signature and field declaration include inline definition
    scope: {string}? -- e.g. {"namespace", "class"}
}

export type ParsedArg = {
    name: string,
    type: string,
    default: string?,
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

export type ParsedDecl = {
    kind: string,       -- "function" | "field" | "unknown"
    name: string,
    attributes: {LuauAttr}?, -- parsed attributes from the @luau line
    ret_type: string?,  -- only for function
    field_type: string?, -- only for field
    args: {ParsedArg}?,
    is_const: boolean,
    is_static: boolean,
    scope: {string}? -- e.g. {"namespace", "class"}
}

ParserTypes.ParsedType = table.freeze({
    Nil = {},
    Boolean = {"boolean"},
    Number = {"int", "float", "double", "std::size_t", "std::int8_t", "std::int16_t", "std::int32_t", "std::int64_t", "std::uint8_t", "std::uint16_t", "std::uint32_t", "std::uint64_t"},
    String = {"std::string"},
})

export type ScopeKind = "root" | "block" | "namespace" | "class" | "enum" | "inline" |"unknown"
ParserTypes.ScopeKind = table.freeze({
    Root = "root" :: ScopeKind,
    Block = "block" :: ScopeKind,
    Namespace = "namespace" :: ScopeKind,
    Class = "class" :: ScopeKind,
    Enum = "enum" :: ScopeKind,
    Inline = "inline" :: ScopeKind,
    Unknown = "unknown" :: ScopeKind,
})

export type ScopeNode = {
    kind: ScopeKind,
    name: string,
    children: {ScopeNode},
    line_start: number?, 
    line_end: number?,
    contains_luau: boolean?, -- whether this scope contains any @luau declarations (for optimization)
}



return ParserTypes