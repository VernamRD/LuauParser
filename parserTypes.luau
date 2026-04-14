local ParserTypes = {}

export type LuauDecl = {
    attributes_line: number, -- line number of the @luau attributes
    attributes_str: string, -- line with @luau attributes
    declaration_line: number, -- line number of the start declaration (function or field)
    declaration_str: string, -- the declaration line, function signature and field declaration include inline definition
    scope: {string}? -- e.g. {"namespace", "class"}
}

export type ParsedArgType = "Nil" | "Boolean" | "Number" | "String"
ParserTypes.ParsedArgType = table.freeze({
    Nil = "Nil" :: ParsedArgType,
    Boolean = "Boolean" :: ParsedArgType,
    Number = "Number" :: ParsedArgType,
    String = "String" :: ParsedArgType,
})

ParserTypes.ArgTypeMapping = table.freeze({
    ["nil"] = "Nil",
    ["boolean"] = "Boolean",
    ["int"] = "Number",
    ["float"] = "Number",
    ["double"] = "Number",
    ["std::size_t"] = "Number",
    ["std::int8_t"] = "Number",
    ["std::int16_t"] = "Number",
    ["std::int32_t"] = "Number",
    ["std::int64_t"] = "Number",
    ["std::uint8_t"] = "Number",
    ["std::uint16_t"] = "Number",
    ["std::uint32_t"] = "Number",
    ["std::uint64_t"] = "Number",
    ["std::string"] = "String",
})

export type ParsedArg = {
    name: string,
    type: ParsedArgType,
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