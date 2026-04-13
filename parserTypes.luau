local ParserTypes = {}

export type LuauDecl = {
    attributes_line: number, -- line number of the @luau attributes
    attributes_str: string, -- line with @luau attributes
    declaration_line: number, -- line number of the start declaration (function or field)
    declaration_strs: {string}, -- lines of the declaration, function signature and field declaration include inline definition
    scope: {string}? -- e.g. {"namespace", "class"}
}

export type ParsedDecl = {
    kind: string,       -- "function" | "field" | "unknown"
    name: string,
    ret_type: string?,  -- only for function
    field_type: string?, -- only for field
    args: {}?,
    is_const: boolean,
    is_static: boolean,
    scope: {string}? -- e.g. {"namespace", "class"}
}

export type ScopeKind = "root" | "block" | "namespace" | "class" | "enum" | "unknown"
ParserTypes.ScopeKind = table.freeze({
    Root = "root" :: ScopeKind,
    Block = "block" :: ScopeKind,
    Namespace = "namespace" :: ScopeKind,
    Class = "class" :: ScopeKind,
    Enum = "enum" :: ScopeKind,
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