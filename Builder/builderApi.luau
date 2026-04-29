--!strict

local BuilderApi = {}

local BuilderTypes = require("builderTypes")

local function parse_scope_decls(builder_decl_tree: BuilderTypes.BuilderDeclTree, indent: number)
    local shift = string.rep("\t", indent)

    local result = ""

    if builder_decl_tree.decls then
        for _, decl in builder_decl_tree.decls do
            print(decl.decl)
            result ..= shift .. decl.decl
        end
    end

    for name, decl_tree in builder_decl_tree do
        if name == "decls" or name == "is_class" or typeof(decl_tree) ~= "table" then
            continue
        end

        result ..= shift
        local is_class: boolean = decl_tree.is_class or false

        if indent == 0 then
            if is_class then 
                result ..= "declare class " .. name .. "\n"
            else
                result ..= "declare " .. name .. ": {\n"
            end
        else
            result ..= name .. ": {\n"
        end

        result ..= parse_scope_decls(decl_tree, indent + 1)

        if indent == 0 then
            if is_class then
                result ..= shift .. "end\n"
            else
                result ..= shift .. "}\n"
            end
        else
            result ..= shift .. "},\n"
        end
    end

    return result
end

function BuilderApi.parse_api_str(manifest_api_file_name: string): string
    local builder_decl_tree: BuilderTypes.BuilderDeclTree = {decls = {}}

    local manifest_api_content = io.readfile(manifest_api_file_name)
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
            local attrs: {BuilderTypes.BuilderAttr}? = {}
            local is_class = false

            -- Attrs
            local attrs_str = BuilderTypes.try_get_attributes(line)
            if attrs_str then
                attrs = BuilderTypes.parse_attributes(attrs_str)
                assert(attrs, "Except Nil")

                -- If has field attr this scope is a class
                if BuilderTypes.has_attr(attrs, BuilderTypes.BuilderAttrType.Field) then
                    is_class = true
                end

                for _, attr in attrs do
                    if attr.type == BuilderTypes.BuilderAttrType.Scope and type(attr.value) == "string" then
                        local scope_arr = attr.value:gmatch("[^%.]+")
                        assert(scope_arr, "Invalid scope format")

                        for scope_part in scope_arr do
                            table.insert(scope, scope_part)
                        end

                        if is_class then    -- Class declaration does not be in a namespaces or nested tables, only in root + class_name scope
                           scope = {scope[#scope]}
                        end

                        line_index += 1 -- skip this attr line
                        line = api_lines[line_index]
                    end
                end
            end

            -- declare
            if not (line == "") then
                local current_builder_decl_tree = builder_decl_tree

                if scope and #scope > 0 then
                    for _, scope_part: string in scope do
                        current_builder_decl_tree[scope_part] = current_builder_decl_tree[scope_part] or {}
                        current_builder_decl_tree = current_builder_decl_tree[scope_part]
                    end
                end

                if attrs then -- Apply class flag to leaf
                    current_builder_decl_tree.is_class = current_builder_decl_tree.is_class or is_class
                end

                local decl: BuilderTypes.BuilderDecl = {decl = (line .. "\n"), attrs = attrs}
                if current_builder_decl_tree.decls then 
                    table.insert(current_builder_decl_tree.decls, decl)
                else
                    current_builder_decl_tree.decls = {decl}
                end
            end
            
            line_index += 1
        end
    end

    return parse_scope_decls(builder_decl_tree, 0)
end

return BuilderApi