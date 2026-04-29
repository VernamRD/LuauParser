assert(arg[1] == "-a", "Expected -a flag")
local manifest_wrappers   = arg[2]
local manifest_reg = arg[3]
local manifest_api = arg[4]
local generated_reg = arg[5]
local generated_api = arg[6]
local output_include = arg[7]

local manifest_wrapper_lines: {string} = {}
local BuilderTypes = require("builderTypes")
local BuilderApi = require("builderApi")

local function get_relative_path(full_path: string): string
    local source_directory = tostring(io.source_directory())

    -- Normalize path
    full_path = full_path:gsub("\\", "/")
    source_directory = source_directory:gsub("\\", "/")

    -- Find shared root directory
    local root_directory = source_directory
    while root_directory ~= "" and full_path:find(root_directory, 1, true) ~= 1 do
        root_directory = root_directory:match("(.*)/[^/]*$") or ""
    end

    -- Make relative path for include
    local relative_path = full_path
    if root_directory ~= "" then
        relative_path = full_path:sub(#root_directory + 1)
    end
    
    relative_path = relative_path:gsub("^[\\/]+", "")
    return relative_path
end

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
    
    io.appendfile(generated_reg, "#include \"" .. "ParserRegister.h" .. "\"\n\n")

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
    io.writefile(generated_api, BuilderApi.parse_api_str(manifest_api))
end

local function build_output_include()
    local result = ""
    result ..= "#pragma once\n\n"

    result ..= "#include \"" .. get_relative_path(generated_reg) .. "\"\n\n"
    result ..= "void register_bindings(lua_State* L)\n{\n"
    result ..= "\tregister_internal(L);\n}"

    io.writefile(output_include, result)
end

build_wrapper()
build_reg()
build_api()
build_output_include()