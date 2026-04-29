local GeneratorFunction = {}

local ParserTypes = require("../Parser/parserTypes")
local BuilderTypes = require("../Builder/builderTypes")

local function scope_to_string_arr(scope: {ParserTypes.ScopeDecl}): {string}
    local scopes: {string} = {}
    for _, scope_part in scope do
        if scope_part.kind == ParserTypes.ScopeKind.Root then
            continue
        end

        table.insert(scopes, scope_part.name)
    end

    return scopes
end

local function get_argument(arg: ParserTypes.ParsedArg, index: number, decl: ParserTypes.ParsedDeclFunc): string
    local def_str = arg.original_type -- @TODO need add flag or marker for namespaced classes or structs, something like "@MUST_BE_RESOLVED@"
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
        luau_get_str = "static_cast<" .. arg.original_type .. ">(luaL_checkudata"
        def_str ..= "*"
        suffix = ")"
    end

    local arg_str = def_str .. " " .. arg.name .. " = " .. luau_get_str .. "(L, " .. tostring(index) .. ")" .. suffix .. ";"

    return arg_str
end

local function start_definition(decl: ParserTypes.ParsedDeclFunc): string
    if decl.ret_original_type then
        return "int luau_" .. decl.name .. "(lua_State* L) \n{"
    end

    return "Invalid declaration: missing return type for function " .. decl.name
end

local function end_definition(): string
    return "}"
end

local function function_call(decl: ParserTypes.ParsedDeclFunc): string
    local result: string = ""

    local function_call: string
    if decl.is_field and not decl.is_static then
        function_call = "self->" .. decl.name
    else
        function_call = decl.name
        if decl.scope and #decl.scope > 1 then  -- first scope is alway root
            function_call = table.concat(scope_to_string_arr(decl.scope), "::") .. "::" .. function_call
        end
    end

    if decl.ret_original_type and decl.ret_type ~= ParserTypes.ParsedArgType.Nil then
        result = result .. decl.ret_original_type .. " result = " 
    end
    result = result .. function_call .. "("

    if decl.args then
        local arg_names: {string} = {}

        for index, arg in ipairs(decl.args) do
            table.insert(arg_names, arg.name)
        end

        if decl.is_field and not decl.is_static then
            table.remove(arg_names, 1)
        end

        result = result .. table.concat(arg_names, ", ")
    end

    result = result .. ");"

    return result
end

local function return_value(decl: ParserTypes.ParsedDeclFunc): string?
    if decl.ret_type == nil then
        return nil
    end

    if decl.ret_type == ParserTypes.ParsedArgType.Boolean then
        return "lua_pushboolean(L, result); \n\treturn 1;"
    elseif decl.ret_type == ParserTypes.ParsedArgType.Number then
        return "lua_pushinteger(L, result); \n\treturn 1;"
    elseif decl.ret_type == ParserTypes.ParsedArgType.String then
        return "lua_pushstring(L, result.c_str()); \n\treturn 1;"
    elseif decl.ret_type == ParserTypes.ParsedArgType.Nil then
        return "return 0;"
    end

    return "return 0; // Unsupported return type"
end

function GeneratorFunction.generate_function_luau_wrapper(decl: ParserTypes.ParsedDeclFunc): string
    local lines: {string} = {}

    table.insert(lines, start_definition(decl))

    if decl.args then
        for index, attr in ipairs(decl.args) do
            table.insert(lines, "\t" .. get_argument(attr, index, decl))
        end
    end

    table.insert(lines, "\t" .. function_call(decl))

    local return_stmt = return_value(decl)
    if return_stmt then
        table.insert(lines, "\t" .. return_stmt)
    end

    table.insert(lines, end_definition())

    return table.concat(lines, "\n")
end

function GeneratorFunction.generate_function_luau_reg(decl: ParserTypes.ParsedDeclFunc): string
    local result: string = ""

    local scope_str: string = ""
    if decl.scope and #decl.scope > 1 then  -- first scope is alway root
        scope_str = table.concat(scope_to_string_arr(decl.scope), ".")
        scope_str = scope_str .. "."
    end

    scope_str = scope_str .. decl.name

    result = result .. "register_nested_func(L, \"" .. scope_str .. "\", " .. "luau_" .. decl.name .. ");\n"

    return result
end

function GeneratorFunction.generate_function_luau_api(decl: ParserTypes.ParsedDeclFunc): string
    local attrs: {BuilderTypes.BuilderAttr} = {}
    local decl_str = ""
    local call_str = ""
    local ret_str = ""

    local scope_str: string = ""
    if decl.scope and #decl.scope > 0 then
        scope_str = table.concat(scope_to_string_arr(decl.scope), ".")
    end
    local is_scoped = scope_str ~= ""

    if decl.is_field and not decl.is_static then
        table.insert(attrs, {
            type = BuilderTypes.BuilderAttrType.Field,
            value = true,
        })
    end

    if decl.is_field then
        decl_str ..= "function " .. decl.name .. "("
        if is_scoped then       -- Scoped function
            table.insert(attrs, {
                type = BuilderTypes.BuilderAttrType.Scope,
                value = scope_str,
            })
        end
    else
        if is_scoped then       -- Scoped function
            table.insert(attrs, {
                type = BuilderTypes.BuilderAttrType.Scope,
                value = scope_str,
            })

            decl_str ..= decl.name .. ": ("
        else                                -- Not scoped function
            decl_str ..= "declare function " .. decl.name .. "("
        end
    end

    if decl.args then
        local args: {string} = {}

        for index, arg in ipairs(decl.args) do
            local arg_type = ""
            
            if arg.is_self then
                table.insert(args, "self")
                continue
            end

            if arg.type == ParserTypes.ParsedArgType.Userdata then
                arg_type = arg.original_type
            else
                arg_type = arg.type
            end
            table.insert(args, arg.name .. ": " .. arg_type)
        end

        call_str ..= table.concat(args, ", ")
    end

    ret_str ..= ")"

    if is_scoped and not decl.is_field then
        ret_str ..= " -> "
    else
        ret_str ..= ": "
    end

    if decl.ret_type and not (decl.ret_type == ParserTypes.ParsedArgType.Nil) then
        ret_str ..= decl.ret_type
    else
        ret_str ..= "()"
    end

    if is_scoped and not decl.is_field then
        ret_str ..= ","
    end

    local attr_str = ""
    if #attrs > 0 then
        attr_str = BuilderTypes.print_attributes(attrs) .. "\n"
    end

    return attr_str .. decl_str .. call_str .. ret_str
end

return GeneratorFunction