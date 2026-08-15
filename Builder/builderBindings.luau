--!strict
local ParserTypes = require("../parserTypes")

local BuilderBindings = {}
BuilderBindings.__index = BuilderBindings

local function get_scope(scope: {ParserTypes.ScopeDecl}): string?
    local scope_local: {string} = {}
    if scope then
       for _, scope_part in scope do
            if scope_part.kind ~= ParserTypes.ScopeKind.Root and scope_part.kind ~= ParserTypes.ScopeKind.Unknown then
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
            table.insert(arg_names, arg.name)
       end
    end

    return arg_names
end

local function arg_get(arg: ParserTypes.ParsedArg, index: number): string
    local def_str = arg.original_type
    local luau_get_str = ""
    local suffix = ""

    if arg.type == ParserTypes.ParsedArgType.Nil then
        luau_get_str = "nil"
    elseif arg.type == ParserTypes.ParsedArgType.Boolean then
        luau_get_str = "luaL_checkboolean"
    elseif arg.type == ParserTypes.ParsedArgType.Number then
        luau_get_str = "luaL_checkinteger"
    elseif arg.type == ParserTypes.ParsedArgType.String then
        luau_get_str = "luaL_checkstring"
    elseif arg.type == ParserTypes.ParsedArgType.Userdata then
        luau_get_str = "static_cast<" .. arg.original_type .. ">(luaL_checkudata*"
        def_str ..= "*"
        suffix = ")"
    end

    local arg_str = def_str .. " " .. arg.name .. " = " .. luau_get_str .. "(L, " .. tostring(index) .. ")" .. suffix .. ";"

    return arg_str
end


local function return_value(decl: ParserTypes.ParsedDecl): string
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

local function build_function(decl: ParserTypes.ParsedDecl): string
    local result: string = ""

    result ..= "int luau_" .. decl.name .. "(lua_State* L)\n{\n"
    
    -- Extract arguments
    if decl.args then
       for arg_index, arg in decl.args do
            result ..= "\t" .. arg_get(arg, arg_index) .. "\n"
       end
    end

    -- Make function call
    if decl.ret_type ~= ParserTypes.ParsedArgType.Nil and decl.ret_original_type then
        result ..= "\t" .. decl.ret_original_type .. " result = "
    else
        result ..= "\t"
    end

    -- Call from self argument if this class field
    if decl.is_field and not decl.is_static and decl.args then
        result ..= decl.args[1].name .. "->" .. decl.name .. "("
    else
        local scope_str = get_scope(decl.scope)
        if scope_str then
            result ..= scope_str .. "::" .. decl.name .. "("
        else
            result ..= decl.name .. "("
        end
    end

    -- Native arguments
    if decl.args then
        result ..= table.concat(get_arg_names(decl.args), ", ")
    end
    result ..= ");\n"

    result ..= return_value(decl) .. "}\n\n"

    return result
end

function BuilderBindings.build(decls: {ParserTypes.ParsedDecl}): string
    local result: string = ""
    
    for _, decl in decls do 
        if decl.kind == ParserTypes.DeclKind.Function then 
            result ..= build_function(decl)
        end
    end

    return result
end

return BuilderBindings

