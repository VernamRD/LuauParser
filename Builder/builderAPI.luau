--!strict
local json = require("../json")
local ParserTypes = require("../parserTypes")

local BuilderApi = {}
BuilderApi.__index = BuilderApi

export type RootNode = {
    methods: {string},
    fields: {string},

    classes: {ClassNode},
    namespaces: {NamespaceNode},
}

export type ClassNode = {
    name: string,

    methods: {string},
    fields: {string},
}

export type NamespaceNode = {
    name: string,

    methods: {string},
    fields: {string},

    children: {NamespaceNode},
}

export type BuilderApi = {
    root_node: RootNode,
    append_decls: (self: BuilderApi, decls: {ParserTypes.ParsedDecl}) -> (),
    build: (self: BuilderApi) -> string
}

local function create_var_string(decl: ParserTypes.ParsedDecl): string
    local var_str = ""

    var_str ..= decl.name .. ": " .. (decl.ret_type or "unknown")

    return var_str
end

local function create_method_string(decl: ParserTypes.ParsedDecl): string
    local method_str = ""

    local global_style: boolean = #decl.scope <= 1

    if global_style then
        method_str ..= decl.name .. "("
    else
        method_str ..= decl.name .. ": ("
    end

    if decl.args and #decl.args > 0 then
        for i, arg in decl.args do
            if arg.is_self then -- Resolve self arg
                method_str ..= arg.name .. ": " .. decl.scope[#decl.scope].name
            else
                method_str ..= arg.name .. ": " .. arg.type
            end

            if i < #decl.args then
                method_str ..= ", "
            end
        end
    end

    method_str ..= ")"

    if global_style then
        method_str ..= ": "
    else
        method_str ..= " -> "
    end

    if not decl.ret_type or decl.ret_type == ParserTypes.ParsedArgType.Nil then
        method_str ..= "()"
    else
        method_str ..= decl.ret_type
    end

    return method_str
end

local function get_namespace_node(child_nodes: {NamespaceNode}, decl: ParserTypes.ParsedDecl, depth: number): NamespaceNode
    if #child_nodes > 0 then
        for _, node in child_nodes do
            if node.name == decl.scope[depth].name then
                if depth == #decl.scope then
                    return node
                else
                    return get_namespace_node(node.children, decl, depth + 1)
                end
            end
        end 
    end

    local new_node: NamespaceNode = {
        name = decl.scope[depth].name,
        methods = {},
        fields = {},
        children = {}
    }
    table.insert(child_nodes, new_node)

    if depth == #decl.scope then
        return new_node
    end

    return get_namespace_node(new_node.children, decl, depth + 1)
end

local function add_decl(root: RootNode, decl: ParserTypes.ParsedDecl)
    local function add_to_class(class: ClassNode, decl: ParserTypes.ParsedDecl)
        if decl.is_var then
            table.insert(class.fields, create_var_string(decl))
        else
            table.insert(class.methods, create_method_string(decl))
        end
    end
        
    if decl.is_field and not decl.is_static then
        local class_name= decl.scope[#decl.scope].name 
    
        for _, class in root.classes do
            if class.name == class_name then
                add_to_class(class, decl)
                return
            end
        end 

        -- If not found
        local new_class: ClassNode = {
            name = class_name,
            fields = {},
            methods = {},
        }
        add_to_class(new_class, decl)
        table.insert(root.classes, new_class)
    else
        if #decl.scope > 1 then -- Find namespace node
            local node = get_namespace_node(root.namespaces, decl, 2 --[[root is 1'nd depth]])
            if decl.is_var then
                table.insert(node.fields, create_var_string(decl))
            else
                table.insert(node.methods, create_method_string(decl))
            end
        else -- Add to root
            if decl.is_var then
                table.insert(root.fields, create_var_string(decl))
            else
                table.insert(root.methods, create_method_string(decl))
            end
        end
    end
end

function BuilderApi.new(): BuilderApi
    local self = setmetatable({}, BuilderApi)
    self.root_node = {
        methods = {},
        fields = {},
        classes = {},
        namespaces = {}
    }
    return (self :: any) :: BuilderApi
end

function BuilderApi.append_decls(self: BuilderApi, decls: {ParserTypes.ParsedDecl})
    for _, decl in decls do
        add_decl(self.root_node, decl)
    end
end

function BuilderApi.build(self: BuilderApi): string
    local result = ""

    -- Add methods and fields at the root level
    for _, method in self.root_node.methods do
        result ..= "declare function " .. method .. "\n"
    end
    for _, field in self.root_node.fields do
        result ..= "declare " .. field .. "\n"
    end

    -- Add classes
    for _, class in self.root_node.classes do
        result ..= "export type " .. class.name .. " = {\n"
        for _, method in class.methods do
            result ..= "\t" .. method .. "\n"
        end
        for _, field in class.fields do
            result ..= "\t" .. field .. "\n"
        end
        result ..= "}\n"
    end

    -- Add Namespaces
    local function print_namespace(node: NamespaceNode, depth: number)
        local shift = string.rep("\t", depth)

        -- Start namespace declaration
        if depth == 0 then
            result ..= shift .. "declare " .. node.name .. ": {\n"
        else
            result ..= shift .. node.name .. ": {\n"
        end

        -- Add methods and fields for this namespace
        for _, method in node.methods do
            result ..= shift .. "\t" .. method .. ",\n"
        end
        for _, field in node.fields do
            result ..= shift .. "\t" .. field .. ",\n"
        end

        for _, child in node.children do
            print_namespace(child, depth + 1)
        end

        -- End namespace declaration
        if depth == 0 then
            result ..= shift .. "}\n"
        else
            result ..= shift .. "},\n"
        end
    end

    for _, namespace in self.root_node.namespaces do
        print_namespace(namespace, 0)
    end

    return result
end

return BuilderApi