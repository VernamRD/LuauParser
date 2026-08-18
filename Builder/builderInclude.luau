--!strict
local ParserTypes = require("../parserTypes")

local BuilderInclude = {}
BuilderInclude.__index = BuilderInclude

local function get_scope_string(scope: {ParserTypes.ScopeDecl}): string
    local scope_arr: {string} = {}

    for _, scope_part in scope do
        if scope_part.kind ~= ParserTypes.ScopeKind.Unknown then
            local scope_str = "\"" .. scope_part.name .. "\""
            table.insert(scope_arr, scope_str)
        end
    end

    return table.concat(scope_arr, ", ")
end

local function start(definition: string, include: string, header_path: string, header_name: string): string
    local result: string = ""

    result ..= "#include \"ParserRegister.h\"\n"
    result ..= "#include \"../include/" .. (string.match(include, "([^/]+)$") or include) .. "\"\n"
    result ..= "#include \"" .. header_path .. "\"\n"
    result ..= "#include \"" .. (string.match(definition, "([^/]+)$") or definition) .. "\"\n\n"

    result ..= "void register_" .. header_name .. "(lua_State* L)\n"
    result ..= "{\n"

    return result
end

function BuilderInclude.build_cpp(decls: {ParserTypes.ParsedDecl}, definition: string, include: string, header_path: string, header_name: string): string
    local result = ""
    result ..= start(definition, include, header_path, header_name)

    for _, decl in decls do
        if decl.kind ~= ParserTypes.DeclKind.Function then
            continue
        end
        
        result ..= "\tregister_scoped_func(L, {" .. get_scope_string(decl.scope) .. "}, \"" .. decl.name .. "\", " .. ParserTypes.parsed_function_prefix .. decl.name .. ");\n"
    end

    result ..= "}\n"

    return result
end

function BuilderInclude.build_include(header_name: string): string
    local result = ""
    result ..= "#pragma once\n\n"
    result ..= "#include \"lua.h\"\n\n"
    result ..= "void register_" .. header_name .. "(lua_State* L);\n"
    return result
end

return BuilderInclude