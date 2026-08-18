--!strict
local ParserTypes = require("../parserTypes")
local BuilderTypeResolver = require("./builderTypeResolver")

local BuilderDefinition = {}
BuilderDefinition.__index = BuilderDefinition

local function get_self_scope_table_string(arg: ParserTypes.ParsedArg): string
    return string.gsub(arg.original_type, "::", ".")
end

local function get_scope(scope: {ParserTypes.ScopeDecl}): string?
    local scope_local: {string} = {}
    if scope then
       for _, scope_part in scope do
            if scope_part.kind ~= ParserTypes.ScopeKind.Unknown then
                table.insert(scope_local, scope_part.name)
            end
       end
    end
  
    return if (#scope_local > 0) then table.concat(scope_local, "::") else nil
end

local function get_arg_names(args: {ParserTypes.ParsedArg}): {string}
    local arg_names: {string} = {}
    if args then
       for _, arg in args do
            if not arg.is_self then
                table.insert(arg_names, arg.name)
            end
       end
    end

    return arg_names
end

local function arg_get(arg: ParserTypes.ParsedArg, index: number, registry_manifest_path: string): (string, {string})
    local include_files: {string} = {}
    local def_str = arg.original_type
    local luau_get_str = ""
    local suffix = ""
    local table_arg: string? = nil

    if arg.type == ParserTypes.ParsedArgType.Nil then
        luau_get_str = "nil"
    elseif arg.type == ParserTypes.ParsedArgType.Boolean then
        luau_get_str = "luaL_checkboolean"
    elseif arg.type == ParserTypes.ParsedArgType.Number then
        luau_get_str = "luaL_checkinteger"
    elseif arg.type == ParserTypes.ParsedArgType.String then
        luau_get_str = "luaL_checkstring"
    elseif arg.type == ParserTypes.ParsedArgType.Userdata then
        def_str ..= "*"
        luau_get_str = "static_cast<" .. def_str .. ">(luaL_checkudata"
        table_arg = ", \"" .. get_self_scope_table_string(arg) .. "\""
        suffix = ")"
    elseif arg.type == ParserTypes.ParsedArgType.Unresolved then
        local registry_entry = BuilderTypeResolver.resolve(arg.original_type, registry_manifest_path)
        if registry_entry then -- Resolve user types
            if registry_entry.kind == ParserTypes.DeclKind.Enum then
                def_str = ParserTypes.concat_scope(registry_entry.scope)
                luau_get_str = "static_cast<" .. def_str .. ">(luaL_checkinteger"
            else
                def_str = ParserTypes.concat_scope(registry_entry.scope) .. "*"
                luau_get_str = "static_cast<" .. arg.original_type .. "*>(luaL_checkudata"
                table_arg = ", \"" .. string.gsub(def_str, "::", ".") .. "\"" 
            end

            suffix = ")"
            table.insert(include_files, registry_entry.header)
        else
            def_str = "could not resolve"    
        end
    end

    local arg_str = def_str .. " " .. arg.name .. " = " .. luau_get_str .. "(L, " .. tostring(index) .. (if table_arg then table_arg else ("")) .. ")" .. suffix .. ";"

    return arg_str, include_files
end


local function return_value(decl: ParserTypes.FunctionDecl): string
    if decl.ret_type == ParserTypes.ParsedArgType.Boolean then
        return "\tlua_pushboolean(L, result); \n\treturn 1;\n"
    elseif decl.ret_type == ParserTypes.ParsedArgType.Number then
        return "\tlua_pushinteger(L, result); \n\treturn 1;\n"
    elseif decl.ret_type == ParserTypes.ParsedArgType.String then
        return "\tlua_pushstring(L, result.c_str()); \n\treturn 1;\n"
    elseif decl.ret_type == ParserTypes.ParsedArgType.Nil then
        return "\treturn 0;\n"
    end

    return "\treturn 0; // Unsupported return type\n"
end

local function try_build_function(decl: ParserTypes.ParsedDecl, registry_manifest_path: string): (string?, {string})
    local include_files: {string} = {}

    if decl.kind ~= ParserTypes.DeclKind.Function then 
        return "", include_files
    end

    local result: string = ""

    local function_decl: ParserTypes.FunctionDecl? = decl["function"]
    if not function_decl then 
        return "", include_files
    end

    result ..= "int " .. ParserTypes.parsed_function_prefix .. decl.name .. "(lua_State* L)\n{\n"
    
    -- Extract arguments
    if function_decl.args then
       for arg_index, arg in function_decl.args do
            local arg_str, arg_include_files = arg_get(arg, arg_index, registry_manifest_path)
            result ..= "\t" .. arg_str .. "\n"
            table.move(arg_include_files, 1, #arg_include_files, #include_files + 1, include_files)
       end
    end

    -- Make function call
    if function_decl.ret_type ~= ParserTypes.ParsedArgType.Nil and function_decl.ret_original_type then
        result ..= "\t" .. function_decl.ret_original_type .. " result = "
    else
        result ..= "\t"
    end

    -- Call from self argument if this class field
    if function_decl.is_field and not function_decl.is_static and function_decl.args then
        result ..= function_decl.args[1].name .. "->" .. decl.name .. "("
    else
        local scope_str = get_scope(decl.scope)
        if scope_str then
            result ..= scope_str .. "::" .. decl.name .. "("
        else
            result ..= decl.name .. "("
        end
    end

    -- Native arguments
    if function_decl.args then
        result ..= table.concat(get_arg_names(function_decl.args), ", ")
    end
    result ..= ");\n"

    result ..= return_value(function_decl) .. "}\n\n"

    return result, include_files
end

function BuilderDefinition.build(decls: {ParserTypes.ParsedDecl}, registry_manifest_path: string): string
    local result: string = ""
    
    local include_files: {string} = {}
    local functions_str: {string} = {}

    for _, decl in decls do 
        local function_str, function_inlcude_files = try_build_function(decl, registry_manifest_path)
        if not function_str then
            continue
        end
        
        table.insert(functions_str, function_str)
        table.move(function_inlcude_files, 1, #function_inlcude_files, #include_files + 1, include_files)
    end

    for _, include_file in include_files do
        result ..= "#include \"" .. include_file .. "\"\n"
    end

    result ..= "\n"

    for _, function_str in functions_str do
        result ..= function_str .. "\n"
    end

    return result
end

return BuilderDefinition

