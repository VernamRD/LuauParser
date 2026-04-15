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
        table.insert(manifest_reg_lines, line)
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

function build_api()
    local manifest_api_content = io.readfile(manifest_api)
    local manifest_api_lines: {string} = {}
    for line in manifest_api_content:gmatch("[^\n]+") do
        table.insert(manifest_api_lines, line)
    end

    for _, api_file in manifest_api_lines do
        local api_content = io.readfile(api_file)
        io.appendfile(generated_api, api_content .. "\n")
    end
end

build_wrapper()
io.writefile(generated_reg, "")
build_reg()
io.writefile(generated_api, "")
build_api()
