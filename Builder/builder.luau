--!strict

assert(arg[1] == "-a", "Expected -a flag")
local manifest_decls   = arg[2]
local generated_api = arg[3]
local generated_definition = arg[4]
local output_include = arg[5]

local BuilderApi = require("builderAPI")
local Json = require("../json")
local ParserTypes = require("../parserTypes")
local BuilderBindings = require("./builderBindings")

local function get_file_name(full_path: string): string
    -- Normalize path to use forward slashes
    local normalized_path = full_path:gsub("\\", "/")
    
    -- Extract the file name after the last slash
    local file_name = normalized_path:match("[^/]+$") or full_path
    
    return file_name
end

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

local manifest_lines: {string} = {}
local manifest_content = io.readfile(manifest_decls)
for line in manifest_content:gmatch("[^\n]+") do
    table.insert(manifest_lines, line)
end

local builder_api: BuilderApi.BuilderApi = BuilderApi.new()

local decls: {ParserTypes.ParsedDecl} = {} 
for _, decls_file in manifest_lines do
    local file_content: string = io.readfile(decls_file)
    local new_decls: {ParserTypes.ParsedDecl} = Json.decode(file_content)
    builder_api:append_decls(new_decls)
    table.move(new_decls, 1, #new_decls, #decls + 1, decls)
end

io.writefile(generated_api, builder_api:build())
io.writefile(generated_definition, BuilderBindings.build(decls))
