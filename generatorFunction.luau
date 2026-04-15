local GeneratorFunction = {}

local ParserTypes = require("parserTypes")

local function get_argument(arg: ParserTypes.ParsedArg, index: number): string
    local arg_str = arg.original_type .. " " .. arg.name .. " = "

    if arg.type == ParserTypes.ParsedArgType.Nil then
        arg_str = arg_str .. "nil"
    elseif arg.type == ParserTypes.ParsedArgType.Boolean then
        arg_str = arg_str .. "luaL_checkboolean"
    elseif arg.type == ParserTypes.ParsedArgType.Number then
        arg_str = arg_str .. "luaL_checkinteger"
    elseif arg.type == ParserTypes.ParsedArgType.String then
        arg_str = arg_str .. "luaL_checkstring"
    end

    arg_str = arg_str .. "(L, " .. tostring(index) .. ");"

    return arg_str
end

local function start_definition(decl: ParserTypes.ParsedDecl): string
    if decl.ret_original_type then
        return "int luau_" .. decl.name .. "(lua_State* L) \n{"
    end

    return "Invalid declaration: missing return type for function " .. decl.name
end

local function end_definition(): string
    return "}"
end

local function function_call(decl: ParserTypes.ParsedDecl): string
    local result: string = ""

    local function_call: string = decl.name
    if decl.scope and #decl.scope > 0 then
        function_call = table.concat(decl.scope, "::") .. "::" .. function_call
    end

    if decl.ret_original_type then
        result = result .. decl.ret_original_type .. " result = " 
    end
    result = result .. function_call .. "("

    if decl.args then
        local arg_names: {string} = {}

        for index, arg in ipairs(decl.args) do
            table.insert(arg_names, arg.name)
        end

        result = result .. table.concat(arg_names, ", ")
    end

    result = result .. ")"

    return result
end

local function return_value(decl: ParserTypes.ParsedDecl): string?
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

function GeneratorFunction.generate_function_luau_wrapper(decl: ParserTypes.ParsedDecl): string
    local lines: {string} = {}

    table.insert(lines, start_definition(decl))

    if decl.args then
        for index, attr in ipairs(decl.args) do
            table.insert(lines, "\t" .. get_argument(attr, index))
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

function GeneratorFunction.generate_function_luau_reg(decl: ParserTypes.ParsedDecl): string
    local result: string = ""

    local scope_str: string = ""
    if decl.scope and #decl.scope > 0 then
        scope_str = table.concat(decl.scope, ".")
        scope_str = scope_str .. "."
    end

    scope_str = scope_str .. decl.name

    result = result .. "register_nested_func(L, \"" .. scope_str .. "\", " .. "luau_" .. decl.name .. ");\n"

    return result
end

function GeneratorFunction.generate_function_luau_api(decl: ParserTypes.ParsedDecl): string
    local result: string = ""

    local scope_str: string = ""
    if decl.scope and #decl.scope > 0 then
        scope_str = table.concat(decl.scope, ".")
        scope_str = scope_str .. "."
    end

    if not (scope_str == "") then       -- Scoped function
        result = result .. "--" .. scope_str .. "--\n"
        result ..= decl.name .. ": ("
    else                                -- Not scoped function
        result = result .. "declare function " .. decl.name .. "("
    end

    if decl.args then
        local args: {string} = {}

        for index, arg in ipairs(decl.args) do
            table.insert(args, arg.name .. ": " .. arg.type)
        end

        result = result .. table.concat(args, ", ")
    end

    if decl.ret_type then
        if not (scope_str == "") then       -- Scoped function
            if decl.ret_type == ParserTypes.ParsedArgType.Nil then
                result = result .. ") -> ()"
            else
                result = result .. ") -> " .. decl.ret_type
            end

            result ..= ","
            
        else                                -- Not scoped function
            result = result .. "): " .. decl.ret_type
        end
    else
        result = result .. ")"
    end

    return result
end

return GeneratorFunction