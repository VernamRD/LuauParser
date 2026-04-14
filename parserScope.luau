local ParserScope = {}

local ParserTypes = require("parserTypes")

function ParserScope.parse_blocks(file_lines: {string}) : ParserTypes.ScopeNode
    local root: ParserTypes.ScopeNode = { kind = ParserTypes.ScopeKind.Root, name = "", children = {}, body = "", line_start = 0}
    local stack = { root }

    root.line_end = #file_lines + 1

    local prev_trimmed = ""  -- previous non-empty line

    local line_index: number = 1
    while line_index <= #file_lines do
        local line = file_lines[line_index]
        local trimmed = line:match("^%s*(.-)%s*$")
        local current = stack[#stack]

        -- Skip empty lines but remember context
        if trimmed == "" then
            line_index += 1
            continue
        end

        -- Try catch @luau decl
        local attr_str = trimmed:match("@luau%s*(.*)")
        if attr_str then
            current.contains_luau = true
            line_index += 1
            continue
        end

        -- { check before } to handle inline blocks correctly
        if trimmed:find("{") then
            -- inline and { } on the same line - skip
            if trimmed:find("}") then
                prev_trimmed = trimmed
                line_index += 1
                continue
            end

            -- Block header: either on this line before {, or it was prev_trimmed
            local header = trimmed:gsub("{.*$", ""):match("^%s*(.-)%s*$")
            if header == "" then
                -- { placed separately - header is the previous line
                header = prev_trimmed
            end

            local kind: ParserTypes.ScopeKind = ParserTypes.ScopeKind.Block
            local name = header

            if header:match("^namespace%s+") then
                kind = ParserTypes.ScopeKind.Namespace
                name = header:match("^namespace%s+(.+)$")
            elseif header:match("^struct%s+") then
                kind = ParserTypes.ScopeKind.Struct
                name = header:match("^struct%s+([%w_]+)")
            elseif header:match("^class%s+") then
                kind = ParserTypes.ScopeKind.Class
                name = header:match("^class%s+([%w_]+)")
            elseif header:match("^enum%s+") then
                kind = ParserTypes.ScopeKind.Enum
                name = header:match("^enum%s*class%s+([%w_]+)") 
                    or header:match("^enum%s+([%w_]+)")
            end

            local node: ParserTypes.ScopeNode = {
                kind       = kind,
                name       = name or header,
                children   = {},
                parent     = current,
                line_start = line_index,
            }

            table.insert(stack[#stack].children, node)
            table.insert(stack, node)

        elseif trimmed:find("^}") then
            if #stack > 1 then
                current.line_end = line_index + 1
                table.remove(stack)
            end
        end

        prev_trimmed = trimmed
        line_index += 1
    end

    return root
end

-- Collect all scopes that contain @luau declarations into a flat array for easier processing
function ParserScope.build_scope_arr_with_decl(root: ParserTypes.ScopeNode): {ParserTypes.ScopeNode}
    local result: {ParserTypes.ScopeNode} = {}
    local stack = { root }

    while #stack > 0 do
        local current = table.remove(stack)
        if current.contains_luau then
            table.insert(result, current)
        end

        for _, child in ipairs(current.children) do
            table.insert(stack, child)
        end
    end

    return result
end

function ParserScope.print_tree(node: ParserTypes.ScopeNode, indent: number)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    print(prefix .. "[" .. node.kind .. "] " .. (node.name or "?") .. " " .. (node.line_start or "?") .. "-" .. (node.line_end or "?") .. (node.contains_luau == true and " (contains @luau)" or ""))

    for _, child in ipairs(node.children) do
        ParserScope.print_tree(child, indent + 1)
    end
end

return ParserScope