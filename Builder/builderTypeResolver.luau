--!strict
local ParserTypes = require("../parserTypes")
local Json = require("../json")

local BuilderTypeResolver = {}

local function find_type_registry(type_string: string, registry_manifest_path: string): ParserTypes.TypeRegistryEntry?
    local file_paths: {string} = {}

    local manifest_content: string = io.readfile(registry_manifest_path)
    for line in manifest_content:gmatch("[^\n]+") do
        table.insert(file_paths, line)
    end

    for _, file in file_paths do
        local registry_content: string = io.readfile(file)
        local type_registry: ParserTypes.TypeRegistry = Json.decode(registry_content) 

        for _, registry_entry in type_registry do
            if registry_entry.name == type_string then
                return registry_entry
            end
        end
    end

    return nil
end

function BuilderTypeResolver.resolve(type_string: string, registry_manifest_path: string): ParserTypes.TypeRegistryEntry?
    local registry_entry = find_type_registry(type_string, registry_manifest_path)
    if registry_entry then
        return registry_entry
    end

    return nil
end

return BuilderTypeResolver