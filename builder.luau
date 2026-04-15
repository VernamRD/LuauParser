assert(arg[1] == "-a", "Expected -a flag")
local manifest_wrappers   = arg[2]
local manifest_reg = arg[3]
local manifest_api = arg[4]
local generated_reg = arg[5]
local generated_api = arg[6]

local manifest_wrapper_lines: {string} = {}

function build_wrapper()
    local manifest_wrapper_content = io.readfile(manifest_wrappers)
    for line in manifest_wrapper_content:gmatch("[^\n]+") do
        table.insert(manifest_wrapper_lines, line)
    end
end

function build_reg()
    local manifest_reg_content = io.readfile(manifest_reg)
    local manifest_reg_lines: {string} = {}
    for line in manifest_reg_content:gmatch("[^\n]+") do
        if not (line == "") then
            table.insert(manifest_reg_lines, line)
        end
    end

    io.writefile(generated_reg, ("#pragma once\n\n"))
    
    io.appendfile(generated_reg, "#include \"" .. "ParserTypes.h" .. "\"\n\n")

    for _, wrapper_file in manifest_wrapper_lines do
        local file_name = wrapper_file:match("([^/]+)$")
        io.appendfile(generated_reg, "#include \"" .. file_name .. "\"\n")
    end
    io.appendfile(generated_reg, "\n")

    io.appendfile(generated_reg, "void register_internal(lua_State* L)\n" .. "{\n")

    for _, reg_file in manifest_reg_lines do
        local reg_content = io.readfile(reg_file)
        io.appendfile(generated_reg, reg_content .. "\n")
    end

    io.appendfile(generated_reg, "}")
end

local function parse_scope_decls(scope_with_decls, indent: number)
    local shift = string.rep("\t", indent)

    local result = ""

    if scope_with_decls.decls then
        result = result .. shift .. scope_with_decls.decls
    end

    for name, scope in scope_with_decls do
        if name ~= "decls" and type(scope) == "table" then
            result ..= shift
            if indent == 0 then
               result ..= "declare "
            end

            result ..= name .. ": {\n"
            result ..= parse_scope_decls(scope, indent + 1)

            if indent == 0 then
                result ..= shift .. "}\n"
            else
                result ..= shift .. "},\n"
            end
        end
    end

    return result
end

function build_api()
    local scope_with_decls = {}

    local manifest_api_content = io.readfile(manifest_api)
    local manifest_api_lines: {string} = {}
    for line in manifest_api_content:gmatch("[^\n]+") do
        table.insert(manifest_api_lines, line)
    end

    for _, api_file in manifest_api_lines do
        local api_content = io.readfile(api_file)
        local api_lines: {string} = {}
        for line in api_content:gmatch("[^\n]+") do
            table.insert(api_lines, line)
        end

        local scope: {string} = {}

        local line_index = 1
        while line_index <= #api_lines do
            local line = api_lines[line_index]

            -- clear previous scope
            scope = {}

            -- Scope comment like api.math
            local scope_comment = line:match("^%-%-(.-)%-%-$")
            if scope_comment then
                for scope_part in scope_comment:gmatch("[^%.]+") do
                    table.insert(scope, scope_part)
                end
                line_index += 1
                line = api_lines[line_index]
            end

            -- declare
            if not (line == "") then
                local current_scope_with_decl = scope_with_decls
                if scope and #scope > 0 then
                    for _, scope_part in scope do
                        current_scope_with_decl[scope_part] = current_scope_with_decl[scope_part] or {}
                        current_scope_with_decl = current_scope_with_decl[scope_part]
                    end
                end

                current_scope_with_decl.decls = (current_scope_with_decl.decls or "") .. line .. "\n"
            end
            
            line_index += 1
        end
    end

    io.writefile(generated_api, parse_scope_decls(scope_with_decls, 0))
end

build_wrapper()
build_reg()
build_api()