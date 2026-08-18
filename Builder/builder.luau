--!strict

assert(arg[1] == "-s", "Expected -s flag")
local decls_json    = arg[2]
local type_registry_manifest = arg[3]
local header_path   = arg[4]
local generated_api = arg[5]
local generated_definition = arg[6]
local output_include = arg[7]
local output_cpp = arg[8]

local BuilderApi = require("builderAPI")
local Json = require("../json")
local ParserTypes = require("../parserTypes")
local BuilderDefinition = require("./builderDefinition")
local BuilderInclude = require("./builderInclude")

local function get_file_name(full_path: string): string
    local normalized_path = full_path:gsub("\\", "/")
    local file_name = normalized_path:match("[^/]+$") or full_path
    return file_name
end

local header_name = (get_file_name(header_path):gsub("%.h$", ""))

local builder_api: BuilderApi.BuilderApi = BuilderApi.new()

local file_content: string = io.readfile(decls_json)
local decls: {ParserTypes.ParsedDecl} = Json.decode(file_content)
builder_api:append_decls(decls)

io.writefile(generated_api, builder_api:build())
io.writefile(generated_definition, BuilderDefinition.build(decls, type_registry_manifest))
io.writefile(output_cpp, BuilderInclude.build_cpp(decls, generated_definition, output_include, header_path, header_name))
io.writefile(output_include, BuilderInclude.build_include(header_name))